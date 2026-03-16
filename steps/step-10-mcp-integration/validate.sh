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

# --- MCP Tool_Group Registration ---
log_step "MCP Tool_Group Registration"
LSD_POD=$(oc get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep "^lsd-rag" | head -1 || true)
if [[ -n "$LSD_POD" ]]; then
    for tg in openshift database slack; do
        TG_EXISTS=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
            curl -sf "http://localhost:8321/v1/toolgroups/mcp::${tg}" 2>/dev/null || true)
        if [[ -n "$TG_EXISTS" ]] && echo "$TG_EXISTS" | grep -q "mcp::${tg}"; then
            echo -e "${GREEN}[PASS]${NC} Tool_group mcp::${tg} registered"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${RED}[FAIL]${NC} Tool_group mcp::${tg} not registered"
            VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
        fi
    done
else
    echo -e "${YELLOW}[WARN]${NC} lsd-rag pod not found — skipping tool_group checks"
    VALIDATE_WARN=$((VALIDATE_WARN + 3))
fi

# --- MCP Functional Tests ---
log_step "MCP Functional Tests"
if [[ -n "$LSD_POD" ]]; then
    # OpenShift MCP — list pods in acme-corp
    OCP_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/tool-runtime/invoke \
        -H "Content-Type: application/json" \
        -d '{"tool_name":"pods_list_in_namespace","kwargs":{"namespace":"acme-corp"},"tool_group_id":"mcp::openshift"}' 2>/dev/null || echo "ERROR")
    if echo "$OCP_RESULT" | grep -qi "acme-equipment"; then
        echo -e "${GREEN}[PASS]${NC} OpenShift MCP: pods_list_in_namespace returned acme-equipment pods"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} OpenShift MCP: pods_list_in_namespace failed"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    # Database MCP — list schemas
    DB_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/tool-runtime/invoke \
        -H "Content-Type: application/json" \
        -d '{"tool_name":"list_schemas","kwargs":{},"tool_group_id":"mcp::database"}' 2>/dev/null || echo "ERROR")
    if echo "$DB_RESULT" | grep -qi "public"; then
        echo -e "${GREEN}[PASS]${NC} Database MCP: list_schemas returned public schema"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} Database MCP: list_schemas failed"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    # Database MCP — execute_sql for equipment lookup
    SQL_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/tool-runtime/invoke \
        -H "Content-Type: application/json" \
        -d '{"tool_name":"execute_sql","kwargs":{"sql":"SELECT equipment_id FROM acme_pod_equipment_map WHERE pod_name = '\''acme-equipment-0007'\''"},"tool_group_id":"mcp::database"}' 2>/dev/null || echo "ERROR")
    if echo "$SQL_RESULT" | grep -qi "L-900-08"; then
        echo -e "${GREEN}[PASS]${NC} Database MCP: equipment lookup returned L-900-08"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} Database MCP: equipment lookup failed (expected L-900-08)"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    # Slack MCP — list channels
    SLACK_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/tool-runtime/invoke \
        -H "Content-Type: application/json" \
        -d '{"tool_name":"channels_list","kwargs":{},"tool_group_id":"mcp::slack"}' 2>/dev/null || echo "ERROR")
    if echo "$SLACK_RESULT" | grep -qi "acme-mcp-demo\|mcp-demo"; then
        echo -e "${GREEN}[PASS]${NC} Slack MCP: channels_list returned demo channel"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} Slack MCP: channels_list failed"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
else
    echo -e "${YELLOW}[WARN]${NC} lsd-rag pod not found — skipping functional tests"
    VALIDATE_WARN=$((VALIDATE_WARN + 4))
fi

# --- Summary ---
echo ""
validation_summary
