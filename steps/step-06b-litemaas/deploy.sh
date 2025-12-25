#!/bin/bash
# =============================================================================
# Step 06B: LiteMaaS Deployment (Experimental)
# =============================================================================
#
# ⚠️ EXPERIMENTAL: This deploys LiteMaaS as a proof-of-concept MaaS platform.
# NOT for production use. See README for full disclaimers.
#
# Usage:
#   ./steps/step-06b-litemaas/deploy.sh          # Deploy
#   ./steps/step-06b-litemaas/deploy.sh cleanup  # Remove all resources
#   ./steps/step-06b-litemaas/deploy.sh status   # Check status
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

NAMESPACE="litemaas"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="${SCRIPT_DIR}/../../gitops/step-06b-litemaas"

# =============================================================================
# Helper Functions
# =============================================================================

print_banner() {
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║     Step 06B: LiteMaaS - Experimental MaaS Platform          ║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║  ⚠️  EXPERIMENTAL: Proof-of-Concept - Not Production Ready   ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_disclaimer() {
    echo -e "${YELLOW}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│                        DISCLAIMER                            │${NC}"
    echo -e "${YELLOW}├──────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│  LiteMaaS is a proof-of-concept from Red Hat AI Services BU  │${NC}"
    echo -e "${YELLOW}│  • NOT officially supported by Red Hat                       │${NC}"
    echo -e "${YELLOW}│  • MIT License - use at your own risk                        │${NC}"
    echo -e "${YELLOW}│  • For demo/learning purposes only                           │${NC}"
    echo -e "${YELLOW}│                                                              │${NC}"
    echo -e "${YELLOW}│  For production MaaS, wait for RHOAI MaaS to reach TP/GA.    │${NC}"
    echo -e "${YELLOW}│  Ref: https://github.com/rh-aiservices-bu/litemaas           │${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

check_prerequisites() {
    echo -e "${BLUE}► Checking prerequisites...${NC}"
    
    # Check oc login
    if ! oc whoami &>/dev/null; then
        echo -e "${RED}✗ Not logged in to OpenShift. Run 'oc login' first.${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Logged in as: $(oc whoami)"
    
    # Check private-ai namespace exists (for model proxying)
    if ! oc get namespace private-ai &>/dev/null; then
        echo -e "${RED}✗ Namespace 'private-ai' not found. Deploy Step-05 first.${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Namespace 'private-ai' exists"
    
    # Check InferenceServices exist
    ISVC_COUNT=$(oc get inferenceservice -n private-ai --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${ISVC_COUNT}" -eq 0 ]]; then
        echo -e "${YELLOW}⚠ No InferenceServices found in private-ai. LiteLLM will have no models to proxy.${NC}"
    else
        echo -e "  ${GREEN}✓${NC} Found ${ISVC_COUNT} InferenceServices in private-ai"
    fi
    
    echo ""
}

# =============================================================================
# Deploy Function
# =============================================================================

deploy() {
    print_banner
    print_disclaimer
    
    read -p "Do you want to continue with deployment? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deployment cancelled.${NC}"
        exit 0
    fi
    
    echo ""
    check_prerequisites
    
    # Phase 1: Apply manifests
    echo -e "${BLUE}► Phase 1: Applying Kustomize manifests...${NC}"
    
    if oc get namespace ${NAMESPACE} &>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC} Namespace '${NAMESPACE}' already exists, updating..."
    fi
    
    kustomize build ${GITOPS_DIR}/base | oc apply -f -
    echo -e "  ${GREEN}✓${NC} Manifests applied"
    echo ""
    
    # Phase 2: Wait for PostgreSQL
    echo -e "${BLUE}► Phase 2: Waiting for PostgreSQL...${NC}"
    oc rollout status deployment/postgres -n ${NAMESPACE} --timeout=120s
    echo -e "  ${GREEN}✓${NC} PostgreSQL is ready"
    echo ""
    
    # Phase 3: Wait for LiteLLM
    echo -e "${BLUE}► Phase 3: Waiting for LiteLLM...${NC}"
    oc rollout status deployment/litellm -n ${NAMESPACE} --timeout=120s
    echo -e "  ${GREEN}✓${NC} LiteLLM is ready"
    echo ""
    
    # Phase 4: Wait for LiteMaaS
    echo -e "${BLUE}► Phase 4: Waiting for LiteMaaS...${NC}"
    oc rollout status deployment/litemaas-backend -n ${NAMESPACE} --timeout=120s || true
    oc rollout status deployment/litemaas-frontend -n ${NAMESPACE} --timeout=120s || true
    echo -e "  ${GREEN}✓${NC} LiteMaaS components deployed"
    echo ""
    
    # Phase 5: Display access information
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Step 06B Deployment Complete!                      ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    LITEMAAS_URL=$(oc get route litemaas -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null)
    LITELLM_URL=$(oc get route litellm -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null)
    
    echo -e "${BLUE}Access URLs:${NC}"
    echo -e "  • LiteMaaS UI:  https://${LITEMAAS_URL}"
    echo -e "  • LiteLLM API:  https://${LITELLM_URL}"
    echo ""
    echo -e "${BLUE}Quick test (LiteLLM):${NC}"
    echo -e "  curl -k https://${LITELLM_URL}/health"
    echo ""
    echo -e "${BLUE}List available models:${NC}"
    echo -e "  curl -k https://${LITELLM_URL}/v1/models \\"
    echo -e "    -H 'Authorization: Bearer sk-litemaas-demo-key-2024'"
    echo ""
    echo -e "${YELLOW}Note:${NC} LiteMaaS requires OAuth setup for full functionality."
    echo -e "      For demo, you can use LiteLLM directly with the master key."
    echo ""
    echo -e "${YELLOW}Cleanup:${NC}"
    echo -e "  ./steps/step-06b-litemaas/deploy.sh cleanup"
    echo ""
}

# =============================================================================
# Cleanup Function
# =============================================================================

cleanup() {
    print_banner
    
    echo -e "${YELLOW}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│                     CLEANUP WARNING                          │${NC}"
    echo -e "${YELLOW}├──────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│  This will DELETE all LiteMaaS resources including:          │${NC}"
    echo -e "${YELLOW}│  • PostgreSQL database and all data                          │${NC}"
    echo -e "${YELLOW}│  • LiteLLM proxy                                             │${NC}"
    echo -e "${YELLOW}│  • LiteMaaS backend and frontend                             │${NC}"
    echo -e "${YELLOW}│  • All PersistentVolumeClaims                                │${NC}"
    echo -e "${YELLOW}│  • The 'litemaas' namespace                                  │${NC}"
    echo -e "${YELLOW}│                                                              │${NC}"
    echo -e "${YELLOW}│  This action is IRREVERSIBLE.                                │${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    read -p "Are you SURE you want to delete all LiteMaaS resources? (yes/NO) " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        echo -e "${YELLOW}Cleanup cancelled.${NC}"
        exit 0
    fi
    
    echo -e "${BLUE}► Deleting LiteMaaS namespace and all resources...${NC}"
    
    if oc get namespace ${NAMESPACE} &>/dev/null; then
        oc delete namespace ${NAMESPACE} --wait=true
        echo -e "  ${GREEN}✓${NC} Namespace '${NAMESPACE}' deleted"
    else
        echo -e "  ${YELLOW}⚠${NC} Namespace '${NAMESPACE}' does not exist"
    fi
    
    # Also delete ArgoCD Application if it exists
    if oc get application step-06b-litemaas -n openshift-gitops &>/dev/null; then
        oc delete application step-06b-litemaas -n openshift-gitops
        echo -e "  ${GREEN}✓${NC} ArgoCD Application deleted"
    fi
    
    echo ""
    echo -e "${GREEN}✓ LiteMaaS cleanup complete!${NC}"
    echo ""
}

# =============================================================================
# Status Function
# =============================================================================

status() {
    print_banner
    
    echo -e "${BLUE}► Checking LiteMaaS status...${NC}"
    echo ""
    
    if ! oc get namespace ${NAMESPACE} &>/dev/null; then
        echo -e "${YELLOW}Namespace '${NAMESPACE}' does not exist. LiteMaaS is not deployed.${NC}"
        exit 0
    fi
    
    echo -e "${BLUE}Deployments:${NC}"
    oc get deployments -n ${NAMESPACE} -o wide
    echo ""
    
    echo -e "${BLUE}Pods:${NC}"
    oc get pods -n ${NAMESPACE} -o wide
    echo ""
    
    echo -e "${BLUE}Services:${NC}"
    oc get services -n ${NAMESPACE}
    echo ""
    
    echo -e "${BLUE}Routes:${NC}"
    oc get routes -n ${NAMESPACE}
    echo ""
    
    echo -e "${BLUE}PVCs:${NC}"
    oc get pvc -n ${NAMESPACE}
    echo ""
    
    # Test LiteLLM health
    LITELLM_URL=$(oc get route litellm -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null)
    if [[ -n "${LITELLM_URL}" ]]; then
        echo -e "${BLUE}LiteLLM Health Check:${NC}"
        curl -sk "https://${LITELLM_URL}/health" | jq . 2>/dev/null || echo "Unable to reach LiteLLM"
        echo ""
    fi
}

# =============================================================================
# Main
# =============================================================================

case "${1:-deploy}" in
    deploy)
        deploy
        ;;
    cleanup|clean|delete|remove)
        cleanup
        ;;
    status|check)
        status
        ;;
    *)
        echo "Usage: $0 {deploy|cleanup|status}"
        echo ""
        echo "Commands:"
        echo "  deploy   Deploy LiteMaaS (default)"
        echo "  cleanup  Remove all LiteMaaS resources"
        echo "  status   Check deployment status"
        exit 1
        ;;
esac

