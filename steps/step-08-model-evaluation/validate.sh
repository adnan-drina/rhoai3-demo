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
if [ "$TEST_KEYS" -ge 4 ]; then
    echo -e "${GREEN}[PASS]${NC} eval-test-cases has $TEST_KEYS test configs (expected 4)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} eval-test-cases has $TEST_KEYS configs (expected 4)"
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
    if [ "$VS_COUNT" -ge 2 ]; then
        echo -e "${GREEN}[PASS]${NC} $VS_COUNT vector stores with data"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} Only $VS_COUNT stores with data (need 2 for full eval)"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
fi

# --- Judge Model (mistral-3-bf16) ---
log_step "Judge Model (mistral-3-bf16)"
JUDGE_READY=$(oc get inferenceservice mistral-3-bf16 -n "$NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [ "$JUDGE_READY" = "True" ]; then
    echo -e "${GREEN}[PASS]${NC} mistral-3-bf16 InferenceService is Ready"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} mistral-3-bf16 not ready (required as judge model)"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- LM-Eval Configuration ---
log_step "LM-Eval Configuration"

PERMIT_ONLINE=$(oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.trustyai.eval.lmeval.permitOnline}' 2>/dev/null || echo "")
if [ "$PERMIT_ONLINE" = "allow" ]; then
    echo -e "${GREEN}[PASS]${NC} DSC permitOnline=allow (LM-Eval can download datasets)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} DSC permitOnline not set — LM-Eval online tasks will fail"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

PERMIT_CODE=$(oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.trustyai.eval.lmeval.permitCodeExecution}' 2>/dev/null || echo "")
if [ "$PERMIT_CODE" = "allow" ]; then
    echo -e "${GREEN}[PASS]${NC} DSC permitCodeExecution=allow"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} DSC permitCodeExecution not set — some LM-Eval tasks will fail"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

LMEVAL_TEMPLATES_EXIST=0
for tpl in granite-8b-eval.yaml mistral-bf16-eval.yaml; do
    if [ -f "$REPO_ROOT/gitops/step-08-model-evaluation/base/lmeval/$tpl" ]; then
        LMEVAL_TEMPLATES_EXIST=$((LMEVAL_TEMPLATES_EXIST + 1))
    fi
done
if [ "$LMEVAL_TEMPLATES_EXIST" -ge 2 ]; then
    echo -e "${GREEN}[PASS]${NC} LMEvalJob templates present ($LMEVAL_TEMPLATES_EXIST)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} LMEvalJob templates missing (found $LMEVAL_TEMPLATES_EXIST, expected 2)"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Dashboard LM-Eval UI ---
DISABLE_LMEVAL=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
    -o jsonpath='{.spec.dashboardConfig.disableLMEval}' 2>/dev/null || echo "true")
if [ "$DISABLE_LMEVAL" = "false" ]; then
    echo -e "${GREEN}[PASS]${NC} Dashboard Evaluations page enabled"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} Dashboard Evaluations page disabled (disableLMEval=$DISABLE_LMEVAL)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Eval Reports in MinIO ---
log_step "Eval Reports (MinIO)"
if [[ -n "$LSD_POD" ]]; then
    REPORT_COUNT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- python3 -c "
import boto3, os
try:
    s3 = boto3.client('s3',
        endpoint_url=os.environ.get('AWS_S3_ENDPOINT','http://minio.minio-storage.svc:9000'),
        aws_access_key_id='rhoai-access-key',
        aws_secret_access_key='rhoai-secret-key-12345',
        verify=False)
    resp = s3.list_objects_v2(Bucket='rhoai-storage', Prefix='eval-results/', MaxKeys=100)
    reports = [o['Key'] for o in resp.get('Contents',[]) if o['Key'].endswith('_report.html')]
    print(len(reports))
except Exception:
    print(0)
" 2>/dev/null || echo "0")
    if [ "$REPORT_COUNT" -ge 4 ]; then
        echo -e "${GREEN}[PASS]${NC} $REPORT_COUNT eval reports found in MinIO"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    elif [ "$REPORT_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}[WARN]${NC} Only $REPORT_COUNT reports in MinIO (expected 4 per run)"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} No eval reports in MinIO — run evaluation first"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
else
    echo -e "${YELLOW}[WARN]${NC} Cannot check MinIO reports (lsd-rag pod not available)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Summary ---
echo ""
validation_summary
