#!/usr/bin/env bash
# Step 01: GPU Infrastructure & RHOAI Prerequisites - Deploy Script
# Deploys all prerequisites for RHOAI 3.4:
# - User Workload Monitoring
# - NFD Operator + Instance
# - GPU Operator + ClusterPolicy + DCGM Dashboard
# - OpenShift Serverless + KnativeServing
# - Cluster Observability + Tempo + OpenTelemetry Operators
# - Red Hat build of Kueue Operator
# - Red Hat Connectivity Link stack for Models-as-a-Service
# - GPU MachineSets (AWS)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-01-gpu-and-prereq"

load_env
check_oc_logged_in

log_step "Step 01: GPU Infrastructure & RHOAI Prerequisites"

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"

log_info "Git Repo: $GIT_REPO_URL"
log_info "Branch: $GIT_REPO_BRANCH"

wait_for_csv() {
    local subscription="$1"
    local namespace="$2"
    local label="$3"
    local installed_csv

    until installed_csv=$(oc get subscription "$subscription" -n "$namespace" -o jsonpath='{.status.installedCSV}' 2>/dev/null) && \
          [[ -n "$installed_csv" ]] && \
          [[ "$(oc get csv "$installed_csv" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null)" == "Succeeded" ]]; do
        log_info "Waiting for ${label}..."
        sleep 10
    done

    log_success "${label} ready (${installed_csv})"
}

approve_matching_installplans() {
    local namespace="$1"
    local pattern="$2"
    local plan approved csvs

    while IFS='|' read -r plan approved csvs; do
        [[ -z "$plan" || "$approved" == "true" ]] && continue
        if [[ "${csvs,,}" =~ $pattern ]]; then
            log_info "Approving install plan ${plan} in ${namespace} (${csvs})"
            oc patch installplan "$plan" -n "$namespace" --type merge -p '{"spec":{"approved":true}}'
        fi
    done < <(oc get installplan -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.approved}{"|"}{.spec.clusterServiceVersionNames}{"\n"}{end}' 2>/dev/null || true)
}

ensure_tempo_operator_api_egress() {
    local api_service_ip available endpoints

    api_service_ip="$(oc get service kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
    if [[ -z "$api_service_ip" ]]; then
        log_warn "Could not determine Kubernetes service IP for Tempo operator egress"
        return 0
    fi

    # Tempo Operator installs a deny-all NetworkPolicy. Its generated API egress
    # policy can target a control-plane node directly, while the operator process
    # uses KUBERNETES_SERVICE_HOST. Add a narrow allow for the service IP.
    cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tempo-operator-egress-to-kubernetes-service
  namespace: openshift-tempo-operator
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/managed-by: operator-lifecycle-manager
      app.kubernetes.io/name: tempo-operator
      app.kubernetes.io/part-of: tempo-operator
      control-plane: controller-manager
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: ${api_service_ip}/32
    ports:
    - protocol: TCP
      port: 443
EOF
    log_success "Tempo Operator can reach Kubernetes service IP ${api_service_ip}:443"

    available="$(oc get deployment tempo-operator-controller -n openshift-tempo-operator -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
    endpoints="$(oc get endpoints tempo-operator-controller-service -n openshift-tempo-operator -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
    if [[ "${available:-0}" != "1" || -z "$endpoints" ]]; then
        log_info "Restarting Tempo Operator so the corrected egress policy takes effect"
        oc delete pod -n openshift-tempo-operator \
            -l app.kubernetes.io/name=tempo-operator,control-plane=controller-manager \
            --ignore-not-found
        oc rollout status deployment/tempo-operator-controller -n openshift-tempo-operator --timeout=3m \
            && log_success "Tempo Operator webhook endpoint ready" \
            || log_warn "Tempo Operator did not become ready within 3 minutes"
    fi
}

CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
AMI_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')
REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')

log_info "Cluster ID: $CLUSTER_ID"
log_info "AMI ID: $AMI_ID"
log_info "Region: $REGION"

log_step "Creating Argo CD Application for GPU Infrastructure"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

log_step "Waiting for NFD Operator..."
until oc get crd nodefeaturediscoveries.nfd.openshift.io &>/dev/null; do
    log_info "Waiting for NFD CRD..."
    sleep 10
done
log_success "NFD CRD available"

log_step "Waiting for GPU Operator..."
until oc get crd clusterpolicies.nvidia.com &>/dev/null; do
    log_info "Waiting for GPU Operator CRD..."
    sleep 10
done
log_success "GPU Operator CRD available"

log_step "Waiting for Serverless Operator..."
until oc get crd knativeservings.operator.knative.dev &>/dev/null; do
    log_info "Waiting for Knative CRD..."
    sleep 10
done
log_success "Serverless CRD available"

log_step "Waiting for OpenShift AI observability prerequisites..."
wait_for_csv "cluster-observability-operator" "openshift-cluster-observability-operator" "Cluster Observability Operator"
wait_for_csv "tempo-product" "openshift-tempo-operator" "Tempo Operator"
ensure_tempo_operator_api_egress
wait_for_csv "opentelemetry-product" "openshift-opentelemetry-operator" "Red Hat build of OpenTelemetry"

