#!/bin/bash
# ACME Demo Flow Validation — 4-Question End-to-End Test
#
# Tests the full agentic workflow:
#   Q1: List pods in acme-corp (openshift-mcp)
#   Q2: Fetch equipment for failed pod (database-mcp)
#   Q3: RAG search for known issues (Milvus/LlamaStack)
#   Q4: Send Slack summary (slack-mcp)

set -euo pipefail

NAMESPACE="private-ai"
ACME_NS="acme-corp"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  ACME Demo Flow Validation (4-Question E2E Test)               ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

PASS=0
FAIL=0

# ═══════════════════════════════════════════════════════════════════
# Pre-flight: Infrastructure
# ═══════════════════════════════════════════════════════════════════
log_step "Pre-flight: Infrastructure"

for dep in milvus-standalone lsd-rag database-mcp openshift-mcp slack-mcp postgresql; do
    if oc get deploy "$dep" -n "$NAMESPACE" &>/dev/null; then
        log_success "  $dep: deployed"
    else
        log_error "  $dep: MISSING"
        FAIL=$((FAIL + 1))
    fi
done

if oc get namespace "$ACME_NS" &>/dev/null; then
    log_success "  acme-corp namespace: exists"
else
    log_error "  acme-corp namespace: MISSING — deploy step-12 first"
    FAIL=$((FAIL + 1))
fi

POD_COUNT=$(oc get pods -n "$ACME_NS" -l app=acme-equipment --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$POD_COUNT" -ge 3 ]; then
    log_success "  acme-corp pods: $POD_COUNT found"
else
    log_error "  acme-corp pods: only $POD_COUNT found (need 3)"
    FAIL=$((FAIL + 1))
fi
echo ""

# Find the lsd-rag pod for API calls
LSD_POD=$(oc get pods -l app.kubernetes.io/name=llamastack-rag -n "$NAMESPACE" \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)

if [ -z "$LSD_POD" ]; then
    log_error "lsd-rag pod not found. Cannot run demo flow tests."
    echo "  Deploy step-09 first."
    exit 1
fi
log_success "Using LlamaStack pod: $LSD_POD"
echo ""

# ═══════════════════════════════════════════════════════════════════
# Q1: List pods in acme-corp
# ═══════════════════════════════════════════════════════════════════
log_step "Q1: List pods in acme-corp project"

Q1_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s http://localhost:8321/v1/tool-runtime/invoke \
    -H "Content-Type: application/json" \
    -d '{
        "tool_name": "list_pods_summary",
        "kwargs": {"namespace": "acme-corp"},
        "tool_group_id": "mcp::openshift"
    }' 2>/dev/null || echo "ERROR")

if echo "$Q1_RESULT" | grep -qi "acme-equipment-0007"; then
    log_success "  Found acme-equipment-0007 in pod listing"
    PASS=$((PASS + 1))
else
    log_error "  acme-equipment-0007 not found in response"
    echo "  Response: ${Q1_RESULT:0:300}"
    FAIL=$((FAIL + 1))
fi

if echo "$Q1_RESULT" | grep -qi "crashloop\|error\|not ready\|0/1"; then
    log_success "  Pod 0007 shows failure status"
    PASS=$((PASS + 1))
else
    log_info "  Pod 0007 failure status not clearly visible (may need agent interpretation)"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# Q2: Fetch equipment for failed pod
# ═══════════════════════════════════════════════════════════════════
log_step "Q2: Fetch equipment name for the failed pod"

Q2_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s http://localhost:8321/v1/tool-runtime/invoke \
    -H "Content-Type: application/json" \
    -d '{
        "tool_name": "query_pod_equipment",
        "kwargs": {"pod_name": "acme-equipment-0007"},
        "tool_group_id": "mcp::database"
    }' 2>/dev/null || echo "ERROR")

if echo "$Q2_RESULT" | grep -qi "L-900-08"; then
    log_success "  Equipment L-900-08 found"
    PASS=$((PASS + 1))
else
    log_error "  Equipment L-900-08 not in response"
    echo "  Response: ${Q2_RESULT:0:300}"
    FAIL=$((FAIL + 1))
fi

if echo "$Q2_RESULT" | grep -qi "L-900 EUV"; then
    log_success "  Product name 'L-900 EUV' found"
    PASS=$((PASS + 1))
else
    log_error "  Product name not in response"
    FAIL=$((FAIL + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# Q3: RAG search for known issues
# ═══════════════════════════════════════════════════════════════════
log_step "Q3: Search for known issues (RAG)"

Q3_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s http://localhost:8321/v1/vector-io/query \
    -H "Content-Type: application/json" \
    -d '{
        "vector_db_id": "acme_corporate",
        "query": "L-900 EUV DFO calibration drift known issues"
    }' 2>/dev/null || echo "ERROR")

CHUNK_COUNT=$(echo "$Q3_RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data.get('chunks', [])))
except:
    print('0')
" 2>/dev/null)

if [ "$CHUNK_COUNT" -gt 0 ]; then
    log_success "  RAG returned $CHUNK_COUNT chunks for L-900 EUV query"
    PASS=$((PASS + 1))
else
    log_error "  RAG returned 0 chunks — acme_corporate collection may be empty"
    log_info "  Fix: cd steps/step-09-rag-pipeline && ./run-batch-ingestion.sh acme"
    FAIL=$((FAIL + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# Q4: Send Slack message
# ═══════════════════════════════════════════════════════════════════
log_step "Q4: Send Slack summary"

Q4_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- curl -s http://localhost:8321/v1/tool-runtime/invoke \
    -H "Content-Type: application/json" \
    -d '{
        "tool_name": "send_slack_message",
        "kwargs": {"message": "[DEMO VALIDATION] Equipment L-900-08 in CrashLoopBackOff. DFO calibration drift detected. Recommended: schedule DFO recalibration using Part P12345."},
        "tool_group_id": "mcp::slack"
    }' 2>/dev/null || echo "ERROR")

if echo "$Q4_RESULT" | grep -qi "sent\|success\|demo\|acme-litho"; then
    log_success "  Slack message sent (demo mode)"
    PASS=$((PASS + 1))
else
    log_error "  Slack message failed"
    echo "  Response: ${Q4_RESULT:0:300}"
    FAIL=$((FAIL + 1))
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════
TOTAL=$((PASS + FAIL))

echo "╔══════════════════════════════════════════════════════════════════╗"
if [ "$FAIL" -eq 0 ]; then
echo "║  DEMO FLOW: ALL CHECKS PASSED ($PASS/$TOTAL)                        ║"
else
echo "║  DEMO FLOW: $FAIL CHECKS FAILED ($PASS/$TOTAL passed)                    ║"
fi
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Q1 (List pods):         openshift-mcp -> acme-corp            ║"
echo "║  Q2 (Equipment lookup):  database-mcp -> PostgreSQL            ║"
echo "║  Q3 (RAG search):        vector-io -> Milvus acme_corporate    ║"
echo "║  Q4 (Slack alert):       slack-mcp -> demo mode                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
