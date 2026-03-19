#!/usr/bin/env bash
# Step 05: GPU-as-a-Service Demo (LLM on vLLM) — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="private-ai"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 05: LLM on vLLM — Validation                            ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- ServingRuntime ---
log_step "ServingRuntime"
SR_COUNT=$(oc get servingruntime -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SR_COUNT" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} ServingRuntime(s) found: $SR_COUNT"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} No ServingRuntime found in $NAMESPACE"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- InferenceServices ---
log_step "InferenceServices"
for isvc in qwen3-8b-agent mistral-3-bf16; do
    EXISTS=$(oc get inferenceservice "$isvc" -n "$NAMESPACE" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
    if [[ "$EXISTS" == "$isvc" ]]; then
        READY=$(oc get inferenceservice "$isvc" -n "$NAMESPACE" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [[ "$READY" == "True" ]]; then
            echo -e "${GREEN}[PASS]${NC} InferenceService $isvc: Ready"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${YELLOW}[WARN]${NC} InferenceService $isvc: exists but not Ready ($READY) — may need GPU nodes or model upload"
            VALIDATE_WARN=$((VALIDATE_WARN + 1))
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} InferenceService $isvc: not found"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
done

# At least one InferenceService must be Ready
READY_COUNT=$(oc get inferenceservice -n "$NAMESPACE" -o json 2>/dev/null \
    | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    count = sum(1 for i in data.get('items', [])
                if any(c.get('type') == 'Ready' and c.get('status') == 'True'
                       for c in i.get('status', {}).get('conditions', [])))
    print(count)
except:
    print(0)
" 2>/dev/null || echo "0")

if [[ "$READY_COUNT" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} At least one InferenceService is Ready ($READY_COUNT total)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} No InferenceService is Ready yet — GPU nodes and model uploads may be pending"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Summary ---
echo ""
validation_summary
