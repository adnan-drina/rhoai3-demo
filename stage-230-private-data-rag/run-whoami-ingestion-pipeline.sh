#!/usr/bin/env bash
# Compile and run the Stage 230 whoami RAG ingestion pipeline through DSPA.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

PROJECT_NS="${RHOAI_STAGE230_PROJECT_NAMESPACE:-enterprise-rag}"
DSPA_NAME="${RHOAI_STAGE230_DSPA_NAME:-private-rag-pipelines}"
DSPA_ROUTE_NAME="${RHOAI_STAGE230_DSPA_ROUTE_NAME:-ds-pipeline-${DSPA_NAME}}"
PIPELINE_NAME="${RHOAI_STAGE230_PIPELINE_NAME:-whoami-rag-ingestion}"
EXPERIMENT_NAME="${RHOAI_STAGE230_EXPERIMENT_NAME:-private-data-rag}"
RUN_NAME="${RHOAI_STAGE230_RUN_NAME:-whoami-rag-$(date +%Y%m%d-%H%M%S)}"
RAG_LSD_NAME="${RHOAI_STAGE230_LSD_NAME:-lsd-private-rag}"
RAG_DOCLING_SERVICE="${RHOAI_STAGE230_DOCLING_SERVICE:-private-rag-docling}"
RAG_VECTOR_DB="${RHOAI_STAGE230_VECTOR_DB:-whoami}"
RAG_EMBEDDING_MODEL="${RHOAI_STAGE230_EMBEDDING_MODEL:-all-MiniLM-L6-v2}"
RAG_EMBEDDING_DIMENSION="${RHOAI_STAGE230_EMBEDDING_DIMENSION:-384}"
RAG_CHUNK_SIZE="${RHOAI_STAGE230_CHUNK_SIZE:-512}"
RAG_PROCESSING_TIMEOUT="${RHOAI_STAGE230_DOCLING_TIMEOUT:-600}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
SOURCE_OBC_NAME="${RHOAI_STAGE230_OBC_NAME:-enterprise-rag-bucket}"
LAST_RUN_CONFIGMAP="${RHOAI_STAGE230_LAST_RUN_CONFIGMAP:-private-rag-pipeline-last-run}"
WAIT_FOR_RUN=true
RUN_TIMEOUT_SECONDS="${RHOAI_STAGE230_PIPELINE_TIMEOUT_SECONDS:-1800}"

for arg in "$@"; do
  case "$arg" in
    --no-wait)
      WAIT_FOR_RUN=false
      ;;
    --wait)
      WAIT_FOR_RUN=true
      ;;
    --run-name=*)
      RUN_NAME="${arg#*=}"
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd oc
require_cmd python3

jsonpath() {
  local resource="$1"
  local namespace="$2"
  local path="$3"
  oc get "$resource" -n "$namespace" -o jsonpath="$path" \
    --insecure-skip-tls-verify=true 2>/dev/null || true
}

wait_for_dspa() {
  echo "-- Waiting for DSPA ${PROJECT_NS}/${DSPA_NAME} --"
  for _ in $(seq 1 90); do
    local ready
    ready=$(jsonpath "dspa/${DSPA_NAME}" "$PROJECT_NS" '{.status.conditions[?(@.type=="Ready")].status}')
    if [[ "$ready" == "True" ]]; then
      echo "[OK] DSPA is Ready"
      return 0
    fi
    sleep 10
  done

  echo "ERROR: DSPA ${PROJECT_NS}/${DSPA_NAME} did not become Ready." >&2
  oc get dspa "$DSPA_NAME" -n "$PROJECT_NS" -o yaml \
    --insecure-skip-tls-verify=true | sed -n '/status:/,$p' >&2 || true
  return 1
}

wait_for_dspa_route() {
  echo "-- Waiting for DSPA route ${PROJECT_NS}/${DSPA_ROUTE_NAME} --" >&2
  for _ in $(seq 1 60); do
    local host
    host=$(jsonpath "route/${DSPA_ROUTE_NAME}" "$PROJECT_NS" '{.spec.host}')
    if [[ -n "$host" ]]; then
      printf '%s' "$host"
      return 0
    fi
    sleep 5
  done

  echo "ERROR: DSPA route ${PROJECT_NS}/${DSPA_ROUTE_NAME} was not created." >&2
  oc get route -n "$PROJECT_NS" --insecure-skip-tls-verify=true >&2 || true
  return 1
}

