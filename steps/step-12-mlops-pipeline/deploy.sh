#!/bin/bash
# =============================================================================
# Step 12: MLOps Training Pipeline
# =============================================================================
# Deploys the pipeline infrastructure (PVC, RBAC) via ArgoCD.
# The pipeline itself is compiled and uploaded via run-training-pipeline.sh.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-12-mlops-pipeline"
NAMESPACE="private-ai"

load_env
check_oc_logged_in

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 12: MLOps Training Pipeline                                    ║"
echo "║  KFP v2: Train → Evaluate → Register → Deploy                       ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Pre-flight Checks
# =============================================================================
log_step "Checking prerequisites..."

if ! oc get dspa dspa-rag -n "$NAMESPACE" &>/dev/null; then
    log_error "DSPA 'dspa-rag' not found. Run Step-07 first."
    exit 1
fi
log_success "DSPA pipeline server available"

if ! oc get inferenceservice face-recognition -n "$NAMESPACE" &>/dev/null; then
    log_error "InferenceService 'face-recognition' not found. Run Step-11 first."
    exit 1
fi
log_success "face-recognition InferenceService exists"

REGISTRY_ROUTE=$(oc get route private-ai-registry-https -n rhoai-model-registries -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -z "$REGISTRY_ROUTE" ]]; then
    log_warn "Model Registry route not found. Run Step-04 first for full MLOps flow."
else
    log_success "Model Registry: https://$REGISTRY_ROUTE"
fi
echo ""

# =============================================================================
# Deploy via ArgoCD
# =============================================================================
log_step "Creating ArgoCD Application for Step 12..."

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"
log_success "ArgoCD Application '${STEP_NAME}' created"
echo ""

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
echo "  Run the training pipeline:"
echo "    ./steps/step-12-mlops-pipeline/run-training-pipeline.sh"
echo ""
echo "  Watch pipeline runs in RHOAI Dashboard:"
echo "    Data Science Projects → private-ai → Pipelines"
echo ""
log_info "Validate: ./steps/step-12-mlops-pipeline/validate.sh"
echo ""
