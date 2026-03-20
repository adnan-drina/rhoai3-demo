#!/usr/bin/env bash
# ACME Demo Flow Validation — 3-Layer End-to-End Test
#
# Layer 1: Tool Runtime (deterministic) — direct MCP tool invocations
# Layer 2: Agentic (LLM-driven) — Responses API with natural language prompts
# Layer 3: Guardrails — PII detection on ACME contact data
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="private-ai"
ACME_NS="acme-corp"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  ACME Demo Flow — 3-Layer E2E Validation                       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════════════
# Pre-flight: Infrastructure
# ═══════════════════════════════════════════════════════════════════════
log_step "Pre-flight: Infrastructure"

for dep in llamastack-postgres database-mcp openshift-mcp slack-mcp postgresql; do
    check "Deployment $dep exists" \
        "oc get deploy $dep -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
        "$dep"
done

if oc get deploy lsd-rag -n "$NAMESPACE" &>/dev/null; then
    echo -e "${GREEN}[PASS]${NC} Deployment lsd-rag exists"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Deployment lsd-rag not found"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

check "acme-corp namespace exists" \
    "oc get namespace $ACME_NS -o jsonpath='{.metadata.name}'" \
    "$ACME_NS"

POD_COUNT=$(oc get pods -n "$ACME_NS" -l app=acme-equipment --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$POD_COUNT" -ge 3 ]]; then
    echo -e "${GREEN}[PASS]${NC} acme-corp equipment pods: $POD_COUNT"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} acme-corp equipment pods: $POD_COUNT (need >= 3)"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

LSD_POD=$(oc get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null \
    | grep "^lsd-rag" | head -1 || true)

if [[ -z "$LSD_POD" ]]; then
    echo -e "${RED}[FAIL]${NC} lsd-rag pod not found — cannot run demo flow tests"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    echo ""
    validation_summary
    exit $?
fi
echo -e "${GREEN}[PASS]${NC} Using LlamaStack pod: $LSD_POD"
VALIDATE_PASS=$((VALIDATE_PASS + 1))
echo ""

# ═══════════════════════════════════════════════════════════════════════
# Layer 1: Tool Runtime (deterministic — direct MCP tool invocations)
# ═══════════════════════════════════════════════════════════════════════
log_step "Layer 1: Tool Runtime — Direct MCP Invocations"

# Q1: OpenShift MCP — list pods in acme-corp
log_step "Q1: pods_list_in_namespace (mcp::openshift)"
Q1_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s http://localhost:8321/v1/tool-runtime/invoke \
    -H "Content-Type: application/json" \
    -d '{"tool_name":"pods_list_in_namespace","kwargs":{"namespace":"acme-corp"},"tool_group_id":"mcp::openshift"}' \
    2>/dev/null || echo "ERROR")

if echo "$Q1_RESULT" | grep -qi "acme-equipment-0007"; then
    echo -e "${GREEN}[PASS]${NC} Found acme-equipment-0007 in pod listing"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} acme-equipment-0007 not found in response"
    echo "  Response: ${Q1_RESULT:0:200}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

if echo "$Q1_RESULT" | grep -qi "CrashLoopBackOff\|Error\|not ready\|0/1"; then
    echo -e "${GREEN}[PASS]${NC} Pod 0007 shows failure status"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} Pod 0007 failure status not clearly visible"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi
echo ""

# Q2: Database MCP — equipment lookup via SQL
log_step "Q2: execute_sql (mcp::database)"
Q2_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s http://localhost:8321/v1/tool-runtime/invoke \
    -H "Content-Type: application/json" \
    -d '{"tool_name":"execute_sql","kwargs":{"sql":"SELECT equipment_id, product_name FROM acme_pod_equipment_map WHERE pod_name = '\''acme-equipment-0007'\''"},"tool_group_id":"mcp::database"}' \
    2>/dev/null || echo "ERROR")

if echo "$Q2_RESULT" | grep -qi "L-900-08"; then
    echo -e "${GREEN}[PASS]${NC} Equipment L-900-08 found"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Equipment L-900-08 not in response"
    echo "  Response: ${Q2_RESULT:0:200}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

if echo "$Q2_RESULT" | grep -qi "L-900 EUV\|Calibration Suite"; then
    echo -e "${GREEN}[PASS]${NC} Product name found"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Product name not in response"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
echo ""

# Q3: RAG — vector store search
log_step "Q3: Vector store search (acme_corporate)"
ACME_VS_ID=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s http://localhost:8321/v1/vector_stores 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(next((s['id'] for s in d['data'] if s['name']=='acme_corporate'),''))" 2>/dev/null || true)

if [[ -z "$ACME_VS_ID" ]]; then
    Q3_RESULT="ERROR: acme_corporate vector store not found"
    CHUNK_COUNT=0
else
    Q3_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s "http://localhost:8321/v1/vector_stores/${ACME_VS_ID}/search" \
        -H "Content-Type: application/json" \
        -d '{"query":"L-900 EUV DFO calibration drift known issues","max_num_results":5}' \
        2>/dev/null || echo "ERROR")

    CHUNK_COUNT=$(echo "$Q3_RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data.get('data', data.get('chunks', []))))
except:
    print('0')
" 2>/dev/null || echo "0")
fi

if [[ "$CHUNK_COUNT" -gt 0 ]]; then
    echo -e "${GREEN}[PASS]${NC} RAG returned $CHUNK_COUNT chunks"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} RAG returned 0 chunks — run step-07 ingestion pipelines"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
echo ""

