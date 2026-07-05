#!/usr/bin/env bash
# validate.sh - Stage 250: Model Evaluation (EvalHub + LMEval + MLflow)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
WARN=0
FAIL=0

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

if [[ -z "${RHOAI_EXPECTED_API_SERVER:-}" ]]; then
  echo "ERROR: RHOAI_EXPECTED_API_SERVER is not set." >&2
  exit 1
fi

ACTUAL_SERVER=$(oc whoami --show-server 2>/dev/null || true)
if [[ "$ACTUAL_SERVER" != *"$RHOAI_EXPECTED_API_SERVER"* ]]; then
  echo "ERROR: Active cluster ($ACTUAL_SERVER) does not match RHOAI_EXPECTED_API_SERVER." >&2
  exit 1
fi

EVAL_NS="${RHOAI_STAGE250_NAMESPACE:-model-evaluation}"
MAAS_NS="${RHOAI_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_SUBSCRIPTION="${RHOAI_STAGE250_MAAS_SUBSCRIPTION:-model-evaluation}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
EVALHUB_DB_SECRET="${RHOAI_STAGE250_EVALHUB_DB_SECRET:-evalhub-db-credentials}"
MODEL_TOKEN_SECRET="${RHOAI_STAGE250_MODEL_TOKEN_SECRET:-model-evaluation-model-token}"
EVALHUB_CR="${RHOAI_STAGE250_EVALHUB_CR:-evalhub}"
LMEVAL_JOB="${RHOAI_STAGE250_LMEVAL_JOB:-nemotron-safety-eval}"

check() {
  local label="$1"; local result="$2"
  if [[ "$result" == "pass" ]]; then
    echo "✓ $label"; (( PASS++ )) || true
  else
    echo "✗ $label  ($result)"; (( FAIL++ )) || true
  fi
}
warn() { echo "! $1  ($2)"; (( WARN++ )) || true; }

jsonpath() {
  local resource="$1"; local namespace="$2"; local path="$3"
  if [[ -n "$namespace" ]]; then
    oc get "$resource" -n "$namespace" -o jsonpath="$path" --insecure-skip-tls-verify=true 2>/dev/null || true
  else
    oc get "$resource" -o jsonpath="$path" --insecure-skip-tls-verify=true 2>/dev/null || true
  fi
}
resource_exists() {
  local resource="$1"; local namespace="$2"
  if [[ -n "$namespace" ]]; then
    oc get "$resource" -n "$namespace" --insecure-skip-tls-verify=true >/dev/null 2>&1
  else
    oc get "$resource" --insecure-skip-tls-verify=true >/dev/null 2>&1
  fi
}

echo "=== Stage 250: GitOps and platform ==="
app_sync=$(jsonpath "applications.argoproj.io/stage-250-model-evaluation" "openshift-gitops" "{.status.sync.status}")
check "Argo CD Application is Synced" "$([[ "$app_sync" == "Synced" ]] && echo pass || echo "sync=$app_sync")"
app_health=$(jsonpath "applications.argoproj.io/stage-250-model-evaluation" "openshift-gitops" "{.status.health.status}")
[[ "$app_health" == "Healthy" ]] && check "Argo CD Application is Healthy" "pass" || warn "Argo CD Application health" "health=$app_health"

check "Namespace ${EVAL_NS} exists" "$(resource_exists "namespace/${EVAL_NS}" "" && echo pass || echo missing)"
tenant_label=$(jsonpath "namespace/${EVAL_NS}" "" "{.metadata.labels.evalhub\.trustyai\.opendatahub\.io/tenant}")
check "Namespace is an EvalHub tenant" "$([[ "$tenant_label" == "true" ]] && echo pass || echo "label=$tenant_label")"
check "RoleBinding rhoai-developers-edit exists" "$(resource_exists "rolebinding/rhoai-developers-edit" "$EVAL_NS" && echo pass || echo missing)"

trustyai_state=$(jsonpath "datasciencecluster/default-dsc" "" "{.spec.components.trustyai.managementState}")
check "DataScienceCluster trustyai is Managed" "$([[ "$trustyai_state" == "Managed" ]] && echo pass || echo "state=$trustyai_state")"
mlflow_state=$(jsonpath "datasciencecluster/default-dsc" "" "{.spec.components.mlflowoperator.managementState}")
check "DataScienceCluster mlflowoperator is Managed" "$([[ "$mlflow_state" == "Managed" ]] && echo pass || echo "state=$mlflow_state")"

check "MaaSSubscription ${MAAS_SUBSCRIPTION} exists" "$(resource_exists "maassubscription/${MAAS_SUBSCRIPTION}" "$MAAS_NS" && echo pass || echo missing)"

echo ""
echo "=== Stage 250: data plane ==="
pg_ready=$(jsonpath "statefulset/evaluation-postgres" "$EVAL_NS" "{.status.readyReplicas}")
check "PostgreSQL StatefulSet is ready" "$([[ "${pg_ready:-0}" -ge 1 ]] 2>/dev/null && echo pass || echo "readyReplicas=${pg_ready:-0}")"
db_url=$(jsonpath "secret/${EVALHUB_DB_SECRET}" "$EVAL_NS" "{.data.db-url}" | base64 --decode 2>/dev/null || true)
check "EvalHub DB Secret holds a db-url" "$([[ "$db_url" == postgresql://* ]] && echo pass || echo "missing or malformed db-url")"

