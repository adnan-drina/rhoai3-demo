#!/bin/bash
# Step 09: AI Safety with NeMo Guardrails — Deploy Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="enterprise-rag"
MODEL_NAMESPACE="maas"
STEP_NAME="step-09-guardrails"

source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 09: AI Safety with NeMo Guardrails                        ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

log_step "Checking prerequisites..."

check_oc_logged_in

if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    log_error "Namespace $NAMESPACE not found."
    exit 1
fi
log_success "Namespace $NAMESPACE exists"

TRUSTYAI_STATE=$(oc get datasciencecluster default-dsc \
    -o jsonpath='{.spec.components.trustyai.managementState}' 2>/dev/null || echo "Unknown")
if [ "$TRUSTYAI_STATE" != "Managed" ]; then
    log_error "trustyai managementState is '$TRUSTYAI_STATE' (expected 'Managed')."
    exit 1
fi
log_success "trustyai: Managed"

if ! oc get crd nemoguardrails.trustyai.opendatahub.io &>/dev/null; then
    log_error "NemoGuardrails CRD not found. Ensure RHOAI 3.4 TrustyAI is installed."
    exit 1
fi
log_success "NemoGuardrails CRD available"

if ! oc get maasmodelref granite-8b-agent -n "$MODEL_NAMESPACE" &>/dev/null; then
    log_error "granite-8b-agent MaaSModelRef not found in $MODEL_NAMESPACE. Deploy step-05 first."
    exit 1
fi
log_success "granite-8b-agent MaaSModelRef present in $MODEL_NAMESPACE"
echo ""

log_step "Deploying Step 09 via ArgoCD..."
oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/$STEP_NAME.yaml"
echo ""

log_step "Waiting for ArgoCD sync..."
sleep 5

TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    SYNC=$(oc get applications.argoproj.io "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(oc get applications.argoproj.io "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    log_info "  Sync: $SYNC | Health: $HEALTH"

    if [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    log_error "Timeout waiting for ArgoCD sync."
    exit 1
fi
echo ""

log_step "Configuring NeMo model access through MaaS..."
ensure_maas_api_key "$NAMESPACE" "rag-maas-api-key" "enterprise-rag-chatbot" \
    "enterprise-demo-subscription" "${RHOAI_DEMO_MAAS_KEY_TTL:-60d}"
MAAS_API_KEY=$(oc get secret rag-maas-api-key -n "$NAMESPACE" -o jsonpath='{.data.MAAS_API_KEY}' | base64 -d)
patch_secret_literal "$NAMESPACE" "nemo-guardrails-api-token" "token" "$MAAS_API_KEY"
log_success "nemo-guardrails-api-token refreshed from MaaS API key"
echo ""

log_step "Waiting for NemoGuardrails service..."
if ! oc wait nemoguardrails/nemo-guardrails -n "$NAMESPACE" \
    --for=jsonpath='{.status.phase}'=Ready --timeout=300s 2>/dev/null; then
    log_warn "NemoGuardrails did not report phase Ready; checking route and continuing to validation."
fi

if ! oc get route nemo-guardrails -n "$NAMESPACE" &>/dev/null; then
    log_error "route/nemo-guardrails was not created"
    exit 1
fi
log_success "NeMo Guardrails route available"
NEMO_DEPLOY=$(oc get deploy -n "$NAMESPACE" -l app.kubernetes.io/instance=nemo-guardrails \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$NEMO_DEPLOY" ]]; then
    NEMO_DEPLOY=$(oc get deploy -n "$NAMESPACE" --no-headers 2>/dev/null | awk '/nemo|guardrails/{print $1; exit}' || true)
fi
if [[ -n "$NEMO_DEPLOY" ]]; then
    oc rollout restart "deployment/${NEMO_DEPLOY}" -n "$NAMESPACE" >/dev/null 2>&1 || true
    oc rollout status "deployment/${NEMO_DEPLOY}" -n "$NAMESPACE" --timeout=180s 2>/dev/null || \
        log_warn "NeMo deployment rollout did not complete after MaaS token refresh"
fi
echo ""

log_step "Restarting chatbot to pick up NeMo guardrails settings..."
if oc get deployment rag-chatbot -n "$NAMESPACE" &>/dev/null; then
    oc rollout restart deployment/rag-chatbot -n "$NAMESPACE" 2>/dev/null || true
    log_success "rag-chatbot restart triggered"
fi
echo ""

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 09 deployment initiated!                                  ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Components:                                                    ║"
echo "║    oc get nemoguardrails nemo-guardrails -n $NAMESPACE          ║"
echo "║    oc get route nemo-guardrails -n $NAMESPACE                   ║"
echo "║                                                                 ║"
echo "║  Validate:                                                      ║"
echo "║    ./steps/step-09-guardrails/validate.sh                       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
