#!/usr/bin/env bash
# =============================================================================
# Step 06: Run GuideLLM Benchmark
# =============================================================================
# Triggers the GuideLLM CronJob to benchmark all running models.
# Results flow to Prometheus → Grafana dashboards.
#
# Usage:
#   ./run-benchmark.sh              # Trigger CronJob (all running models)
#   ./run-benchmark.sh granite      # Single model job template
#   ./run-benchmark.sh mistral-bf16 # Single model job template
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

NAMESPACE="private-ai"

check_oc_logged_in

MODEL="${1:-}"

if [[ -n "$MODEL" ]]; then
    case "$MODEL" in
        qwen3|qwen3-8b-agent)
            JOB_FILE="$REPO_ROOT/gitops/step-06-model-metrics/base/guidellm/job-templates/qwen3-8b-agent.yaml"
            ;;
        mistral|mistral-bf16|mistral-3-bf16)
            JOB_FILE="$REPO_ROOT/gitops/step-06-model-metrics/base/guidellm/job-templates/mistral-3-bf16.yaml"
            ;;
        *)
            log_error "Unknown model: $MODEL"
            echo "  Available: granite, mistral-bf16"
            exit 1
            ;;
    esac

    log_step "Creating benchmark job for $MODEL..."
    oc create -f "$JOB_FILE"
    log_success "Job created. Watch with: oc get pods -n $NAMESPACE -l app=guidellm -w"
else
    log_step "Triggering GuideLLM CronJob (benchmarks all running models)..."

    if ! oc get cronjob guidellm-daily -n "$NAMESPACE" &>/dev/null; then
        log_error "GuideLLM CronJob not found. Deploy Step 06 first."
        exit 1
    fi

    JOB_NAME="bench-$(date +%Y%m%d-%H%M)"
    oc create job "$JOB_NAME" --from=cronjob/guidellm-daily -n "$NAMESPACE"
    log_success "Job '$JOB_NAME' created"

    echo ""
    log_info "Watch progress:"
    echo "  oc logs -f job/$JOB_NAME -n $NAMESPACE"
    echo ""
    log_info "View results in Grafana:"
    GRAFANA_URL=$(oc get route grafana-route -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "loading...")
    echo "  https://$GRAFANA_URL"
fi
