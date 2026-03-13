#!/usr/bin/env bash
# Step 09: AI Safety with Guardrails — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="private-ai"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 09: Guardrails — Validation                              ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Argo CD Application ---
log_step "Argo CD Application"
check_argocd_app "step-09-guardrails"

# --- GuardrailsOrchestrator ---
log_step "GuardrailsOrchestrator"
check "GuardrailsOrchestrator exists" \
    "oc get guardrailsorchestrator -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}'" \
    "guardrails"

check_pods_ready "$NAMESPACE" "app=guardrails-orchestrator" 1

# --- Detector InferenceServices ---
log_step "Detector InferenceServices"
for detector in hap-detector prompt-injection-detector; do
    READY=$(oc get inferenceservice "$detector" -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NOT_FOUND")
    if [[ "$READY" == "True" ]]; then
        echo -e "${GREEN}[PASS]${NC} Detector $detector: Ready"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} Detector $detector: not Ready ($READY)"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
done

# --- Orchestrator Health ---
log_step "Orchestrator Health"
ORCH_POD=$(oc get pods -l app=guardrails-orchestrator -n "$NAMESPACE" \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)

if [[ -n "$ORCH_POD" ]]; then
    HEALTH=$(oc exec "$ORCH_POD" -n "$NAMESPACE" -c guardrails-orchestrator -- \
        curl -s http://localhost:8032/health 2>/dev/null || echo "ERROR")
    if echo "$HEALTH" | grep -qi "ok\|healthy\|UP"; then
        echo -e "${GREEN}[PASS]${NC} Orchestrator health check passed"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} Orchestrator health check inconclusive: $HEALTH"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
else
    echo -e "${RED}[FAIL]${NC} Orchestrator pod not found"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- LlamaStack Shields ---
log_step "LlamaStack Shields"
for label_name in "llamastack:lsd-genai-playground" "llamastack-rag:lsd-rag"; do
    label=$(echo "$label_name" | cut -d: -f1)
    name=$(echo "$label_name" | cut -d: -f2)
    POD=$(oc get pods -l "app.kubernetes.io/name=$label" -n "$NAMESPACE" \
        --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)
    if [[ -n "$POD" ]]; then
        SHIELDS=$(oc exec "$POD" -n "$NAMESPACE" -- \
            curl -s http://localhost:8321/v1/shields 2>/dev/null || echo "ERROR")
        if echo "$SHIELDS" | grep -qi "shield\|identifier"; then
            echo -e "${GREEN}[PASS]${NC} Shields registered in $name"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${YELLOW}[WARN]${NC} No shields found in $name"
            VALIDATE_WARN=$((VALIDATE_WARN + 1))
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} Pod for $name not found — skipping shields check"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
done

# --- Summary ---
echo ""
validation_summary
