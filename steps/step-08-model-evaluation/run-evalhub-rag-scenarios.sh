#!/usr/bin/env bash
# Submit the ACME and whoami pre/post RAG scenario suite through EvalHub.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/lib.sh"

NAMESPACE="${NAMESPACE:-enterprise-rag}"
EVALHUB_NAMESPACE="${EVALHUB_NAMESPACE:-evalhub-system}"
RUN_ID="${1:-evalhub-rag-$(date +%s)}"
JOB_NAME="${EVALHUB_RAG_JOB_NAME:-evalhub-rag-pre-post-${RUN_ID}}"
EXPERIMENT_NAME="${EVALHUB_RAG_EXPERIMENT_NAME:-evalhub-rag-pre-post}"
MODEL_NAME="${EVALHUB_RAG_MODEL_NAME:-granite-8b-agent}"
MODEL_URL="${EVALHUB_RAG_MODEL_URL:-http://lsd-rag-service.enterprise-rag.svc.cluster.local:8321}"
PROVIDER_ID="${EVALHUB_RAG_PROVIDER_ID:-rhoai_rag_scenarios}"
COLLECTION_ID="${EVALHUB_RAG_COLLECTION_ID:-rhoai-rag-pre-post-v1}"
USE_COLLECTION="${EVALHUB_RAG_USE_COLLECTION:-true}"
POLL_ATTEMPTS="${EVALHUB_RAG_POLL_ATTEMPTS:-180}"
POLL_SECONDS="${EVALHUB_RAG_POLL_SECONDS:-10}"

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
    data.get("resource", {}).get("id"),
    data.get("name"),
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

log_step "Checking RAG scenario provider"
PROVIDER_JSON="$WORK_DIR/provider.json"
PROVIDER_CODE="$(curl_json GET "$EVALHUB_URL/api/v1/evaluations/providers/$PROVIDER_ID" "$PROVIDER_JSON")"
if [[ "$PROVIDER_CODE" != "200" ]]; then
    log_error "Provider $PROVIDER_ID not found in EvalHub: HTTP $PROVIDER_CODE"
    cat "$PROVIDER_JSON" || true
    exit 1
fi
for benchmark in acme_corporate_pre_rag acme_corporate_post_rag whoami_pre_rag whoami_post_rag; do
    if ! grep -q "$benchmark" "$PROVIDER_JSON"; then
        log_error "Benchmark $benchmark not available from provider $PROVIDER_ID"
        cat "$PROVIDER_JSON" || true
        exit 1
    fi
done
log_success "Provider available: $PROVIDER_ID"

if [[ "$USE_COLLECTION" == "true" ]]; then
    log_step "Checking RAG scenario collection"
    COLLECTION_JSON="$WORK_DIR/collection.json"
    COLLECTION_CODE="$(curl_json GET "$EVALHUB_URL/api/v1/evaluations/collections/$COLLECTION_ID" "$COLLECTION_JSON")"
    if [[ "$COLLECTION_CODE" != "200" ]]; then
        log_error "Collection $COLLECTION_ID not found in EvalHub: HTTP $COLLECTION_CODE"
        cat "$COLLECTION_JSON" || true
        exit 1
    fi
    log_success "Collection available: $COLLECTION_ID"
fi

log_step "Submitting EvalHub RAG scenario job"
REQUEST_JSON="$WORK_DIR/evalhub-rag-request.json"
RESPONSE_JSON="$WORK_DIR/evalhub-rag-response.json"
python3 - "$REQUEST_JSON" <<PY
import json
import os
import sys

request = {
    "name": os.environ.get("JOB_NAME", "$JOB_NAME"),
    "description": "ACME Corp and whoami pre/post RAG scenario evaluation",
    "tags": ["rag", "pre-post", "acme", "whoami"],
    "model": {
        "url": os.environ.get("MODEL_URL", "$MODEL_URL"),
        "name": os.environ.get("MODEL_NAME", "$MODEL_NAME"),
    },
    "experiment": {
        "name": os.environ.get("EXPERIMENT_NAME", "$EXPERIMENT_NAME"),
        "tags": [
            {"key": "rhoai.demo.step", "value": "08"},
            {"key": "rhoai.demo.capability", "value": "evalhub-rag-scenario-evaluation"},
            {"key": "rhoai.demo.run_id", "value": "$RUN_ID"},
        ],
    },
}

if "$USE_COLLECTION".lower() == "true":
    request["collection"] = {"id": "$COLLECTION_ID"}
else:
    request["benchmarks"] = [
        {
            "provider_id": "$PROVIDER_ID",
            "id": "acme_corporate_pre_rag",
            "parameters": {"config_name": "acme_corporate_pre_rag_tests.yaml"},
        },
        {
            "provider_id": "$PROVIDER_ID",
            "id": "acme_corporate_post_rag",
            "parameters": {"config_name": "acme_corporate_post_rag_tests.yaml"},
        },
        {
            "provider_id": "$PROVIDER_ID",
            "id": "whoami_pre_rag",
            "parameters": {"config_name": "whoami_pre_rag_tests.yaml"},
        },
        {
            "provider_id": "$PROVIDER_ID",
            "id": "whoami_post_rag",
            "parameters": {"config_name": "whoami_post_rag_tests.yaml"},
        },
    ]

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(request, handle, indent=2)
PY

SUBMIT_CODE="$(curl_json POST "$EVALHUB_URL/api/v1/evaluations/jobs" "$RESPONSE_JSON" \
    -H "Content-Type: application/json" \
    -d "@$REQUEST_JSON")"
if [[ "$SUBMIT_CODE" != "202" && "$SUBMIT_CODE" != "200" ]]; then
    log_error "EvalHub RAG scenario job submission failed: HTTP $SUBMIT_CODE"
    cat "$REQUEST_JSON" || true
    cat "$RESPONSE_JSON" || true
    exit 1
fi

JOB_ID="$(extract_job_id "$RESPONSE_JSON")"
if [[ -z "$JOB_ID" ]]; then
    log_error "EvalHub did not return a job id"
    cat "$RESPONSE_JSON" || true
    exit 1
fi
log_success "EvalHub RAG scenario job submitted: $JOB_ID"

STATUS_JSON="$WORK_DIR/evalhub-rag-status.json"
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
        log_info "EvalHub RAG scenario job $JOB_ID state: ${STATE:-unknown} ($attempt/$POLL_ATTEMPTS)"
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
        log_success "EvalHub RAG scenario job completed"
        ;;
    failed|cancelled|partially_failed)
        log_error "EvalHub RAG scenario job finished in terminal state: $STATE"
        cat "$STATUS_JSON" || true
        exit 1
        ;;
    *)
        log_error "EvalHub RAG scenario job did not finish within $((POLL_ATTEMPTS * POLL_SECONDS)) seconds"
        cat "$STATUS_JSON" || true
        exit 1
        ;;
esac

echo ""
echo "EvalHub RAG scenario results:"
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
