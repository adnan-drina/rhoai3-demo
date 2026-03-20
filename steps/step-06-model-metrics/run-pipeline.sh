#!/bin/bash
# Trigger a GuideLLM benchmark pipeline run via DSPA.
# Usage: ./run-pipeline.sh [model_name] [run_id]
#   model_name: granite-8b-agent (default) or mistral-3-bf16
#   run_id:     unique identifier (default: bench-<timestamp>)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"
MODEL_INPUT="${1:-granite}"
RUN_ID="${2:-bench-$(date +%s)}"

source "$REPO_ROOT/scripts/lib.sh"

case "$MODEL_INPUT" in
    granite|granite-8b-agent)
        MODEL_NAME="granite-8b-agent"
        PIPELINE_NAME="bench-granite-8b"
        PIPELINE_YAML="$REPO_ROOT/artifacts/bench-granite-8b.yaml"
        ;;
    mistral|mistral-bf16|mistral-3-bf16)
        MODEL_NAME="mistral-3-bf16"
        PIPELINE_NAME="bench-mistral-bf16"
        PIPELINE_YAML="$REPO_ROOT/artifacts/bench-mistral-bf16.yaml"
        ;;
    *)
        log_error "Unknown model: $MODEL_INPUT. Available: granite, mistral-bf16"
        exit 1
        ;;
esac

if [ ! -f "$PIPELINE_YAML" ]; then
    log_info "Compiling pipeline..."
    VENV_PATH="$REPO_ROOT/.venv-kfp"
    if [ ! -d "$VENV_PATH" ]; then
        python3 -m venv "$VENV_PATH"
        "$VENV_PATH/bin/pip" install -q --upgrade pip kfp
    fi
    (cd "$SCRIPT_DIR/kfp" && "$VENV_PATH/bin/python3" benchmark_pipeline.py)
fi

if [ ! -f "$PIPELINE_YAML" ]; then
    log_error "Pipeline compilation failed: $PIPELINE_YAML not found"
    exit 1
fi

log_info "Launching benchmark pipeline (model=$MODEL_NAME, run_id=$RUN_ID)..."

OC_TOKEN=$(oc whoami -t 2>/dev/null || true)
if [ -z "$OC_TOKEN" ]; then
    log_error "Unable to obtain oc token. Run 'oc login' first."
    exit 1
fi
export NAMESPACE MODEL_NAME RUN_ID PIPELINE_YAML PIPELINE_NAME

"$VENV_PATH/bin/python3" << 'PYTHON_SCRIPT'
import os, sys, time
from kfp import client

NAMESPACE = os.environ["NAMESPACE"]
MODEL_NAME = os.environ["MODEL_NAME"]
RUN_ID = os.environ["RUN_ID"]
PIPELINE_YAML = os.environ["PIPELINE_YAML"]
AUTH_TOKEN = os.popen("oc whoami -t 2>/dev/null").read().strip()

DSPA_ROUTE = os.popen(
    f"oc get route ds-pipeline-dspa-rag -n {NAMESPACE} -o jsonpath='{{.spec.host}}' 2>/dev/null"
).read().strip()

if not DSPA_ROUTE:
    DSPA_ROUTE = os.popen(
        f"oc get route -n {NAMESPACE} -l app=ds-pipeline-dspa-rag -o jsonpath='{{.items[0].spec.host}}' 2>/dev/null"
    ).read().strip()

if not DSPA_ROUTE:
    print("Could not detect DSPA route. Upload pipeline manually via RHOAI Dashboard.")
    sys.exit(1)

DSPA_URL = f"https://{DSPA_ROUTE}"
print(f"DSPA: {DSPA_URL}")

PIPELINE_NAME = os.environ["PIPELINE_NAME"]

try:
    kfp_client = client.Client(
        host=DSPA_URL,
        namespace=NAMESPACE,
        existing_token=AUTH_TOKEN,
    )
except Exception as e:
    print(f"KFP client init failed: {e}")
    sys.exit(1)

try:
    pipeline = kfp_client.upload_pipeline(
        pipeline_package_path=PIPELINE_YAML,
        pipeline_name=PIPELINE_NAME,
    )
    pipeline_id = pipeline.pipeline_id
    print(f"Pipeline uploaded: {pipeline_id}")
except Exception as e:
    if "already exists" in str(e):
        pipelines = kfp_client.list_pipelines(page_size=100).pipelines or []
        pipeline = next((p for p in pipelines if p.name == PIPELINE_NAME), None)
        if pipeline:
            pipeline_id = pipeline.pipeline_id
            print(f"Pipeline exists: {pipeline_id}")
        else:
            print(f"Pipeline not found: {e}")
            sys.exit(1)
    else:
        print(f"Pipeline upload failed: {e}")
        sys.exit(1)

version = kfp_client.upload_pipeline_version(
    pipeline_package_path=PIPELINE_YAML,
    pipeline_version_name=f"{PIPELINE_NAME}-{int(time.time())}",
    pipeline_id=pipeline_id,
)
version_id = version.pipeline_version_id
print(f"Pipeline version: {version_id}")

experiment_name = "model-benchmarking"
try:
    experiment = kfp_client.create_experiment(name=experiment_name, namespace=NAMESPACE)
    experiment_id = experiment.experiment_id
except Exception:
    experiments = kfp_client.list_experiments(page_size=100).experiments or []
    experiment = next((e for e in experiments if e.display_name == experiment_name), None)
    if experiment:
        experiment_id = experiment.experiment_id
    else:
        print(f"Could not create/find experiment '{experiment_name}'")
        sys.exit(1)

params = {
    "model_name": MODEL_NAME,
    "run_id": RUN_ID,
}

run = kfp_client.run_pipeline(
    experiment_id=experiment_id,
    job_name=f"bench-{MODEL_NAME}-{RUN_ID}",
    pipeline_id=pipeline_id,
    version_id=version_id,
    params=params,
    enable_caching=False,
)
print(f"Run created: {run.run_id}")
print(f"View: {DSPA_URL}/#/runs/details/{run.run_id}")
PYTHON_SCRIPT

if [ $? -eq 0 ]; then
    log_success "Benchmark pipeline launched (model=$MODEL_NAME, run_id=$RUN_ID)"
    echo ""
    log_info "View in RHOAI Dashboard: Develop & train → Pipelines → Runs"
else
    log_error "Benchmark pipeline launch failed"
    exit 1
fi
