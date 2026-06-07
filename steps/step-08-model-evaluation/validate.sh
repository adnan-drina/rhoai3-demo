#!/usr/bin/env bash
# Step 08: Model Evaluation — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="enterprise-rag"
EVALHUB_NAMESPACE="evalhub-system"
MODEL_NAMESPACE="maas"
EVALHUB_SMOKE_NAME_PREFIX="evalhub-granite-smoke"
EVALHUB_EXPERIMENT_NAME="evalhub-granite-smoke"

record_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
}

record_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
}

record_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
}

evalhub_url() {
    local route_host cr_url
    route_host="$(oc get route evalhub -n "$EVALHUB_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
    if [[ -n "$route_host" ]]; then
        printf 'https://%s' "$route_host"
        return 0
    fi

    cr_url="$(oc get evalhub evalhub -n "$EVALHUB_NAMESPACE" -o jsonpath='{.status.url}' 2>/dev/null || true)"
    if [[ "$cr_url" == https://* || "$cr_url" == http://* ]]; then
        printf '%s' "$cr_url"
        return 0
    fi

    return 1
}

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 08: Model Evaluation — Validation                        ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- ArgoCD ---
log_step "ArgoCD Application"
check "step-08-model-evaluation ArgoCD app exists" \
    "oc get applications.argoproj.io step-08-model-evaluation -n openshift-gitops -o jsonpath='{.metadata.name}'" \
    "step-08-model-evaluation"

SYNC_STATUS=$(oc get applications.argoproj.io step-08-model-evaluation -n openshift-gitops \
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

# --- RHOAI 3.4 EvalHub Readiness Gates ---
log_step "RHOAI 3.4 EvalHub Readiness Gates"
EXPECTED_API_SERVER="${RHOAI_EXPECTED_API_SERVER:-${RHOAI_EXPECTED_CLUSTER:-}}"
CURRENT_API_SERVER="$(oc whoami --show-server 2>/dev/null || true)"
if [[ -n "$EXPECTED_API_SERVER" ]]; then
    check "OpenShift API server matches configured guard" \
        "oc whoami --show-server" \
        "$EXPECTED_API_SERVER"
else
    record_pass "OpenShift API server reachable: ${CURRENT_API_SERVER:-unknown}"
fi

check "RHOAI operator CSV is 3.4.0" \
    "oc get subscription rhods-operator -n redhat-ods-operator -o jsonpath='{.status.installedCSV}'" \
    "rhods-operator.3.4.0"

check "DataScienceCluster/default-dsc is Ready" \
    "oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'" \
    "Ready"

check "TrustyAI component is Managed" \
    "oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.trustyai.managementState}'" \
    "Managed"

KSERVE_RAW_MODE="$(oc get datasciencecluster default-dsc \
    -o jsonpath='{.spec.components.kserve.rawDeploymentServiceConfig}' 2>/dev/null || true)"
if [[ -n "$KSERVE_RAW_MODE" ]]; then
    record_pass "KServe RawDeployment service config present: $KSERVE_RAW_MODE"
else
    record_fail "KServe RawDeployment service config missing"
fi

check_crd_exists "evalhubs.trustyai.opendatahub.io"
EVALHUB_DATABASE_EXPLAIN="$(oc explain evalhub.spec.database --api-version=trustyai.opendatahub.io/v1alpha1 2>/dev/null || true)"
if [[ "$EVALHUB_DATABASE_EXPLAIN" == *"db-url"* && "$EVALHUB_DATABASE_EXPLAIN" == *"postgresql"* ]]; then
    record_pass "EvalHub database schema exposes PostgreSQL db-url secret support"
else
    record_fail "EvalHub database schema does not expose expected PostgreSQL db-url secret support"
fi

check "Step 12 MLflow server is Available" \
    "oc get mlflow mlflow -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}'" \
    "True"

for provider in lm-evaluation-harness garak guidellm lighteval; do
    PROVIDER_CONFIGMAP_COUNT="$(oc get configmap -n redhat-ods-applications \
        -l "trustyai.opendatahub.io/evalhub-provider-name=${provider}" \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$PROVIDER_CONFIGMAP_COUNT" -gt 0 ]]; then
        record_pass "EvalHub provider ConfigMap present: $provider"
    else
        record_fail "EvalHub provider ConfigMap missing: $provider"
    fi
done

COLLECTION_CONFIGMAP_COUNT="$(oc get configmap -n redhat-ods-applications \
    -l "trustyai.opendatahub.io/evalhub-collection-name=safety-and-fairness-v1" \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$COLLECTION_CONFIGMAP_COUNT" -gt 0 ]]; then
    record_pass "EvalHub collection ConfigMap present: safety-and-fairness-v1"
