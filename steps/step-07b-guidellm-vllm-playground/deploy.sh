#!/bin/bash
# Step 07B: GuideLLM + vLLM-Playground - Deployment Script
# ============================================================================
# ⚠️ WORK IN PROGRESS - NOT READY FOR DEPLOYMENT
#
# This step will deploy a custom vLLM-Playground configured for:
#   - Option 3: Kubernetes Job Pattern (benchmarks only)
#   - Connecting to existing InferenceServices
#   - Integrated GuideLLM benchmarking UI
#
# Current Status:
#   - Community image requires custom modifications
#   - Deployment is DISABLED (replicas: 0)
#   - See README.md for implementation plan
#
# Usage:
#   ./deploy.sh              # Deploy (disabled by default)
#   ./deploy.sh --cleanup    # Remove all Step 07B resources
#   ./deploy.sh --status     # Check current status
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NAMESPACE="private-ai"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 07B: GuideLLM + vLLM-Playground${NC}"
echo -e "${YELLOW}  ⚠️ WORK IN PROGRESS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"

# --- Cleanup Mode ---
if [ "$1" == "--cleanup" ]; then
    echo ""
    echo -e "${YELLOW}▶ Cleaning up Step 07B resources...${NC}"
    
    # vLLM-Playground resources
    oc delete deployment vllm-playground -n ${NAMESPACE} --ignore-not-found
    oc delete service vllm-playground -n ${NAMESPACE} --ignore-not-found
    oc delete route vllm-playground -n ${NAMESPACE} --ignore-not-found
    oc delete serviceaccount vllm-playground-sa -n ${NAMESPACE} --ignore-not-found
    oc delete role vllm-pod-manager -n ${NAMESPACE} --ignore-not-found
    oc delete rolebinding vllm-pod-manager-binding -n ${NAMESPACE} --ignore-not-found
    oc delete clusterrole vllm-playground-node-reader --ignore-not-found
    oc delete clusterrolebinding vllm-playground-node-reader-binding --ignore-not-found
    oc delete configmap vllm-playground-config-gpu -n ${NAMESPACE} --ignore-not-found
    oc delete pvc vllm-model-cache -n ${NAMESPACE} --ignore-not-found
    
    echo -e "${GREEN}  ✓ Cleanup complete${NC}"
    exit 0
fi

# --- Status Mode ---
if [ "$1" == "--status" ]; then
    echo ""
    echo -e "${YELLOW}▶ Current Status:${NC}"
    echo ""
    echo -e "  ${CYAN}Implementation Status:${NC}"
    echo "     - GitOps Manifests: ✅ Created (in gitops/step-07b-guidellm-vllm-playground/)"
    echo "     - Custom Image: ❌ Not built"
    echo "     - Deployment: ⏸️  Disabled (replicas: 0)"
    echo ""
    echo -e "  ${CYAN}Next Steps:${NC}"
    echo "     1. Fork vLLM-Playground repository"
    echo "     2. Modify for Option 3 (Kubernetes Job Pattern)"
    echo "     3. Build and push custom image"
    echo "     4. Update deployment.yaml with new image"
    echo "     5. Set replicas: 1 to enable"
    echo ""
    echo -e "  ${CYAN}For benchmarking now, use Step 07:${NC}"
    echo "     ./steps/step-07-model-performance-metrics/deploy.sh --benchmark"
    echo ""
    exit 0
fi

# --- Default: Deploy (disabled) ---
echo ""
echo -e "${YELLOW}▶ Deployment Status:${NC}"
echo ""
echo -e "  ${RED}⚠️ This step is WORK IN PROGRESS${NC}"
echo ""
echo -e "  The vLLM-Playground deployment is currently disabled (replicas: 0)"
echo "  because the community image needs to be customized for our use case."
echo ""
echo -e "  ${CYAN}What we need:${NC}"
echo "     - Custom image that creates GuideLLM Jobs (not vLLM pods)"
echo "     - Pre-configured with our InferenceService endpoints"
echo "     - Result visualization integrated with Grafana"
echo ""
echo -e "  ${CYAN}Alternative (use Step 07):${NC}"
echo "     ./steps/step-07-model-performance-metrics/deploy.sh --benchmark"
echo ""
echo -e "  ${CYAN}For status:${NC}"
echo "     ./deploy.sh --status"
echo ""
echo -e "  ${CYAN}To cleanup:${NC}"
echo "     ./deploy.sh --cleanup"
echo ""

