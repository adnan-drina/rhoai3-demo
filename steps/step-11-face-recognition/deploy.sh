#!/bin/bash
# =============================================================================
# Step 11: Face Recognition with YOLO11 + OpenVINO
# =============================================================================
# Deploys a YOLO11 face recognition model (ONNX) on KServe RawDeployment
# using the OpenVINO Model Server runtime. CPU-only — no GPU required.
#
# Components:
#   1. kserve-ovms ServingRuntime (OpenVINO Model Server)
#   2. face-recognition InferenceService (ONNX, CPU-only)
#   3. Model upload job (YOLO11n-face ONNX from HuggingFace -> MinIO)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-11-face-recognition"
NAMESPACE="private-ai"

load_env
check_oc_logged_in

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 11: Face Recognition (YOLO11 + OpenVINO)                      ║"
echo "║  Predictive AI — CPU-Only Model Serving                             ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Pre-flight Checks
# =============================================================================
log_step "Checking prerequisites..."

if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    log_error "'private-ai' namespace does not exist. Run Step-03 first."
    exit 1
fi
log_success "Namespace '$NAMESPACE' exists"

if ! oc get deployment minio -n minio-storage &>/dev/null; then
    log_error "MinIO not found. Run Step-03 first."
    exit 1
fi
log_success "MinIO storage available"

if ! oc get secret minio-connection -n "$NAMESPACE" &>/dev/null; then
    log_error "minio-connection secret not found. Run Step-03 first."
    exit 1
fi
log_success "minio-connection secret exists"

# Verify kserve-ovms template is available on the platform
if oc get template kserve-ovms -n redhat-ods-applications &>/dev/null; then
    log_success "kserve-ovms template found on platform"
    OVMS_IMAGE=$(oc process -n redhat-ods-applications kserve-ovms -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || echo "")
    if [[ -n "$OVMS_IMAGE" ]]; then
        log_info "Platform OVMS image: ${OVMS_IMAGE}"
    fi
else
    log_warn "kserve-ovms template not found — using GitOps ServingRuntime with placeholder image"
    log_warn "Update the image digest in gitops/step-11-face-recognition/base/serving-runtime/kserve-ovms.yaml"
fi
echo ""

# =============================================================================
# Create HF token secret (workbench uses this for faster HF downloads)
# =============================================================================
if [[ -n "${HF_TOKEN:-}" ]]; then
    log_step "Ensuring HuggingFace token secret exists..."
    oc create secret generic hf-token -n "$NAMESPACE" \
        --from-literal=token="$HF_TOKEN" \
        --dry-run=client -o yaml | oc apply -f - 2>/dev/null
    log_success "hf-token secret ready in $NAMESPACE"
    echo ""
fi

# =============================================================================
# Upload YOLO11n-face ONNX model to MinIO
# =============================================================================
log_step "Ensuring face recognition model is in MinIO..."

UPLOAD_YAML="$REPO_ROOT/gitops/step-11-face-recognition/base/model-upload/upload-face-model.yaml"
UPLOAD_NS="minio-storage"

EXISTING=$(oc get job upload-face-model -n "$UPLOAD_NS" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "")
if [[ "$EXISTING" == "1" ]]; then
    log_success "Upload job already completed — model in MinIO"
else
    oc delete job upload-face-model -n "$UPLOAD_NS" 2>/dev/null || true
    oc apply -f "$UPLOAD_YAML"
    log_info "Upload job started — waiting for completion (~1-2 min for ~11MB model)..."
    TIMEOUT=300
    ELAPSED=0
    while [[ $ELAPSED -lt $TIMEOUT ]]; do
        STATUS=$(oc get job upload-face-model -n "$UPLOAD_NS" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "")
        if [[ "$STATUS" == "1" ]]; then
            log_success "Model upload completed"
            break
        fi
        FAILED=$(oc get job upload-face-model -n "$UPLOAD_NS" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
        if [[ "${FAILED:-0}" -ge 3 ]]; then
            log_error "Upload job failed — check: oc logs job/upload-face-model -n $UPLOAD_NS"
            break
        fi
        sleep 10
        ELAPSED=$((ELAPSED + 10))
        if (( ELAPSED % 60 == 0 )); then
            log_info "  Upload in progress... (${ELAPSED}s elapsed)"
        fi
    done
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        log_error "Upload job did not complete within ${TIMEOUT}s"
        exit 1
    fi
fi
echo ""

# =============================================================================
# Deploy via ArgoCD
# =============================================================================
log_step "Creating ArgoCD Application for Step 11..."

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"
log_success "ArgoCD Application '${STEP_NAME}' created"
echo ""

# =============================================================================
# Upload notebook assets to workbench (if available locally)
# =============================================================================
NOTEBOOKS_DIR="$SCRIPT_DIR/notebooks"
if [[ -d "$NOTEBOOKS_DIR/images" || -d "$NOTEBOOKS_DIR/my_photos" ]]; then
    log_step "Uploading notebook assets to workbench..."
    "$SCRIPT_DIR/upload-to-workbench.sh"
else
    log_info "No local notebook assets found — skip upload"
    log_info "Upload images/, videos/, my_photos/ to the workbench manually"
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
echo "  Watch model status:"
echo "    oc get inferenceservice face-recognition -n $NAMESPACE -w"
echo ""
echo "  Test model readiness:"
echo "    oc exec -n $NAMESPACE deploy/face-recognition-predictor -- \\"
echo "      curl -s localhost:8888/v2/models/face-recognition/ready"
echo ""
echo "  Workbench:"
echo "    Open JupyterLab from RHOAI Dashboard → private-ai → face-recognition-wb"
echo "    Or upload assets manually: ./steps/step-11-face-recognition/upload-to-workbench.sh"
echo ""
log_info "Validate: ./steps/step-11-face-recognition/validate.sh"
echo ""
