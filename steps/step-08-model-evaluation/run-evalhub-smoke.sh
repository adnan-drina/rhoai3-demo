#!/usr/bin/env bash
# Submit a small EvalHub job against the granite-8b-agent model.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/lib.sh"

NAMESPACE="${NAMESPACE:-enterprise-rag}"
EVALHUB_NAMESPACE="${EVALHUB_NAMESPACE:-evalhub-system}"
RUN_ID="${1:-evalhub-$(date +%s)}"
JOB_NAME="${EVALHUB_JOB_NAME:-evalhub-granite-smoke-${RUN_ID}}"
EXPERIMENT_NAME="${EVALHUB_EXPERIMENT_NAME:-evalhub-granite-smoke}"
MODEL_NAME="${EVALHUB_MODEL_NAME:-granite-8b-agent}"
MODEL_URL="${EVALHUB_MODEL_URL:-http://granite-8b-agent-predictor.maas.svc.cluster.local:8080/v1}"
PROVIDER_ID="${EVALHUB_PROVIDER_ID:-lm_evaluation_harness}"
BENCHMARK_ID="${EVALHUB_BENCHMARK_ID:-tinyTruthfulQA}"
POLL_ATTEMPTS="${EVALHUB_POLL_ATTEMPTS:-120}"
POLL_SECONDS="${EVALHUB_POLL_SECONDS:-10}"

json_field() {
    local file="$1"
    local expression="$2"
    python3 - "$file" "$expression" <<'PY'
import json
import sys

path = sys.argv[2].split(".")
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        value = json.load(handle)
    for part in path:
        if isinstance(value, dict):
            value = value.get(part, "")
        else:
            value = ""
            break
    if isinstance(value, (dict, list)):
        print(json.dumps(value))
    elif value is None:
        print("")
    else:
        print(value)
except Exception:
    print("")
PY
}

extract_job_id() {
    local file="$1"
    python3 - "$file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    data = {}

candidates = [
    data.get("id"),
    data.get("job_id"),
    data.get("name"),
    data.get("resource", {}).get("id"),
    data.get("metadata", {}).get("name"),
]
print(next((str(value) for value in candidates if value), ""))
PY
}

curl_json() {
    local method="$1"
    local url="$2"
    local output="$3"
    shift 3

    curl -sk --max-time 60 -X "$method" "$url" \
        -H "Authorization: Bearer $TOKEN" \
        -H "X-Tenant: $NAMESPACE" \
        "$@" \
        -o "$output" \
        -w "%{http_code}"
}

check_oc_logged_in