# Q4: Slack MCP — send message
log_step "Q4: conversations_add_message (mcp::slack)"
Q4_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s http://localhost:8321/v1/tool-runtime/invoke \
    -H "Content-Type: application/json" \
    -d '{"tool_name":"conversations_add_message","kwargs":{"channel_id":"C09JL81TUQJ","payload":"[E2E VALIDATION] Equipment L-900-08 (acme-equipment-0007) in CrashLoopBackOff. DFO calibration drift detected. Recommended: schedule recalibration."},"tool_group_id":"mcp::slack"}' \
    2>/dev/null || echo "ERROR")

if echo "$Q4_RESULT" | grep -qi "ok\|sent\|success\|message_ts\|acme"; then
    echo -e "${GREEN}[PASS]${NC} Slack message sent"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Slack message failed"
    echo "  Response: ${Q4_RESULT:0:200}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════
# Layer 2: Agentic — Responses API (LLM-driven, non-deterministic)
# ═══════════════════════════════════════════════════════════════════════
log_step "Layer 2: Agentic — Responses API"

# LlamaStack Responses API uses SSE transport natively — always /sse for all servers.
# Each agentic test scopes tools to the relevant MCP server to avoid overwhelming
# Granite 8B with 31+ tools. In the chatbot UI, conversational context compensates;
# in independent E2E tests, scoped tools ensure reliable tool selection.
# file_search requires the vector store ID (not name) for the Responses API to return results.
ACME_VS_ID_FOR_AGENT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s http://localhost:8321/v1/vector_stores 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(next((s['id'] for s in d.get('data',[]) if s['name']=='acme_corporate'),'acme_corporate'))" 2>/dev/null || echo "acme_corporate")

OPENSHIFT_TOOLS='[{"type":"mcp","server_label":"openshift","server_url":"http://openshift-mcp.private-ai.svc:8000/sse","require_approval":"never"}]'
DATABASE_TOOLS='[{"type":"mcp","server_label":"database","server_url":"http://database-mcp.private-ai.svc:8080/sse","require_approval":"never"}]'
SLACK_TOOLS='[{"type":"mcp","server_label":"slack","server_url":"http://slack-mcp.private-ai.svc:8080/sse","require_approval":"never"}]'
RAG_TOOLS="[{\"type\":\"file_search\",\"vector_store_ids\":[\"${ACME_VS_ID_FOR_AGENT}\"]}]"

AGENT_INSTRUCTIONS="You are a helpful assistant. You MUST use your tools to answer questions. Base your answer on the tool results, not prior knowledge. If a tool call fails, retry with corrected parameters. For database lookups, use execute_sql on the acme_pod_equipment_map table (columns: pod_name, equipment_id, product_name)."

run_agentic_test() {
    local label="$1"
    local prompt="$2"
    local pass_pattern="$3"
    local tools="$4"

    log_step "$label"
    local RESULT
    RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s --max-time 180 http://localhost:8321/v1/responses \
        -H "Content-Type: application/json" \
        -d "{
            \"model\":\"vllm-inference/granite-8b-agent\",
            \"instructions\":\"$AGENT_INSTRUCTIONS\",
            \"input\":\"$prompt\",
            \"tools\":$tools,
            \"tool_choice\":\"required\",
            \"max_infer_iters\":20,
            \"stream\":false
        }" 2>/dev/null || echo "ERROR")

    if echo "$RESULT" | grep -qiE "$pass_pattern"; then
        echo -e "${GREEN}[PASS]${NC} Agent response matches expected pattern"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} Agent response did not match pattern (LLM non-deterministic)"
        echo "  Expected: $pass_pattern"
        echo "  Response: ${RESULT:0:200}"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
    echo ""
}

run_agentic_test "A1: List pods in acme-corp" \
    "List all pods in the acme-corp namespace" \
    "acme-equipment|0007|CrashLoop" \
    "$OPENSHIFT_TOOLS"

run_agentic_test "A2: Equipment for failed pod" \
    "Fetch the equipment name for pod acme-equipment-0007" \
    "L-900|EUV|Calibration" \
    "$DATABASE_TOOLS"

run_agentic_test "A3: Search known issues" \
    "Search for known issues related to the L-900 EUV scanner" \
    "calibration|DFO|drift|procedure" \
    "$RAG_TOOLS"

run_agentic_test "A4: Send Slack summary" \
    "Send a brief summary of the L-900-08 issue to Slack channel C09JL81TUQJ" \
    "slack|sent|message|conversations_add" \
    "$SLACK_TOOLS"

# ═══════════════════════════════════════════════════════════════════════
# Layer 3: Guardrails — PII Detection
# ═══════════════════════════════════════════════════════════════════════
log_step "Layer 3: Guardrails — PII Detection"

ORCH_POD=$(oc get pods -l app=guardrails-orchestrator -n "$NAMESPACE" \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1 || true)

if [[ -n "$ORCH_POD" ]]; then
    PII_COUNT=$(oc exec "$ORCH_POD" -n "$NAMESPACE" -c guardrails-orchestrator -- \
        curl -sk https://localhost:8032/api/v2/text/detection/content \
        -H "Content-Type: application/json" \
        -d '{"detectors":{"regex":{"regex":["email","(?i)\\+31[\\s-]*\\d[\\s-]*\\d{3,}","(?i)linkedin\\.com/in/\\w+"]}},"content":"Contact Dr. Jan de Vries at jan.devries@acme-litho.nl or +31 6 1234 5678. LinkedIn: linkedin.com/in/jandevries"}' \
        2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('detections',[])))" 2>/dev/null || echo "0")

    if [[ "$PII_COUNT" -ge 2 ]]; then
        echo -e "${GREEN}[PASS]${NC} Guardrails PII: $PII_COUNT patterns detected (email, phone, LinkedIn)"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} Guardrails PII: only $PII_COUNT patterns detected (expected >= 2)"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
else
    echo -e "${YELLOW}[WARN]${NC} Guardrails orchestrator not found — skipping PII test"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════
validation_summary
