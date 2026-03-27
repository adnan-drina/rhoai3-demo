#!/bin/bash
# Step 12: MLOps Training Pipeline — full deploy + pipeline execution
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-12-mlops-pipeline"
NAMESPACE="private-ai"

load_env
check_oc_logged_in

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 12: MLOps Training Pipeline                                    ║"
echo "║  KFP v2: Train → Evaluate → Register → Deploy → Monitor             ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

log_step "Checking prerequisites..."

if ! oc get dspa dspa-rag -n "$NAMESPACE" &>/dev/null; then
    log_error "DSPA 'dspa-rag' not found. Run Step-07 first."
    exit 1
fi
log_success "DSPA pipeline server available"

if ! oc get inferenceservice face-recognition -n "$NAMESPACE" &>/dev/null; then
    log_error "InferenceService 'face-recognition' not found. Run Step-11 first."
    exit 1
fi
log_success "face-recognition InferenceService exists"

REGISTRY_ROUTE=$(oc get route private-ai-registry-https -n rhoai-model-registries -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -z "$REGISTRY_ROUTE" ]]; then
    log_warn "Model Registry route not found. Run Step-04 first for full MLOps flow."
else
    log_success "Model Registry: https://$REGISTRY_ROUTE"
fi
echo ""

log_step "Creating ArgoCD Application for Step 12..."
oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"
log_success "ArgoCD Application '${STEP_NAME}' created"
echo ""

# Wait for ArgoCD sync
log_step "Waiting for ArgoCD sync..."
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    HEALTH=$(oc get application "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    if [ "$HEALTH" = "Healthy" ]; then
        log_success "ArgoCD sync complete"
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done
if [ $ELAPSED -ge $TIMEOUT ]; then
    log_warn "ArgoCD sync not complete — continuing (resources may sync in background)"
fi
echo ""

# Upload training photos to MinIO
log_step "Uploading training data to MinIO..."
if [ -f "$SCRIPT_DIR/upload-training-data.sh" ]; then
    PHOTOS_DIR="$REPO_ROOT/steps/step-11-face-recognition/notebooks/my_photos"
    if [ -d "$PHOTOS_DIR" ] && [ "$(find "$PHOTOS_DIR" -name "*.jpeg" -o -name "*.jpg" -o -name "*.png" 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
        chmod +x "$SCRIPT_DIR/upload-training-data.sh"
        "$SCRIPT_DIR/upload-training-data.sh" || log_warn "Training data upload had issues — pipeline may use existing data"
    else
        log_info "No local training photos found — pipeline will use existing data in MinIO"
    fi
else
    log_info "upload-training-data.sh not found — skip upload"
fi
echo ""

# Ensure yolo26m.pt base model is in MinIO (pipeline's prepare_dataset needs it)
log_step "Ensuring YOLO11 base model in MinIO..."
VENV_PATH="$REPO_ROOT/.venv-kfp"
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH"
fi
"$VENV_PATH/bin/pip" install -q boto3 2>/dev/null

oc port-forward -n minio-storage svc/minio 9000:9000 &>/dev/null &
PF_PID=$!
sleep 3

MINIO_ACCESS=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
MINIO_SECRET=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

"$VENV_PATH/bin/python3" -c "
import boto3, os, urllib.request
from botocore.config import Config
s3 = boto3.client('s3', endpoint_url='http://localhost:9000',
    aws_access_key_id='${MINIO_ACCESS}', aws_secret_access_key='${MINIO_SECRET}',
    config=Config(signature_version='s3v4'))
try:
    s3.head_object(Bucket='models', Key='yolo26m.pt')
    print('yolo26m.pt already in MinIO')
except:
    print('Downloading yolo26m.pt from ultralytics...')
    urllib.request.urlretrieve('https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo26m.pt', '/tmp/yolo26m.pt')
    s3.upload_file('/tmp/yolo26m.pt', 'models', 'yolo26m.pt')
    print('Uploaded to s3://models/yolo26m.pt')
" 2>/dev/null && log_success "YOLO11 base model ready in MinIO" || log_warn "Could not verify base model"

kill $PF_PID 2>/dev/null
echo ""

# Compile and launch the training pipeline
log_step "Launching training pipeline..."
if [ -f "$SCRIPT_DIR/run-training-pipeline.sh" ]; then
    chmod +x "$SCRIPT_DIR/run-training-pipeline.sh"
    "$SCRIPT_DIR/run-training-pipeline.sh" || log_warn "Pipeline launch had issues — check Dashboard"
else
    log_error "run-training-pipeline.sh not found"
fi
echo ""

# Wait for pipeline completion
log_step "Waiting for pipeline to complete (~20 min)..."
TIMEOUT=1500
ELAPSED=0
PIPELINE_DONE=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check for any running pipeline pods
    ACTIVE=$(oc get pods -n "$NAMESPACE" -l pipeline/runid --no-headers 2>/dev/null | grep -v Completed | grep -v Error | wc -l | tr -d ' ')
    if [ "$ACTIVE" -eq 0 ] && [ $ELAPSED -gt 60 ]; then
        PIPELINE_DONE=true
        break
    fi
    sleep 30
    ELAPSED=$((ELAPSED + 30))
    if (( ELAPSED % 120 == 0 )); then
        log_info "  Pipeline in progress... (${ELAPSED}s elapsed, $ACTIVE pods active)"
    fi
done
if [ "$PIPELINE_DONE" = "true" ]; then
    log_success "Training pipeline completed"
else
    log_warn "Pipeline did not complete within ${TIMEOUT}s — check Dashboard"
fi
echo ""

# Setup TrustyAI monitoring
log_step "Setting up TrustyAI monitoring..."
if [ -f "$SCRIPT_DIR/setup-trustyai-metrics.sh" ]; then
    chmod +x "$SCRIPT_DIR/setup-trustyai-metrics.sh"
    "$SCRIPT_DIR/setup-trustyai-metrics.sh" || log_warn "TrustyAI setup had issues — configure manually"
else
    log_info "setup-trustyai-metrics.sh not found — skip monitoring setup"
fi
echo ""

log_step "Deployment Complete"
echo ""
echo "  Pipeline runs: RHOAI Dashboard → Data Science Projects → private-ai → Pipelines"
echo "  Model Registry: RHOAI Dashboard → Settings → Model registries → private-ai-registry"
echo "  TrustyAI metrics: RHOAI Dashboard → Model Serving → face-recognition → Model bias"
echo ""
log_info "Validate: ./steps/step-12-mlops-pipeline/validate.sh"
echo ""
