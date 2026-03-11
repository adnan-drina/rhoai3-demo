#!/bin/bash
# Step 09: RAG Pipeline — Deploy Script
# Deploys Milvus, Docling, DSPA, LlamaStack (RAG), uploads documents,
# compiles pipeline, and launches ingestion for all 3 scenarios.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"
STEP_NAME="step-08-rag-pipeline"

source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 09: RAG Pipeline (Llama Stack + Milvus + Docling + DSPA) ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 0: Prerequisites
# ═══════════════════════════════════════════════════════════════════════════
log_step "Checking prerequisites..."

check_oc_logged_in

if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    log_error "Namespace $NAMESPACE not found. Deploy step-03 first."
    exit 1
fi
log_success "Namespace $NAMESPACE exists"

if ! oc get crd llamastackdistributions.llamastack.io &>/dev/null; then
    log_error "LlamaStackDistribution CRD not found. Is RHOAI 3.3 installed (step-02)?"
    exit 1
fi
log_success "LlamaStackDistribution CRD available"

if ! oc get crd datasciencepipelinesapplications.datasciencepipelinesapplications.opendatahub.io &>/dev/null; then
    log_error "DSPA CRD not found. Ensure aipipelines is Managed in DataScienceCluster."
    exit 1
fi
log_success "DSPA CRD available"

if ! oc get inferenceservice granite-8b-agent -n "$NAMESPACE" &>/dev/null; then
    log_error "granite-8b-agent InferenceService not found. Deploy step-05 first."
    exit 1
fi
log_success "granite-8b-agent InferenceService present"

if ! oc get secret minio-connection -n "$NAMESPACE" &>/dev/null; then
    log_error "minio-connection secret not found in $NAMESPACE. Deploy step-03 first."
    exit 1
fi
log_success "minio-connection secret present"

PIPELINES_STATE=$(oc get datasciencecluster default-dsc \
    -o jsonpath='{.spec.components.aipipelines.managementState}' 2>/dev/null || echo "Unknown")
if [ "$PIPELINES_STATE" != "Managed" ]; then
    log_error "aipipelines managementState is '$PIPELINES_STATE' (expected 'Managed')."
    exit 1
fi
log_success "aipipelines: Managed"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 1: Create DSPA MinIO credentials secret
# ═══════════════════════════════════════════════════════════════════════════
log_step "Creating DSPA MinIO credentials secret..."

