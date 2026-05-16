#!/bin/bash
# Trigger a RAG evaluation pipeline run.
# Usage: ./run-rag-eval.sh [run_id]
#
# Optional prompt metadata env vars:
#   PROMPT_NAME, PROMPT_VERSION, PROMPT_ALIAS, PROMPT_SOURCE,
#   PROMPT_COMMIT_MESSAGE

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="enterprise-rag"
RUN_ID="${1:-eval-$(date +%s)}"
PROMPT_NAME="${PROMPT_NAME:-acme-rag-agentic}"
PROMPT_VERSION="${PROMPT_VERSION:-v1}"
PROMPT_ALIAS="${PROMPT_ALIAS:-staging}"
PROMPT_SOURCE="${PROMPT_SOURCE:-rhoai-gen-ai-studio-prompts}"
PROMPT_COMMIT_MESSAGE="${PROMPT_COMMIT_MESSAGE:-Initial agentic RAG prompt}"

source "$REPO_ROOT/scripts/lib.sh"

PIPELINE_YAML="$REPO_ROOT/artifacts/rag-eval.yaml"
VENV_PATH="$REPO_ROOT/.venv-kfp"
log_info "Compiling pipeline..."
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH"
fi
"$VENV_PATH/bin/pip" install -q --upgrade pip kfp kfp-kubernetes
(cd "$SCRIPT_DIR/kfp" && "$VENV_PATH/bin/python3" eval_pipeline.py)

log_info "Launching eval pipeline (run_id=$RUN_ID)..."
log_info "Prompt metadata: ${PROMPT_NAME}@${PROMPT_VERSION} (${PROMPT_ALIAS})"

OC_TOKEN=$(oc whoami -t 2>/dev/null || true)
if [ -z "$OC_TOKEN" ]; then
    log_error "Unable to obtain oc token. Run 'oc login' first."
    exit 1
fi
MINIO_CONSOLE_ROUTE=$(oc get route minio-console -n minio-storage -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
MINIO_CONSOLE_URL=""
if [ -n "$MINIO_CONSOLE_ROUTE" ]; then
    MINIO_CONSOLE_URL="https://$MINIO_CONSOLE_ROUTE"
fi

MLFLOW_TRACKING_URI=$(oc get mlflow mlflow -o jsonpath='{.status.address.url}' 2>/dev/null || true)
if [[ -z "$MLFLOW_TRACKING_URI" ]]; then
    MLFLOW_TRACKING_URI=$(oc get mlflow mlflow -o jsonpath='{.status.url}' 2>/dev/null || true)
fi
if [[ -n "$MLFLOW_TRACKING_URI" ]]; then
    log_info "MLflow tracking URI: $MLFLOW_TRACKING_URI"
else
    MLFLOW_TRACKING_URI="https://mlflow.redhat-ods-applications.svc:8443"
    log_warn "MLflow server not found; pipeline will skip MLflow logging if the server is unavailable"
fi

export NAMESPACE RUN_ID PIPELINE_YAML MINIO_CONSOLE_URL MLFLOW_TRACKING_URI
export PROMPT_NAME PROMPT_VERSION PROMPT_ALIAS PROMPT_SOURCE PROMPT_COMMIT_MESSAGE

"$VENV_PATH/bin/python3" << 'PYTHON_SCRIPT'
import os, sys, time
from kfp import client

NAMESPACE = os.environ["NAMESPACE"]
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

PIPELINE_NAME = "rag-eval"

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
    if "already exists" in str(e) or "409" in str(e) or "Conflict" in str(e):
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

# Upload a new version each run to ensure latest code is used
version = kfp_client.upload_pipeline_version(
    pipeline_package_path=PIPELINE_YAML,
    pipeline_version_name=f"{PIPELINE_NAME}-{int(time.time())}",
    pipeline_id=pipeline_id,
)
version_id = version.pipeline_version_id
print(f"Pipeline version: {version_id}")

experiment_name = "rag-evaluation"
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

MINIO_CONSOLE_URL = os.environ.get("MINIO_CONSOLE_URL", "")
MLFLOW_TRACKING_URI = os.environ.get("MLFLOW_TRACKING_URI", "https://mlflow.redhat-ods-applications.svc:8443")
params = {
    "run_id": RUN_ID,
    "minio_console_url": MINIO_CONSOLE_URL,
    "mlflow_tracking_uri": MLFLOW_TRACKING_URI,
    "prompt_name": os.environ.get("PROMPT_NAME", "acme-rag-agentic"),
    "prompt_version": os.environ.get("PROMPT_VERSION", "v1"),
    "prompt_alias": os.environ.get("PROMPT_ALIAS", "staging"),
    "prompt_source": os.environ.get("PROMPT_SOURCE", "rhoai-gen-ai-studio-prompts"),
    "prompt_commit_message": os.environ.get("PROMPT_COMMIT_MESSAGE", "Initial agentic RAG prompt"),
    "enable_mlflow_tracking": True,
}

run = kfp_client.run_pipeline(
    experiment_id=experiment_id,
    job_name=f"rag-eval-{RUN_ID}",
    pipeline_id=pipeline_id,
    version_id=version_id,
    params=params,
    enable_caching=False,
)
print(f"Run created: {run.run_id}")
print(f"View: {DSPA_URL}/#/runs/details/{run.run_id}")
PYTHON_SCRIPT

if [ $? -eq 0 ]; then
    log_success "Eval pipeline launched (run_id=$RUN_ID)"
else
    log_error "Eval pipeline launch failed"
    exit 1
fi