else
    record_fail "EvalHub collection ConfigMap missing: safety-and-fairness-v1"
fi

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

# --- MLflow Workspace ---
log_step "MLflow Workspace (RAG evaluation evidence)"
check_crd_exists "mlflows.mlflow.opendatahub.io"
check_crd_exists "mlflowconfigs.mlflow.kubeflow.org"

check "enterprise-rag MLflowConfig points at artifact connection" \
    "oc get mlflowconfig mlflow -n $NAMESPACE -o jsonpath='{.spec.artifactRootSecret}'" \
    "mlflow-artifact-connection"

check "enterprise-rag MLflow artifact connection exists" \
    "oc get secret mlflow-artifact-connection -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "mlflow-artifact-connection"

check "RAG pipeline ServiceAccount has MLflow integration RoleBinding" \
    "oc get rolebinding rag-eval-pipeline-mlflow-client -n $NAMESPACE -o jsonpath='{.roleRef.name}'" \
    "mlflow-operator-mlflow-integration"

MLFLOW_SELECTOR=$(oc get mlflow mlflow -o json 2>/dev/null | python3 -c '
import json
import sys

selector = json.load(sys.stdin).get("spec", {}).get("workspaceLabelSelector", {})
values = []
for expr in selector.get("matchExpressions", []):
    if expr.get("key") == "kubernetes.io/metadata.name" and expr.get("operator") == "In":
        values.extend(expr.get("values") or [])
print(",".join(sorted(values)))
' 2>/dev/null || true)
if [[ "$MLFLOW_SELECTOR" == *"enterprise-rag"* && "$MLFLOW_SELECTOR" == *"enterprise-mlops"* ]]; then
    echo -e "${GREEN}[PASS]${NC} MLflow server selects enterprise-rag and enterprise-mlops workspaces"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} MLflow server does not yet select enterprise-rag workspaces"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- EvalHub Server and Tenant ---
log_step "EvalHub Server"
check "EvalHub namespace exists" \
    "oc get namespace $EVALHUB_NAMESPACE -o jsonpath='{.metadata.name}'" \
    "$EVALHUB_NAMESPACE"

EVALHUB_DB_URL="$(oc get secret evalhub-db-credentials -n "$EVALHUB_NAMESPACE" \
    -o jsonpath='{.data.db-url}' 2>/dev/null | base64 -d 2>/dev/null || true)"
if [[ "$EVALHUB_DB_URL" == postgres*evalhub-postgres* ]]; then
    record_pass "EvalHub PostgreSQL db-url Secret exists"
else
    record_fail "EvalHub PostgreSQL db-url Secret missing or invalid"
fi

check "EvalHub PostgreSQL PVC exists" \
    "oc get pvc evalhub-postgres-data -n $EVALHUB_NAMESPACE -o jsonpath='{.metadata.name}'" \
    "evalhub-postgres-data"

POSTGRES_AVAILABLE="$(oc get deployment evalhub-postgres -n "$EVALHUB_NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)"
if [[ "$POSTGRES_AVAILABLE" == "True" ]]; then
    record_pass "EvalHub PostgreSQL deployment is Available"
else
    record_fail "EvalHub PostgreSQL deployment is not Available (status: ${POSTGRES_AVAILABLE:-Missing})"
fi

check "EvalHub custom resource exists" \
    "oc get evalhub evalhub -n $EVALHUB_NAMESPACE -o jsonpath='{.metadata.name}'" \
    "evalhub"

EVALHUB_POD_COUNT="$(oc get pods -l app=eval-hub -n "$EVALHUB_NAMESPACE" \
    --no-headers 2>/dev/null | grep -c "Running" || true)"
if [[ "$EVALHUB_POD_COUNT" -gt 0 ]]; then
    record_pass "EvalHub pod is Running"
else
    record_fail "No EvalHub pod with label app=eval-hub is Running"
fi

EVALHUB_PHASE="$(oc get evalhub evalhub -n "$EVALHUB_NAMESPACE" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [[ "$EVALHUB_PHASE" == "Ready" ]]; then
    record_pass "EvalHub CR phase is Ready"
else
    record_fail "EvalHub CR phase is ${EVALHUB_PHASE:-Missing}"
fi

check "EvalHub service exists" \
    "oc get service evalhub -n $EVALHUB_NAMESPACE -o jsonpath='{.metadata.name}'" \
    "evalhub"

