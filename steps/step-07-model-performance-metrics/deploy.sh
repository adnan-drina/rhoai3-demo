#!/bin/bash
# =============================================================================
# Step 07: Model Performance Metrics
# =============================================================================
# Deploys Observability Stack and Benchmarking Tools:
#
#   Observability:
#     - User-Managed Grafana (Deployment + Route)
#     - Local Prometheus (Deployment) for high-res vLLM scraping
#     - ServiceMonitor (vLLM integration)
#     - Dashboards: vLLM Production, DCGM, Mistral Comparison
#
#   Benchmarking:
#     - GuideLLM Job (Cron + Manual)
#     - Results PVC (guidellm-results)
#
# =============================================================================

set -e

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 07: Model Performance Metrics                                  ║"
echo "║  Grafana, Prometheus, and GuideLLM Benchmarking                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="${SCRIPT_DIR}/../../gitops/step-07-model-performance-metrics/base"
APP_FILE="${SCRIPT_DIR}/../../gitops/argocd/app-of-apps/step-07-model-performance-metrics.yaml"

# =============================================================================
# Pre-flight Checks
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Pre-flight Checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check for private-ai namespace
if ! oc get namespace private-ai &>/dev/null; then
  echo "❌ Error: 'private-ai' namespace does not exist. Run Step-03/05 first."
  exit 1
fi
echo "✓ Namespace 'private-ai' exists"

# Check for vLLM models (at least one should be running)
if ! oc get servingruntime vllm-runtime -n private-ai &>/dev/null; then
  echo "❌ Error: vLLM Runtime not found. Run Step-05 first."
  exit 1
fi
echo "✓ vLLM ServingRuntime found"

echo ""

read -p "Continue with deployment? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Deployment cancelled."
  exit 0
fi

# =============================================================================
# Deploy ArgoCD Application
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Deploying via ArgoCD"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Applying ArgoCD Application..."
oc apply -f "${APP_FILE}"

echo "Waiting for ArgoCD to sync..."
# Wait loop for ArgoCD app health
for i in {1..30}; do
  STATUS=$(oc get application step-07-model-performance-metrics -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  SYNC=$(oc get application step-07-model-performance-metrics -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  
  if [[ "$STATUS" == "Healthy" && "$SYNC" == "Synced" ]]; then
    echo "✓ Application is Healthy and Synced"
    break
  fi
  
  echo "  Waiting for sync... (Status: $STATUS, Sync: $SYNC)"
  sleep 5
done

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 07 Deployment Complete                                         ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║                                                                      ║"
echo "║  Dashboards (Grafana):                                               ║"
echo "║    Route: https://$(oc get route grafana -n private-ai -o jsonpath='{.spec.host}')"
echo "║    Credentials: admin / admin (Anonymous enabled)                    ║"
echo "║                                                                      ║"
echo "║  Benchmarking:                                                       ║"
echo "║    Job: oc create job --from=cronjob/guidellm-daily manual-run       ║"
echo "║                                                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