nemotron_replicas=$(jsonpath "llminferenceservice/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.replicas}")
NEMOTRON_UP=false
if [[ -n "$nemotron_replicas" && "$nemotron_replicas" != "0" ]]; then
  NEMOTRON_UP=true
  check "Nemotron is scaled up (replicas=${nemotron_replicas})" "pass"
else
  warn "Nemotron is parked (replicas=${nemotron_replicas:-unset})" "functional model-eval checks will be skipped"
fi

check "MaaS proxy deployment is available" "$([[ "$(jsonpath "deployment/maas-internal-proxy" "$EVAL_NS" "{.status.availableReplicas}")" -ge 1 ]] 2>/dev/null && echo pass || echo unavailable)"
model_token=$(jsonpath "secret/${MODEL_TOKEN_SECRET}" "$EVAL_NS" "{.data.token}" | base64 --decode 2>/dev/null || true)
check "Model API token Secret holds a MaaS key" "$([[ "$model_token" == sk-oai-* ]] && echo pass || echo "token missing or not sk-oai-*")"
cm_dump=$(oc get configmap -n "$EVAL_NS" -o json --insecure-skip-tls-verify=true 2>/dev/null || true)
if [[ -n "$cm_dump" ]] && ! grep -q 'sk-oai-\|postgresql://' <<<"$cm_dump"; then
  check "No secrets leaked into ${EVAL_NS} ConfigMaps" "pass"
else
  check "No secrets leaked into ${EVAL_NS} ConfigMaps" "found a secret value in a ConfigMap"
fi

echo ""
echo "=== Stage 250: MLflow ==="
mlflow_avail=$(jsonpath "mlflow/mlflow" "" "{.status.conditions[?(@.type=='Available')].status}")
[[ "$mlflow_avail" == "True" ]] && check "MLflow is Available" "pass" || warn "MLflow availability" "status=${mlflow_avail:-unknown}"
mlflow_url=$(jsonpath "mlflow/mlflow" "" "{.status.url}")
check "MLflow dashboard route is published" "$([[ -n "$mlflow_url" ]] && echo pass || echo missing)"

echo ""
echo "=== Stage 250: EvalHub ==="
check "EvalHub CR exists" "$(resource_exists "evalhub/${EVALHUB_CR}" "$EVAL_NS" && echo pass || echo missing)"
evalhub_ready=$(jsonpath "deployment/evalhub" "$EVAL_NS" "{.status.availableReplicas}")
check "EvalHub deployment is available" "$([[ "${evalhub_ready:-0}" -ge 1 ]] 2>/dev/null && echo pass || echo "availableReplicas=${evalhub_ready:-0}")"

# Functional REST probes: run from inside a cluster pod against the EvalHub
# Service. All requests except /health require the X-Tenant header.
evalhub_pod=$(oc get pods -n "$EVAL_NS" -l app.kubernetes.io/name=evalhub --field-selector=status.phase=Running -o name --insecure-skip-tls-verify=true 2>/dev/null | head -1)
[[ -z "$evalhub_pod" ]] && evalhub_pod=$(oc get pods -n "$EVAL_NS" --field-selector=status.phase=Running --insecure-skip-tls-verify=true 2>/dev/null | grep '^evalhub' | awk '{print "pod/"$1}' | head -1)
if [[ -n "$evalhub_pod" ]]; then
  health=$(oc exec -n "$EVAL_NS" "$evalhub_pod" --insecure-skip-tls-verify=true -- \
    curl -sk --max-time 15 http://localhost:8080/api/v1/health 2>/dev/null || true)
  if grep -qiE 'healthy|ok|"status"' <<<"$health"; then
    check "EvalHub /health responds" "pass"
  else
    warn "EvalHub /health" "no healthy response: $(head -c 80 <<<"$health")"
  fi
  providers=$(oc exec -n "$EVAL_NS" "$evalhub_pod" --insecure-skip-tls-verify=true -- \
    curl -sk --max-time 15 -H "X-Tenant: ${EVAL_NS}" http://localhost:8080/api/v1/evaluations/providers 2>/dev/null || true)
  if grep -q 'lm-evaluation-harness\|lm_evaluation_harness' <<<"$providers"; then
    check "EvalHub lists providers" "pass"
  else
    warn "EvalHub providers" "provider list not returned: $(head -c 80 <<<"$providers")"
  fi
else
  warn "EvalHub REST probes" "no running evalhub pod to query from"
fi

echo ""
echo "=== Stage 250: LMEval (dashboard-driven) ==="
check "LMEvalJob ${LMEVAL_JOB} exists" "$(resource_exists "lmevaljob/${LMEVAL_JOB}" "$EVAL_NS" && echo pass || echo missing)"
lmeval_state=$(jsonpath "lmevaljob/${LMEVAL_JOB}" "$EVAL_NS" "{.status.state}")
if [[ "$NEMOTRON_UP" == "true" ]]; then
  case "$lmeval_state" in
    Complete) check "LMEvalJob completed" "pass" ;;
    Running|Scheduled|Pending) warn "LMEvalJob state" "still ${lmeval_state} (evaluation takes time)" ;;
    *) warn "LMEvalJob state" "state=${lmeval_state:-unknown}" ;;
  esac
else
  warn "LMEvalJob" "Nemotron parked; job cannot run"
fi

echo ""
echo "Stage 250 validation summary: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
if (( FAIL > 0 )); then
  exit 1
fi
