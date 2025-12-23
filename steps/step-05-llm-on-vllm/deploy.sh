#!/bin/bash
# =============================================================================
# Step 05: LLM Serving with vLLM (Official S3 Storage Approach)
# =============================================================================
# Deploys Mistral Small 24B in two configurations:
#   1. mistral-small-24b-tp4 (4-GPU, BF16, tensor parallel)
#   2. mistral-small-24b     (1-GPU, FP8, Neural Magic optimized)
#
# Storage: Models downloaded from MinIO (S3) by KServe storage-initializer
# =============================================================================

set -e

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 05: LLM Serving with vLLM                                      ║"
echo "║  Official S3 Storage Approach (RHOAI 3.0 Recommended)                ║"
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

# Check for MinIO
if ! oc get deployment minio -n minio-storage &>/dev/null; then
  echo "❌ Error: MinIO not found. Run Step-03 first."
  exit 1
fi
echo "✓ MinIO storage available"

# Check for storage-config secret
if ! oc get secret storage-config -n private-ai &>/dev/null; then
  echo "❌ Error: storage-config secret not found in private-ai namespace."
  echo "  This secret is required for KServe to access MinIO."
  exit 1
fi
echo "✓ storage-config secret exists"

# Check for Model Registry (optional)
if oc get modelregistry private-ai-registry -n rhoai-model-registries &>/dev/null; then
  echo "✓ Model Registry 'private-ai-registry' exists"
else
  echo "⚠️  Warning: Model Registry not found (optional for serving)"
fi

echo ""

# =============================================================================
# Storage Check - Model Weights in MinIO
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Model Storage Check (MinIO)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Required model locations in MinIO:"
echo "    s3://rhoai-artifacts/mistral-small-24b/      (for 4-GPU BF16)"
echo "    s3://rhoai-artifacts/mistral-small-24b-fp8/  (for 1-GPU FP8)"
echo ""
echo "  To upload models, use the helper job:"
echo "    oc create secret generic hf-token -n private-ai --from-literal=token=hf_xxx"
echo "    oc apply -f ${GITOPS_DIR}/model-upload/upload-mistral-job.yaml"
echo ""

# =============================================================================
# Infrastructure Scaling
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Infrastructure Requirements (5 GPUs Total)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Required MachineSets:"
echo "    - 1x g6.12xlarge (4-GPU) → mistral-small-24b-tp4"
echo "    - 1x g6.4xlarge  (1-GPU) → mistral-small-24b (FP8)"
echo ""
echo "  Scale commands:"
echo "    CLUSTER_ID=\$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')"
echo "    oc scale machineset \${CLUSTER_ID}-gpu-g6-12xlarge-us-east-2b -n openshift-machine-api --replicas=1"
echo "    oc scale machineset \${CLUSTER_ID}-gpu-g6-4xlarge-us-east-2b -n openshift-machine-api --replicas=1"
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

# Delete old resources if they exist (from previous OCI approach)
echo "Cleaning up old resources..."
oc delete inferenceservice mistral-3-bf16 mistral-3-fp8 mistral-24b-fp8 mistral-24b-full -n private-ai --ignore-not-found=true 2>/dev/null || true
oc delete servingruntime vllm-mistral-runtime -n private-ai --ignore-not-found=true 2>/dev/null || true

# Apply Kustomize
echo "Applying Kustomize manifests..."
oc apply -k "${GITOPS_DIR}"

echo ""
echo "✓ Resources applied"

# =============================================================================
# Check ServingRuntime
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ServingRuntime Status"
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
echo "  1. GPU nodes are available and scheduled"
echo "  2. Model weights exist in MinIO (s3://rhoai-artifacts/...)"
echo "  3. KServe storage-initializer downloads weights successfully"
echo "  4. vLLM loads the model into GPU memory"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 05 Deployment Complete                                         ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║                                                                      ║"
echo "║  Storage: S3/MinIO (Official RHOAI 3.0 Approach)                    ║"
echo "║                                                                      ║"
echo "║  Models:                                                            ║"
echo "║    1. mistral-small-24b-tp4 → 4-GPU, BF16, High-throughput          ║"
echo "║    2. mistral-small-24b     → 1-GPU, FP8, Cost-efficient            ║"
echo "║                                                                      ║"
echo "║  Endpoints (when ready):                                             ║"
echo "║    • http://mistral-small-24b-tp4.private-ai.svc.cluster.local      ║"
echo "║    • http://mistral-small-24b.private-ai.svc.cluster.local          ║"
echo "║                                                                      ║"
echo "║  Watch startup:                                                      ║"
echo "║    oc get pods -n private-ai -l serving.kserve.io/inferenceservice  ║"
echo "║    oc logs -n private-ai <pod> -c storage-initializer               ║"
echo "║                                                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
