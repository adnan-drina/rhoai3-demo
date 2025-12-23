#!/usr/bin/env bash
# =============================================================================
# Step 05: High-Efficiency LLM Inference with vLLM
# =============================================================================
# Deploys Mistral-Small-24B in two configurations:
# - Full precision (BF16) on 4x NVIDIA L4 GPUs
# - FP8 quantized on 1x NVIDIA L4 GPU (Neural Magic optimized)
#
# This demonstrates the cost-efficiency of FP8 quantization on Ada Lovelace.
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
echo "║  Step 05: High-Efficiency LLM Inference                              ║"
echo "║  Mistral-24B with FP8 Quantization on NVIDIA L4                      ║"
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

# Check Model Registry is available
if ! oc get modelregistry.modelregistry.opendatahub.io private-ai-registry -n rhoai-model-registries &>/dev/null; then
    log_error "Model Registry 'private-ai-registry' not found!"
    exit 1
fi

# Check MinIO has model artifacts
if ! oc get pods -n minio-storage -l app=minio --no-headers 2>/dev/null | grep -q Running; then
    log_warn "MinIO not running - model artifacts may not be available"
fi

# Check GPU nodes available
GPU_NODES=$(oc get nodes -l nvidia.com/gpu.product=NVIDIA-L4 --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$GPU_NODES" -lt 1 ]]; then
    log_warn "No NVIDIA L4 GPU nodes found - inference will be pending"
else
    log_info "Found ${GPU_NODES} NVIDIA L4 GPU node(s)"
fi

log_success "Prerequisites verified"

# =============================================================================
# Deploy via Argo CD Application
# =============================================================================
log_step "Creating Argo CD Application for LLM Inference"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

# =============================================================================
# Wait for Model Registration
# =============================================================================
log_step "Waiting for Mistral model registration..."

TIMEOUT=180
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    JOB_STATUS=$(oc get job mistral-model-registration -n rhoai-model-registries -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$JOB_STATUS" == "1" ]]; then
        log_success "Mistral models registered"
        break
    fi
    log_info "Waiting for model registration... (${ELAPSED}s)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log_warn "Model registration taking longer than expected"
    log_info "Check: oc logs job/mistral-model-registration -n rhoai-model-registries"
fi

# =============================================================================
# Wait for ServingRuntime
# =============================================================================
log_step "Waiting for vLLM ServingRuntime..."

TIMEOUT=60
ELAPSED=0
until oc get servingruntime vllm-mistral-runtime -n private-ai &>/dev/null; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        log_warn "ServingRuntime not found yet"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
log_success "vLLM ServingRuntime ready"

# =============================================================================
# Wait for InferenceServices
# =============================================================================
log_step "Waiting for InferenceServices..."

# Wait for FP8 deployment (primary demo)
log_info "Waiting for mistral-24b-fp8 (FP8 quantized, 1-GPU)..."
TIMEOUT=600
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    READY=$(oc get inferenceservice mistral-24b-fp8 -n private-ai -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [[ "$READY" == "True" ]]; then
        log_success "mistral-24b-fp8 is ready"
        break
    fi
    log_info "Waiting for model to load... (${ELAPSED}s) - this may take several minutes"
    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

# Check BF16 deployment (optional, requires 4 GPUs)
log_info "Checking mistral-24b-full (BF16, 4-GPU)..."
FULL_READY=$(oc get inferenceservice mistral-24b-full -n private-ai -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [[ "$FULL_READY" == "True" ]]; then
    log_success "mistral-24b-full is ready"
else
    log_warn "mistral-24b-full not ready (requires 4 GPUs)"
fi

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

DASHBOARD_URL=$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')
FP8_URL=$(oc get route mistral-24b-fp8 -n private-ai -o jsonpath='{.spec.host}' 2>/dev/null || echo 'pending...')
FULL_URL=$(oc get route mistral-24b-full -n private-ai -o jsonpath='{.spec.host}' 2>/dev/null || echo 'pending...')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "High-Efficiency LLM Inference Deployed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Deployments:"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────────┐"
echo "  │ mistral-24b-fp8 (RECOMMENDED)                                       │"
echo "  │   Precision: FP8 (Neural Magic optimized)                           │"
echo "  │   GPUs:      1x NVIDIA L4 (~15GB VRAM)                              │"
echo "  │   Cost:      ~\$1.00/hr on AWS                                       │"
echo "  │   URL:       https://${FP8_URL}"
echo "  └─────────────────────────────────────────────────────────────────────┘"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────────┐"
echo "  │ mistral-24b-full                                                    │"
echo "  │   Precision: BF16 (full precision)                                  │"
echo "  │   GPUs:      4x NVIDIA L4 (tensor parallel)                         │"
echo "  │   Cost:      ~\$4.00/hr on AWS                                       │"
echo "  │   URL:       https://${FULL_URL}"
echo "  └─────────────────────────────────────────────────────────────────────┘"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Test the FP8 endpoint:"
echo ""
echo "  curl -X POST \"https://${FP8_URL}/v1/chat/completions\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"model\": \"mistral-24b-fp8\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}]}'"
echo ""
log_info "Validation Commands:"
echo ""
echo "  # Check InferenceServices"
echo "  oc get inferenceservice -n private-ai"
echo ""
echo "  # Check GPU usage"
echo "  oc get pods -n private-ai -l serving.kserve.io/inferenceservice -o wide"
echo ""
echo "  # Check registered models"
echo "  oc logs job/mistral-model-registration -n rhoai-model-registries"
echo ""
log_info "Dashboard: https://${DASHBOARD_URL}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Key Insight: FP8 delivers 4x cost reduction with near-identical accuracy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