resolve_llamastack_url() {
  local service port
  for candidate in "$RAG_LSD_NAME" "${RAG_LSD_NAME}-service"; do
    if oc get svc "$candidate" -n "$PROJECT_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      service="$candidate"
      break
    fi
  done

  if [[ -z "${service:-}" ]]; then
    service=$(oc get svc -n "$PROJECT_NS" -o json --insecure-skip-tls-verify=true |
      jq -r --arg name "$RAG_LSD_NAME" '
        .items[]
        | select(.metadata.name | startswith($name))
        | .metadata.name
      ' | head -n 1)
  fi

  if [[ -z "${service:-}" ]]; then
    echo "ERROR: could not find a Service for Llama Stack distribution ${RAG_LSD_NAME}." >&2
    oc get svc -n "$PROJECT_NS" --insecure-skip-tls-verify=true >&2 || true
    return 1
  fi

  port=$(oc get svc "$service" -n "$PROJECT_NS" -o json --insecure-skip-tls-verify=true |
    jq -r '
      (.spec.ports[] | select(.name == "http") | .port),
      (.spec.ports[] | select(.port == 8321) | .port),
      (.spec.ports[0].port)
    ' | head -n 1)

  if [[ -z "$port" || "$port" == "null" ]]; then
    echo "ERROR: could not determine Llama Stack Service port for ${service}." >&2
    return 1
  fi

  printf 'http://%s.%s.svc.cluster.local:%s' "$service" "$PROJECT_NS" "$port"
}

compile_pipeline() {
  echo "-- Compiling KFP pipeline --"
  local venv="$ROOT_DIR/.venv-kfp"
  if [[ ! -d "$venv" ]]; then
    python3 -m venv "$venv"
  fi
  "$venv/bin/pip" install -q --upgrade pip
  "$venv/bin/pip" install -q "kfp>=2.14,<3" kfp-kubernetes

  (cd "$SCRIPT_DIR/kfp" && "$venv/bin/python3" pipeline.py)
  echo "[OK] Compiled artifacts/stage-230-whoami-rag-ingestion.yaml"
}

submit_pipeline() {
  local route_host="$1"
  local llamastack_url="$2"
  local result_file="$3"
  local token bucket host port endpoint pipeline_yaml s3_uri venv dspa_url docling_service

  token=$(oc whoami -t --insecure-skip-tls-verify=true)
  bucket=$(jsonpath "configmap/${SOURCE_OBC_NAME}" "$PROJECT_NS" '{.data.BUCKET_NAME}')
  host=$(jsonpath "configmap/${SOURCE_OBC_NAME}" "$PROJECT_NS" '{.data.BUCKET_HOST}')
  port=$(jsonpath "configmap/${SOURCE_OBC_NAME}" "$PROJECT_NS" '{.data.BUCKET_PORT}')
  if [[ -z "$bucket" || -z "$host" || -z "$port" ]]; then
    echo "ERROR: source OBC ConfigMap ${PROJECT_NS}/${SOURCE_OBC_NAME} is missing bucket connection data." >&2
    return 1
  fi

  endpoint="https://${host}:${port}"
  s3_uri="s3://${bucket}/private-rag/whoami/"
  dspa_url="https://${route_host}"
  docling_service="http://${RAG_DOCLING_SERVICE}.${PROJECT_NS}.svc.cluster.local:5001"
  pipeline_yaml="$ROOT_DIR/artifacts/stage-230-whoami-rag-ingestion.yaml"
  venv="$ROOT_DIR/.venv-kfp"

  echo "-- Submitting pipeline run --"
  echo "   DSPA:        ${dspa_url}"
  echo "   S3 source:   ${s3_uri}"
  echo "   Llama Stack: ${llamastack_url}"

  export PROJECT_NS PIPELINE_NAME EXPERIMENT_NAME RUN_NAME DSPA_URL="$dspa_url" OC_TOKEN="$token"
  export PIPELINE_YAML="$pipeline_yaml" RESULT_FILE="$result_file"
  export S3_URI="$s3_uri" S3_ENDPOINT="$endpoint" DOCLING_SERVICE="$docling_service" LLAMASTACK_URL="$llamastack_url"
  export NEMOTRON_MODEL_RESOURCE RAG_VECTOR_DB RAG_EMBEDDING_MODEL RAG_EMBEDDING_DIMENSION RAG_CHUNK_SIZE RAG_PROCESSING_TIMEOUT
  export WAIT_FOR_RUN RUN_TIMEOUT_SECONDS

  "$venv/bin/python3" <<'PY'
import inspect
import json
import os
import sys
import time

import kfp


def get_attr(obj, *names):
    for name in names:
        value = getattr(obj, name, None)
        if value:
            return value
    return None


def as_dict(obj):
    if hasattr(obj, "to_dict"):
        return obj.to_dict()
    if isinstance(obj, dict):
        return obj
    return getattr(obj, "__dict__", {})


def state_from_run(run_obj):
    data = as_dict(run_obj)
    candidates = [
        data.get("state"),
        data.get("status"),
        data.get("run", {}).get("state") if isinstance(data.get("run"), dict) else None,
        data.get("run", {}).get("status") if isinstance(data.get("run"), dict) else None,
    ]
    run = getattr(run_obj, "run", None)
    if run is not None:
        candidates.extend([getattr(run, "state", None), getattr(run, "status", None)])
    for candidate in candidates:
        if candidate:
            return str(candidate).split(".")[-1].upper()
    return "UNKNOWN"


client_kwargs = {
    "host": os.environ["DSPA_URL"],
    "namespace": os.environ["PROJECT_NS"],
    "existing_token": os.environ["OC_TOKEN"],
}
if "verify_ssl" in inspect.signature(kfp.Client).parameters:
    client_kwargs["verify_ssl"] = False

try:
    kfp_client = kfp.Client(**client_kwargs)
except TypeError:
    client_kwargs.pop("verify_ssl", None)
    kfp_client = kfp.Client(**client_kwargs)

pipeline_name = os.environ["PIPELINE_NAME"]
pipeline_yaml = os.environ["PIPELINE_YAML"]
version_name = "v-" + os.environ["RUN_NAME"].replace("_", "-")

try:
    pipeline = kfp_client.upload_pipeline(
        pipeline_package_path=pipeline_yaml,
        pipeline_name=pipeline_name,
    )
    pipeline_id = get_attr(pipeline, "pipeline_id", "id")
    print(f"Uploaded pipeline {pipeline_name}: {pipeline_id}")
except Exception as exc:
    print(f"Pipeline upload returned {exc}; looking up existing pipeline")
    filter_json = json.dumps(
        {
            "predicates": [
                {
                    "key": "name",
                    "operation": "EQUALS",
                    "stringValue": pipeline_name,
                }
            ]
        }
    )
    pipelines = kfp_client.list_pipelines(filter=filter_json)
    items = getattr(pipelines, "pipelines", None) or []
    if not items:
        raise
    pipeline = items[0]
    pipeline_id = get_attr(pipeline, "pipeline_id", "id")

version = kfp_client.upload_pipeline_version(
    pipeline_package_path=pipeline_yaml,
    pipeline_version_name=version_name,
    pipeline_id=pipeline_id,
)
version_id = get_attr(version, "pipeline_version_id", "id")
print(f"Uploaded version {version_name}: {version_id}")

experiment_name = os.environ["EXPERIMENT_NAME"]
try:
    experiment = kfp_client.create_experiment(
        name=experiment_name,
        namespace=os.environ["PROJECT_NS"],
    )
except Exception:
    experiments = kfp_client.list_experiments(namespace=os.environ["PROJECT_NS"])
    items = getattr(experiments, "experiments", None) or []
    experiment = next(
        item for item in items
        if get_attr(item, "display_name", "name") == experiment_name
    )
experiment_id = get_attr(experiment, "experiment_id", "id")

run = kfp_client.run_pipeline(
    experiment_id=experiment_id,
    job_name=os.environ["RUN_NAME"],
    pipeline_id=pipeline_id,
    version_id=version_id,
    params={
        "s3_uri": os.environ["S3_URI"],
        "s3_endpoint": os.environ["S3_ENDPOINT"],
        "docling_service": os.environ["DOCLING_SERVICE"],
        "llamastack_url": os.environ["LLAMASTACK_URL"],
        "inference_model": os.environ["NEMOTRON_MODEL_RESOURCE"],
        "embedding_model": os.environ["RAG_EMBEDDING_MODEL"],
        "embedding_dimension": int(os.environ["RAG_EMBEDDING_DIMENSION"]),
        "vector_db_id": os.environ["RAG_VECTOR_DB"],
        "chunk_size_tokens": int(os.environ["RAG_CHUNK_SIZE"]),
        "processing_timeout": int(os.environ["RAG_PROCESSING_TIMEOUT"]),
        "reset_vector_db": True,
    },
    enable_caching=False,
)
run_id = get_attr(run, "run_id", "id")
if not run_id:
    raise RuntimeError(f"Could not determine run id from {run}")
print(f"Created run {os.environ['RUN_NAME']}: {run_id}")

status = "SUBMITTED"
if os.environ["WAIT_FOR_RUN"].lower() == "true":
    deadline = time.time() + int(os.environ["RUN_TIMEOUT_SECONDS"])
    terminal_success = {"SUCCEEDED", "SUCCESS"}
    terminal_failure = {"FAILED", "FAILURE", "CANCELED", "CANCELLED", "ERROR", "TERMINATED"}
    while time.time() < deadline:
        run_obj = kfp_client.get_run(run_id=run_id)
        status = state_from_run(run_obj)
        print(f"Run state: {status}")
        if status in terminal_success:
            break
        if status in terminal_failure:
            raise RuntimeError(f"Pipeline run failed: {status}")
        time.sleep(20)
    else:
        raise TimeoutError(f"Timed out waiting for pipeline run {run_id}")

result = {
    "pipeline_id": pipeline_id,
    "version_id": version_id,
    "run_id": run_id,
    "run_name": os.environ["RUN_NAME"],
    "status": status,
}
with open(os.environ["RESULT_FILE"], "w", encoding="utf-8") as handle:
    json.dump(result, handle)
print(json.dumps(result, indent=2))
PY
}

record_last_run() {
  local result_file="$1"
  local run_id run_name status version_id
  run_id=$(jq -r '.run_id' "$result_file")
  run_name=$(jq -r '.run_name' "$result_file")
  status=$(jq -r '.status' "$result_file")
  version_id=$(jq -r '.version_id' "$result_file")

  oc create configmap "$LAST_RUN_CONFIGMAP" -n "$PROJECT_NS" \
    --from-literal=run_id="$run_id" \
    --from-literal=run_name="$run_name" \
    --from-literal=status="$status" \
    --from-literal=pipeline_version_id="$version_id" \
    --from-literal=vector_db="$RAG_VECTOR_DB" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  oc label configmap "$LAST_RUN_CONFIGMAP" -n "$PROJECT_NS" --overwrite \
    app.kubernetes.io/name="$LAST_RUN_CONFIGMAP" \
    app.kubernetes.io/component=rag-ingestion-evidence \
    app.kubernetes.io/part-of=rhoai3-demo \
    demo.rhoai.io/stage=230 \
    --insecure-skip-tls-verify=true >/dev/null

  echo "[OK] Recorded latest pipeline run ${run_id} (${status})"
}

wait_for_dspa
route_host=$(wait_for_dspa_route)
llamastack_url=$(resolve_llamastack_url)
compile_pipeline
result_file=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-pipeline-result.XXXXXX")
submit_pipeline "$route_host" "$llamastack_url" "$result_file"
record_last_run "$result_file"

echo "Stage 230 whoami ingestion pipeline complete."
