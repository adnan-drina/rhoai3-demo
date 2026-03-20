#!/bin/bash
# =============================================================================
# Step 05: LLM Serving on vLLM
# =============================================================================
# Deploys 2 Red Hat Validated models with GPU scheduling:
#   1. granite-8b-agent  (1-GPU, OCI ModelCar, FP8 — RAG, MCP, Guardrails)
#   2. mistral-3-bf16    (4-GPU, S3/MinIO, BF16 — Playground, Eval judge)
#
# 3 additional models are registered in the Model Registry (seed job) and
# can be deployed from GenAI Studio when needed.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-05-llm-on-vllm"
NAMESPACE="private-ai"

load_env
check_oc_logged_in

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 05: LLM Serving on vLLM                                        ║"
echo "║  2 Active Models on GPU Nodes                                         ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Pre-flight Checks
# =============================================================================
log_step "Checking prerequisites..."

if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    log_error "'private-ai' namespace does not exist. Run Step-03 first."
    exit 1
fi
log_success "Namespace '$NAMESPACE' exists"

if ! oc get deployment minio -n minio-storage &>/dev/null; then
    log_error "MinIO not found. Run Step-03 first."
    exit 1
fi
log_success "MinIO storage available"

if ! oc get secret minio-connection -n "$NAMESPACE" &>/dev/null; then
    log_error "minio-connection secret not found. Run Step-03 first."
    exit 1
fi
log_success "minio-connection secret exists"

GPU_NODES=$(oc get nodes -l nvidia.com/gpu.product=NVIDIA-L4 --no-headers 2>/dev/null | wc -l | tr -d ' ')
log_info "GPU nodes available: ${GPU_NODES}"
echo ""

# =============================================================================
# Model Portfolio Summary
# =============================================================================
log_step "Model Portfolio (5 GPUs Total)"
echo ""
echo "  granite-8b-agent   1-GPU  OCI  FP8   RAG/MCP/Guardrails/Eval candidate"
echo "  mistral-3-bf16     4-GPU  S3   BF16  Playground chat/Eval judge"
echo ""

# =============================================================================
# Create HF token secret (upload jobs need this before ArgoCD sync)
# =============================================================================
log_step "Ensuring HuggingFace token secret exists..."

if [[ -n "${HF_TOKEN:-}" ]]; then
    oc create secret generic hf-token -n minio-storage \
        --from-literal=token="$HF_TOKEN" \
        --dry-run=client -o yaml | oc apply -f - 2>/dev/null
    log_success "hf-token secret ready in minio-storage"
else
    log_warn "HF_TOKEN not set in .env — uploads will use unauthenticated HF access (slower)"
fi

# =============================================================================
# Upload mistral-3-bf16 model to MinIO (must complete before ISVC creation)
# =============================================================================
log_step "Ensuring mistral-3-bf16 model is in MinIO..."

UPLOAD_YAML="$REPO_ROOT/gitops/step-05-llm-on-vllm/base/model-upload/upload-mistral-bf16.yaml"
UPLOAD_NS="minio-storage"

EXISTING=$(oc get job upload-mistral-bf16 -n "$UPLOAD_NS" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "")
if [[ "$EXISTING" == "1" ]]; then
    log_success "Upload job already completed — model in MinIO"
else
    oc delete job upload-mistral-bf16 -n "$UPLOAD_NS" 2>/dev/null || true
    oc apply -f "$UPLOAD_YAML"
    log_info "Upload job started — waiting for completion (15-25 min for 48GB model)..."
    TIMEOUT=1800
    ELAPSED=0
    while [[ $ELAPSED -lt $TIMEOUT ]]; do
        STATUS=$(oc get job upload-mistral-bf16 -n "$UPLOAD_NS" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "")
        if [[ "$STATUS" == "1" ]]; then
            log_success "Model upload completed"
            break
        fi
        FAILED=$(oc get job upload-mistral-bf16 -n "$UPLOAD_NS" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
        if [[ "${FAILED:-0}" -ge 3 ]]; then
            log_error "Upload job failed after $FAILED attempts — check: oc logs job/upload-mistral-bf16 -n $UPLOAD_NS"
            break
        fi
        sleep 30
        ELAPSED=$((ELAPSED + 30))
        if (( ELAPSED % 120 == 0 )); then
            log_info "  Upload in progress... (${ELAPSED}s elapsed)"
        fi
    done
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        log_warn "Upload job did not complete within ${TIMEOUT}s — ISVC may CrashLoop until upload finishes"
    fi
fi
echo ""

# =============================================================================
# Deploy via ArgoCD
# =============================================================================
log_step "Creating ArgoCD Application for Step 05..."

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"
log_success "ArgoCD Application '${STEP_NAME}' created"
echo ""

# =============================================================================
# AI Asset Labels for GenAI Playground
# =============================================================================
log_step "Applying AI Asset labels for GenAI Playground..."

MODELS="mistral-3-bf16 granite-8b-agent"

get_use_case() {
    case "$1" in
        mistral-3-bf16)     echo "enterprise chat assistant" ;;
        granite-8b-agent)   echo "agentic tool-calling" ;;
    esac
}

