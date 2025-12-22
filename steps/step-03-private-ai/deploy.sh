#!/usr/bin/env bash
# =============================================================================
# Step 03: Private AI - Deploy Script
# =============================================================================
# Deploys private LLM models using RHOAI 3.0 model serving
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-03-private-ai"

load_env
check_oc_logged_in

log_step "Step 03: Private AI"

# =============================================================================
# Prerequisites check
# =============================================================================
log_step "Checking prerequisites..."

# Check step-02-rhoai was deployed
if ! oc get applications -n openshift-gitops step-02-rhoai &>/dev/null; then
    log_error "step-02-rhoai Argo CD Application not found!"
    log_info "Please run: ./steps/step-02-rhoai/deploy.sh first"
    exit 1
fi

# Check DSC is ready
DSC_PHASE=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$DSC_PHASE" != "Ready" ]]; then
    log_error "DataScienceCluster is not Ready (current: $DSC_PHASE)"
    exit 1
fi

log_success "Prerequisites verified"

# =============================================================================
# Create HuggingFace token secret if provided
# =============================================================================
if [[ -n "${HF_TOKEN:-}" ]]; then
    log_step "Creating HuggingFace token secret..."
    ensure_namespace "rhoai-models"
    ensure_secret_from_env "hf-token" "rhoai-models" "token=${HF_TOKEN}"
    log_success "HuggingFace token secret created"
else
    log_warn "HF_TOKEN not set - gated models (e.g., Llama) won't be accessible"
fi

# =============================================================================
# Deploy via Argo CD Application
# =============================================================================
log_step "Creating Argo CD Application for Private AI"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
log_info "Argo CD Application status:"
echo "  oc get applications -n openshift-gitops ${STEP_NAME}"
echo ""
log_info "Check InferenceServices:"
echo "  oc get inferenceservice -n rhoai-models"
echo ""
