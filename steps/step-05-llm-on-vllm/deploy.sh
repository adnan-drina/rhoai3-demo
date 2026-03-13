#!/bin/bash
# =============================================================================
# Step 05: GPU-as-a-Service Demo
# =============================================================================
# Deploys 5 Red Hat Validated models with Kueue-managed GPU allocation:
#
#   Active (minReplicas: 1):
#     1. granite-8b-agent   (1-GPU, S3, FP8 — RAG, MCP, Guardrails workhorse)
#     2. mistral-3-bf16     (4-GPU, S3, BF16 full precision)
#
#   Queued (minReplicas: 0):
#     3. mistral-3-int4     (1-GPU, OCI ModelCar, INT4 W4A16)
#     4. devstral-2         (4-GPU, S3, Agentic tool-calling)
#     5. gpt-oss-20b        (4-GPU, S3, High-reasoning)
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
echo "║  Step 05: GPU-as-a-Service Demo                                      ║"
echo "║  5 Red Hat Validated Models with Kueue Quota Management              ║"
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

if oc get clusterqueue rhoai-main-queue &>/dev/null; then
    log_success "Kueue ClusterQueue 'rhoai-main-queue' exists"
else
    log_warn "Kueue ClusterQueue not found (required for quota management)"
fi

GPU_NODES=$(oc get nodes -l nvidia.com/gpu.product=NVIDIA-L4 --no-headers 2>/dev/null | wc -l | tr -d ' ')
log_info "Current GPU nodes: ${GPU_NODES}"
echo ""

# =============================================================================
# Model Portfolio Summary
# =============================================================================
log_step "Model Portfolio (5 GPUs Total)"
echo ""
echo "  Active (minReplicas: 1):"
echo "    granite-8b-agent   1-GPU  S3   FP8   RAG/MCP/Guardrails"
echo "    mistral-3-bf16     4-GPU  S3   BF16  Enterprise chat"
echo ""
echo "  Queued (minReplicas: 0):"
echo "    mistral-3-int4     1-GPU  OCI  INT4  Cost-optimized chat"
echo "    devstral-2         4-GPU  S3   BF16  Agentic coding"
echo "    gpt-oss-20b        4-GPU  S3   BF16  Complex reasoning"
echo ""

# =============================================================================
# Confirmation
# =============================================================================
if [[ "${CONFIRM:-}" == "true" ]]; then
    REPLY=y
else
    read -p "Continue with deployment? (y/n) " -n 1 -r
    echo ""
fi
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Deployment cancelled."
    exit 0
fi

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

set +u
declare -A MODEL_USE_CASES=(
    ["mistral-3-int4"]="chat assistant"
    ["mistral-3-bf16"]="enterprise chat assistant"
    ["devstral-2"]="agentic coding assistant"
    ["gpt-oss-20b"]="complex reasoning"
    ["granite-8b-agent"]="agentic tool-calling"
)

for model in "${!MODEL_USE_CASES[@]}"; do
    use_case="${MODEL_USE_CASES[$model]}"
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
set -u
echo ""

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
echo "  Watch model status:"
echo "    oc get inferenceservice -n $NAMESPACE -w"
echo "    oc get workload -n $NAMESPACE -w"
echo ""
echo "  GenAI Playground:"
echo "    1. RHOAI Dashboard → GenAI Studio → Playground"
echo "    2. Select 'Private AI - GPU as a Service' project"
echo "    3. Create playground with RUNNING models only"
echo ""
log_info "Validate: ./steps/step-05-llm-on-vllm/validate.sh"
echo ""
