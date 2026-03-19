#!/bin/bash
# Step 08: Model Evaluation — Deploy Script
# 1. Applies ArgoCD Application (deploys ConfigMaps + PostSync Job for eval configs)
# 2. Compiles the RAG eval pipeline
# 3. Launches an evaluation run against all scenarios (pre + post RAG)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STEP_NAME="step-08-model-evaluation"
NAMESPACE="private-ai"
RUN_ID="eval-$(date +%s)"

source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 08: Model Evaluation                                     ║"
echo "║  RAG Evaluation (KFP) + Standard Benchmarks (LM-Eval)          ║"
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

if ! oc get pvc rag-pipeline-workspace -n "$NAMESPACE" &>/dev/null; then
    log_error "PVC rag-pipeline-workspace not found. Deploy step-07 first."
    exit 1
fi
log_success "PVC rag-pipeline-workspace present"
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
# Step 2: Wait for ArgoCD sync (ConfigMaps + PostSync Job copies configs)
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
    log_warn "ArgoCD not fully synced ($SYNC_STATUS) — continuing, but eval configs may not be ready"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: Compile RAG eval pipeline
# ═══════════════════════════════════════════════════════════════════════════
log_step "Compiling RAG eval pipeline..."

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
# Step 4: Upload and run RAG eval pipeline
# ═══════════════════════════════════════════════════════════════════════════
log_step "Launching RAG eval pipeline (run_id=$RUN_ID)..."

if [ -f "$SCRIPT_DIR/run-rag-eval.sh" ]; then
    chmod +x "$SCRIPT_DIR/run-rag-eval.sh"
    "$SCRIPT_DIR/run-rag-eval.sh" "$RUN_ID" || log_error "Pipeline launch failed — try manually via RHOAI Dashboard"
else
    log_info "run-rag-eval.sh not found — upload pipeline manually via RHOAI Dashboard"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 08 deployed!                                             ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                ║"
echo "║  RAG Evaluation (automated):                                   ║"
echo "║    Reports: s3://rhoai-storage/eval-results/$RUN_ID/      ║"
echo "║    Monitor: oc get pods -n $NAMESPACE -l pipeline/runid   ║"
echo "║    Rerun:   ./run-rag-eval.sh                                  ║"
echo "║    Quick:   ./run-eval-report.sh                               ║"
echo "║                                                                ║"
echo "║  Standard Benchmarks (on-demand):                              ║"
echo "║    CLI:     ./run-lmeval.sh qwen3-8b-agent                   ║"
echo "║    CLI:     ./run-lmeval.sh mistral-3-bf16                     ║"
echo "║    Dashboard: Develop & train > Evaluations                    ║"
echo "║                                                                ║"
echo "║  Validate:                                                     ║"
echo "║    ./steps/step-08-model-evaluation/validate.sh                ║"
echo "║                                                                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
