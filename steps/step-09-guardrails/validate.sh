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
        curl -s http://localhost:8034/health 2>/dev/null || echo "ERROR")
    if echo "$HEALTH" | grep -qi "ok\|healthy\|UP\|fms-guardrails"; then
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

# --- LlamaStack Safety Provider ---
log_step "LlamaStack Safety Provider"
LSD_POD=$(oc get pods -l app.kubernetes.io/instance=lsd-rag -n "$NAMESPACE" \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)
if [[ -z "$LSD_POD" ]]; then
    LSD_POD=$(oc get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep "lsd-rag" | awk '{print $1}' | head -1)
fi
if [[ -n "$LSD_POD" ]]; then
    HAS_SAFETY=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/providers 2>/dev/null | \
        python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len([p for p in data['data'] if p['provider_id']=='trustyai_fms']))
except:
    print('0')
" 2>/dev/null || echo "0")
    if [[ "$HAS_SAFETY" -ge 1 ]]; then
        echo -e "${GREEN}[PASS]${NC} trustyai_fms safety provider registered in lsd-rag"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} trustyai_fms provider not found in lsd-rag"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
else
    echo -e "${YELLOW}[WARN]${NC} lsd-rag pod not found — skipping safety provider check"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Summary ---
echo ""
validation_summary
