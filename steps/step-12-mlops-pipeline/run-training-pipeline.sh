#!/bin/bash
# Launch the face recognition training pipeline.
# Usage: ./run-training-pipeline.sh [--version VERSION] [--epochs N] [--threshold F]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"

source "$REPO_ROOT/scripts/lib.sh"
load_env

# Parse arguments
VERSION="$(date +%Y%m%d-%H%M%S)"
EPOCHS=15
THRESHOLD=0.7
for arg in "$@"; do
    case "$arg" in
        --version=*) VERSION="${arg#*=}" ;;
        --epochs=*) EPOCHS="${arg#*=}" ;;
        --threshold=*) THRESHOLD="${arg#*=}" ;;
    esac
done

check_oc_logged_in

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Face Recognition Training Pipeline                                  ║"
echo "║  Version: $VERSION   Epochs: $EPOCHS   Threshold: $THRESHOLD                   ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Compile pipeline if needed
# =============================================================================
PIPELINE_YAML="$REPO_ROOT/artifacts/face-recognition-training.yaml"
VENV_PATH="$REPO_ROOT/.venv-kfp"

if [ ! -d "$VENV_PATH" ]; then
    log_info "Creating KFP venv..."
    python3 -m venv "$VENV_PATH"
    "$VENV_PATH/bin/pip" install -q --upgrade pip kfp kfp-kubernetes
fi

if [ ! -f "$PIPELINE_YAML" ]; then
    log_step "Compiling pipeline..."
    mkdir -p "$REPO_ROOT/artifacts"
    (cd "$SCRIPT_DIR/kfp" && "$VENV_PATH/bin/python3" pipeline.py)
    mv "$SCRIPT_DIR/kfp/face-recognition-training.yaml" "$PIPELINE_YAML"
    log_success "Compiled: $PIPELINE_YAML"
fi
echo ""

# =============================================================================
# Get cluster info
# =============================================================================
OC_TOKEN=$(oc whoami -t 2>/dev/null || true)
if [ -z "$OC_TOKEN" ]; then
    log_error "Unable to obtain oc token. Run 'oc login' first."
    exit 1
fi

DSPA_ROUTE=$(oc get route ds-pipeline-dspa-rag -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -z "$DSPA_ROUTE" ]; then
    log_error "DSPA route not found. Ensure Step-07 is deployed."
    exit 1
fi
DSPA_URL="https://$DSPA_ROUTE"

REGISTRY_ROUTE=$(oc get route private-ai-registry-https -n rhoai-model-registries -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
REGISTRY_URL="https://$REGISTRY_ROUTE"

CLUSTER_DOMAIN=$(echo "$DSPA_ROUTE" | sed 's/.*\.apps\./apps./')

log_info "DSPA: $DSPA_URL"
log_info "Registry: $REGISTRY_URL"
echo ""

# =============================================================================
# Upload and run pipeline
# =============================================================================
log_step "Submitting pipeline run..."

export NAMESPACE VERSION EPOCHS THRESHOLD PIPELINE_YAML DSPA_URL REGISTRY_URL OC_TOKEN

"$VENV_PATH/bin/python3" << 'PYTHON_SCRIPT'
import os, sys
from kfp import client

NAMESPACE = os.environ["NAMESPACE"]
VERSION = os.environ["VERSION"]
EPOCHS = int(os.environ["EPOCHS"])
THRESHOLD = float(os.environ["THRESHOLD"])
PIPELINE_YAML = os.environ["PIPELINE_YAML"]
DSPA_URL = os.environ["DSPA_URL"]
REGISTRY_URL = os.environ["REGISTRY_URL"]
AUTH_TOKEN = os.environ["OC_TOKEN"]

PIPELINE_NAME = "face-recognition-training"
EXPERIMENT_NAME = "face-recognition"

try:
    kfp_client = client.Client(
        host=DSPA_URL,
        namespace=NAMESPACE,
        existing_token=AUTH_TOKEN,
    )
except Exception as e:
    print(f"KFP client init failed: {e}")
    sys.exit(1)

# Upload or reuse pipeline
try:
    pipeline = kfp_client.upload_pipeline(
        pipeline_package_path=PIPELINE_YAML,
        pipeline_name=PIPELINE_NAME,
    )
    pipeline_id = pipeline.pipeline_id
    print(f"Pipeline uploaded: {pipeline_id}")
except Exception:
    filter_json = '{"predicates":[{"key":"name","operation":"EQUALS","stringValue":"' + PIPELINE_NAME + '"}]}'
    pipelines = kfp_client.list_pipelines(filter=filter_json)
    if pipelines.pipelines:
        pipeline_id = pipelines.pipelines[0].pipeline_id
        print(f"Pipeline exists: {pipeline_id}")
    else:
        print("Could not find or upload pipeline")
        sys.exit(1)

# Upload new version
try:
    pv = kfp_client.upload_pipeline_version(
        pipeline_package_path=PIPELINE_YAML,
        pipeline_version_name=f"v-{VERSION}",
        pipeline_id=pipeline_id,
    )
    version_id = pv.pipeline_version_id
    print(f"Version uploaded: v-{VERSION} ({version_id})")
except Exception as e:
    print(f"Version upload: {e}")
    versions = kfp_client.list_pipeline_versions(pipeline_id=pipeline_id, sort_by="created_at desc")
    version_id = versions.pipeline_versions[0].pipeline_version_id

# Create or reuse experiment
try:
    exp = kfp_client.create_experiment(name=EXPERIMENT_NAME, namespace=NAMESPACE)
except Exception:
    exps = kfp_client.list_experiments(namespace=NAMESPACE)
    exp = next(e for e in exps.experiments if e.display_name == EXPERIMENT_NAME)

# Create run
run = kfp_client.run_pipeline(
    experiment_id=exp.experiment_id,
    job_name=f"train-{VERSION}",
    pipeline_id=pipeline_id,
    version_id=version_id,
    params={
        "photos_s3_prefix": "s3://face-training-photos/adnan/",
        "model_name": "face-recognition",
        "version": VERSION,
        "epochs": EPOCHS,
        "mAP_threshold": THRESHOLD,
        "minio_endpoint": "http://minio.minio-storage.svc.cluster.local:9000",
        "registry_url": REGISTRY_URL,
        "isvc_namespace": NAMESPACE,
    },
)

print(f"\nPipeline run created: {run.run_id}")
print(f"  Name: train-{VERSION}")
print(f"  Monitor: RHOAI Dashboard → Data Science Projects → private-ai → Pipelines")
PYTHON_SCRIPT
