#!/usr/bin/env bash
# =============================================================================
# Step 01: GPU Infrastructure - Deploy Script
# =============================================================================
# Deploys:
# - NFD Operator + Instance
# - GPU Operator + ClusterPolicy
# - DCGM Dashboard
# - GPU MachineSets (AWS)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

load_env
check_oc_logged_in

log_step "Step 01: GPU Infrastructure"

# Get cluster infrastructure details
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
AMI_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')
REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')

log_info "Cluster ID: $CLUSTER_ID"
log_info "AMI ID: $AMI_ID"
log_info "Region: $REGION"

# =============================================================================
# Deploy Operators
# =============================================================================
log_step "Deploying NFD + GPU Operator"

# Apply base manifests (namespaces, operatorgroups, subscriptions)
oc apply -f "$REPO_ROOT/gitops/step-01-gpu/base/nfd/namespace.yaml"
oc apply -f "$REPO_ROOT/gitops/step-01-gpu/base/nfd/operatorgroup.yaml"
oc apply -f "$REPO_ROOT/gitops/step-01-gpu/base/nfd/subscription.yaml"

oc apply -f "$REPO_ROOT/gitops/step-01-gpu/base/gpu-operator/namespace.yaml"
oc apply -f "$REPO_ROOT/gitops/step-01-gpu/base/gpu-operator/operatorgroup.yaml"
oc apply -f "$REPO_ROOT/gitops/step-01-gpu/base/gpu-operator/subscription.yaml"

# Apply DCGM Dashboard
oc apply -f "$REPO_ROOT/gitops/step-01-gpu/base/gpu-operator/dcgm-dashboard-configmap.yaml"

log_success "Operator subscriptions created"

# Wait for NFD operator
log_info "Waiting for NFD operator..."
until oc get crd nodefeaturediscoveries.nfd.openshift.io &>/dev/null; do
    sleep 5
done
log_success "NFD CRD available"

# Apply NFD instance
oc apply -f "$REPO_ROOT/gitops/step-01-gpu/base/nfd/instance.yaml"
log_success "NFD instance created"

# Wait for GPU operator
log_info "Waiting for GPU operator..."
until oc get crd clusterpolicies.nvidia.com &>/dev/null; do
    sleep 5
done
log_success "GPU Operator CRD available"

# Apply ClusterPolicy
oc apply -f "$REPO_ROOT/gitops/step-01-gpu/base/gpu-operator/clusterpolicy.yaml"
log_success "ClusterPolicy created"

# =============================================================================
# Deploy MachineSets
# =============================================================================
log_step "Deploying GPU MachineSets"

for instance_type in "g6.4xlarge" "g6.12xlarge"; do
    ms_name="${CLUSTER_ID}-gpu-${instance_type//./-}-${REGION}b"
    
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
        machine.openshift.io/cluster-api-machine-type: ${instance_type//./-}
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
echo "Operators:"
echo "  - NFD Operator (openshift-nfd)"
echo "  - GPU Operator (nvidia-gpu-operator)"
echo "  - ClusterPolicy: gpu-cluster-policy"
echo "  - DCGM Dashboard: Observe → Dashboards"
echo ""
echo "MachineSets (replicas=1):"
echo "  - ${CLUSTER_ID}-gpu-g6-4xlarge-${REGION}b"
echo "  - ${CLUSTER_ID}-gpu-g6-12xlarge-${REGION}b"
echo ""
log_info "Check GPU node status:"
echo "  oc get machines -n openshift-machine-api | grep gpu"
echo "  oc get nodes -l node-role.kubernetes.io/gpu"
