#!/usr/bin/env bash
# =============================================================================
# Step 02: Red Hat OpenShift AI 3.0 - Deploy Script
# =============================================================================
# Deploys RHOAI 3.0 Platform Layer:
# - RHOAI Operator (fast-3.x channel)
# - DSCInitialization (Service Mesh: Managed)
# - DataScienceCluster with full 3.0 components
# - Auth resource for user/admin groups
# - GenAI Studio configuration
# - Hardware Profiles for AWS G6 GPU nodes
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-02-rhoai"

load_env
check_oc_logged_in

log_step "Step 02: Red Hat OpenShift AI 3.0"

# =============================================================================
# Prerequisites check
# =============================================================================
log_step "Checking prerequisites..."

# Check step-01-gpu-and-prereq was deployed
if ! oc get applications -n openshift-gitops step-01-gpu-and-prereq &>/dev/null; then
    log_error "step-01-gpu-and-prereq Argo CD Application not found!"
    log_info "Please run: ./steps/step-01-gpu-and-prereq/deploy.sh first"
    exit 1
fi

# Check Serverless is ready (required for KServe)
if ! oc get knativeserving -n knative-serving knative-serving &>/dev/null; then
    log_error "KnativeServing not found - required for KServe"
    log_info "Please ensure step-01-gpu-and-prereq is fully synced"
    exit 1
fi

# Check GPU nodes exist
GPU_NODES=$(oc get nodes -l node-role.kubernetes.io/gpu --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$GPU_NODES" -eq 0 ]]; then
    log_warn "No GPU nodes found with label 'node-role.kubernetes.io/gpu'"
    log_info "Hardware Profiles will be ready but won't schedule until GPU nodes are available"
fi

log_success "Prerequisites verified"

# =============================================================================
# Deploy via Argo CD Application
# =============================================================================
log_step "Creating Argo CD Application for RHOAI"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

# =============================================================================
# Wait for operator
# =============================================================================
log_step "Waiting for RHOAI Operator..."

# Wait for namespace
until oc get namespace redhat-ods-operator &>/dev/null; do
    log_info "Waiting for namespace redhat-ods-operator..."
    sleep 10
done

# Wait for CSV to succeed
log_info "Waiting for RHOAI Operator CSV (this may take a few minutes)..."
until oc get csv -n redhat-ods-operator -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift AI")].status.phase}' 2>/dev/null | grep -q "Succeeded"; do
    sleep 15
done
log_success "RHOAI Operator installed"

# Wait for RHOAI 3.0 CRDs
log_info "Waiting for DSCInitialization CRD..."
until oc get crd dscinitializations.dscinitialization.opendatahub.io &>/dev/null; do
    sleep 5
done
log_success "DSCInitialization CRD available"

log_info "Waiting for DataScienceCluster CRD..."
until oc get crd datascienceclusters.datasciencecluster.opendatahub.io &>/dev/null; do
    sleep 5
done
log_success "DataScienceCluster CRD available"

# Wait for DSC to be created
log_info "Waiting for DataScienceCluster to be created..."
until oc get datasciencecluster default-dsc &>/dev/null; do
    sleep 10
done
log_success "DataScienceCluster created"

# Wait for DSC to be Ready
log_info "Waiting for DataScienceCluster to become Ready (this may take several minutes)..."
until [[ "$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null)" == "Ready" ]]; do
    PHASE=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    log_info "Current phase: $PHASE"
    sleep 30
done
log_success "DataScienceCluster is Ready"

# =============================================================================
# Verify Hardware Profiles
# =============================================================================
log_step "Verifying Hardware Profiles..."

# Wait for hardware profiles
until oc get hardwareprofiles -n redhat-ods-applications --no-headers 2>/dev/null | grep -q .; do
    sleep 5
done

PROFILES=$(oc get hardwareprofiles -n redhat-ods-applications -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
log_success "Hardware Profiles available: $PROFILES"

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "RHOAI 3.0 Platform Deployed Successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Enabled Components:"
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components}' 2>/dev/null | \
  jq -r 'to_entries | .[] | "  • \(.key): \(.value.managementState)"' 2>/dev/null || \
  echo "  (use 'oc get datasciencecluster default-dsc -o yaml' to view)"
echo ""
echo "Hardware Profiles:"
oc get hardwareprofiles -n redhat-ods-applications \
  -o custom-columns=NAME:.metadata.name,DISPLAY:.metadata.annotations."opendatahub\.io/display-name" 2>/dev/null || \
  echo "  (use 'oc get hardwareprofiles -n redhat-ods-applications' to view)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Argo CD Application status:"
echo "  oc get applications -n openshift-gitops ${STEP_NAME}"
echo ""
log_info "RHOAI status:"
echo "  oc get datasciencecluster default-dsc"
echo "  oc get pods -n redhat-ods-applications"
echo ""
log_info "Dashboard URL:"
DASHBOARD_URL=$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')
echo "  https://${DASHBOARD_URL}"
echo ""
