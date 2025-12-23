#!/usr/bin/env bash
# =============================================================================
# Step 05: LLM Inference with vLLM
# =============================================================================
# Deploys the Granite 3.1 8B Instruct FP8 model to a KServe inference endpoint.
#
# Components:
# - vLLM ServingRuntime
# - InferenceService for Granite 3.1
# - GPU allocation via Kueue
#
# TODO: Implement deployment logic
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-05-llm-on-vllm"

load_env
check_oc_logged_in

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 05: LLM Inference with vLLM                                    ║"
echo "║  Deploying Granite 3.1 8B to KServe                                  ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Prerequisites check
# =============================================================================
log_step "Checking prerequisites..."

# Check step-04 was deployed
if ! oc get applications -n openshift-gitops step-04-model-registry &>/dev/null; then
    log_error "step-04-model-registry Argo CD Application not found!"
    log_info "Please run: ./steps/step-04-model-registry/deploy.sh first"
    exit 1
fi

# Check model is registered
if ! oc run check-model --rm -i --restart=Never --image=curlimages/curl -n rhoai-model-registries -- \
    curl -sf http://private-ai-registry-internal:8080/api/model_registry/v1alpha3/registered_models 2>/dev/null | grep -q "Granite"; then
    log_warn "Granite model may not be registered in Model Registry"
fi

log_success "Prerequisites verified"

# =============================================================================
# Deploy via Argo CD Application
# =============================================================================
log_step "Creating Argo CD Application for LLM Inference"

# TODO: Uncomment when manifests are ready
# oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_warn "Step 05 is a placeholder - manifests not yet implemented"
log_info "TODO: Implement vLLM ServingRuntime and InferenceService"

# =============================================================================
# TODO: Wait for InferenceService
# =============================================================================
# log_step "Waiting for InferenceService..."
# 
# TIMEOUT=600
# ELAPSED=0
# until oc get inferenceservice granite-3-1-8b-instruct -n private-ai -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; do
#     if [[ $ELAPSED -ge $TIMEOUT ]]; then
#         log_warn "InferenceService taking longer than expected"
#         break
#     fi
#     log_info "Waiting for model to load... (${ELAPSED}s)"
#     sleep 30
#     ELAPSED=$((ELAPSED + 30))
# done

# =============================================================================
# Summary
# =============================================================================
log_step "Placeholder Created"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 05: LLM Inference - PLACEHOLDER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "TODO:"
echo "  • Implement vLLM ServingRuntime manifest"
echo "  • Implement InferenceService manifest"
echo "  • Configure model loading from MinIO"
echo "  • Integrate with Kueue for GPU scheduling"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

