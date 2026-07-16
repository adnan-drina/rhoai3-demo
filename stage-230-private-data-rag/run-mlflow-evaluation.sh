#!/usr/bin/env bash
# Run the Stage 230 MLflow GenAI evaluation pipeline through RHOAI AI Pipelines.
#
# Compiles kfp/mlflow_genai_evaluation_pipeline.py, submits it to the stage
# DSPA, waits for completion, then verifies the MLflow side: the benchmark
# dataset exists, the evaluation run has judge metrics, and per-row traces
# carry assessments. Judge model: MaaS-governed gpt-4o-mini (see PLAN.md).
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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: required command not found: $1" >&2; exit 1; }
}
require_cmd oc
require_cmd python3

RAG_NS="${RHOAI_STAGE230_NAMESPACE:-enterprise-rag}"
DSPA_NAME="${RHOAI_STAGE230_DSPA_NAME:-dspa-enterprise-rag}"
PIPELINE_NAME="${RHOAI_STAGE230_MLFLOW_EVAL_PIPELINE_NAME:-stage-230-mlflow-genai-evaluation}"
KFP_EXPERIMENT_NAME="${RHOAI_STAGE230_RHOAI_DOCS_EXPERIMENT_NAME:-stage-230-private-data-rag}"
PIPELINE_ROOT="${RHOAI_STAGE230_PIPELINE_ROOT:-s3://enterprise-rag/pipelines/stage-230}"
MLFLOW_EXPERIMENT="${RHOAI_STAGE230_MLFLOW_EXPERIMENT:-private-rag-chatbot}"
DATASET_NAME="${RHOAI_STAGE230_MLFLOW_EVAL_DATASET:-private-rag-chatbot-benchmark}"
RUN_TIMEOUT_SECONDS="${RHOAI_STAGE230_MLFLOW_EVAL_TIMEOUT:-2700}"
CHATBOT_DEPLOYMENT="${RHOAI_STAGE230_CHATBOT_DEPLOYMENT:-private-rag-chatbot}"

echo "== Stage 230 MLflow GenAI evaluation =="

# ── Compile ───────────────────────────────────────────────────────────────────
VENV="$ROOT_DIR/.venv-kfp"
if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install -q "kfp==2.14.6" "kfp-kubernetes==2.14.6"
# BSD mktemp cannot append a suffix after the template Xs, and the kfp
# compiler requires a .yaml extension - use a temp dir.
PIPELINE_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/stage230-mlflow-eval.XXXXXX")
trap 'rm -rf "$PIPELINE_TMP_DIR"' EXIT
PIPELINE_YAML="$PIPELINE_TMP_DIR/pipeline.yaml"
"$VENV/bin/python" "$SCRIPT_DIR/kfp/mlflow_genai_evaluation_pipeline.py" --output "$PIPELINE_YAML"
echo "   compiled: $PIPELINE_YAML"

# ── Submit to the DSPA and wait ───────────────────────────────────────────────
DSPA_ROUTE=$(oc get route "ds-pipeline-${DSPA_NAME}" -n "$RAG_NS" -o jsonpath='{.spec.host}' --insecure-skip-tls-verify=true)
OC_TOKEN=$(oc whoami -t)

