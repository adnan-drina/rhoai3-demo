#!/bin/bash
# =============================================================================
# Step 13: Edge AI — Face Recognition at the Edge
# =============================================================================
# Deploys a simulated edge environment with:
#   1. OpenVINO Model Server serving the same face recognition model as step-11
#   2. Streamlit camera app for phone-based inference
#
# Prerequisites:
#   - Steps 01-03 deployed (RHOAI, MinIO, storage)
#   - Step 11 deployed (face recognition model in MinIO)
#   - Edge camera container image built and pushed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-13-edge-ai"
NAMESPACE="edge-ai-demo"
CONTAINER_IMAGE="${EDGE_CAMERA_IMAGE:-quay.io/adrina/edge-camera:latest}"

load_env
check_oc_logged_in

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 13: Edge AI — Face Recognition at the Edge                    ║"
echo "║  Streamlit Camera App + OpenVINO Inference (CPU-Only)              ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Pre-flight Checks
# =============================================================================
log_step "Checking prerequisites..."

if ! oc get deployment minio -n minio-storage &>/dev/null; then
    log_error "MinIO not found. Run Step-03 first."
    exit 1
fi
log_success "MinIO storage available"

MODEL_EXISTS=$(oc exec -n minio-storage deploy/minio -- \
    mc ls local/models/face-recognition/1/model.onnx 2>/dev/null || echo "")
if [[ -z "$MODEL_EXISTS" ]]; then
    log_warn "Face recognition model not found in MinIO."
    log_warn "Run Step-11 deploy.sh first to upload the model."
    log_warn "Continuing anyway — the InferenceService will wait for the model."
fi
log_success "Pre-flight checks passed"
echo ""

# =============================================================================
# Build container image (optional — skip if image already exists)
# =============================================================================
log_step "Checking edge-camera container image..."

if command -v podman &>/dev/null; then
    BUILD_TOOL="podman"
elif command -v docker &>/dev/null; then
    BUILD_TOOL="docker"
else
    BUILD_TOOL=""
fi

if [[ "${BUILD_EDGE_CAMERA:-false}" == "true" && -n "$BUILD_TOOL" ]]; then
    log_info "Building edge-camera image with $BUILD_TOOL..."
    $BUILD_TOOL build \
        -t "$CONTAINER_IMAGE" \
        -f "$SCRIPT_DIR/app/Containerfile" \
        "$SCRIPT_DIR/app/"
    log_info "Pushing $CONTAINER_IMAGE..."
    $BUILD_TOOL push "$CONTAINER_IMAGE"
    log_success "Image built and pushed: $CONTAINER_IMAGE"
else
    log_info "Using pre-built image: $CONTAINER_IMAGE"
    log_info "Set BUILD_EDGE_CAMERA=true to build locally"
fi
echo ""

# =============================================================================
# Deploy via ArgoCD
# =============================================================================
log_step "Creating ArgoCD Application for Step 13..."

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"
log_success "ArgoCD Application '${STEP_NAME}' created"
echo ""

# =============================================================================
# Wait for edge InferenceService
# =============================================================================
log_step "Waiting for edge InferenceService to become Ready..."

TIMEOUT=300
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    READY=$(oc get inferenceservice face-recognition-edge -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$READY" == "True" ]]; then
        log_success "face-recognition-edge InferenceService is Ready"
        break
    fi
    if (( ELAPSED % 30 == 0 )); then
        log_info "  Waiting for model server... (${ELAPSED}s elapsed)"
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done
if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log_warn "InferenceService not Ready within ${TIMEOUT}s — check:"
    log_warn "  oc get inferenceservice face-recognition-edge -n $NAMESPACE"
    log_warn "  oc logs deploy/face-recognition-edge-predictor -n $NAMESPACE"
fi
echo ""

# =============================================================================
# Wait for Streamlit app
# =============================================================================
log_step "Waiting for edge-camera Deployment to be ready..."

ELAPSED=0
while [[ $ELAPSED -lt 120 ]]; do
    READY=$(oc get deployment edge-camera -n "$NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "${READY:-0}" -ge 1 ]]; then
        log_success "edge-camera: $READY replica(s) ready"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
if [[ $ELAPSED -ge 120 ]]; then
    log_warn "edge-camera not ready within 120s — check:"
    log_warn "  oc get pods -n $NAMESPACE -l app.kubernetes.io/name=edge-camera"
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

ROUTE_HOST=$(oc get route edge-camera -n "$NAMESPACE" \
    -o jsonpath='{.spec.host}' 2>/dev/null || echo "unknown")

echo ""
echo "  Edge Camera App:"
echo "    https://$ROUTE_HOST"
echo "    (open this URL on your phone for camera access)"
echo ""
echo "  Edge Model Server:"
echo "    oc get inferenceservice face-recognition-edge -n $NAMESPACE"
echo ""
echo "  Test model readiness:"
echo "    oc exec -n $NAMESPACE deploy/face-recognition-edge-predictor -- \\"
echo "      curl -s localhost:8888/v2/models/face-recognition-edge/ready"
echo ""
log_info "Validate: ./steps/step-13-edge-ai/validate.sh"
echo ""