for crd in \
    monitoringstacks.monitoring.rhobs \
    perses.perses.dev \
    persesdashboards.perses.dev \
    persesdatasources.perses.dev \
    tempomonolithics.tempo.grafana.com \
    opentelemetrycollectors.opentelemetry.io; do
    until oc get crd "$crd" &>/dev/null; do
        log_info "Waiting for observability CRD: $crd"
        sleep 10
    done
    log_success "Observability CRD available: $crd"
done

log_step "Waiting for Red Hat build of Kueue Operator..."
wait_for_csv "kueue-operator" "openshift-kueue-operator" "Kueue Operator"

log_step "Waiting for Kueue CRD..."
until oc get crd kueues.kueue.openshift.io &>/dev/null; do
    log_info "Waiting for Kueue CRD..."
    sleep 10
done
log_success "Kueue CRD available"

log_step "Waiting for Red Hat Connectivity Link stack..."
repair_maas_authconfig_for_authorino_upgrade || true
until RHCL_CSV=$(oc get subscription rhcl-operator -n openshift-operators -o jsonpath='{.status.installedCSV}' 2>/dev/null) && \
      [[ -n "$RHCL_CSV" ]] && \
      [[ "$(oc get csv "$RHCL_CSV" -n openshift-operators -o jsonpath='{.status.phase}' 2>/dev/null)" == "Succeeded" ]]; do
    approve_matching_installplans "openshift-operators" "rhcl-operator|authorino-operator|limitador-operator|dns-operator"
    repair_maas_authconfig_for_authorino_upgrade || true
    log_info "Waiting for Red Hat Connectivity Link Operator..."
    sleep 10
done
log_success "Red Hat Connectivity Link Operator ready (${RHCL_CSV})"
wait_for_csv "authorino-operator-stable-redhat-operators-rhoai-openshift-marketplace" "openshift-operators" "RHCL Authorino dependency"
wait_for_csv "limitador-operator-stable-redhat-operators-rhoai-openshift-marketplace" "openshift-operators" "RHCL Limitador dependency"
wait_for_csv "dns-operator-stable-redhat-operators-rhoai-openshift-marketplace" "openshift-operators" "RHCL DNS dependency"

for crd in \
    authconfigs.authorino.kuadrant.io \
    authorinos.operator.authorino.kuadrant.io \
    kuadrants.kuadrant.io \
    authpolicies.kuadrant.io \
    tokenratelimitpolicies.kuadrant.io; do
    until oc get crd "$crd" &>/dev/null; do
        log_info "Waiting for RHCL CRD: $crd"
        sleep 10
    done
    log_success "RHCL CRD available: $crd"
done

log_step "Re-syncing Step 01 after RHCL CRDs are available"
while [[ "$(oc get applications.argoproj.io "$STEP_NAME" -n openshift-gitops -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)" == "Running" ]]; do
    log_info "Waiting for current Argo CD sync operation to finish..."
    sleep 10
done
oc annotate applications.argoproj.io "$STEP_NAME" -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite || true
oc patch applications.argoproj.io "$STEP_NAME" -n openshift-gitops --type merge -p \
    '{"operation":{"sync":{"prune":true,"syncOptions":["CreateNamespace=true","ServerSideDiff=true","SkipDryRunOnMissingResource=true","RespectIgnoreDifferences=true"]}}}' || true

until oc get kuadrant kuadrant -n kuadrant-system &>/dev/null; do
    log_info "Waiting for Kuadrant custom resource..."
    sleep 10
done

oc wait kuadrant kuadrant -n kuadrant-system --for=condition=Ready --timeout=10m
log_success "Kuadrant ready"

log_step "Enabling Kuadrant observability for MaaS"
oc patch kuadrant kuadrant -n kuadrant-system --type merge \
    -p '{"spec":{"observability":{"enable":true}}}'
log_success "Kuadrant observability enabled"

log_step "Enabling Limitador detailed telemetry for MaaS Usage metrics"
until oc get limitador limitador -n kuadrant-system &>/dev/null; do
    log_info "Waiting for generated Limitador custom resource..."
    sleep 10
done
oc patch limitador limitador -n kuadrant-system --type merge \
    -p '{"spec":{"telemetry":"exhaustive"}}' \
    && log_success "Limitador detailed telemetry enabled" \
    || log_warn "Limitador telemetry patch failed; Step 01 validation will report any drift"
oc rollout status deployment/limitador-limitador -n kuadrant-system --timeout=3m \
    || log_warn "Limitador rollout did not complete before timeout"

log_step "Configuring Authorino TLS for MaaS"
until oc get service authorino-authorino-authorization -n kuadrant-system &>/dev/null; do
    log_info "Waiting for Authorino authorization service..."
    sleep 10
done

oc annotate service authorino-authorino-authorization \
    -n kuadrant-system \
    service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
    --overwrite

