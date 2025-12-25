#!/bin/bash
# Step 06B: LiteMaaS Deployment Script
# ⚠️ EXPERIMENTAL: This deploys a proof-of-concept MaaS platform

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="${SCRIPT_DIR}/../../gitops/step-06b-private-ai-litemaas"
NAMESPACE="litemaas"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}⚠️  EXPERIMENTAL: LiteMaaS is a proof-of-concept${NC}"
echo ""

case "${1:-deploy}" in
  deploy)
    echo -e "${GREEN}=== Deploying LiteMaaS ===${NC}"
    
    # Check prerequisites
    echo "Checking prerequisites..."
    
    if ! oc get oauthclient litemaas-oauth-client &>/dev/null; then
      echo -e "${RED}ERROR: OAuthClient 'litemaas-oauth-client' not found${NC}"
      echo "Please create the OAuthClient first (requires cluster-admin)"
      exit 1
    fi
    
    if ! oc get group litemaas-admins &>/dev/null; then
      echo -e "${RED}ERROR: Group 'litemaas-admins' not found${NC}"
      echo "Please create OpenShift groups first (requires cluster-admin)"
      exit 1
    fi
    
    echo "Prerequisites OK"
    echo ""
    
    # Apply manifests
    echo "Applying LiteMaaS manifests..."
    oc apply -k "${GITOPS_DIR}/base"
    
    echo ""
    echo "Waiting for deployments..."
    oc rollout status statefulset/postgres -n ${NAMESPACE} --timeout=300s
    oc rollout status deployment/litellm -n ${NAMESPACE} --timeout=300s
    oc rollout status deployment/backend -n ${NAMESPACE} --timeout=300s
    oc rollout status deployment/frontend -n ${NAMESPACE} --timeout=300s
    
    echo ""
    echo -e "${GREEN}=== LiteMaaS Deployed ===${NC}"
    echo ""
    echo "Access URLs:"
    echo "  UI:      https://$(oc get route litemaas -n ${NAMESPACE} -o jsonpath='{.spec.host}')"
    echo "  API:     https://$(oc get route litemaas-api -n ${NAMESPACE} -o jsonpath='{.spec.host}')"
    echo "  LiteLLM: https://$(oc get route litellm -n ${NAMESPACE} -o jsonpath='{.spec.host}')"
    ;;
    
  status)
    echo -e "${GREEN}=== LiteMaaS Status ===${NC}"
    echo ""
    oc get pods -n ${NAMESPACE}
    echo ""
    oc get routes -n ${NAMESPACE}
    ;;
    
  cleanup)
    echo -e "${YELLOW}=== Cleaning up LiteMaaS ===${NC}"
    echo ""
    
    # Delete ArgoCD app if exists
    oc delete application step-06b-private-ai-litemaas -n openshift-gitops --ignore-not-found
    
    # Delete namespace
    oc delete namespace ${NAMESPACE} --ignore-not-found
    
    # Delete cluster-level resources
    echo "Cleaning up cluster-level resources..."
    oc delete oauthclient litemaas-oauth-client --ignore-not-found
    oc delete group litemaas-admins litemaas-readonly litemaas-users --ignore-not-found
    
    echo ""
    echo -e "${GREEN}Cleanup complete${NC}"
    ;;
    
  *)
    echo "Usage: $0 {deploy|status|cleanup}"
    exit 1
    ;;
esac

