#!/usr/bin/env bash
# Step 07: RAG Pipeline — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="private-ai"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 07: RAG Pipeline — Validation                            ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Argo CD Application ---
# step-07 ArgoCD app shows Unknown sync due to ignoreDifferences on LSD spec
log_step "Argo CD Application"
SYNC=$(oc get application step-07-rag -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NOT_FOUND")
HEALTH=$(oc get application step-07-rag -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "NOT_FOUND")
if [[ "$SYNC" == "Synced" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app 'step-07-rag' sync: Synced"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
elif [[ "$SYNC" == "Unknown" ]]; then
    echo -e "${YELLOW}[WARN]${NC} Argo CD app 'step-07-rag' sync: Unknown (ignoreDifferences on LSD spec)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
else
    echo -e "${RED}[FAIL]${NC} Argo CD app 'step-07-rag' sync: $SYNC"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
if [[ "$HEALTH" == "Healthy" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app 'step-07-rag' health: Healthy"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} Argo CD app 'step-07-rag' health: $HEALTH"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Infrastructure ---
log_step "Infrastructure"
check_pods_ready "$NAMESPACE" "app=llamastack-postgres" 1
DOCLING_READY=$(oc get pods -n "$NAMESPACE" -l app=docling-service --no-headers 2>/dev/null \
    | grep -c "Running" || true)
if [[ "$DOCLING_READY" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} Docling service running"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} Docling service not running ($DOCLING_READY pods) — may be restarting"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

check "DSPA dspa-rag exists" \
    "oc get dspa dspa-rag -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "dspa-rag"

check "LlamaStackDistribution lsd-rag Ready" \
    "oc get llamastackdistribution lsd-rag -n $NAMESPACE -o jsonpath='{.status.phase}'" \
    "Ready"

# --- pgvector Extension ---
log_step "pgvector Extension"
PGVECTOR=$(oc exec deploy/llamastack-postgres -n "$NAMESPACE" -- \
    psql -U llamastack -d llamastack -tA -c "SELECT extname FROM pg_extension WHERE extname='vector';" 2>/dev/null || echo "")
if [[ "$PGVECTOR" == "vector" ]]; then
    echo -e "${GREEN}[PASS]${NC} pgvector extension enabled"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} pgvector extension not found"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Vector Stores ---
log_step "Vector Stores"
LSD_POD=$(oc get pods -l app.kubernetes.io/instance=lsd-rag -n "$NAMESPACE" \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)

if [[ -z "$LSD_POD" ]]; then
    LSD_POD=$(oc get pods -l app=llama-stack -n "$NAMESPACE" \
        --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep "lsd-rag" | head -1)
fi

if [[ -n "$LSD_POD" ]]; then
    VS_COUNT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/vector_stores 2>/dev/null | \
        python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    stores = data.get('data', [])
    populated = [v for v in stores if v['file_counts']['completed'] > 0]
    print(len(populated))
except:
    print('0')
" 2>/dev/null || echo "0")

    if [[ "$VS_COUNT" -ge 3 ]]; then
        echo -e "${GREEN}[PASS]${NC} $VS_COUNT vector stores with data"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    elif [[ "$VS_COUNT" -ge 1 ]]; then
        echo -e "${YELLOW}[WARN]${NC} $VS_COUNT vector store(s) with data (expected 3)"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    else
        echo -e "${RED}[FAIL]${NC} No vector stores with data"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    # --- Providers ---
    log_step "LlamaStack Providers"
    for provider in pgvector sentence-transformers vllm-inference; do
        HAS=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
            curl -s http://localhost:8321/v1/providers 2>/dev/null | \
            python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len([p for p in data['data'] if p['provider_id']=='$provider']))
except:
    print('0')
" 2>/dev/null || echo "0")
        if [[ "$HAS" -ge 1 ]]; then
            echo -e "${GREEN}[PASS]${NC} Provider $provider registered"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${RED}[FAIL]${NC} Provider $provider not found"
            VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
        fi
    done
else
    echo -e "${RED}[FAIL]${NC} lsd-rag pod not found"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Summary ---
echo ""
validation_summary
