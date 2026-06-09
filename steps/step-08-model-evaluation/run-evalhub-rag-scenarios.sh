#!/usr/bin/env bash
# Submit the ACME and whoami pre/post RAG scenario evaluations through EvalHub.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/lib.sh"

NAMESPACE="${NAMESPACE:-enterprise-rag}"
EVALHUB_NAMESPACE="${EVALHUB_NAMESPACE:-redhat-ods-applications}"
RUN_ID="${1:-evalhub-rag-$(date +%s)}"
MODEL_NAME="${EVALHUB_RAG_MODEL_NAME:-granite-8b-agent}"
MODEL_URL="${EVALHUB_RAG_MODEL_URL:-http://lsd-rag-service.enterprise-rag.svc.cluster.local:8321}"
PROVIDER_ID="${EVALHUB_RAG_PROVIDER_ID:-rhoai_rag_scenarios}"
COLLECTION_ID="${EVALHUB_RAG_COLLECTION_ID:-rhoai-rag-pre-post-v1}"
JUDGE_PROMPT_FILE="${EVALHUB_RAG_JUDGE_PROMPT_FILE:-$SCRIPT_DIR/eval-configs/scoring-templates/judge_prompt.txt}"
SUBMISSION_MODE="${EVALHUB_RAG_SUBMISSION_MODE:-independent}"
USE_COLLECTION="${EVALHUB_RAG_USE_COLLECTION:-true}"
SCENARIO_FILTER="${EVALHUB_RAG_SCENARIOS:-all}"
POLL_ATTEMPTS="${EVALHUB_RAG_POLL_ATTEMPTS:-180}"
POLL_SECONDS="${EVALHUB_RAG_POLL_SECONDS:-10}"

ALL_SCENARIOS=(
    acme_corporate_pre_rag
    acme_corporate_post_rag
    whoami_pre_rag
    whoami_post_rag
)

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

scenario_config_name() {
    case "$1" in
        acme_corporate_pre_rag) printf '%s' "acme_corporate_pre_rag_tests.yaml" ;;
        acme_corporate_post_rag) printf '%s' "acme_corporate_post_rag_tests.yaml" ;;
        whoami_pre_rag) printf '%s' "whoami_pre_rag_tests.yaml" ;;
        whoami_post_rag) printf '%s' "whoami_post_rag_tests.yaml" ;;
        *) return 1 ;;
    esac
}

scenario_slug() {
    case "$1" in
        acme_corporate_pre_rag) printf '%s' "acme-corporate-pre-rag" ;;
        acme_corporate_post_rag) printf '%s' "acme-corporate-post-rag" ;;
        whoami_pre_rag) printf '%s' "whoami-pre-rag" ;;
        whoami_post_rag) printf '%s' "whoami-post-rag" ;;
        *) return 1 ;;
    esac
}

scenario_use_case() {
    case "$1" in
        acme_corporate_pre_rag|acme_corporate_post_rag) printf '%s' "acme" ;;
        whoami_pre_rag|whoami_post_rag) printf '%s' "whoami" ;;
        *) return 1 ;;
    esac
}

scenario_mode() {
    case "$1" in
        acme_corporate_pre_rag|whoami_pre_rag) printf '%s' "pre-rag" ;;
        acme_corporate_post_rag|whoami_post_rag) printf '%s' "post-rag" ;;
        *) return 1 ;;
    esac
}

scenario_title() {
    case "$1" in
        acme_corporate_pre_rag) printf '%s' "ACME Corporate Pre-RAG Baseline" ;;
        acme_corporate_post_rag) printf '%s' "ACME Corporate Post-RAG Evaluation" ;;
        whoami_pre_rag) printf '%s' "Whoami Pre-RAG Baseline" ;;
        whoami_post_rag) printf '%s' "Whoami Post-RAG Evaluation" ;;
        *) return 1 ;;
    esac
}

selected_scenarios() {
    local scenario normalized

    if [[ "$SCENARIO_FILTER" == "all" || -z "$SCENARIO_FILTER" ]]; then
        printf '%s\n' "${ALL_SCENARIOS[@]}"
        return 0
    fi

    normalized="${SCENARIO_FILTER//,/ }"
    for scenario in $normalized; do
        scenario_config_name "$scenario" >/dev/null || {
            log_error "Unknown RAG scenario '$scenario'. Valid values: ${ALL_SCENARIOS[*]}"
            exit 1
        }
        printf '%s\n' "$scenario"
    done
}