for model in $MODELS; do
    use_case="$(get_use_case "$model")"
    if oc get inferenceservice "${model}" -n "$NAMESPACE" &>/dev/null; then
        oc patch inferenceservice "${model}" -n "$NAMESPACE" --type=merge -p "{
          \"metadata\": {
            \"labels\": {
              \"opendatahub.io/genai-asset\": \"true\"
            },
            \"annotations\": {
              \"opendatahub.io/model-type\": \"generative\",
              \"opendatahub.io/genai-use-case\": \"${use_case}\",
              \"security.opendatahub.io/enable-auth\": \"false\"
            }
          }
        }" &>/dev/null
        log_success "${model} labeled (${use_case})"
    fi
done
echo ""

# =============================================================================
# Link InferenceServices to Model Registry entries
# Registry IDs are dynamic (assigned by seed job), so we query them at runtime.
# =============================================================================
log_step "Linking InferenceServices to Model Registry..."

REGISTRY_ROUTE=$(oc get route private-ai-registry-https -n rhoai-model-registries \
    -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [[ -n "$REGISTRY_ROUTE" ]]; then
    TOKEN=$(oc whoami -t 2>/dev/null || echo "")
    API_BASE="https://${REGISTRY_ROUTE}/api/model_registry/v1alpha3"

    # Registry-name → ISVC-name mapping
    declare -A REGISTRY_MAP=(
        ["Granite-3.1-8B-Agent"]="granite-8b-agent"
        ["Mistral-3-BF16"]="mistral-3-bf16"
    )

    MODELS_JSON=$(curl -sk -H "Authorization: Bearer $TOKEN" \
        "${API_BASE}/registered_models" 2>/dev/null || echo '{"items":[]}')

    for REG_NAME in "${!REGISTRY_MAP[@]}"; do
        ISVC_NAME="${REGISTRY_MAP[$REG_NAME]}"

        RM_ID=$(echo "$MODELS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for m in data.get('items', []):
    if m['name'] == '${REG_NAME}':
        print(m['id']); break
else:
    print('')
" 2>/dev/null)

        if [[ -z "$RM_ID" ]]; then
            log_warn "  ${REG_NAME} not found in registry — skipping"
            continue
        fi

        # Get latest version for this model
        VERSIONS_JSON=$(curl -sk -H "Authorization: Bearer $TOKEN" \
            "${API_BASE}/model_versions?registeredModelId=${RM_ID}" 2>/dev/null || echo '{"items":[]}')

        MV_ID=$(echo "$VERSIONS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
versions = [v for v in data.get('items', []) if v.get('registeredModelId') == '${RM_ID}']
if versions:
    print(sorted(versions, key=lambda v: v['id'], reverse=True)[0]['id'])
else:
    print('')
" 2>/dev/null)

        if [[ -z "$MV_ID" ]]; then
            log_warn "  ${REG_NAME} has no versions — skipping"
            continue
        fi

        if oc get inferenceservice "$ISVC_NAME" -n "$NAMESPACE" &>/dev/null; then
            oc patch inferenceservice "$ISVC_NAME" -n "$NAMESPACE" --type=merge -p "{
              \"metadata\": {
                \"labels\": {
                  \"modelregistry.opendatahub.io/registered-model-id\": \"${RM_ID}\",
                  \"modelregistry.opendatahub.io/model-version-id\": \"${MV_ID}\"
                }
              }
            }" &>/dev/null
            log_success "${ISVC_NAME} → registry model=${RM_ID} version=${MV_ID}"
        fi
    done
else
    log_warn "Model Registry route not found — skipping ISVC linking"
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
echo "  Watch model status:"
echo "    oc get inferenceservice -n $NAMESPACE -w"
echo ""
echo "  GenAI Playground:"
echo "    1. RHOAI Dashboard → GenAI Studio → Playground"
echo "    2. Select 'Private AI - GPU as a Service' project"
echo "    3. Create playground with RUNNING models only"
echo ""
log_info "Validate: ./steps/step-05-llm-on-vllm/validate.sh"
echo ""
