#!/bin/bash
# Step 06B: LiteMaaS Deployment Script
# ⚠️ EXPERIMENTAL: This deploys a proof-of-concept MaaS platform

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="${SCRIPT_DIR}/../../gitops/step-06b-private-ai-litemaas"
ARGOCD_DIR="${SCRIPT_DIR}/../../gitops/argocd/app-of-apps"
NAMESPACE="litemaas"
MASTER_KEY="sk-1b4f0a05549af06f80db6cd51b37fd01"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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
      echo ""
      echo "Example:"
      echo "  oc apply -f - <<EOF"
      echo "  apiVersion: oauth.openshift.io/v1"
      echo "  kind: OAuthClient"
      echo "  metadata:"
      echo "    name: litemaas-oauth-client"
      echo "  secret: 277e639bb4ebed8e0e5dd9517dc947cf"
      echo "  redirectURIs:"
      echo "    - 'https://litemaas-litemaas.apps.<cluster>/api/auth/callback'"
      echo "  grantMethod: auto"
      echo "  EOF"
      exit 1
    fi
    
    echo "Prerequisites OK"
    echo ""
    
    # Apply ArgoCD Application
    echo "Applying ArgoCD Application..."
    oc apply -f "${ARGOCD_DIR}/step-06b-private-ai-litemaas.yaml"
    
    echo ""
    echo "Waiting for namespace to be created..."
    until oc get namespace ${NAMESPACE} &>/dev/null; do
      sleep 2
    done
    
    echo "Waiting for deployments..."
    oc rollout status statefulset/postgres -n ${NAMESPACE} --timeout=300s || true
    oc rollout status deployment/litellm -n ${NAMESPACE} --timeout=300s || true
    oc rollout status deployment/backend -n ${NAMESPACE} --timeout=300s || true
    oc rollout status deployment/frontend -n ${NAMESPACE} --timeout=300s || true
    
    echo ""
    echo -e "${CYAN}=== Running Post-Deployment Setup ===${NC}"
    
    # Fix OpenShift OAuth compatibility
    echo "Fixing OpenShift OAuth compatibility..."
    oc exec -n ${NAMESPACE} postgres-0 -- psql -U litemaas_admin -d litemaas_db -c \
      "ALTER TABLE users ALTER COLUMN oauth_id DROP NOT NULL;" 2>/dev/null || true
    
    # Register models in backend database
    echo "Registering models in backend database..."
    oc exec -n ${NAMESPACE} postgres-0 -- psql -U litemaas_admin -d litemaas_db -c "
    INSERT INTO models (id, name, provider, description, category, context_length, input_cost_per_token, output_cost_per_token, supports_function_calling, supports_streaming, availability, api_base) VALUES
    ('mistral-3-int4', 'Mistral-3 INT4', 'vLLM', 'Mistral-3 INT4 quantized model (1-GPU)', 'chat', 16384, 0, 0, false, true, 'available', 'http://mistral-3-int4-predictor.private-ai.svc.cluster.local:8080/v1'),
    ('granite-8b-agent', 'Granite-8B Agent', 'vLLM', 'Granite-3.1-8B Agent for tool calling', 'agent', 16384, 0, 0, true, true, 'available', 'http://granite-8b-agent-predictor.private-ai.svc.cluster.local:8080/v1'),
    ('mistral-3-bf16', 'Mistral-3 BF16', 'vLLM', 'Mistral-3 BF16 full precision (4-GPU)', 'chat', 32768, 0, 0, false, true, 'available', 'http://mistral-3-bf16-predictor.private-ai.svc.cluster.local:8080/v1'),
    ('devstral-2', 'Devstral-2', 'vLLM', 'Devstral-2 agentic coding assistant (4-GPU)', 'coding', 131072, 0, 0, true, true, 'available', 'http://devstral-2-predictor.private-ai.svc.cluster.local:8080/v1'),
    ('gpt-oss-20b', 'GPT-OSS-20B', 'vLLM', 'GPT-OSS-20B for complex reasoning (4-GPU)', 'reasoning', 32768, 0, 0, false, true, 'available', 'http://gpt-oss-20b-predictor.private-ai.svc.cluster.local:8080/v1')
    ON CONFLICT (id) DO NOTHING;" 2>/dev/null || true
    
    # Register models in LiteLLM
    echo "Registering models in LiteLLM..."
    for model in mistral-3-int4 granite-8b-agent mistral-3-bf16 devstral-2 gpt-oss-20b; do
      oc exec deployment/backend -n ${NAMESPACE} -- curl -s -X POST http://litellm:4000/model/new \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"model_name\": \"$model\", \"litellm_params\": {\"model\": \"openai/$model\", \"api_base\": \"http://${model}-predictor.private-ai.svc.cluster.local:8080/v1\", \"api_key\": \"none\"}}" 2>/dev/null || true
    done
    
    echo ""
    echo -e "${GREEN}=== LiteMaaS Deployed Successfully ===${NC}"
    echo ""
    echo "Access URLs:"
    echo "  UI:      https://$(oc get route litemaas -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo 'litemaas-litemaas.apps.<cluster>')"
    echo "  API:     https://$(oc get route litemaas-api -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo 'litemaas-api-litemaas.apps.<cluster>')"
    echo "  LiteLLM: https://$(oc get route litellm -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo 'litellm-litemaas.apps.<cluster>')"
    echo ""
    echo "Next steps:"
    echo "  1. Navigate to the UI URL"
    echo "  2. Click 'Login with OpenShift'"
    echo "  3. Subscribe to models"
    echo "  4. Create an API key"
    echo "  5. Use the Chatbot Playground or API"
    ;;
    
  status)
    echo -e "${GREEN}=== LiteMaaS Status ===${NC}"
    echo ""
    echo "Pods:"
    oc get pods -n ${NAMESPACE} 2>/dev/null || echo "Namespace not found"
    echo ""
    echo "Routes:"
    oc get routes -n ${NAMESPACE} 2>/dev/null || echo "No routes"
    echo ""
    echo "Models in LiteLLM:"
    oc exec deployment/backend -n ${NAMESPACE} -- curl -s http://litellm:4000/model/info \
      -H "Authorization: Bearer ${MASTER_KEY}" 2>/dev/null | jq -r '.data[].model_name' 2>/dev/null || echo "Could not fetch models"
    echo ""
    echo "Models in Backend DB:"
    oc exec -n ${NAMESPACE} postgres-0 -- psql -U litemaas_admin -d litemaas_db -c \
      "SELECT id, name FROM models;" 2>/dev/null || echo "Could not query database"
    ;;
    
  cleanup)
    echo -e "${YELLOW}=== Cleaning up LiteMaaS ===${NC}"
    echo ""
    
    # Delete ArgoCD app if exists
    echo "Removing ArgoCD application..."
    oc delete application step-06b-private-ai-litemaas -n openshift-gitops --ignore-not-found
    
    # Delete namespace
    echo "Deleting namespace..."
    oc delete namespace ${NAMESPACE} --ignore-not-found --wait=false
    
    # Delete cluster-level resources
    echo "Cleaning up cluster-level resources..."
    oc delete oauthclient litemaas-oauth-client --ignore-not-found
    oc delete group litemaas-admins litemaas-users --ignore-not-found 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}Cleanup complete${NC}"
    ;;
    
  *)
    echo "Usage: $0 {deploy|status|cleanup}"
    echo ""
    echo "Commands:"
    echo "  deploy   - Deploy LiteMaaS (default)"
    echo "  status   - Show deployment status"
    echo "  cleanup  - Remove all LiteMaaS resources"
    exit 1
    ;;
esac
