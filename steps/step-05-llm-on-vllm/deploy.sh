#!/bin/bash
# =============================================================================
# Step 05: LLM Serving - Triple Play
# =============================================================================
# Deploys three LLMs using vLLM:
#   1. Mistral 3 24B BF16 (4-GPU, tensor parallel)
#   2. Mistral 3 24B FP8 (1-GPU, Neural Magic optimized)
#   3. Devstral 2 24B BF16 (4-GPU, coding model)
# =============================================================================

set -e

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 05: LLM Serving - Triple Play                                  ║"
echo "║  Mistral 3 (BF16 + FP8) + Devstral 2 (Coding)                       ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="${SCRIPT_DIR}/../../gitops/step-05-llm-on-vllm/base"

# =============================================================================
# Pre-flight Checks
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Pre-flight Checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check for private-ai namespace
if ! oc get namespace private-ai &>/dev/null; then
  echo "❌ Error: 'private-ai' namespace does not exist. Run Step-03 first."
  exit 1
fi
echo "✓ Namespace 'private-ai' exists"

# Check for Model Registry
if ! oc get modelregistry private-ai-registry -n rhoai-model-registries &>/dev/null; then
  echo "❌ Error: Model Registry not found. Run Step-04 first."
  exit 1
fi
echo "✓ Model Registry 'private-ai-registry' exists"

# Check for LocalQueue
if ! oc get localqueue private-ai-local-queue -n private-ai &>/dev/null; then
  echo "⚠️  Warning: LocalQueue 'private-ai-local-queue' not found"
fi

echo ""

# =============================================================================
# Infrastructure Scaling Reminder
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Infrastructure Requirements (9 GPUs Total)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Required MachineSets:"
echo "    - 2x g6.12xlarge (4-GPU each) → Mistral BF16 + Devstral"
echo "    - 1x g6.4xlarge  (1-GPU)      → Mistral FP8"
echo ""
echo "  Scale commands:"
echo "    CLUSTER_ID=\$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')"
echo "    oc scale machineset \${CLUSTER_ID}-gpu-g6-12xlarge -n openshift-machine-api --replicas=2"
echo "    oc scale machineset \${CLUSTER_ID}-gpu-g6-4xlarge -n openshift-machine-api --replicas=1"
echo ""

# Check current GPU node count
GPU_NODES=$(oc get nodes -l nvidia.com/gpu.product=NVIDIA-L4 --no-headers 2>/dev/null | wc -l)
echo "  Current GPU nodes: ${GPU_NODES}"
echo ""

read -p "Continue with deployment? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Deployment cancelled."
  exit 0
fi

# =============================================================================
# Deploy Step 05 Resources
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Deploying Step-05 Resources"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Delete old InferenceServices if they exist
echo "Cleaning up old resources..."
oc delete inferenceservice mistral-24b-fp8 mistral-24b-full -n private-ai --ignore-not-found=true 2>/dev/null || true
oc delete servingruntime vllm-mistral-runtime -n private-ai --ignore-not-found=true 2>/dev/null || true

# Apply Kustomize
echo "Applying Kustomize manifests..."
oc apply -k "${GITOPS_DIR}"

echo ""
echo "✓ Resources applied"

# =============================================================================
# Wait for Model Registration
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Waiting for Model Registration Job"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

oc wait --for=condition=complete job/llm-model-registration -n rhoai-model-registries --timeout=120s 2>/dev/null || true

echo ""
echo "Registration job logs:"
oc logs job/llm-model-registration -n rhoai-model-registries --tail=20 2>/dev/null || echo "(Job may still be running)"

# =============================================================================
# Wait for ServingRuntime
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Checking ServingRuntime"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

oc get servingruntime -n private-ai

# =============================================================================
# Check InferenceServices
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "InferenceService Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

oc get inferenceservice -n private-ai

echo ""
echo "Note: InferenceServices will show READY=True once:"
echo "  1. GPU nodes are available and ready"
echo "  2. Model weights are uploaded to MinIO (s3://models/)"
echo "  3. Pods are scheduled and healthy"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 05 Deployment Complete                                         ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║                                                                      ║"
echo "║  Models Deployed:                                                    ║"
echo "║    1. mistral-3-bf16    → 4-GPU, Full Precision                     ║"
echo "║    2. mistral-3-fp8     → 1-GPU, Neural Magic FP8                   ║"
echo "║    3. devstral-2-bf16   → 4-GPU, Coding Model                       ║"
echo "║                                                                      ║"
echo "║  Endpoints (when ready):                                             ║"
echo "║    • http://mistral-3-bf16-predictor.private-ai.svc.cluster.local   ║"
echo "║    • http://mistral-3-fp8-predictor.private-ai.svc.cluster.local    ║"
echo "║    • http://devstral-2-bf16-predictor.private-ai.svc.cluster.local  ║"
echo "║                                                                      ║"
echo "║  Validation:                                                         ║"
echo "║    oc get inferenceservice -n private-ai                            ║"
echo "║    oc get pods -n private-ai -l serving.kserve.io/inferenceservice  ║"
echo "║                                                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