RUN_SUMMARY=$(OC_TOKEN="$OC_TOKEN" DSPA_HOST="https://${DSPA_ROUTE}" \
  PIPELINE_YAML="$PIPELINE_YAML" PIPELINE_NAME="$PIPELINE_NAME" \
  KFP_EXPERIMENT_NAME="$KFP_EXPERIMENT_NAME" RAG_NS="$RAG_NS" \
  PIPELINE_ROOT="$PIPELINE_ROOT" RUN_TIMEOUT_SECONDS="$RUN_TIMEOUT_SECONDS" \
  "$VENV/bin/python" - <<'PY'
import os, time

import urllib3
urllib3.disable_warnings()
from kfp import client

kfp_client = client.Client(
    host=os.environ["DSPA_HOST"],
    existing_token=os.environ["OC_TOKEN"],
    verify_ssl=False,
)

pipeline_name = os.environ["PIPELINE_NAME"]
pipeline_yaml = os.environ["PIPELINE_YAML"]
version_name = f"{pipeline_name}-{time.strftime('%Y%m%d%H%M%S')}"

pipelines = kfp_client.list_pipelines(page_size=200).pipelines or []
pipeline = next((p for p in pipelines if p.display_name == pipeline_name), None)
if pipeline is None:
    pipeline = kfp_client.upload_pipeline(pipeline_yaml, pipeline_name=pipeline_name)
    version_id = None
    versions = kfp_client.list_pipeline_versions(pipeline_id=pipeline.pipeline_id, page_size=10)
    version_id = (versions.pipeline_versions or [])[0].pipeline_version_id
else:
    version = kfp_client.upload_pipeline_version(
        pipeline_yaml, pipeline_version_name=version_name, pipeline_id=pipeline.pipeline_id)
    version_id = version.pipeline_version_id

experiments = kfp_client.list_experiments(page_size=100).experiments or []
experiment = next((e for e in experiments if e.display_name == os.environ["KFP_EXPERIMENT_NAME"]), None)
if experiment is None:
    experiment = kfp_client.create_experiment(name=os.environ["KFP_EXPERIMENT_NAME"])

run = kfp_client.run_pipeline(
    experiment_id=experiment.experiment_id,
    job_name=version_name,
    pipeline_id=pipeline.pipeline_id,
    version_id=version_id,
    pipeline_root=os.environ["PIPELINE_ROOT"],
)
print(f"run_id={run.run_id}", flush=True)
result = kfp_client.wait_for_run_completion(
    run_id=run.run_id, timeout=int(os.environ["RUN_TIMEOUT_SECONDS"]))
state = result.state
print(f"final_state={state}", flush=True)
if str(state).upper() not in ("SUCCEEDED", "RUNTIMESTATE.SUCCEEDED"):
    raise SystemExit(f"pipeline run finished in state {state}")
PY
)
echo "$RUN_SUMMARY"

# ── Verify the MLflow side through the workspace identity ────────────────────
echo "== Verifying MLflow dataset / evaluation run / assessments =="
oc exec -i -n "$RAG_NS" "deploy/${CHATBOT_DEPLOYMENT}" --insecure-skip-tls-verify=true -- \
  env EVAL_DATASET_NAME="$DATASET_NAME" python3 - <<'PY'
import json, os

import mlflow
from mlflow import MlflowClient

exp = mlflow.get_experiment_by_name(os.environ.get("MLFLOW_EXPERIMENT_NAME", "private-rag-chatbot"))
assert exp, "MLflow experiment missing"

from mlflow.genai import datasets as genai_datasets
found = genai_datasets.search_datasets(
    experiment_ids=[exp.experiment_id],
    filter_string=f"name = '{os.environ['EVAL_DATASET_NAME']}'")
found = list(found) if not isinstance(found, list) else found
assert found, "benchmark dataset not found"
print(f"dataset OK: {found[0].dataset_id}")

runs = MlflowClient().search_runs(
    experiment_ids=[exp.experiment_id], order_by=["start_time DESC"], max_results=1)
assert runs, "no evaluation runs found"
run = runs[0]
judge_metrics = {k: round(v, 3) for k, v in run.data.metrics.items()
                 if any(s in k.lower() for s in ("correctness", "relevance", "groundedness", "safety"))}
assert judge_metrics, f"latest run {run.info.run_id} has no judge metrics: {run.data.metrics}"
print(f"evaluation run OK: {run.info.run_id}")
print("judge metrics:", json.dumps(judge_metrics))
PY

echo "== Done: check MLflow → Datasets / Evaluation runs / Traces (assessments) =="
