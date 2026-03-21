#!/bin/bash
# Launch a batch RAG ingestion pipeline run for a given scenario.
# Usage: ./run-batch-ingestion.sh <scenario> [--eval]
#   scenario: acme | whoami

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"

source "$REPO_ROOT/scripts/lib.sh"
load_env

EVAL_AFTER=false
SCENARIO=""
for arg in "$@"; do
    case "$arg" in
        --eval) EVAL_AFTER=true ;;
        *) SCENARIO="$arg" ;;
    esac
done

if [ -z "$SCENARIO" ]; then
    log_error "Scenario parameter required"
    echo ""
    echo "Usage: $0 <scenario> [--eval]"
    echo ""
    echo "Available scenarios:"
    echo "  acme       - ACME Corporate lithography docs (8 PDFs)"
    echo "  whoami     - Personal CV (1 PDF)"
    echo ""
    echo "Options:"
    echo "  --eval     - Trigger RAG evaluation after ingestion completes"
    echo ""
    echo "Examples:"
    echo "  $0 acme                     # Ingest only"
    echo "  $0 acme --eval              # Ingest then evaluate"
    echo "  for s in acme whoami; do $0 \$s --eval; done"
    exit 1
fi

case "$SCENARIO" in
    acme)
        S3_PREFIX="s3://rag-documents/acme/"
        VECTOR_DB_ID="acme_corporate"
        DESCRIPTION="ACME Corporate Lithography Documentation"
        ;;
    whoami)
        S3_PREFIX="s3://rag-documents/whoami/"
        VECTOR_DB_ID="whoami"
        DESCRIPTION="Personal CV"
        ;;
    *)
        log_error "Invalid scenario: $SCENARIO (valid: acme, whoami)"
        exit 1
        ;;
esac

log_step "RAG Batch Ingestion Pipeline"
log_info "Scenario:    $SCENARIO"
log_info "S3 Path:     $S3_PREFIX"
log_info "Collection:  $VECTOR_DB_ID"
log_info "Description: $DESCRIPTION"
echo ""

OC_TOKEN=$(oc whoami -t 2>/dev/null || true)
if [ -z "$OC_TOKEN" ]; then
    log_error "Unable to obtain oc token. Run 'oc login' first."
    exit 1
fi
log_success "oc token acquired"

VENV_PATH="$REPO_ROOT/.venv-kfp"
if [ ! -d "$VENV_PATH" ]; then
    log_info "Creating Python venv..."
    python3 -m venv "$VENV_PATH"
fi
"$VENV_PATH/bin/pip" install -q --upgrade pip kfp "kfp-server-api>=2.0,<3.0" 2>/dev/null

PIPELINE_YAML="$REPO_ROOT/artifacts/rag-ingestion-batch.yaml"
if [ ! -f "$PIPELINE_YAML" ]; then
    log_step "Compiling pipeline..."
    mkdir -p "$REPO_ROOT/artifacts"
    (cd "$SCRIPT_DIR/kfp" && "$VENV_PATH/bin/python3" pipeline.py)
    if [ ! -f "$PIPELINE_YAML" ]; then
        log_error "Pipeline compilation failed — $PIPELINE_YAML not found"
        exit 1
    fi
fi

log_info "Launching pipeline run via KFP client..."
export S3_PREFIX VECTOR_DB_ID SCENARIO NAMESPACE OC_TOKEN REPO_ROOT

"$VENV_PATH/bin/python3" << 'PYTHON_SCRIPT'
import os, sys, time
from kfp import client

NAMESPACE = os.environ["NAMESPACE"]
SCENARIO = os.environ["SCENARIO"]
S3_PREFIX = os.environ["S3_PREFIX"]
VECTOR_DB_ID = os.environ["VECTOR_DB_ID"]
AUTH_TOKEN = os.environ.get("OC_TOKEN") or os.popen("oc whoami -t 2>/dev/null").read().strip()

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

PIPELINE_NAME = "rag-ingestion-batch"
PIPELINE_YAML = os.path.join(
    os.environ.get("REPO_ROOT", os.path.dirname(os.path.abspath(__file__)) + "/../.."),
    "artifacts/rag-ingestion-batch.yaml",
)

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
    print(f"Pipeline details: {DSPA_URL}/#/pipelines/details/{pipeline_id}")
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

# Get the latest pipeline version (required by KFP v2)
versions = kfp_client.list_pipeline_versions(pipeline_id=pipeline_id, page_size=10)
if versions.pipeline_versions:
    version_id = versions.pipeline_versions[0].pipeline_version_id
    print(f"Pipeline version: {version_id}")
else:
    # Upload creates the first version — try uploading a version explicitly
    version = kfp_client.upload_pipeline_version(
        pipeline_package_path=PIPELINE_YAML,
        pipeline_version_name=f"{PIPELINE_NAME}-{int(time.time())}",
        pipeline_id=pipeline_id,
    )
    version_id = version.pipeline_version_id
    print(f"Pipeline version created: {version_id}")

experiment_name = f"rag-ingestion-{SCENARIO}"
try:
    experiment = kfp_client.create_experiment(name=experiment_name, namespace=NAMESPACE)
    experiment_id = experiment.experiment_id
    print(f"Experiment details: {DSPA_URL}/#/experiments/details/{experiment_id}")
except Exception:
    experiments = kfp_client.list_experiments(page_size=100).experiments or []
    experiment = next((e for e in experiments if e.display_name == experiment_name), None)
    if experiment:
        experiment_id = experiment.experiment_id
    else:
        print(f"Could not create/find experiment '{experiment_name}'")
        sys.exit(1)

params = {
    "s3_prefix": S3_PREFIX,
    "vector_db_id": VECTOR_DB_ID,
}

run_name = f"{SCENARIO}-ingestion-{int(time.time())}"
run = kfp_client.run_pipeline(
    experiment_id=experiment_id,
    job_name=run_name,
    pipeline_id=pipeline_id,
    version_id=version_id,
    params=params,
    enable_caching=False,
)
print(f"Run created: {run.run_id}")
print(f"View: {DSPA_URL}/#/runs/details/{run.run_id}")
PYTHON_SCRIPT

if [ $? -eq 0 ]; then
    echo ""
    log_success "Pipeline launched for scenario: $SCENARIO"

    if [ "$EVAL_AFTER" = true ]; then
        echo ""
        log_step "Triggering RAG evaluation after ingestion..."
        EVAL_SCRIPT="$SCRIPT_DIR/../step-08-model-evaluation/run-rag-eval.sh"
        if [ -x "$EVAL_SCRIPT" ] || [ -f "$EVAL_SCRIPT" ]; then
            log_info "Waiting 30s for ingestion to settle before evaluating..."
            sleep 30
            chmod +x "$EVAL_SCRIPT"
            "$EVAL_SCRIPT" "eval-after-${SCENARIO}-$(date +%s)" || \
                log_error "Eval pipeline launch failed — run manually: ./steps/step-08-model-evaluation/run-rag-eval.sh"
        else
            log_error "Eval script not found: $EVAL_SCRIPT"
            log_error "Run manually: ./steps/step-08-model-evaluation/run-rag-eval.sh"
        fi
    fi
else
    echo ""
    log_error "Pipeline launch failed for $SCENARIO"
    exit 1
fi