write_independent_request() {
    local scenario="$1"
    local output="$2"
    local slug title use_case mode config_name job_name experiment_name

    slug="$(scenario_slug "$scenario")"
    title="$(scenario_title "$scenario")"
    use_case="$(scenario_use_case "$scenario")"
    mode="$(scenario_mode "$scenario")"
    config_name="$(scenario_config_name "$scenario")"
    if [[ -n "${EVALHUB_RAG_JOB_NAME:-}" && "$SCENARIO_FILTER" != "all" ]]; then
        job_name="$EVALHUB_RAG_JOB_NAME"
    else
        job_name="${EVALHUB_RAG_JOB_NAME_PREFIX:-evalhub-${slug}}-${RUN_ID}"
    fi
    experiment_name="${EVALHUB_RAG_EXPERIMENT_NAME:-evalhub-${slug}}"

    JOB_NAME="$job_name" \
    EXPERIMENT_NAME="$experiment_name" \
    TITLE="$title" \
    USE_CASE="$use_case" \
    MODE="$mode" \
    CONFIG_NAME="$config_name" \
    SCENARIO="$scenario" \
    MODEL_URL="$MODEL_URL" \
    MODEL_NAME="$MODEL_NAME" \
    PROVIDER_ID="$PROVIDER_ID" \
    JUDGE_PROMPT_FILE="$JUDGE_PROMPT_FILE" \
    RUN_ID="$RUN_ID" \
    python3 - "$output" <<'PY'
import json
import os
import sys

scenario = os.environ["SCENARIO"]
use_case = os.environ["USE_CASE"]
mode = os.environ["MODE"]
title = os.environ["TITLE"]
parameters = {"config_name": os.environ["CONFIG_NAME"]}
judge_prompt_file = os.environ.get("JUDGE_PROMPT_FILE", "")
if judge_prompt_file and os.path.exists(judge_prompt_file):
    with open(judge_prompt_file, encoding="utf-8") as handle:
        parameters["judge_prompt"] = handle.read()

request = {
    "name": os.environ["JOB_NAME"],
    "description": f"{title}: independent ACME/whoami RAG scenario evaluation",
    "tags": ["rag", "llm-as-judge", "independent", use_case, mode],
    "model": {
        "url": os.environ["MODEL_URL"],
        "name": os.environ["MODEL_NAME"],
    },
    "experiment": {
        "name": os.environ["EXPERIMENT_NAME"],
        "tags": [
            {"key": "rhoai.demo.step", "value": "08"},
            {"key": "rhoai.demo.capability", "value": "evalhub-rag-scenario-evaluation"},
            {"key": "rhoai.demo.run_id", "value": os.environ["RUN_ID"]},
            {"key": "rhoai.demo.evaluation_style", "value": "independent"},
            {"key": "rhoai.demo.scenario", "value": scenario},
            {"key": "rhoai.demo.use_case", "value": use_case},
            {"key": "rhoai.demo.mode", "value": mode},
        ],
    },
    "benchmarks": [
        {
            "provider_id": os.environ["PROVIDER_ID"],
            "id": scenario,
            "parameters": parameters,
        }
    ],
}

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(request, handle, indent=2)
PY
}

write_grouped_request() {
    local output="$1"
    local job_name="${EVALHUB_RAG_JOB_NAME:-evalhub-rag-pre-post-${RUN_ID}}"
    local experiment_name="${EVALHUB_RAG_EXPERIMENT_NAME:-evalhub-rag-pre-post}"

    JOB_NAME="$job_name" \
    EXPERIMENT_NAME="$experiment_name" \
    MODEL_URL="$MODEL_URL" \
    MODEL_NAME="$MODEL_NAME" \
    PROVIDER_ID="$PROVIDER_ID" \
    COLLECTION_ID="$COLLECTION_ID" \
    JUDGE_PROMPT_FILE="$JUDGE_PROMPT_FILE" \
    USE_COLLECTION="$USE_COLLECTION" \
    RUN_ID="$RUN_ID" \
    python3 - "$output" <<'PY'
import json
import os
import sys

def benchmark(benchmark_id, config_name):
    parameters = {"config_name": config_name}
    judge_prompt_file = os.environ.get("JUDGE_PROMPT_FILE", "")
    if judge_prompt_file and os.path.exists(judge_prompt_file):
        with open(judge_prompt_file, encoding="utf-8") as handle:
            parameters["judge_prompt"] = handle.read()
    return {
        "provider_id": os.environ["PROVIDER_ID"],
        "id": benchmark_id,
        "parameters": parameters,
    }

request = {
    "name": os.environ["JOB_NAME"],
    "description": "Grouped ACME Corp and whoami pre/post RAG scenario evaluation",
    "tags": ["rag", "pre-post", "acme", "whoami", "grouped"],
    "model": {
        "url": os.environ["MODEL_URL"],
        "name": os.environ["MODEL_NAME"],
    },
    "experiment": {
        "name": os.environ["EXPERIMENT_NAME"],
        "tags": [
            {"key": "rhoai.demo.step", "value": "08"},
            {"key": "rhoai.demo.capability", "value": "evalhub-rag-scenario-evaluation"},
            {"key": "rhoai.demo.run_id", "value": os.environ["RUN_ID"]},
            {"key": "rhoai.demo.evaluation_style", "value": "grouped"},
        ],
    },
}

if os.environ["USE_COLLECTION"].lower() == "true":
    request["collection"] = {"id": os.environ["COLLECTION_ID"]}
else:
    request["benchmarks"] = [
        benchmark("acme_corporate_pre_rag", "acme_corporate_pre_rag_tests.yaml"),
        benchmark("acme_corporate_post_rag", "acme_corporate_post_rag_tests.yaml"),
        benchmark("whoami_pre_rag", "whoami_pre_rag_tests.yaml"),
        benchmark("whoami_post_rag", "whoami_post_rag_tests.yaml"),
    ]

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(request, handle, indent=2)
PY
}

