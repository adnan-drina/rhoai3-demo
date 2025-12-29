#!/bin/bash
# Step 08: Distributed Inference with llm-d
# Deploy script for llm-d distributed inference demo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  Step 08: Distributed Inference with llm-d                                   ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Prerequisites Check
# ═══════════════════════════════════════════════════════════════════════════════
echo "→ Checking prerequisites..."

# Check LLMInferenceService CRD
if ! oc api-resources | grep -q "llminferenceservice"; then
    echo "❌ LLMInferenceService CRD not found. Is RHOAI 3.0 installed?"
    exit 1
fi
echo "  ✓ LLMInferenceService CRD available"

# Check LeaderWorkerSet operator (operator API only on this cluster)
if ! oc api-resources | grep -q "leaderworkersetoperator"; then
    echo "❌ LeaderWorkerSet operator API not found. Is the operator installed (Step 01)?"
    exit 1
fi
echo "  ✓ LeaderWorkerSet operator API available"

# Check Red Hat Connectivity Link (RHCL) - AuthPolicy CRD required by llm-d
if ! oc get crd authpolicies.kuadrant.io &>/dev/null; then
    echo "❌ AuthPolicy CRD not found (authpolicies.kuadrant.io)"
    echo "   The llm-d controller requires RHCL (Red Hat Connectivity Link) operator."
    echo ""
    echo "   Install RHCL via Step 01:"
    echo "   oc apply -k gitops/step-01-gpu-and-prereq/base/rhcl-operator/"
    exit 1
fi
echo "  ✓ RHCL AuthPolicy CRD available"

# Check Gateway API is available (RHOAI enables Gateway API automatically)
if ! oc api-resources | grep -q "^gatewayclasses"; then
    echo "❌ Gateway API resources not found (GatewayClass). Is Gateway API enabled on the cluster?"
    exit 1
fi
if ! oc api-resources | grep -q "^gateways[[:space:]]"; then
    echo "❌ Gateway API resources not found (Gateway). Is Gateway API enabled on the cluster?"
    exit 1
fi
echo "  ✓ Gateway API resources available"

# Check llm-d reserved queue exists (created in Step 03)
if ! oc get clusterqueue rhoai-llmd-queue &>/dev/null; then
    echo "❌ ClusterQueue 'rhoai-llmd-queue' not found."
    echo "   This provides a HARD RESERVATION of 2 GPUs for llm-d."
    echo ""
    echo "   Apply the llm-d queue manifests:"
    echo "   oc apply -f gitops/step-03-private-ai/base/cluster-queue-llmd.yaml"
    echo "   oc apply -f gitops/step-03-private-ai/base/local-queue-llmd.yaml"
    exit 1
fi
if ! oc get localqueue llmd -n private-ai &>/dev/null; then
    echo "❌ LocalQueue 'llmd' not found in namespace private-ai."
    echo ""
    echo "   Apply the llm-d LocalQueue:"
    echo "   oc apply -f gitops/step-03-private-ai/base/local-queue-llmd.yaml"
    exit 1
fi
# Show queue capacity
LLMD_GPUS=$(oc get clusterqueue rhoai-llmd-queue -o jsonpath='{.spec.resourceGroups[0].flavors[0].resources[?(@.name=="nvidia.com/gpu")].nominalQuota}' 2>/dev/null || echo "?")
echo "  ✓ Kueue llm-d reserved queue present (${LLMD_GPUS} GPUs reserved)"

# Check GPU nodes
GPU_NODES=$(oc get nodes -l node.kubernetes.io/instance-type=g6.4xlarge --no-headers 2>/dev/null | wc -l)
if [ "$GPU_NODES" -lt 2 ]; then
    echo "⚠️  Warning: Only $GPU_NODES g6.4xlarge nodes found."
    echo "   This Step is configured for tensor parallelism=2 and requires 2 GPUs."
    echo "   With g6.4xlarge (1 GPU/node), that means 2 nodes are required."
fi
echo "  ✓ Found $GPU_NODES g6.4xlarge GPU nodes"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Deployment
# ═══════════════════════════════════════════════════════════════════════════════
echo "→ Deploying Step 08 via ArgoCD..."

# Apply ArgoCD Application
oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/step-08-llm-d.yaml"

echo ""
echo "→ Waiting for ArgoCD sync..."
sleep 5

# Wait for sync (with timeout)
TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    SYNC_STATUS=$(oc get application step-08-llm-d -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH_STATUS=$(oc get application step-08-llm-d -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    
    echo "  Sync: $SYNC_STATUS | Health: $HEALTH_STATUS"
    
    if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Healthy" ]; then
        break
    fi
    
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "⚠️  Timeout waiting for sync. Check ArgoCD for details:"
    echo "   oc get application step-08-llm-d -n openshift-gitops"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Validation
# ═══════════════════════════════════════════════════════════════════════════════
echo "→ Validating deployment..."

# Check LLMInferenceService
echo ""
echo "LLMInferenceService:"
oc get llminferenceservice -n private-ai

# Check pods
echo ""
echo "Distributed Worker Pods:"
oc get pods -n private-ai -l app=mistral-3-distributed -o wide 2>/dev/null || echo "  No pods yet (may be starting)"

# LWS workload CR is not exposed on this cluster (operator API only), so we don't
# attempt to `oc get leaderworkerset` here.

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  Step 08 deployment initiated!                                               ║"
echo "║                                                                              ║"
echo "║  Monitor progress:                                                           ║"
echo "║    oc get llminferenceservice -n private-ai -w                              ║"
echo "║    oc get pods -n private-ai -l app=mistral-3-distributed -w                ║"
echo "║                                                                              ║"
echo "║  Test endpoint (when ready):                                                 ║"
echo "║    curl -sk \$(oc get llminferenceservice mistral-3-distributed \\            ║"
echo "║      -n private-ai -o jsonpath='{.status.url}')/v1/models                   ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"

