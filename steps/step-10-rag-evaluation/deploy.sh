#!/bin/bash
# Step 10: RAG Evaluation — Deploy Script
# Copies eval configs to the cluster PVC, compiles the eval pipeline,
# and launches an evaluation run against all 3 RAG scenarios.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"
PVC_NAME="rag-pipeline-workspace"
RUN_ID="eval-$(date +%s)"

source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 10: RAG Evaluation Pipeline                               ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 0: Prerequisites
# ═══════════════════════════════════════════════════════════════════════════
log_step "Checking prerequisites..."

check_oc_logged_in

if ! oc get llamastackdistribution lsd-rag -n "$NAMESPACE" &>/dev/null; then
    log_error "lsd-rag not found. Deploy step-09 first."
    exit 1
fi
log_success "lsd-rag present"

if ! oc get dspa dspa-rag -n "$NAMESPACE" &>/dev/null; then
    log_error "dspa-rag not found. Deploy step-09 first."
    exit 1
fi
log_success "dspa-rag present"

if ! oc get pvc "$PVC_NAME" -n "$NAMESPACE" &>/dev/null; then
    log_error "PVC $PVC_NAME not found. Deploy step-09 first."
    exit 1
fi
log_success "PVC $PVC_NAME present"

# Verify at least one Milvus collection has data
LSD_POD=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=llamastack-rag \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)
if [ -n "$LSD_POD" ]; then
    CHUNK_COUNT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/vector-io/query \
        -H "Content-Type: application/json" \
        -d '{"vector_db_id":"acme_corporate","query":"test"}' 2>/dev/null | \
        python3 -c "import sys,json; print(len(json.load(sys.stdin).get('chunks',[])))" 2>/dev/null || echo "0")
    if [ "$CHUNK_COUNT" -gt 0 ]; then
        log_success "Milvus has data (acme_corporate: $CHUNK_COUNT chunks)"
    else
        log_info "Milvus may be empty — eval will still run but RAG answers may be generic"
    fi
else
    log_info "Could not verify Milvus data — lsd-rag pod not found"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 1: Copy eval configs to cluster PVC
# ═══════════════════════════════════════════════════════════════════════════
log_step "Copying eval configs to cluster PVC..."

HELPER_POD="eval-config-copy-$(date +%s)"
oc run "$HELPER_POD" -n "$NAMESPACE" \
    --image=busybox --restart=Never \
    --overrides="{
      \"spec\": {
        \"containers\": [{
          \"name\": \"copy\",
          \"image\": \"busybox\",
          \"command\": [\"sleep\", \"300\"],
          \"volumeMounts\": [{
            \"name\": \"workspace\",
            \"mountPath\": \"/eval-configs\"
          }]
        }],
        \"volumes\": [{
          \"name\": \"workspace\",
          \"persistentVolumeClaim\": {
            \"claimName\": \"$PVC_NAME\"
          }
        }]
      }
    }" 2>/dev/null

log_info "  Waiting for helper pod..."
oc wait pod/"$HELPER_POD" -n "$NAMESPACE" --for=condition=Ready --timeout=60s 2>/dev/null

log_info "  Uploading eval-configs/..."
oc exec "$HELPER_POD" -n "$NAMESPACE" -- mkdir -p /eval-configs/scoring-templates 2>/dev/null

for yaml_file in "$SCRIPT_DIR"/eval-configs/*_tests.yaml; do
    [ -f "$yaml_file" ] || continue
    filename=$(basename "$yaml_file")
    oc cp "$yaml_file" "$NAMESPACE/$HELPER_POD:/eval-configs/$filename" 2>/dev/null
    log_info "    Copied $filename"
done

for txt_file in "$SCRIPT_DIR"/eval-configs/scoring-templates/*.txt; do
    [ -f "$txt_file" ] || continue
    filename=$(basename "$txt_file")
    oc cp "$txt_file" "$NAMESPACE/$HELPER_POD:/eval-configs/scoring-templates/$filename" 2>/dev/null
    log_info "    Copied scoring-templates/$filename"
done

oc delete pod "$HELPER_POD" -n "$NAMESPACE" --wait=false 2>/dev/null
log_success "Eval configs uploaded to PVC"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 2: Compile eval pipeline
# ═══════════════════════════════════════════════════════════════════════════
log_step "Compiling eval pipeline..."

VENV_PATH="$REPO_ROOT/.venv-kfp"
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH"
fi
"$VENV_PATH/bin/pip" install -q --upgrade pip
"$VENV_PATH/bin/pip" install -q kfp

mkdir -p "$REPO_ROOT/artifacts"
(cd "$SCRIPT_DIR/kfp" && "$VENV_PATH/bin/python3" eval_pipeline.py)

if [ -f "$REPO_ROOT/artifacts/rag-eval.yaml" ]; then
    log_success "Pipeline compiled: artifacts/rag-eval.yaml"
else
    log_error "Pipeline compilation failed"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: Upload and run pipeline
# ═══════════════════════════════════════════════════════════════════════════
log_step "Launching eval pipeline run (run_id=$RUN_ID)..."

if [ -f "$SCRIPT_DIR/run-eval.sh" ]; then
    chmod +x "$SCRIPT_DIR/run-eval.sh"
    "$SCRIPT_DIR/run-eval.sh" "$RUN_ID" || log_error "Pipeline launch failed — try manually via RHOAI Dashboard"
else
    log_info "run-eval.sh not found — upload pipeline manually via RHOAI Dashboard"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 4: Show results location
# ═══════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 10 evaluation launched!                                   ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                 ║"
echo "║  Monitor:                                                       ║"
echo "║    oc get pods -n $NAMESPACE -l pipeline/runid              ║"
echo "║                                                                 ║"
echo "║  Reports will be at:                                            ║"
echo "║    s3://pipelines/eval-results/$RUN_ID/                    ║"
echo "║                                                                 ║"
echo "║  Validate:                                                      ║"
echo "║    ./steps/step-10-rag-evaluation/validate.sh                  ║"
echo "║                                                                 ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
