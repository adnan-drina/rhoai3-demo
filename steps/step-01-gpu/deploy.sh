#!/usr/bin/env bash
# =============================================================================
# Step 01: GPU Infrastructure - Deploy Script
# =============================================================================
# Deploys NFD, GPU Operator, and GPU MachineSets via GitOps
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-01-gpu"
GITOPS_PATH="gitops/step-01-gpu/overlays/aws"

load_env
check_oc_logged_in

log_step "Step 01: GPU Infrastructure"

# Get cluster infrastructure details
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
AMI_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')

log_info "Cluster ID: $CLUSTER_ID"
log_info "AMI ID: $AMI_ID"

# Template the MachineSet manifests
log_step "Templating MachineSet manifests"
MACHINESET_DIR="$REPO_ROOT/gitops/step-01-gpu/overlays/aws/machinesets"

for f in "$MACHINESET_DIR"/*.yaml; do
    sed -i.bak \
        -e "s/CLUSTER_ID/$CLUSTER_ID/g" \
        -e "s/AMI_ID/$AMI_ID/g" \
        "$f"
    rm -f "$f.bak"
    log_info "Templated: $(basename "$f")"
done

# Validate kustomize build
log_step "Validating Kustomize build"
oc kustomize "$REPO_ROOT/$GITOPS_PATH" > /dev/null
log_success "Kustomize validation passed"

# Apply Argo CD Application
log_step "Deploying Argo CD Application"
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $STEP_NAME
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: rhoai-demo
  source:
    repoURL: ${GIT_REPO_URL:-https://github.com/YOUR_ORG/rhoai3-demo.git}
    targetRevision: ${GIT_REPO_BRANCH:-main}
    path: $GITOPS_PATH
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

log_success "Application $STEP_NAME deployed"

# Print next steps
echo ""
log_info "MachineSets created with replicas=0"
log_info "To scale GPU nodes:"
log_info "  oc scale machineset $CLUSTER_ID-gpu-g6-4xlarge-us-east-2b -n openshift-machine-api --replicas=1"
log_info "  oc scale machineset $CLUSTER_ID-gpu-g6-12xlarge-us-east-2b -n openshift-machine-api --replicas=1"
