#!/bin/bash
# Step 08: RAG Evaluation — Deploy Script
# 1. Applies ArgoCD Application (deploys ConfigMaps + sync Job)
# 2. Compiles the eval pipeline
# 3. Launches an evaluation run against all 3 RAG scenarios (pre + post RAG)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STEP_NAME="step-08-model-evaluation"
NAMESPACE="private-ai"
PVC_NAME="rag-pipeline-workspace"
RUN_ID="eval-$(date +%s)"

source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 08: RAG Evaluation Pipeline                               ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 0: Prerequisites (step-07 must be deployed)
# ═══════════════════════════════════════════════════════════════════════════
log_step "Checking prerequisites..."

check_oc_logged_in

if ! oc get llamastackdistribution lsd-rag -n "$NAMESPACE" &>/dev/null; then
    log_error "lsd-rag not found. Deploy step-07 first."
    exit 1
fi
log_success "lsd-rag present"

if ! oc get dspa dspa-rag -n "$NAMESPACE" &>/dev/null; then
    log_error "dspa-rag not found. Deploy step-07 first."
    exit 1
fi
log_success "dspa-rag present"

if ! oc get pvc "$PVC_NAME" -n "$NAMESPACE" &>/dev/null; then
    log_error "PVC $PVC_NAME not found. Deploy step-07 first."
    exit 1
fi
log_success "PVC $PVC_NAME present"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 1: Deploy via ArgoCD
# ═══════════════════════════════════════════════════════════════════════════
log_step "Deploying Step 08 via ArgoCD..."

ARGOCD_APP="$REPO_ROOT/gitops/argocd/app-of-apps/$STEP_NAME.yaml"
if [ ! -f "$ARGOCD_APP" ]; then
    log_error "ArgoCD Application not found: $ARGOCD_APP"
    exit 1
fi

oc apply -f "$ARGOCD_APP"
log_success "ArgoCD Application applied: $STEP_NAME"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 2: Wait for ArgoCD sync (ConfigMaps + PostSync Job)
# ═══════════════════════════════════════════════════════════════════════════
log_step "Waiting for ArgoCD sync..."
sleep 5

TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    SYNC_STATUS=$(oc get application "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(oc get application "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
        log_success "ArgoCD sync complete: $SYNC_STATUS / $HEALTH"
        break
    fi

    log_info "  Status: $SYNC_STATUS / $HEALTH (${ELAPSED}s / ${TIMEOUT}s)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ "$SYNC_STATUS" != "Synced" ]; then
    log_info "ArgoCD not fully synced yet — continuing (eval configs may sync in background)"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: Verify eval configs on PVC (from PostSync Job or manual fallback)
# ═══════════════════════════════════════════════════════════════════════════
log_step "Verifying eval configs on PVC..."

# Check if the PostSync Job already copied the configs
LSD_POD=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=llamastack-rag \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)

CONFIG_COUNT=0
if [ -n "$LSD_POD" ]; then
    CONFIG_COUNT=$(oc exec -n "$NAMESPACE" deploy/rag-wb -- ls /opt/app-root/src/ 2>/dev/null | grep -c "_tests.yaml" || echo "0")
fi

if [ "$CONFIG_COUNT" -lt 2 ]; then
    log_info "Eval configs not yet on PVC — copying manually..."

    HELPER_POD="eval-cfg-copy-$(date +%s)"
    oc run "$HELPER_POD" -n "$NAMESPACE" \
        --image=busybox --restart=Never \
        --overrides="{
          \"spec\": {
            \"containers\": [{
              \"name\": \"copy\",
              \"image\": \"busybox\",
              \"command\": [\"sleep\", \"120\"],
              \"volumeMounts\": [{
                \"name\": \"workspace\",
                \"mountPath\": \"/workspace\"
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

    oc wait pod/"$HELPER_POD" -n "$NAMESPACE" --for=condition=Ready --timeout=60s 2>/dev/null
    oc exec "$HELPER_POD" -n "$NAMESPACE" -- mkdir -p /workspace/eval-configs/scoring-templates 2>/dev/null

    for yaml_file in "$SCRIPT_DIR"/eval-configs/*_tests.yaml; do
        [ -f "$yaml_file" ] || continue
        filename=$(basename "$yaml_file")
        oc cp "$yaml_file" "$NAMESPACE/$HELPER_POD:/workspace/eval-configs/$filename" 2>/dev/null
        log_info "    Copied $filename"
    done

    for txt_file in "$SCRIPT_DIR"/eval-configs/scoring-templates/*.txt; do
        [ -f "$txt_file" ] || continue
        filename=$(basename "$txt_file")
        oc cp "$txt_file" "$NAMESPACE/$HELPER_POD:/workspace/eval-configs/scoring-templates/$filename" 2>/dev/null
        log_info "    Copied scoring-templates/$filename"
    done

    oc delete pod "$HELPER_POD" -n "$NAMESPACE" --wait=false 2>/dev/null
    log_success "Eval configs copied to PVC"
else
    log_success "Eval configs already on PVC ($CONFIG_COUNT test files)"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 4: Compile eval pipeline
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
# Step 5: Upload and run pipeline
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
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 08 evaluation launched!                                   ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                 ║"
echo "║  Monitor:                                                       ║"
echo "║    oc get pods -n $NAMESPACE -l pipeline/runid              ║"
echo "║                                                                 ║"
echo "║  Reports will be at:                                            ║"
echo "║    s3://pipelines/eval-results/$RUN_ID/                    ║"
echo "║                                                                 ║"
echo "║  Validate:                                                      ║"
echo "║    ./steps/step-08-model-evaluation/validate.sh                 ║"
echo "║                                                                 ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