submit_and_wait() {
    local label="$1"
    local request_json="$2"
    local response_json="$3"
    local status_json="$4"
    local submit_code status_code state attempt

    log_step "Submitting EvalHub RAG scenario job: $label"
    submit_code="$(curl_json POST "$EVALHUB_URL/api/v1/evaluations/jobs" "$response_json" \
        -H "Content-Type: application/json" \
        -d "@$request_json")"
    if [[ "$submit_code" != "202" && "$submit_code" != "200" ]]; then
        log_error "EvalHub RAG scenario job submission failed: HTTP $submit_code"
        cat "$request_json" || true
        cat "$response_json" || true
        exit 1
    fi

    SUBMITTED_JOB_ID="$(extract_job_id "$response_json")"
    if [[ -z "$SUBMITTED_JOB_ID" ]]; then
        log_error "EvalHub did not return a job id"
        cat "$response_json" || true
        exit 1
    fi
    log_success "EvalHub RAG scenario job submitted: $SUBMITTED_JOB_ID"

    state=""
    for attempt in $(seq 1 "$POLL_ATTEMPTS"); do
        status_code="$(curl_json GET "$EVALHUB_URL/api/v1/evaluations/jobs/$SUBMITTED_JOB_ID" "$status_json")"
        if [[ "$status_code" != "200" ]]; then
            log_warn "Job status returned HTTP $status_code (attempt $attempt/$POLL_ATTEMPTS)"
        else
            state="$(json_field "$status_json" "status.state")"
            if [[ -z "$state" ]]; then
                state="$(json_field "$status_json" "state")"
            fi
            if [[ -z "$state" ]]; then
                state="$(json_field "$status_json" "status")"
            fi
            log_info "EvalHub RAG scenario job $SUBMITTED_JOB_ID state: ${state:-unknown} ($attempt/$POLL_ATTEMPTS)"
            case "$state" in
                completed|failed|cancelled|partially_failed)
                    break
                    ;;
            esac
        fi
        sleep "$POLL_SECONDS"
    done

    case "$state" in
        completed)
            log_success "EvalHub RAG scenario job completed: $label"
            if [[ -x "$SCRIPT_DIR/materialize-evalhub-rag-mlflow.sh" ]]; then
                "$SCRIPT_DIR/materialize-evalhub-rag-mlflow.sh" "$SUBMITTED_JOB_ID"
            fi
            ;;
        failed|cancelled|partially_failed)
            log_error "EvalHub RAG scenario job finished in terminal state: $state"
            cat "$status_json" || true
            exit 1
            ;;
        *)
            log_error "EvalHub RAG scenario job did not finish within $((POLL_ATTEMPTS * POLL_SECONDS)) seconds"
            cat "$status_json" || true
            exit 1
            ;;
    esac
}

print_results() {
    local label="$1"
    local status_json="$2"

    echo ""
    echo "EvalHub RAG scenario results: $label"
    python3 - "$status_json" <<'PY'
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
for benchmark in "${ALL_SCENARIOS[@]}"; do
    if ! grep -q "$benchmark" "$PROVIDER_JSON"; then
        log_error "Benchmark $benchmark not available from provider $PROVIDER_ID"
        cat "$PROVIDER_JSON" || true
        exit 1
    fi
done
log_success "Provider available: $PROVIDER_ID"

if [[ "$SUBMISSION_MODE" == "collection" || "$SUBMISSION_MODE" == "grouped" ]]; then
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

    REQUEST_JSON="$WORK_DIR/evalhub-rag-grouped-request.json"
    RESPONSE_JSON="$WORK_DIR/evalhub-rag-grouped-response.json"
    STATUS_JSON="$WORK_DIR/evalhub-rag-grouped-status.json"
    write_grouped_request "$REQUEST_JSON"
    submit_and_wait "grouped pre/post collection" "$REQUEST_JSON" "$RESPONSE_JSON" "$STATUS_JSON"
    print_results "grouped pre/post collection" "$STATUS_JSON"
else
    log_step "Submitting independent RAG scenario evaluations"
    while IFS= read -r scenario; do
        [[ -z "$scenario" ]] && continue
        slug="$(scenario_slug "$scenario")"
        label="$(scenario_title "$scenario")"
        REQUEST_JSON="$WORK_DIR/evalhub-rag-${slug}-request.json"
        RESPONSE_JSON="$WORK_DIR/evalhub-rag-${slug}-response.json"
        STATUS_JSON="$WORK_DIR/evalhub-rag-${slug}-status.json"
        write_independent_request "$scenario" "$REQUEST_JSON"
        submit_and_wait "$label" "$REQUEST_JSON" "$RESPONSE_JSON" "$STATUS_JSON"
        print_results "$label" "$STATUS_JSON"
    done < <(selected_scenarios)
fi
