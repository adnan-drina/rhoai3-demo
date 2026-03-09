#!/bin/bash
# Step 11: AI Safety with Guardrails — Validation Script

set -euo pipefail

NAMESPACE="private-ai"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 11: Guardrails — Validation                              ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Infrastructure ---
log_step "Infrastructure"

echo ""
echo "GuardrailsOrchestrator:"
oc get guardrailsorchestrator -n "$NAMESPACE" 2>/dev/null || echo "  NOT FOUND"

echo ""
echo "Detector InferenceServices:"
oc get isvc hap-detector prompt-injection-detector -n "$NAMESPACE" 2>/dev/null || echo "  NOT FOUND"

echo ""
echo "Orchestrator pods:"
oc get pods -l app=guardrails-orchestrator -n "$NAMESPACE" 2>/dev/null || echo "  NOT FOUND"

echo ""

# --- Health check ---
log_step "Orchestrator health check"
ORCH_POD=$(oc get pods -l app=guardrails-orchestrator -n "$NAMESPACE" \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)

if [ -n "$ORCH_POD" ]; then
    oc exec "$ORCH_POD" -n "$NAMESPACE" -c guardrails-orchestrator -- \
        curl -s http://localhost:8032/health 2>/dev/null && echo "" || \
        echo "  Could not reach health endpoint"
else
    echo "  Orchestrator pod not found"
fi

echo ""

# --- PII detection test ---
log_step "PII detection test (email via regex detector)"
if [ -n "$ORCH_POD" ]; then
    RESULT=$(oc exec "$ORCH_POD" -n "$NAMESPACE" -c guardrails-orchestrator -- \
        curl -s http://localhost:8032/api/v2/text/detection/content \
        -H "Content-Type: application/json" \
        -d '{"detectors":{"regex":{"regex":["email"]}},"content":"my email is test@example.com"}' \
        2>/dev/null || echo "{}")
    echo "  Response:"
    echo "$RESULT" | python3 -m json.tool 2>/dev/null || echo "  $RESULT"
else
    echo "  Skipped (no orchestrator pod)"
fi

echo ""

# --- LlamaStack shields ---
log_step "LlamaStack shields (lsd-genai-playground)"
LSD_POD=$(oc get pods -l app.kubernetes.io/name=llamastack -n "$NAMESPACE" \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)

if [ -n "$LSD_POD" ]; then
    oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/shields 2>/dev/null | \
        python3 -m json.tool 2>/dev/null || echo "  Could not query shields"
else
    echo "  lsd-genai-playground pod not found"
fi

echo ""

# --- LlamaStack shields (lsd-rag) ---
log_step "LlamaStack shields (lsd-rag)"
RAG_POD=$(oc get pods -l app.kubernetes.io/name=llamastack-rag -n "$NAMESPACE" \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)

if [ -n "$RAG_POD" ]; then
    oc exec "$RAG_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/shields 2>/dev/null | \
        python3 -m json.tool 2>/dev/null || echo "  Could not query shields"
else
    echo "  lsd-rag pod not found"
fi

echo ""
log_success "Validation complete"
