#!/bin/bash
# Step 09: AI Safety with Guardrails — Deploy Script
# Deploys the Guardrails Orchestrator, HAP detector, prompt injection detector,
# and Gateway with preset safety routes. Restarts LlamaStack pods to connect.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"
STEP_NAME="step-09-guardrails"

source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 09: AI Safety with Guardrails                             ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 0: Prerequisites
# ═══════════════════════════════════════════════════════════════════════════
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

if ! oc get inferenceservice granite-8b-agent -n "$NAMESPACE" &>/dev/null; then
    log_error "granite-8b-agent InferenceService not found. Deploy step-05 first."
    exit 1
fi
log_success "granite-8b-agent present"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 1: Deploy via ArgoCD
# ═══════════════════════════════════════════════════════════════════════════
log_step "Deploying Step 09 via ArgoCD..."

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/$STEP_NAME.yaml"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 2: Wait for ArgoCD sync
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
    log_error "Timeout waiting for ArgoCD sync."
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: Wait for detectors
# ═══════════════════════════════════════════════════════════════════════════
log_step "Waiting for HAP detector..."
oc wait inferenceservice/hap-detector -n "$NAMESPACE" \
    --for=condition=Ready --timeout=300s 2>/dev/null || \
    log_error "HAP detector did not become ready"

log_step "Waiting for prompt injection detector..."
oc wait inferenceservice/prompt-injection-detector -n "$NAMESPACE" \
    --for=condition=Ready --timeout=300s 2>/dev/null || \
    log_error "Prompt injection detector did not become ready"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 4: Wait for Orchestrator
# ═══════════════════════════════════════════════════════════════════════════
log_step "Waiting for Guardrails Orchestrator..."

ORCH_READY=false
for i in $(seq 1 30); do
    POD_STATUS=$(oc get pods -l app=guardrails-orchestrator -n "$NAMESPACE" \
        --no-headers -o custom-columns=":status.phase" 2>/dev/null | head -1)
    if [ "$POD_STATUS" = "Running" ]; then
        ORCH_READY=true
        break
    fi
    sleep 10
done

if [ "$ORCH_READY" = "true" ]; then
    log_success "Guardrails Orchestrator is running"
else
    log_error "Guardrails Orchestrator did not reach Running state"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 5: Restart LlamaStack pods to connect to Orchestrator
# ═══════════════════════════════════════════════════════════════════════════
log_step "Restarting LlamaStack pods to connect to Guardrails Orchestrator..."

if oc get llamastackdistribution lsd-genai-playground -n "$NAMESPACE" &>/dev/null; then
    oc rollout restart deployment/lsd-genai-playground -n "$NAMESPACE" 2>/dev/null || true
    log_success "lsd-genai-playground restart triggered"
fi

if oc get llamastackdistribution lsd-rag -n "$NAMESPACE" &>/dev/null; then
    oc rollout restart deployment/lsd-rag -n "$NAMESPACE" 2>/dev/null || true
    log_success "lsd-rag restart triggered"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 6: Validation output
# ═══════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 09 deployment initiated!                                  ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                 ║"
echo "║  Components:                                                    ║"
echo "║    oc get guardrailsorchestrator -n $NAMESPACE             ║"
echo "║    oc get isvc hap-detector prompt-injection-detector          ║"
echo "║                                                                 ║"
echo "║  Gateway routes (in-cluster):                                   ║"
echo "║    /passthrough/v1/chat/completions  (no detectors)            ║"
echo "║    /pii/v1/chat/completions          (PII regex)               ║"
echo "║    /safe/v1/chat/completions         (PII + HAP + injection)   ║"
echo "║                                                                 ║"
echo "║  Validate:                                                      ║"
echo "║    ./steps/step-09-guardrails/validate.sh                      ║"
echo "║                                                                 ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
