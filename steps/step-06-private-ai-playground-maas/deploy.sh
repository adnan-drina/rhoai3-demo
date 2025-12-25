#!/bin/bash
# =============================================================================
# Step 06: GenAI Playground Deployment
# =============================================================================
# Deploys the LlamaStack backend and configures AI Asset Endpoints
# for the GenAI Playground in RHOAI 3.0.
#
# Components:
#   - LlamaStackDistribution CR
#   - llama-stack-config ConfigMap (all 5 models)
#   - AI Asset labels on InferenceServices
#
# Usage:
#   ./steps/step-06-private-ai-playground-maas/deploy.sh
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="private-ai"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="${SCRIPT_DIR}/../../gitops/step-06-private-ai-playground-maas"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Step 06: GenAI Playground Deployment                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Prerequisites Check
# =============================================================================
echo -e "${YELLOW}► Checking prerequisites...${NC}"

# Check oc login
if ! oc whoami &>/dev/null; then
    echo -e "${RED}✗ Not logged in to OpenShift. Run 'oc login' first.${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Logged in as: $(oc whoami)"

# Check namespace exists
if ! oc get namespace ${NAMESPACE} &>/dev/null; then
    echo -e "${RED}✗ Namespace '${NAMESPACE}' not found. Deploy Step-03 first.${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Namespace '${NAMESPACE}' exists"

# Check InferenceServices exist
ISVC_COUNT=$(oc get inferenceservice -n ${NAMESPACE} --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${ISVC_COUNT}" -eq 0 ]]; then
    echo -e "${RED}✗ No InferenceServices found. Deploy Step-05 first.${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Found ${ISVC_COUNT} InferenceServices"

# Check LlamaStack operator is managed
LLS_STATE=$(oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.llamastackoperator.managementState}' 2>/dev/null || echo "unknown")
if [[ "${LLS_STATE}" != "Managed" ]]; then
    echo -e "${RED}✗ LlamaStack operator not managed. Check DataScienceCluster config.${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} LlamaStack operator is Managed"

# Check LlamaStackDistribution CRD exists
if ! oc get crd llamastackdistributions.llamastack.io &>/dev/null; then
    echo -e "${RED}✗ LlamaStackDistribution CRD not found. Ensure RHOAI 3.0 is installed.${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} LlamaStackDistribution CRD available"

echo ""

# =============================================================================
# Phase 1: Add AI Asset Labels to InferenceServices
# =============================================================================
echo -e "${YELLOW}► Phase 1: Adding AI Asset labels to InferenceServices...${NC}"

# Define models and their use cases
declare -A MODEL_USE_CASES=(
    ["mistral-3-int4"]="chat assistant"
    ["mistral-3-bf16"]="enterprise chat assistant"
    ["devstral-2"]="agentic coding assistant"
    ["gpt-oss-20b"]="complex reasoning"
    ["granite-8b-agent"]="agentic tool-calling"
)

for model in "${!MODEL_USE_CASES[@]}"; do
    use_case="${MODEL_USE_CASES[$model]}"
    
    if oc get inferenceservice ${model} -n ${NAMESPACE} &>/dev/null; then
        # Check if already labeled
        current_label=$(oc get inferenceservice ${model} -n ${NAMESPACE} -o jsonpath='{.metadata.labels.opendatahub\.io/genai-asset}' 2>/dev/null || echo "")
        
        if [[ "${current_label}" == "true" ]]; then
            echo -e "  ${GREEN}✓${NC} ${model} - already labeled"
        else
            oc patch inferenceservice ${model} -n ${NAMESPACE} --type=merge -p "{
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
            echo -e "  ${GREEN}✓${NC} ${model} - labeled (${use_case})"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} ${model} - not found, skipping"
    fi
done

echo ""

# =============================================================================
# Phase 2: Deploy LlamaStackDistribution
# =============================================================================
echo -e "${YELLOW}► Phase 2: Deploying LlamaStackDistribution...${NC}"

# Check if already exists
if oc get llamastackdistribution lsd-genai-playground -n ${NAMESPACE} &>/dev/null; then
    CURRENT_PHASE=$(oc get llamastackdistribution lsd-genai-playground -n ${NAMESPACE} -o jsonpath='{.status.phase}')
    echo -e "  ${GREEN}✓${NC} LlamaStackDistribution already exists (Phase: ${CURRENT_PHASE})"
    
    # Update ConfigMap with latest model configuration
    echo -e "  → Updating llama-stack-config ConfigMap..."
    oc apply -f ${GITOPS_DIR}/base/playground/llamastack.yaml &>/dev/null
    
    # Restart to pick up changes
    oc rollout restart deployment/lsd-genai-playground -n ${NAMESPACE} &>/dev/null
    echo -e "  ${GREEN}✓${NC} Restarted LlamaStack to apply config changes"
else
    # Apply fresh deployment
    echo -e "  → Applying LlamaStackDistribution and ConfigMap..."
    oc apply -f ${GITOPS_DIR}/base/playground/llamastack.yaml
    echo -e "  ${GREEN}✓${NC} LlamaStackDistribution created"
fi

echo ""

# =============================================================================
# Phase 3: Wait for LlamaStack Ready
# =============================================================================
echo -e "${YELLOW}► Phase 3: Waiting for LlamaStack to be ready...${NC}"

echo -e "  → Waiting for deployment (timeout: 5m)..."
if oc wait llamastackdistribution/lsd-genai-playground -n ${NAMESPACE} \
    --for=jsonpath='{.status.phase}'=Ready --timeout=300s &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} LlamaStackDistribution is Ready"
else
    echo -e "${RED}✗ LlamaStackDistribution failed to become Ready${NC}"
    echo -e "  Check logs: oc logs deployment/lsd-genai-playground -n ${NAMESPACE}"
    exit 1
fi

echo ""

# =============================================================================
# Validation
# =============================================================================
echo -e "${YELLOW}► Validating deployment...${NC}"

# Check LlamaStack status
LLS_VERSION=$(oc get llamastackdistribution lsd-genai-playground -n ${NAMESPACE} \
    -o jsonpath='{.status.version.llamaStackServerVersion}' 2>/dev/null || echo "unknown")
echo -e "  ${GREEN}✓${NC} LlamaStack version: ${LLS_VERSION}"

# Count registered vLLM providers
PROVIDER_COUNT=$(oc get llamastackdistribution lsd-genai-playground -n ${NAMESPACE} \
    -o jsonpath='{.status.distributionConfig.providers}' 2>/dev/null | \
    jq '[.[] | select(.provider_type=="remote::vllm")] | length' 2>/dev/null || echo "0")
echo -e "  ${GREEN}✓${NC} vLLM providers registered: ${PROVIDER_COUNT}"

# Count AI Asset endpoints
ASSET_COUNT=$(oc get inferenceservice -n ${NAMESPACE} -l 'opendatahub.io/genai-asset=true' --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo -e "  ${GREEN}✓${NC} AI Asset Endpoints: ${ASSET_COUNT}"

# Check pod status
POD_STATUS=$(oc get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=lsd-genai-playground \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "unknown")
echo -e "  ${GREEN}✓${NC} LlamaStack pod status: ${POD_STATUS}"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Step 06 Deployment Complete!                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Open RHOAI Dashboard"
echo -e "  2. Navigate to GenAI Studio → Playground"
echo -e "  3. Select a running model and test prompts"
echo ""
echo -e "${YELLOW}Note:${NC} Models with minReplicas: 0 won't work in Playground until scaled up."
echo -e "      Use the GPU Orchestrator notebook to manage model scaling."
echo ""
