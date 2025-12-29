#!/usr/bin/env bash
# =============================================================================
# Step 01: GPU Infrastructure & RHOAI Prerequisites - Deploy Script
# =============================================================================
# Deploys all prerequisites for RHOAI 3.0:
# - User Workload Monitoring
# - NFD Operator + Instance
# - GPU Operator + ClusterPolicy + DCGM Dashboard
# - OpenShift Serverless + KnativeServing
# - LeaderWorkerSet Operator
# - Red Hat Connectivity Link (RHCL, Authorino, Limitador, DNS)
# - GPU MachineSets (AWS)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-01-gpu-and-prereq"

load_env
check_oc_logged_in

log_step "Step 01: GPU Infrastructure & RHOAI Prerequisites"

# Get Git repo info
GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"

log_info "Git Repo: $GIT_REPO_URL"
log_info "Branch: $GIT_REPO_BRANCH"

# Get cluster infrastructure details
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
AMI_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')
REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')

log_info "Cluster ID: $CLUSTER_ID"
log_info "AMI ID: $AMI_ID"
log_info "Region: $REGION"

# =============================================================================
# Deploy via Argo CD Application
# =============================================================================
log_step "Creating Argo CD Application for GPU Infrastructure"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

# =============================================================================
# Wait for critical operators
# =============================================================================
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

log_step "Waiting for LeaderWorkerSet Operator..."
until oc get csv -n openshift-lws-operator 2>/dev/null | grep -q "Succeeded"; do
    log_info "Waiting for LWS Operator..."
    sleep 10
done
log_success "LeaderWorkerSet Operator ready"

log_step "Waiting for Red Hat Connectivity Link (RHCL)..."
until oc get crd authpolicies.kuadrant.io &>/dev/null; do
    log_info "Waiting for RHCL AuthPolicy CRD..."
    sleep 10
done
log_success "RHCL AuthPolicy CRD available"

# =============================================================================
# Deploy MachineSets (cluster-specific, not in GitOps)
# =============================================================================
log_step "Deploying GPU MachineSets"

for instance_type in "g6.4xlarge" "g6.12xlarge"; do
    ms_name="${CLUSTER_ID}-gpu-${instance_type//./-}-${REGION}b"
    
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
            availabilityZone: ${REGION}b
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
                  - ${CLUSTER_ID}-subnet-private-${REGION}b
          tags:
            - name: kubernetes.io/cluster/${CLUSTER_ID}
              value: owned
          userDataSecret:
            name: worker-user-data
EOF
done

log_success "GPU MachineSets created"

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
echo "Operators deployed via GitOps:"
echo "  - User Workload Monitoring"
echo "  - NFD Operator (openshift-nfd)"
echo "  - GPU Operator (nvidia-gpu-operator)"
echo "  - OpenShift Serverless + KnativeServing"
echo "  - LeaderWorkerSet (openshift-lws-operator)"
echo "  - Authorino (openshift-authorino)"
echo "  - Limitador (openshift-limitador-operator)"
echo "  - DNS Operator (openshift-dns-operator)"
echo "  - Red Hat Connectivity Link (rhcl-operator)"
echo ""
echo "MachineSets (replicas=1):"
echo "  - ${CLUSTER_ID}-gpu-g6-4xlarge-${REGION}b"
echo "  - ${CLUSTER_ID}-gpu-g6-12xlarge-${REGION}b"
echo ""
log_info "Check Argo CD Application status:"
echo "  oc get applications -n openshift-gitops ${STEP_NAME}"
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
echo "  oc get csv -n openshift-lws-operator | grep leader"
echo "  oc get csv -n rhcl-operator | grep rhcl"
echo "  oc get crd authpolicies.kuadrant.io"
