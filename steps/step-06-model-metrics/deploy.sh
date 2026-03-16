#!/usr/bin/env bash
# =============================================================================
# Step 06: Model Performance Metrics — Deploy Script
# =============================================================================
# Deploys via ArgoCD:
#   - Grafana Operator + Instance + 2 Dashboards
#   - GuideLLM CronJob (daily benchmarks) + Job templates
#   - Model Benchmarking Workbench
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-06-model-metrics"
NAMESPACE="private-ai"

load_env
check_oc_logged_in

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 06: Model Performance Metrics                             ║"
echo "║  \"The ROI of Quantization\" Demo                                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Prerequisites
# =============================================================================
log_step "Checking prerequisites..."

if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    log_error "Namespace '$NAMESPACE' not found. Run Step 03 first."
    exit 1
fi
log_success "Namespace '$NAMESPACE' exists"

ISVC_COUNT=$(oc get inferenceservice -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$ISVC_COUNT" -eq 0 ]; then
    log_warn "No InferenceServices found. Deploy models from Step 05 first."
else
    log_success "Found $ISVC_COUNT InferenceService(s)"
fi

if ! oc get cm cluster-monitoring-config -n openshift-monitoring -o yaml 2>/dev/null | grep -q "enableUserWorkload: true"; then
    log_warn "User Workload Monitoring may not be enabled"
else
    log_success "User Workload Monitoring enabled"
fi
echo ""

# =============================================================================
# Deploy via ArgoCD
# =============================================================================
log_step "Creating ArgoCD Application for Model Metrics..."

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"
log_success "ArgoCD Application '${STEP_NAME}' created"
echo ""

# =============================================================================
# Wait for Grafana
# =============================================================================
log_step "Waiting for Grafana Operator..."
until oc get csv -n grafana-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Succeeded"; do
    log_info "Waiting for Grafana Operator CSV..."
    sleep 10
done
log_success "Grafana Operator installed"

log_step "Waiting for Grafana instance..."
oc rollout status deployment/grafana-deployment -n "$NAMESPACE" --timeout=120s 2>/dev/null || \
    log_warn "Grafana deployment not ready yet"

GRAFANA_URL=$(oc get route grafana-route -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$GRAFANA_URL" ]; then
    log_success "Grafana: https://$GRAFANA_URL"
else
    log_warn "Grafana route not found yet"
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
echo "  Components deployed:"
echo "    - Grafana Operator + Instance (anonymous access)"
echo "    - 2 GrafanaDashboards (vLLM Latency/Throughput/Cache, DCGM GPU Metrics)"
echo "    - GuideLLM CronJob (daily at 2:00 AM UTC)"
echo "    - Model Benchmarking Workbench"
echo ""
echo "  Run a benchmark now:"
echo "    ./steps/step-06-model-metrics/run-benchmark.sh"
echo ""
echo "  Or manually:"
echo "    oc create -f gitops/step-06-model-metrics/base/guidellm/job-templates/granite-8b-agent.yaml"
echo "    oc create -f gitops/step-06-model-metrics/base/guidellm/job-templates/mistral-3-bf16.yaml"
echo ""
log_info "Validate: ./steps/step-06-model-metrics/validate.sh"
echo ""
