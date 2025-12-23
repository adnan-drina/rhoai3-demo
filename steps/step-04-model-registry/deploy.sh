#!/usr/bin/env bash
# =============================================================================
# Step 04: Model Registry
# =============================================================================
# Deploys Model Registry infrastructure:
# - Model Registry CR
# - PostgreSQL database for metadata
# - S3 integration with MinIO
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-04-model-registry"

load_env
check_oc_logged_in

log_step "Step 04: Model Registry"

# =============================================================================
# Prerequisites check
# =============================================================================
log_step "Checking prerequisites..."

# Check step-03-private-ai was deployed
if ! oc get applications -n openshift-gitops step-03-private-ai &>/dev/null; then
    log_error "step-03-private-ai Argo CD Application not found!"
    log_info "Please run: ./steps/step-03-private-ai/deploy.sh first"
    exit 1
fi

# Check MinIO is available
if ! oc get pods -n minio-storage -l app=minio --no-headers 2>/dev/null | grep -q Running; then
    log_warn "MinIO not running in minio-storage namespace"
    log_info "Model Registry requires S3 storage for artifacts"
fi

log_success "Prerequisites verified"

# =============================================================================
# Deploy via Argo CD Application
# =============================================================================
log_step "Creating Argo CD Application for Model Registry"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

# =============================================================================
# TODO: Add resource verification
# =============================================================================
log_warn "Step 04 is a placeholder - implementation pending"

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete (Placeholder)"

DASHBOARD_URL=$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Model Registry - Placeholder"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_warn "This step is not yet implemented."
echo ""
log_info "Coming soon:"
echo "  • Model Registry CR deployment"
echo "  • PostgreSQL database for metadata"
echo "  • S3 integration with MinIO"
echo "  • Dashboard integration"
echo ""
log_info "RHOAI Dashboard:"
echo "  https://${DASHBOARD_URL}"
echo ""