EVALHUB_BASE_URL="$(evalhub_url || true)"
if [[ -n "$EVALHUB_BASE_URL" ]]; then
    record_pass "EvalHub route URL resolved: $EVALHUB_BASE_URL"
    HEALTH_CODE="$(curl -sk --max-time 20 -o /tmp/evalhub-health.json -w '%{http_code}' \
        "$EVALHUB_BASE_URL/api/v1/health" 2>/dev/null || echo "000")"
    if [[ "$HEALTH_CODE" == "200" ]]; then
        record_pass "EvalHub health endpoint returned HTTP 200"
    else
        record_fail "EvalHub health endpoint returned HTTP $HEALTH_CODE"
    fi
else
    record_fail "EvalHub route URL could not be resolved"
fi

log_step "EvalHub Tenant and RBAC"
TENANT_LABEL_PRESENT="$(oc get namespace "$NAMESPACE" -o json 2>/dev/null | python3 -c '
import json
import sys
labels = json.load(sys.stdin).get("metadata", {}).get("labels", {})
print("present" if "evalhub.trustyai.opendatahub.io/tenant" in labels else "missing")
' 2>/dev/null || echo "missing")"
if [[ "$TENANT_LABEL_PRESENT" == "present" ]]; then
    record_pass "enterprise-rag has EvalHub tenant label"
else
    record_fail "enterprise-rag is missing EvalHub tenant label"
fi

check "evalhub-evaluator Role exists" \
    "oc get role evalhub-evaluator -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "evalhub-evaluator"

check "evalhub-evaluator RoleBinding exists" \
    "oc get rolebinding evalhub-evaluator-access -n $NAMESPACE -o jsonpath='{.roleRef.name}'" \
    "evalhub-evaluator"

TENANT_OPERATOR_OBJECTS="$(oc get serviceaccount,rolebinding,configmap -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c evalhub || true)"
if [[ "$TENANT_OPERATOR_OBJECTS" -gt 0 ]]; then
    record_pass "TrustyAI operator created EvalHub tenant resources ($TENANT_OPERATOR_OBJECTS objects)"
else
    record_fail "TrustyAI operator-created EvalHub tenant resources not found"
fi

for user in kube:admin ai-admin ai-developer; do
    if [[ "$(oc auth can-i create evaluations.trustyai.opendatahub.io -n "$NAMESPACE" --as="$user" 2>/dev/null || true)" == "yes" ]]; then
        record_pass "$user can create EvalHub evaluations in $NAMESPACE"
    else
        record_fail "$user cannot create EvalHub evaluations in $NAMESPACE"
    fi
done

if [[ "$(oc auth can-i create evaluations.trustyai.opendatahub.io -n "$NAMESPACE" \
    --as=rhoai-group-check --as-group=rhoai-users 2>/dev/null || true)" == "yes" ]]; then
    record_pass "rhoai-users group can create EvalHub evaluations in $NAMESPACE"
else
    record_fail "rhoai-users group cannot create EvalHub evaluations in $NAMESPACE"
fi

if [[ "$(oc auth can-i get experiments.mlflow.kubeflow.org -n "$NAMESPACE" --as=ai-developer 2>/dev/null || true)" == "yes" ]]; then
    record_pass "ai-developer can access MLflow experiments for EvalHub"
else
    record_fail "ai-developer cannot access MLflow experiments for EvalHub"
fi

log_step "EvalHub API and Smoke Job"
if [[ -n "${EVALHUB_BASE_URL:-}" ]]; then
    TOKEN="$(oc whoami -t 2>/dev/null || true)"
    PROVIDERS_JSON="$(curl -sk --max-time 30 \
        -H "Authorization: Bearer $TOKEN" \
        -H "X-Tenant: $NAMESPACE" \
        "$EVALHUB_BASE_URL/api/v1/evaluations/providers" 2>/dev/null || true)"
    if echo "$PROVIDERS_JSON" | grep -q "lm_evaluation_harness"; then
        record_pass "EvalHub providers API includes lm_evaluation_harness"
    else
        record_fail "EvalHub providers API does not include lm_evaluation_harness"
    fi

    JOBS_JSON="$(curl -sk --max-time 30 \
        -H "Authorization: Bearer $TOKEN" \
        -H "X-Tenant: $NAMESPACE" \
        "$EVALHUB_BASE_URL/api/v1/evaluations/jobs?limit=20" 2>/dev/null || true)"
    JOBS_FILE="$(mktemp)"
    printf '%s' "$JOBS_JSON" > "$JOBS_FILE"
    SMOKE_INFO="$(python3 - "$JOBS_FILE" "$EVALHUB_SMOKE_NAME_PREFIX" "$EVALHUB_EXPERIMENT_NAME" <<'PY' 2>/dev/null || true
