#!/bin/bash
# =============================================================================
# Step 05: GPU-as-a-Service Demo
# =============================================================================
# Deploys 5 Red Hat Validated models with Kueue-managed GPU allocation:
#
#   Active (minReplicas: 1):
#     1. mistral-3-bf16     (4-GPU, S3, BF16 full precision)
#     2. mistral-3-int4     (1-GPU, OCI ModelCar, INT4 W4A16)
#
#   Queued (minReplicas: 0):
#     3. devstral-2         (4-GPU, S3, Agentic tool-calling)
#     4. gpt-oss-20b        (4-GPU, S3, High-reasoning)
#     5. granite-8b-agent   (1-GPU, S3, RAG/Tool-call)
#
# RHOAI 3.0 Patterns Used:
#   - Kueue quota management (5 GPU limit)
#   - KServe with S3 and OCI storage
#   - Model Registry integration
# =============================================================================

set -e

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 05: GPU-as-a-Service Demo                                      ║"
echo "║  5 Red Hat Validated Models with Kueue Quota Management              ║"
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

# Check for minio-connection secret
if ! oc get secret minio-connection -n private-ai &>/dev/null; then
  echo "❌ Error: minio-connection secret not found in private-ai namespace."
  echo "  This secret is required for KServe to access MinIO."
  exit 1
fi
echo "✓ minio-connection secret exists"

# Check for Kueue ClusterQueue
if oc get clusterqueue rhoai-main-queue &>/dev/null; then
  echo "✓ Kueue ClusterQueue 'rhoai-main-queue' exists"
else
  echo "⚠️  Warning: Kueue ClusterQueue not found (required for quota management)"
fi

# Check for Model Registry (optional)
if oc get modelregistry private-ai-registry -n rhoai-model-registries &>/dev/null; then
  echo "✓ Model Registry 'private-ai-registry' exists"
else
  echo "⚠️  Warning: Model Registry not found (optional for serving)"
fi

echo ""

# =============================================================================
# Infrastructure Requirements
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Infrastructure Requirements (5 GPUs Total)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Required MachineSets:"
echo "    - 1x g6.12xlarge (4-GPU) → BF16 models (mistral-3-bf16, devstral-2, gpt-oss-20b)"
echo "    - 1x g6.4xlarge  (1-GPU) → INT4/FP8 models (mistral-3-int4, granite-8b-agent)"
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

# =============================================================================
# Model Storage Status
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Model Storage Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  S3 Models (MinIO):"
echo "    s3://models/mistral-small-24b/           → mistral-3-bf16, devstral-2"
echo "    s3://models/gpt-oss-20b/                 → gpt-oss-20b"
echo "    s3://models/granite-3.1-8b-instruct-fp8/ → granite-8b-agent"
echo ""
echo "  OCI ModelCar (Red Hat Registry):"
echo "    registry.redhat.io/rhelai1/modelcar-mistral-small-24b-instruct-2501-quantized-w4a16:1.5"
echo "    → mistral-3-int4 (~13.5GB INT4 W4A16)"
echo ""
echo "  To upload S3 models:"
echo "    oc create secret generic hf-token -n minio-storage --from-literal=token=hf_xxx"
echo "    oc apply -f ${GITOPS_DIR}/model-upload/upload-mistral-bf16.yaml"
echo "    oc apply -f ${GITOPS_DIR}/model-upload/upload-gpt-oss-20b.yaml"
echo "    oc apply -f ${GITOPS_DIR}/model-upload/upload-granite-8b.yaml"
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

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 05 Deployment Complete                                         ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║                                                                      ║"
echo "║  Enterprise Model Portfolio (5 Models, 14 GPUs potential):          ║"
echo "║                                                                      ║"
echo "║    Active (minReplicas: 1):                                         ║"
echo "║      • mistral-3-bf16     (4-GPU) BF16 full precision               ║"
echo "║      • mistral-3-int4     (1-GPU) INT4 W4A16 quantized              ║"
echo "║                                                                      ║"
echo "║    Queued (minReplicas: 0):                                         ║"
echo "║      • devstral-2         (4-GPU) Agentic tool-calling              ║"
echo "║      • gpt-oss-20b        (4-GPU) High-reasoning                    ║"
echo "║      • granite-8b-agent   (1-GPU) RAG/Tool-call                     ║"
echo "║                                                                      ║"
echo "║  Watch status:                                                       ║"
echo "║    oc get inferenceservice -n private-ai -w                         ║"
echo "║    oc get workload -n private-ai -w                                 ║"
echo "║                                                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
