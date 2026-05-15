#!/usr/bin/env bash
# Step 01: GPU Infrastructure & RHOAI Prerequisites - Deploy Script
# Deploys all prerequisites for RHOAI 3.4:
# - User Workload Monitoring
# - NFD Operator + Instance
# - GPU Operator + ClusterPolicy + DCGM Dashboard
# - OpenShift Serverless + KnativeServing
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

log_step "Waiting for Red Hat build of Kueue Operator..."
wait_for_csv "kueue-operator" "openshift-kueue-operator" "Kueue Operator"

log_step "Waiting for Kueue CRD..."
until oc get crd kueues.kueue.openshift.io &>/dev/null; do
    log_info "Waiting for Kueue CRD..."
    sleep 10
done
log_success "Kueue CRD available"

log_step "Waiting for Red Hat Connectivity Link stack..."
wait_for_csv "authorino-operator" "openshift-authorino" "Authorino Operator"
wait_for_csv "limitador-operator" "openshift-limitador-operator" "Limitador Operator"
wait_for_csv "dns-operator" "openshift-dns-operator" "DNS Operator"
wait_for_csv "rhcl-operator" "openshift-operators" "Red Hat Connectivity Link Operator"

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
while [[ "$(oc get application "$STEP_NAME" -n openshift-gitops -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)" == "Running" ]]; do
    log_info "Waiting for current Argo CD sync operation to finish..."
    sleep 10
done
oc annotate application "$STEP_NAME" -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite || true
oc patch application "$STEP_NAME" -n openshift-gitops --type merge -p \
    '{"operation":{"sync":{"prune":true,"syncOptions":["CreateNamespace=true","ServerSideDiff=true","SkipDryRunOnMissingResource=true","RespectIgnoreDifferences=true"]}}}' || true

until oc get kuadrant kuadrant -n kuadrant-system &>/dev/null; do
    log_info "Waiting for Kuadrant custom resource..."
    sleep 10
done

oc wait kuadrant kuadrant -n kuadrant-system --for=condition=Ready --timeout=10m
log_success "Kuadrant ready"

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

oc wait --for=condition=ready pod -l authorino-resource=authorino -n kuadrant-system --timeout=150s
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
echo "  - LeaderWorkerSet remains deferred for llm-d distributed inference in BACKLOG.md"
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