import json
import sys

path = sys.argv[1]
prefix = sys.argv[2]
experiment_name = sys.argv[3]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    data = {}

items = data.get("items") or data.get("jobs") or []
if isinstance(items, dict):
    items = list(items.values())

matches = []
for item in items:
    name = item.get("name") or item.get("metadata", {}).get("name") or ""
    experiment = item.get("experiment") or {}
    experiment_matches = experiment.get("name") == experiment_name
    if name.startswith(prefix) or experiment_matches:
        resource = item.get("resource") or {}
        created = resource.get("created_at") or item.get("created_at") or ""
        matches.append((created, item))

if not matches:
    sys.exit(0)

matches.sort(key=lambda pair: pair[0], reverse=True)
item = matches[0][1]
resource = item.get("resource") or {}
status = item.get("status") or {}
if isinstance(status, dict):
    state = status.get("state") or item.get("state") or ""
else:
    state = str(status or item.get("state") or "")
results = item.get("results") or {}
print("|".join([
    resource.get("id") or item.get("id") or "",
    item.get("name") or "",
    state,
    results.get("mlflow_experiment_url") or "",
    resource.get("created_at") or item.get("created_at") or "",
]))
PY
)"
    rm -f "$JOBS_FILE"
    if [[ -n "$SMOKE_INFO" ]]; then
        SMOKE_JOB_ID="${SMOKE_INFO%%|*}"
        REST="${SMOKE_INFO#*|}"
        SMOKE_JOB_NAME="${REST%%|*}"
        REST="${REST#*|}"
        SMOKE_STATE="${REST%%|*}"
        REST="${REST#*|}"
        SMOKE_MLFLOW_URL="${REST%%|*}"
        SMOKE_CREATED="${REST#*|}"

        if [[ "$SMOKE_STATE" == "completed" ]]; then
            record_pass "Latest EvalHub smoke job completed: ${SMOKE_JOB_NAME:-$SMOKE_JOB_ID}"
        else
            record_fail "Latest EvalHub smoke job state is ${SMOKE_STATE:-unknown}: ${SMOKE_JOB_NAME:-$SMOKE_JOB_ID}"
        fi
        check_recent_timestamp "Latest EvalHub smoke job" "$SMOKE_CREATED" "${DEMO_FRESHNESS_HOURS:-24}" "warn"

        if [[ -n "$SMOKE_MLFLOW_URL" ]]; then
            record_pass "EvalHub smoke job has MLflow experiment URL: $SMOKE_MLFLOW_URL"
        else
            record_fail "EvalHub smoke job results missing mlflow_experiment_url"
        fi
    else
        record_fail "No EvalHub smoke job found — run: ./steps/step-08-model-evaluation/run-evalhub-smoke.sh"
    fi
else
    record_fail "Skipping EvalHub API checks because route URL is missing"
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
JUDGE_READY=$(oc get inferenceservice mistral-3-bf16 -n "$MODEL_NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [ "$JUDGE_READY" = "True" ]; then
    echo -e "${GREEN}[PASS]${NC} mistral-3-bf16 InferenceService is Ready in $MODEL_NAMESPACE"
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

for job in granite-8b-agent-eval mistral-3-bf16-eval; do
    JOB_CREATED=$(oc get lmevaljob "$job" -n "$NAMESPACE" \
        -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "")
    JOB_STATE=$(oc get lmevaljob "$job" -n "$NAMESPACE" \
        -o jsonpath='{.status.state}' 2>/dev/null || echo "")
    if [[ "$JOB_STATE" == "Complete" ]]; then
        echo -e "${GREEN}[PASS]${NC} LMEvalJob $job completed"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    elif [[ -n "$JOB_CREATED" ]]; then
        echo -e "${YELLOW}[WARN]${NC} LMEvalJob $job state: ${JOB_STATE:-Unknown}"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} LMEvalJob $job not found — run: ./steps/step-08-model-evaluation/run-lmeval.sh ${job%-eval}"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
    check_recent_timestamp "LMEvalJob $job" "$JOB_CREATED" "${DEMO_FRESHNESS_HOURS:-24}" "warn"
done

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
    MINIO_ACCESS=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' 2>/dev/null | base64 -d)
    MINIO_SECRET=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' 2>/dev/null | base64 -d)
    REPORT_INFO=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- python3 -c "
