#!/usr/bin/env bash
# Step 10: MCP Integration — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="enterprise-rag"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 10: MCP Integration — Validation                         ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Argo CD Application ---
log_step "Argo CD Application"
APP_SYNC=$(oc get applications.argoproj.io step-10-mcp-integration -n openshift-gitops \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NOT_FOUND")
APP_HEALTH=$(oc get applications.argoproj.io step-10-mcp-integration -n openshift-gitops \
    -o jsonpath='{.status.health.status}' 2>/dev/null || echo "NOT_FOUND")

if [[ "$APP_SYNC" == "Synced" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app 'step-10-mcp-integration' sync: Synced"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Argo CD app 'step-10-mcp-integration' sync (expected: Synced, got: $APP_SYNC)"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

if [[ "$APP_HEALTH" == "Healthy" || "$APP_HEALTH" == "Degraded" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app 'step-10-mcp-integration' health: $APP_HEALTH (expected for failing ACME pod demo)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Argo CD app 'step-10-mcp-integration' health (expected: Healthy or Degraded, got: $APP_HEALTH)"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

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

# Verify SSE-only servers have transport:sse (gen-ai backend defaults to streamable-http)
for mcp_key in "Database-MCP" "Slack-MCP"; do
    TRANSPORT=$(oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications \
        -o jsonpath="{.data.${mcp_key}}" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('transport',''))" 2>/dev/null || true)
    if [[ "$TRANSPORT" == "sse" ]]; then
        echo -e "${GREEN}[PASS]${NC} $mcp_key has transport: sse"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} $mcp_key missing transport: sse — Dashboard may show Error"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
done

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

# --- Llama Stack MCP Connectors ---
log_step "Llama Stack MCP Connectors"
LSD_POD=$(oc get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep "^lsd-rag" | head -1 || true)
if [[ -n "$LSD_POD" ]]; then
    CONNECTORS=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -sf --max-time 15 "http://localhost:8321/v1beta/connectors" 2>/dev/null || true)
    for connector in openshift-mcp database-mcp slack-mcp; do
        if echo "$CONNECTORS" | grep -q "\"connector_id\":\"${connector}\""; then
            echo -e "${GREEN}[PASS]${NC} Connector ${connector} registered"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${RED}[FAIL]${NC} Connector ${connector} not registered"
            VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
        fi
    done
else
    echo -e "${YELLOW}[WARN]${NC} lsd-rag pod not found — skipping connector checks"
    VALIDATE_WARN=$((VALIDATE_WARN + 3))
fi

# --- MCP Tool Discovery ---
log_step "MCP Tool Discovery"
if [[ -n "$LSD_POD" ]]; then
    for connector in openshift-mcp database-mcp slack-mcp; do
        TOOLS=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
            curl -sf --max-time 30 "http://localhost:8321/v1beta/connectors/${connector}/tools" 2>/dev/null || true)
        if echo "$TOOLS" | grep -q '"name"'; then
            TOOL_COUNT=$(echo "$TOOLS" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("data", [])))' 2>/dev/null || echo "unknown")
            echo -e "${GREEN}[PASS]${NC} ${connector}: discovered ${TOOL_COUNT} MCP tools"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${RED}[FAIL]${NC} ${connector}: no MCP tools discovered"
            VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
        fi
    done
else
    echo -e "${YELLOW}[WARN]${NC} lsd-rag pod not found — skipping tool discovery"
    VALIDATE_WARN=$((VALIDATE_WARN + 3))
fi

# --- Summary ---
echo ""
validation_summary