ROUTE_HOST="$(oc get route evalhub -n "$EVALHUB_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
if [[ -z "$ROUTE_HOST" ]]; then
    CR_URL="$(oc get evalhub evalhub -n "$EVALHUB_NAMESPACE" -o jsonpath='{.status.url}' 2>/dev/null || true)"
    if [[ "$CR_URL" == https://* || "$CR_URL" == http://* ]]; then
        EVALHUB_URL="$CR_URL"
    else
        log_error "EvalHub route not found in $EVALHUB_NAMESPACE"
        exit 1
    fi
else
    EVALHUB_URL="${EVALHUB_URL:-https://${ROUTE_HOST}}"
fi

TOKEN="$(oc whoami -t)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log_step "Checking EvalHub health"
HEALTH_JSON="$WORK_DIR/health.json"
HEALTH_CODE="$(curl -sk --max-time 30 "$EVALHUB_URL/api/v1/health" -o "$HEALTH_JSON" -w "%{http_code}" || echo "000")"
if [[ "$HEALTH_CODE" != "200" ]]; then
    log_error "EvalHub health check failed: HTTP $HEALTH_CODE"
    cat "$HEALTH_JSON" || true
    exit 1
fi
log_success "EvalHub health endpoint is ready"

log_step "Checking EvalHub providers"
PROVIDERS_JSON="$WORK_DIR/providers.json"
PROVIDERS_CODE="$(curl_json GET "$EVALHUB_URL/api/v1/evaluations/providers" "$PROVIDERS_JSON")"
if [[ "$PROVIDERS_CODE" != "200" ]]; then
    log_error "Provider list failed: HTTP $PROVIDERS_CODE"
    cat "$PROVIDERS_JSON" || true
    exit 1
fi
if ! grep -q "$PROVIDER_ID" "$PROVIDERS_JSON"; then
    log_error "Provider $PROVIDER_ID not found in EvalHub provider list"
    cat "$PROVIDERS_JSON"
    exit 1
fi
log_success "Provider available: $PROVIDER_ID"

PROVIDER_JSON="$WORK_DIR/provider.json"
PROVIDER_CODE="$(curl_json GET "$EVALHUB_URL/api/v1/evaluations/providers/$PROVIDER_ID" "$PROVIDER_JSON")"
if [[ "$PROVIDER_CODE" != "200" ]] || ! grep -q "$BENCHMARK_ID" "$PROVIDER_JSON"; then
    log_error "Benchmark $BENCHMARK_ID not available from provider $PROVIDER_ID"
    cat "$PROVIDER_JSON" || true
    exit 1
fi
log_success "Benchmark available: $BENCHMARK_ID"

log_step "Submitting EvalHub smoke job"
REQUEST_JSON="$WORK_DIR/evalhub-smoke-request.json"
RESPONSE_JSON="$WORK_DIR/evalhub-smoke-response.json"
cat > "$REQUEST_JSON" <<JSON
{
  "name": "$JOB_NAME",
  "model": {
    "url": "$MODEL_URL",
    "name": "$MODEL_NAME"
  },
  "benchmarks": [
    {
      "provider_id": "$PROVIDER_ID",
      "benchmark_id": "$BENCHMARK_ID"
    }
  ],
  "experiment": {
    "name": "$EXPERIMENT_NAME"
  }
}
JSON

SUBMIT_CODE="$(curl_json POST "$EVALHUB_URL/api/v1/evaluations/jobs" "$RESPONSE_JSON" \
    -H "Content-Type: application/json" \
    -d "@$REQUEST_JSON")"
if [[ "$SUBMIT_CODE" != "202" && "$SUBMIT_CODE" != "200" ]]; then
    log_error "EvalHub job submission failed: HTTP $SUBMIT_CODE"
    cat "$RESPONSE_JSON" || true
    exit 1
fi

JOB_ID="$(extract_job_id "$RESPONSE_JSON")"
if [[ -z "$JOB_ID" ]]; then
    log_error "EvalHub did not return a job id"
    cat "$RESPONSE_JSON" || true
    exit 1
fi
log_success "EvalHub job submitted: $JOB_ID"

STATUS_JSON="$WORK_DIR/evalhub-smoke-status.json"
STATE=""
for attempt in $(seq 1 "$POLL_ATTEMPTS"); do
    STATUS_CODE="$(curl_json GET "$EVALHUB_URL/api/v1/evaluations/jobs/$JOB_ID" "$STATUS_JSON")"
    if [[ "$STATUS_CODE" != "200" ]]; then
        log_warn "Job status returned HTTP $STATUS_CODE (attempt $attempt/$POLL_ATTEMPTS)"
    else
        STATE="$(json_field "$STATUS_JSON" "status.state")"
        if [[ -z "$STATE" ]]; then
            STATE="$(json_field "$STATUS_JSON" "state")"
        fi
        if [[ -z "$STATE" ]]; then
            STATE="$(json_field "$STATUS_JSON" "status")"
        fi
        log_info "EvalHub job $JOB_ID state: ${STATE:-unknown} ($attempt/$POLL_ATTEMPTS)"
        case "$STATE" in
            completed|failed|cancelled|partially_failed)
                break
                ;;
        esac
    fi
    sleep "$POLL_SECONDS"
done

case "$STATE" in
    completed)
        log_success "EvalHub smoke job completed"
        ;;
    failed|cancelled|partially_failed)
        log_error "EvalHub smoke job finished in terminal state: $STATE"
        cat "$STATUS_JSON" || true
        exit 1
        ;;
    *)
        log_error "EvalHub smoke job did not finish within $((POLL_ATTEMPTS * POLL_SECONDS)) seconds"
        cat "$STATUS_JSON" || true
        exit 1
        ;;
esac

echo ""
echo "EvalHub results:"
python3 - "$STATUS_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

results = data.get("results") or {}
print(json.dumps(results, indent=2, sort_keys=True))
url = results.get("mlflow_experiment_url")
if url:
    print(f"MLflow experiment URL: {url}")
PY