import boto3, os
try:
    s3 = boto3.client('s3',
        endpoint_url=os.environ.get('AWS_S3_ENDPOINT','http://minio.minio-storage.svc:9000'),
        aws_access_key_id='${MINIO_ACCESS}',
        aws_secret_access_key='${MINIO_SECRET}',
        verify=False)
    objects = []
    paginator = s3.get_paginator('list_objects_v2')
    for page in paginator.paginate(Bucket='rhoai-storage', Prefix='eval-results/'):
        objects.extend(page.get('Contents', []))
    reports = [o for o in objects if o['Key'].endswith('_report.html')]
    latest = max([o['LastModified'].isoformat() for o in reports] or [''])
    print(str(len(reports)) + '|' + latest)
except Exception:
    print('0|')
" 2>/dev/null || echo "0")
    REPORT_COUNT="${REPORT_INFO%%|*}"
    REPORT_LATEST="${REPORT_INFO#*|}"
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
    check_recent_timestamp "Latest RAG eval report" "$REPORT_LATEST" "${DEMO_FRESHNESS_HOURS:-24}" "warn"
else
    echo -e "${YELLOW}[WARN]${NC} Cannot check MinIO reports (lsd-rag pod not available)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- MLflow Run Evidence ---
log_step "MLflow Run Evidence"
MLFLOW_URL=$(oc get mlflow mlflow -o jsonpath='{.status.url}' 2>/dev/null || true)
OC_TOKEN=$(oc whoami -t 2>/dev/null || true)
MLFLOW_RUN_INFO=""
if [[ -n "$MLFLOW_URL" && -n "$OC_TOKEN" ]]; then
    EXPERIMENT_JSON=$(curl -sk --max-time 20 -X POST "$MLFLOW_URL/api/2.0/mlflow/experiments/search" \
        -H "Authorization: Bearer $OC_TOKEN" \
        -H "x-mlflow-workspace: $NAMESPACE" \
        -H "Content-Type: application/json" \
        -d '{"filter":"name = '\''enterprise-rag'\''","max_results":1}' 2>/dev/null || true)
    EXPERIMENT_ID=$(echo "$EXPERIMENT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); ex=d.get('experiments') or []; print(ex[0].get('experiment_id','') if ex else '')" 2>/dev/null || true)

    if [[ -n "$EXPERIMENT_ID" ]]; then
        RUN_JSON=$(curl -sk --max-time 20 -X POST "$MLFLOW_URL/api/2.0/mlflow/runs/search" \
            -H "Authorization: Bearer $OC_TOKEN" \
            -H "x-mlflow-workspace: $NAMESPACE" \
            -H "Content-Type: application/json" \
            -d "{\"experiment_ids\":[\"$EXPERIMENT_ID\"],\"max_results\":5,\"order_by\":[\"attributes.start_time DESC\"]}" 2>/dev/null || true)
        MLFLOW_RUN_INFO=$(echo "$RUN_JSON" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
for run in data.get("runs", []):
    info = run.get("info", {})
    tags = {tag.get("key"): tag.get("value") for tag in run.get("data", {}).get("tags", [])}
    if tags.get("rhoai.demo.step") == "08" or (info.get("run_name") or "").startswith("rag-eval-"):
        start = str(int(info.get("start_time", 0)) // 1000)
        print("|".join([
            info.get("status", ""),
            start,
            info.get("run_id", ""),
            info.get("run_name", ""),
        ]))
        break
' 2>/dev/null || true)
    fi
fi

if [[ -n "$MLFLOW_RUN_INFO" ]]; then
    MLFLOW_STATE="${MLFLOW_RUN_INFO%%|*}"
    REST="${MLFLOW_RUN_INFO#*|}"
    MLFLOW_START="${REST%%|*}"
    REST="${REST#*|}"
    MLFLOW_RUN_ID="${REST%%|*}"
    MLFLOW_RUN_NAME="${REST#*|}"
    if [[ "$MLFLOW_STATE" == "FINISHED" ]]; then
        echo -e "${GREEN}[PASS]${NC} Latest Step 08 MLflow run finished: $MLFLOW_RUN_NAME ($MLFLOW_RUN_ID)"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} Latest Step 08 MLflow run $MLFLOW_RUN_NAME state: $MLFLOW_STATE"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
    check_recent_timestamp "Latest Step 08 MLflow run" "$MLFLOW_START" "${DEMO_FRESHNESS_HOURS:-24}" "warn"
else
    echo -e "${YELLOW}[WARN]${NC} No Step 08 MLflow run found — run: ./steps/step-08-model-evaluation/run-rag-eval.sh"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Summary ---
echo ""
validation_summary
