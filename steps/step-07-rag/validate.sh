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
DOCLING_READY=$(oc get pods -n "$NAMESPACE" -l app=docling --no-headers 2>/dev/null \
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
    VS_JSON=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/vector_stores 2>/dev/null || echo '{"data":[]}')

    for vs_name in acme_corporate whoami; do
        VS_FILES=$(echo "$VS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    store = next((v for v in data.get('data', []) if v['name'] == '$vs_name'), None)
    print(store['file_counts']['completed'] if store else 0)
except:
    print(0)
" 2>/dev/null || echo "0")
        if [[ "$VS_FILES" -ge 1 ]]; then
            echo -e "${GREEN}[PASS]${NC} Vector store '$vs_name' has $VS_FILES file(s)"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${RED}[FAIL]${NC} Vector store '$vs_name' missing or empty — run: ./steps/step-07-rag/run-batch-ingestion.sh $vs_name"
            VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
        fi
    done

    # --- File Attributes (citation metadata) ---
    log_step "File Citation Attributes"
    FIRST_VS_ID=$(echo "$VS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    store = next((v for v in data.get('data', []) if v['name'] == 'acme_corporate'), None)
    print(store['id'] if store else '')
except:
    print('')
" 2>/dev/null || echo "")
    if [[ -n "$FIRST_VS_ID" ]]; then
        HAS_SOURCE=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
            curl -s "http://localhost:8321/v1/vector_stores/${FIRST_VS_ID}/files" 2>/dev/null | \
            python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    files_with_source = [f for f in data.get('data', []) if f.get('attributes', {}).get('source')]
    print(len(files_with_source))
except:
    print(0)
" 2>/dev/null || echo "0")
        if [[ "$HAS_SOURCE" -ge 1 ]]; then
            echo -e "${GREEN}[PASS]${NC} File attributes have 'source' metadata ($HAS_SOURCE files)"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${YELLOW}[WARN]${NC} Files missing 'source' attribute — re-ingest: for s in acme whoami; do ./steps/step-07-rag/run-batch-ingestion.sh \$s; done"
            VALIDATE_WARN=$((VALIDATE_WARN + 1))
        fi
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