until oc get secret authorino-server-cert -n kuadrant-system &>/dev/null; do
    log_info "Waiting for Authorino serving certificate..."
    sleep 5
done

oc patch authorino authorino -n kuadrant-system --type=merge --patch \
    '{"spec":{"listener":{"tls":{"enabled":true,"certSecretRef":{"name":"authorino-server-cert"}}}}}'

oc -n kuadrant-system set env deployment/authorino \
    SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt

oc wait --for=condition=Ready pod -l authorino-resource=authorino -n kuadrant-system --timeout=150s
log_success "Authorino TLS configured"

# Deploy MachineSets (cluster-specific, not in GitOps)
log_step "Deploying GPU MachineSets"

AZ=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.placement.availabilityZone}')
log_info "Detected availability zone: $AZ"

for instance_type in "g6.4xlarge" "g6.12xlarge"; do
    ms_name="${CLUSTER_ID}-gpu-${instance_type//./-}-${AZ}"
    
    # Check if MachineSet already exists
    if oc get machineset -n openshift-machine-api "$ms_name" &>/dev/null; then
        log_info "MachineSet $ms_name already exists, skipping..."
        continue
    fi
    
    case "$instance_type" in
        "g6.4xlarge")
            GPU_COUNT=1
            VCPU=16
            MEMORY_MB=65536
            VOLUME_SIZE=200
            ;;
        "g6.12xlarge")
            GPU_COUNT=4
            VCPU=48
            MEMORY_MB=196608
            VOLUME_SIZE=500
            ;;
    esac

    log_info "Creating MachineSet: $ms_name"
    
    cat <<EOF | oc apply -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  name: ${ms_name}
  namespace: openshift-machine-api
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
  annotations:
    machine.openshift.io/GPU: "${GPU_COUNT}"
    machine.openshift.io/memoryMb: "${MEMORY_MB}"
    machine.openshift.io/vCPU: "${VCPU}"
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${ms_name}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: gpu-worker
        machine.openshift.io/cluster-api-machine-type: gpu-worker
        machine.openshift.io/cluster-api-machineset: ${ms_name}
    spec:
      lifecycleHooks: {}
      metadata:
        labels:
          node-role.kubernetes.io/gpu: ""
      taints:
        - key: nvidia.com/gpu
          value: "true"
          effect: NoSchedule
      providerSpec:
        value:
          apiVersion: machine.openshift.io/v1beta1
          kind: AWSMachineProviderConfig
          ami:
            id: ${AMI_ID}
          instanceType: ${instance_type}
          placement:
            availabilityZone: ${AZ}
            region: ${REGION}
          blockDevices:
            - ebs:
                encrypted: true
                volumeSize: ${VOLUME_SIZE}
                volumeType: gp3
          credentialsSecret:
            name: aws-cloud-credentials
          iamInstanceProfile:
            id: ${CLUSTER_ID}-worker-profile
          securityGroups:
            - filters:
                - name: tag:Name
                  values:
                    - ${CLUSTER_ID}-node
            - filters:
                - name: tag:Name
                  values:
                    - ${CLUSTER_ID}-lb
          subnet:
            filters:
              - name: tag:Name
                values:
                  - ${CLUSTER_ID}-subnet-private-${AZ}
          tags:
            - name: kubernetes.io/cluster/${CLUSTER_ID}
              value: owned
          userDataSecret:
            name: worker-user-data
EOF
done

log_success "GPU MachineSets created"

log_step "Deployment Complete"

echo ""
echo "Operators deployed via GitOps:"
echo "  - User Workload Monitoring"
echo "  - NFD Operator (openshift-nfd)"
echo "  - GPU Operator (nvidia-gpu-operator)"
echo "  - OpenShift Serverless + KnativeServing"
echo "  - Red Hat build of Kueue (openshift-kueue-operator)"
echo "  - Red Hat Connectivity Link stack for Models-as-a-Service"
echo "  - LeaderWorkerSet remains deferred for llm-d distributed inference in docs/BACKLOG.md"
echo ""
echo "MachineSets (replicas=1):"
echo "  - ${CLUSTER_ID}-gpu-g6-4xlarge-${AZ}"
echo "  - ${CLUSTER_ID}-gpu-g6-12xlarge-${AZ}"
echo ""
log_info "Check Argo CD Application status:"
echo "  oc get applications.argoproj.io -n openshift-gitops ${STEP_NAME}"
echo ""
log_info "Check GPU node status:"
echo "  oc get machines -n openshift-machine-api | grep gpu"
echo "  oc get nodes -l node-role.kubernetes.io/gpu"
echo ""
log_info "Validate all operators:"
echo "  oc get csv -n openshift-nfd | grep nfd"
echo "  oc get csv -n nvidia-gpu-operator | grep gpu"
echo "  oc get csv -n openshift-serverless | grep serverless"
echo "  oc get knativeserving -n knative-serving"
echo "  oc get csv -n openshift-kueue-operator"
echo "  oc get crd kueues.kueue.openshift.io"
echo "  oc get kuadrant kuadrant -n kuadrant-system"
