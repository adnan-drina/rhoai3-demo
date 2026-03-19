#!/bin/bash
# Trigger a standard LM-Eval benchmark run for a deployed model.
# Uses RHOAI 3.3 LMEvalJob CR (TrustyAI operator).
#
# Usage:
#   ./run-lmeval.sh <model>           # Apply template with default limit (50)
#   ./run-lmeval.sh <model> <limit>   # Override sample limit
#   ./run-lmeval.sh <model> 0         # Full benchmark (no limit)
#
# Models: qwen3-8b-agent | mistral-3-bf16

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"

source "$REPO_ROOT/scripts/lib.sh"

MODEL="${1:-}"
LIMIT="${2:-}"

if [ -z "$MODEL" ]; then
    echo "Usage: $0 <model> [limit]"
    echo ""
    echo "Models:"
    echo "  qwen3-8b-agent   — 8B reasoning model (1 GPU)"
    echo "  mistral-3-bf16     — 24B general model (4 GPU)"
    echo ""
    echo "Options:"
    echo "  limit  — Number of samples per task (default: 50, 0 = full benchmark)"
    echo ""
    echo "Examples:"
    echo "  $0 qwen3-8b-agent        # Quick eval (~10 min)"
    echo "  $0 qwen3-8b-agent 200    # Medium eval (~30 min)"
    echo "  $0 mistral-3-bf16 0        # Full benchmark (hours)"
    exit 1
fi

case "$MODEL" in
    qwen3-8b-agent|granite)
        TEMPLATE="$REPO_ROOT/gitops/step-08-model-evaluation/base/lmeval/qwen3-8b-eval.yaml"
        JOB_NAME="qwen3-8b-agent-eval"
        ;;
    mistral-3-bf16|mistral)
        TEMPLATE="$REPO_ROOT/gitops/step-08-model-evaluation/base/lmeval/mistral-bf16-eval.yaml"
        JOB_NAME="mistral-3-bf16-eval"
        ;;
    *)
        log_error "Unknown model: $MODEL"
        echo "Valid: qwen3-8b-agent, mistral-3-bf16"
        exit 1
        ;;
esac

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  LM-Eval Standard Benchmark                                    ║"
echo "║  Model: $MODEL"
echo "║  Tasks: hellaswag, arc_challenge, winogrande, boolq            ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

check_oc_logged_in

if ! oc get inferenceservice "$MODEL" -n "$NAMESPACE" &>/dev/null; then
    log_error "InferenceService $MODEL not found in $NAMESPACE"
    exit 1
fi
log_success "InferenceService $MODEL found"

# Delete previous run if exists (LMEvalJob names are fixed per template)
if oc get lmevaljob "$JOB_NAME" -n "$NAMESPACE" &>/dev/null; then
    log_info "Deleting previous LMEvalJob $JOB_NAME..."
    oc delete lmevaljob "$JOB_NAME" -n "$NAMESPACE" --wait=false 2>/dev/null || true
    sleep 3
fi

# Apply template, optionally overriding the limit
if [ -n "$LIMIT" ]; then
    if [ "$LIMIT" = "0" ]; then
        log_info "Applying template without sample limit (full benchmark)..."
        # Remove the limit field entirely
        sed '/^  limit:/d' "$TEMPLATE" | oc apply -n "$NAMESPACE" -f -
    else
        log_info "Applying template with limit=$LIMIT..."
        sed "s/^  limit: .*/  limit: \"$LIMIT\"/" "$TEMPLATE" | oc apply -n "$NAMESPACE" -f -
    fi
else
    log_info "Applying template with default limit..."
    oc apply -f "$TEMPLATE" -n "$NAMESPACE"
fi

log_success "LMEvalJob $JOB_NAME created"
echo ""

log_info "Monitor progress:"
echo "  oc get lmevaljob $JOB_NAME -n $NAMESPACE -w"
echo ""
log_info "View results when complete:"
echo "  oc get lmevaljob $JOB_NAME -n $NAMESPACE -o template --template='{{.status.results}}' | jq '.results'"
echo ""
log_info "Or view in Dashboard: Develop & train > Evaluations"
