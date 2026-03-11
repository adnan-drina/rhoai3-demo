#!/bin/bash
# Launch a batch RAG ingestion pipeline run for a given scenario.
# Usage: ./run-batch-ingestion.sh <scenario>
#   scenario: acme | eu-ai-act | whoami

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCENARIO="${1:-}"

if [ -z "$SCENARIO" ]; then
    echo -e "${RED}Error: Scenario parameter required${NC}"
    echo ""
    echo "Usage: $0 <scenario>"
    echo ""
    echo "Available scenarios:"
    echo "  acme       - ACME Corporate lithography docs (8 PDFs)"
    echo "  eu-ai-act  - EU AI Act official documents (3 PDFs)"
    echo "  whoami     - Personal CV (1 PDF)"
    echo ""
    echo "Run all: for s in acme eu-ai-act whoami; do $0 \$s; done"
    exit 1
fi

case "$SCENARIO" in
    acme)
        S3_PREFIX="s3://rag-documents/scenario2-acme/"
        VECTOR_DB_ID="acme_corporate"
        DESCRIPTION="ACME Corporate Lithography Documentation"
        ;;
    eu-ai-act)
        S3_PREFIX="s3://rag-documents/scenario3-eu-ai-act/"
        VECTOR_DB_ID="eu_ai_act"
        DESCRIPTION="EU AI Act Official Documents"
        ;;
    whoami)
        S3_PREFIX="s3://rag-documents/scenario4-whoami/"
        VECTOR_DB_ID="whoami"
        DESCRIPTION="Personal CV"
        ;;
    *)
        echo -e "${RED}Error: Invalid scenario: $SCENARIO${NC}"
        echo "Valid options: acme, eu-ai-act, whoami"
        exit 1
        ;;
esac

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE} RAG Batch Ingestion Pipeline${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}  Scenario:${NC}    $SCENARIO"
echo -e "${GREEN}  S3 Path:${NC}     $S3_PREFIX"
echo -e "${GREEN}  Collection:${NC}  $VECTOR_DB_ID"
echo -e "${GREEN}  Description:${NC} $DESCRIPTION"
echo ""

OC_TOKEN=$(oc whoami -t 2>/dev/null || true)
if [ -z "$OC_TOKEN" ]; then
    echo -e "${RED}Unable to obtain oc token. Run 'oc login' first.${NC}"
    exit 1
fi
echo -e "${GREEN}  oc token acquired${NC}"

PIPELINE_YAML="$REPO_ROOT/artifacts/rag-ingestion-batch.yaml"
if [ ! -f "$PIPELINE_YAML" ]; then
    echo "Compiling pipeline..."
    VENV_PATH="$REPO_ROOT/.venv-kfp"
    if [ ! -d "$VENV_PATH" ]; then
        python3 -m venv "$VENV_PATH"
        "$VENV_PATH/bin/pip" install -q --upgrade pip kfp
    fi
    (cd "$SCRIPT_DIR/kfp" && "$VENV_PATH/bin/python3" pipeline.py)
fi

echo "Launching pipeline run via KFP client..."

VENV_PATH="$REPO_ROOT/.venv-kfp"
export S3_PREFIX VECTOR_DB_ID SCENARIO NAMESPACE

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

experiment_name = f"rag-ingestion-{SCENARIO}"
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
    "s3_prefix": S3_PREFIX,
    "vector_db_id": VECTOR_DB_ID,
    "cache_buster": str(int(time.time())),
}

run_name = f"{SCENARIO}-ingestion-{int(time.time())}"
run = kfp_client.run_pipeline(
    experiment_id=experiment_id,
    job_name=run_name,
    pipeline_id=pipeline_id,
    params=params,
    enable_caching=False,
)
print(f"Run created: {run.run_id}")
print(f"View: {DSPA_URL}/#/runs/details/{run.run_id}")
PYTHON_SCRIPT

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}Pipeline launched for scenario: $SCENARIO${NC}"
else
    echo ""
    echo -e "${RED}Pipeline launch failed for $SCENARIO${NC}"
    exit 1
fi
