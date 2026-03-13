#!/usr/bin/env bash
# Step 08: Model Evaluation — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="private-ai"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 08: Model Evaluation — Validation                        ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- ArgoCD ---
log_step "ArgoCD Application"
check "step-08-model-evaluation ArgoCD app exists" \
    "oc get application step-08-model-evaluation -n openshift-gitops -o jsonpath='{.metadata.name}'" \
    "step-08-model-evaluation"

SYNC_STATUS=$(oc get application step-08-model-evaluation -n openshift-gitops \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Missing")
if [ "$SYNC_STATUS" = "Synced" ]; then
    echo -e "${GREEN}[PASS]${NC} ArgoCD app is Synced"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} ArgoCD app status: $SYNC_STATUS"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Prerequisites (from step-07) ---
log_step "Prerequisites (step-07 infrastructure)"
check "lsd-rag LlamaStackDistribution exists" \
    "oc get llamastackdistribution lsd-rag -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "lsd-rag"

check "DSPA dspa-rag exists" \
    "oc get dspa dspa-rag -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "dspa-rag"

check "PVC rag-pipeline-workspace exists" \
    "oc get pvc rag-pipeline-workspace -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "rag-pipeline-workspace"

# --- Eval ConfigMaps ---
log_step "Eval ConfigMaps (ArgoCD-managed)"
check "ConfigMap eval-configs exists" \
    "oc get configmap eval-configs -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "eval-configs"

check "ConfigMap eval-test-cases exists" \
    "oc get configmap eval-test-cases -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "eval-test-cases"

TEST_KEYS=$(oc get configmap eval-test-cases -n "$NAMESPACE" -o json 2>/dev/null | \
    python3 -c "import json,sys; print(len(json.load(sys.stdin).get('data',{})))" 2>/dev/null || echo "0")
if [ "$TEST_KEYS" -ge 6 ]; then
    echo -e "${GREEN}[PASS]${NC} eval-test-cases has $TEST_KEYS test configs (expected 6)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} eval-test-cases has $TEST_KEYS configs (expected 6)"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- LlamaStack Eval API ---
log_step "LlamaStack Eval API"
LSD_POD=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/instance=lsd-rag \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)
if [[ -z "$LSD_POD" ]]; then
    LSD_POD=$(oc get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep "lsd-rag.*Running" | awk '{print $1}' | head -1)
fi

if [[ -n "$LSD_POD" ]]; then
    # Check eval provider
    EVAL_PROVIDER=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/providers 2>/dev/null | \
        python3 -c "import json,sys; print(len([p for p in json.load(sys.stdin)['data'] if p['api']=='eval']))" 2>/dev/null || echo "0")
    if [ "$EVAL_PROVIDER" -gt 0 ]; then
        echo -e "${GREEN}[PASS]${NC} Eval provider active ($EVAL_PROVIDER)"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} No eval provider — eval API will not work"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    # Check scoring API
    SCORE_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/scoring/score \
        -H "Content-Type: application/json" \
        -d '{"input_rows":[{"input_query":"test","generated_answer":"test answer","expected_answer":"test answer"}],"scoring_functions":{"basic::subset_of":null}}' \
        2>/dev/null || echo "ERROR")
    if echo "$SCORE_RESULT" | grep -qi "results\|score"; then
        echo -e "${GREEN}[PASS]${NC} Scoring API responds (basic::subset_of)"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} Scoring API error"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    # Check localfs dataset provider
    DS_PROVIDER=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/providers 2>/dev/null | \
        python3 -c "import json,sys; print(len([p for p in json.load(sys.stdin)['data'] if p['provider_id']=='localfs']))" 2>/dev/null || echo "0")
    if [ "$DS_PROVIDER" -gt 0 ]; then
        echo -e "${GREEN}[PASS]${NC} localfs dataset provider active"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} localfs dataset provider missing"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
else
    echo -e "${RED}[FAIL]${NC} lsd-rag pod not found"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Vector Stores (RAG data for post-RAG eval) ---
log_step "Vector Stores (needed for post-RAG evaluation)"
if [[ -n "$LSD_POD" ]]; then
    VS_COUNT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/vector_stores 2>/dev/null | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print(len([v for v in d.get('data',[]) if v['file_counts']['completed']>0]))" 2>/dev/null || echo "0")
    if [ "$VS_COUNT" -ge 3 ]; then
        echo -e "${GREEN}[PASS]${NC} $VS_COUNT vector stores with data"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} Only $VS_COUNT stores with data (need 3 for full eval)"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
fi

# --- Summary ---
echo ""
validation_summary
