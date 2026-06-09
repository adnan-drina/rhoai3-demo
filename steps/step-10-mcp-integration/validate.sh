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

ACME_0007_REASON=$(oc get pod acme-equipment-0007 -n acme-corp \
    -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
ACME_0007_ANNOTATIONS=$(oc get pod acme-equipment-0007 -n acme-corp -o json 2>/dev/null || echo '{}')
ACME_0007_IGNORE_HEALTH=$(printf '%s' "$ACME_0007_ANNOTATIONS" \
    | jq -r '.metadata.annotations["argocd.argoproj.io/ignore-healthcheck"] // ""' 2>/dev/null || true)
ACME_0007_IGNORE_UPDATES=$(printf '%s' "$ACME_0007_ANNOTATIONS" \
    | jq -r '.metadata.annotations["argocd.argoproj.io/ignore-resource-updates"] // ""' 2>/dev/null || true)
ACME_0007_DEMO_FAILURE=$(printf '%s' "$ACME_0007_ANNOTATIONS" \
    | jq -r '.metadata.annotations["demo.rhoai.redhat.com/intentional-failure"] // ""' 2>/dev/null || true)
if [[ "$ACME_0007_DEMO_FAILURE" == "true" && "$ACME_0007_IGNORE_HEALTH" == "true" && "$ACME_0007_IGNORE_UPDATES" == "true" ]]; then
    echo -e "${GREEN}[PASS]${NC} acme-equipment-0007 is marked as intentional demo failure and ignored for Argo CD resource-update noise"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} acme-equipment-0007 missing demo failure or Argo CD ignore annotations"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

if [[ "$APP_HEALTH" == "Healthy" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app 'step-10-mcp-integration' health: Healthy"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Argo CD app health unexpected (got: $APP_HEALTH, acme-equipment-0007 reason: ${ACME_0007_REASON:-unknown})"
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
    TRANSPORT=$(oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o json 2>/dev/null \
        | jq -r --arg key "$mcp_key" '.data[$key] | fromjson | .transport // ""' 2>/dev/null || true)
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

for pod in acme-equipment-0001 acme-equipment-0005; do
    PHASE=$(oc get pod "$pod" -n acme-corp -o jsonpath='{.status.phase}' 2>/dev/null || echo "NOT_FOUND")
    if [[ "$PHASE" == "Running" ]]; then
        echo -e "${GREEN}[PASS]${NC} $pod is Running"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} $pod expected Running, got $PHASE"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
done

ACME_0007_REASON=$(oc get pod acme-equipment-0007 -n acme-corp \
    -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
if [[ "$ACME_0007_REASON" == "CrashLoopBackOff" ]]; then
    echo -e "${GREEN}[PASS]${NC} acme-equipment-0007 is intentionally CrashLoopBackOff for the RAG/MCP troubleshooting story"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} acme-equipment-0007 expected CrashLoopBackOff, got ${ACME_0007_REASON:-unknown}"
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
