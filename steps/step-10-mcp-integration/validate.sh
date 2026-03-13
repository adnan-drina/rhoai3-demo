#!/usr/bin/env bash
# Step 10: MCP Integration — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="private-ai"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 10: MCP Integration — Validation                         ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Argo CD Application ---
log_step "Argo CD Application"
check_argocd_app "step-10-mcp-integration"

# --- MCP Server Deployments ---
log_step "MCP Server Deployments"
for server in database-mcp openshift-mcp slack-mcp; do
    check "Deployment $server ready" \
        "oc get deploy $server -n $NAMESPACE -o jsonpath='{.status.availableReplicas}'" \
        "1"
done

# --- PostgreSQL ---
log_step "PostgreSQL"
check_pods_ready "$NAMESPACE" "app=postgresql" 1

# --- Playground ConfigMap ---
log_step "Playground MCP ConfigMap"
check "ConfigMap gen-ai-aa-mcp-servers exists" \
    "oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o jsonpath='{.metadata.name}'" \
    "gen-ai-aa-mcp-servers"

# --- ACME Demo Namespace ---
log_step "ACME Demo Environment"
check "acme-corp namespace exists" \
    "oc get namespace acme-corp -o jsonpath='{.metadata.name}'" \
    "acme-corp"

ACME_PODS=$(oc get pods -n acme-corp -l app=acme-equipment --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$ACME_PODS" -ge 3 ]]; then
    echo -e "${GREEN}[PASS]${NC} ACME equipment pods: $ACME_PODS"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} ACME equipment pods: $ACME_PODS (expected 3)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- MCP Server Connectivity ---
log_step "MCP Server Connectivity"
for server_port in "database-mcp:8080" "openshift-mcp:8000" "slack-mcp:8080"; do
    server=$(echo "$server_port" | cut -d: -f1)
    port=$(echo "$server_port" | cut -d: -f2)
    POD=$(oc get pods -l "app=$server" -n "$NAMESPACE" \
        --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)
    if [[ -n "$POD" ]]; then
        echo -e "${GREEN}[PASS]${NC} $server pod found: $POD (port $port)"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} $server: no pod found"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
done

# --- Summary ---
echo ""
validation_summary