ACCESS_KEY=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
SECRET_KEY=$(oc get secret minio-connection -n "$NAMESPACE" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

oc create secret generic dspa-minio-credentials \
    -n "$NAMESPACE" \
    --from-literal=accesskey="$ACCESS_KEY" \
    --from-literal=secretkey="$SECRET_KEY" \
    --dry-run=client -o yaml | oc apply -f -

log_success "dspa-minio-credentials secret ready"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 2: Deploy via ArgoCD
# ═══════════════════════════════════════════════════════════════════════════
log_step "Deploying Step 09 via ArgoCD..."

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/$STEP_NAME.yaml"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: Wait for ArgoCD sync
# ═══════════════════════════════════════════════════════════════════════════
log_step "Waiting for ArgoCD sync..."
sleep 5

TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    SYNC=$(oc get application "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(oc get application "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    log_info "  Sync: $SYNC | Health: $HEALTH"

    if [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    log_error "Timeout waiting for ArgoCD sync. Check:"
    log_error "  oc get application $STEP_NAME -n openshift-gitops"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 4: Wait for components
# ═══════════════════════════════════════════════════════════════════════════
log_step "Waiting for Milvus..."
oc wait deploy/milvus-standalone -n "$NAMESPACE" \
    --for=condition=Available --timeout=180s 2>/dev/null || \
    log_error "Milvus did not become available in 180s"

log_step "Waiting for Docling..."
oc wait deploy/docling-service -n "$NAMESPACE" \
    --for=condition=Available --timeout=600s 2>/dev/null || \
    log_error "Docling did not become available (first start can take ~10min)"

log_step "Waiting for LlamaStack RAG..."
oc wait llamastackdistribution/lsd-rag -n "$NAMESPACE" \
    --for=jsonpath='{.status.phase}'=Ready --timeout=300s 2>/dev/null || \
    log_error "LlamaStack lsd-rag did not reach Ready state"

log_step "Waiting for DSPA..."
DSPA_READY=false
for i in $(seq 1 30); do
    STATUS=$(oc get dspa dspa-rag -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
    if [ "$STATUS" = "Ready" ]; then
        DSPA_READY=true
        break
    fi
    sleep 10
done
if [ "$DSPA_READY" = "true" ]; then
    log_success "DSPA dspa-rag is Ready"
else
    log_error "DSPA did not reach Ready state"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 4b: Restart GenAI Playground to connect to remote Milvus
# ═══════════════════════════════════════════════════════════════════════════
# Step-06's lsd-genai-playground is configured to use remote::milvus
# (same Milvus deployed by step-09). A restart ensures it connects now
# that Milvus is available. This enables RAG queries from the Playground UI.
log_step "Restarting GenAI Playground to connect to Milvus..."
if oc get llamastackdistribution lsd-genai-playground -n "$NAMESPACE" &>/dev/null; then
    oc rollout restart deployment/lsd-genai-playground -n "$NAMESPACE" 2>/dev/null || true
    log_success "lsd-genai-playground restart triggered"
    log_info "  Playground will reconnect to remote Milvus on startup"
else
    log_info "  lsd-genai-playground not found (step-06 not deployed) — skipping"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 5: Upload scenario PDFs to MinIO
# ═══════════════════════════════════════════════════════════════════════════
log_step "Uploading scenario documents to MinIO..."

if [ -f "$SCRIPT_DIR/upload-to-minio.sh" ]; then
    chmod +x "$SCRIPT_DIR/upload-to-minio.sh"

    for scenario_dir in "$SCRIPT_DIR"/scenario-docs/*/; do
        [ -d "$scenario_dir" ] || continue
        scenario=$(basename "$scenario_dir")
        pdf_count=$(find "$scenario_dir" -name "*.pdf" 2>/dev/null | wc -l | tr -d ' ')

        if [ "$pdf_count" -eq 0 ]; then
            log_info "  No PDFs in $scenario (placeholder directory)"
            continue
        fi

        log_info "  Uploading $pdf_count PDF(s) for $scenario..."
        for pdf in "$scenario_dir"*.pdf; do
            [ -f "$pdf" ] || continue
            filename=$(basename "$pdf")
            "$SCRIPT_DIR/upload-to-minio.sh" "$pdf" "rag-documents/$scenario/$filename" || \
                log_error "  Failed to upload $filename"
        done
    done
else
    log_info "  upload-to-minio.sh not found — upload documents manually"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 6: Compile KFP pipeline
# ═══════════════════════════════════════════════════════════════════════════
log_step "Compiling KFP pipeline..."

VENV_PATH="$REPO_ROOT/.venv-kfp"
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH"
fi
"$VENV_PATH/bin/pip" install -q --upgrade pip
"$VENV_PATH/bin/pip" install -q kfp

mkdir -p "$REPO_ROOT/artifacts"
(cd "$SCRIPT_DIR/kfp" && "$VENV_PATH/bin/python3" pipeline.py)

if [ -f "$REPO_ROOT/artifacts/rag-ingestion-batch.yaml" ]; then
    log_success "Pipeline compiled: artifacts/rag-ingestion-batch.yaml"
else
    log_error "Pipeline compilation failed"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 7: Launch batch ingestion (if run-batch-ingestion.sh exists)
# ═══════════════════════════════════════════════════════════════════════════
log_step "Launching batch ingestion pipelines..."

if [ -f "$SCRIPT_DIR/run-batch-ingestion.sh" ]; then
    chmod +x "$SCRIPT_DIR/run-batch-ingestion.sh"
    for scenario in redhat acme eu-ai-act; do
        log_info "  Launching: $scenario"
        "$SCRIPT_DIR/run-batch-ingestion.sh" "$scenario" || \
            log_error "  Pipeline launch failed for $scenario (may need manual retry)"
        sleep 2
    done
else
    log_info "  run-batch-ingestion.sh not found — launch pipelines via RHOAI Dashboard"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 8: Validation output
# ═══════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 09 deployment initiated!                                  ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                 ║"
echo "║  Monitor progress:                                              ║"
echo "║    oc get deploy milvus-standalone -n $NAMESPACE                ║"
echo "║    oc get dspa dspa-rag -n $NAMESPACE                          ║"
echo "║    oc get llamastackdistribution lsd-rag -n $NAMESPACE         ║"
echo "║                                                                 ║"
echo "║  Validate RAG:                                                  ║"
echo "║    ./steps/step-08-rag-pipeline/validate.sh                    ║"
echo "║                                                                 ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
