#!/bin/bash
# =============================================================================
# Step 13 Validation: Edge AI
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

NAMESPACE="edge-ai-demo"
PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if eval "$@" &>/dev/null; then
        log_success "$desc"
        PASS=$((PASS + 1))
    else
        log_error "FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 13 Validation: Edge AI                                        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

check "Namespace $NAMESPACE exists" \
    "oc get namespace $NAMESPACE"

check "ServingRuntime kserve-ovms exists" \
    "oc get servingruntime kserve-ovms -n $NAMESPACE"

check "InferenceService face-recognition-edge exists" \
    "oc get inferenceservice face-recognition-edge -n $NAMESPACE"

check "InferenceService face-recognition-edge is Ready" \
    "test \$(oc get inferenceservice face-recognition-edge -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}') = 'True'"

check "edge-camera Deployment exists" \
    "oc get deployment edge-camera -n $NAMESPACE"

check "edge-camera has ready replicas" \
    "test \$(oc get deployment edge-camera -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0) -ge 1"

check "edge-camera Route exists" \
    "oc get route edge-camera -n $NAMESPACE"

ROUTE_HOST=$(oc get route edge-camera -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -n "$ROUTE_HOST" ]]; then
    check "edge-camera health endpoint responds" \
        "curl -sk https://$ROUTE_HOST/_stcore/health | grep -q ok"
fi

check "storage-config secret exists" \
    "oc get secret storage-config -n $NAMESPACE"

check "ArgoCD Application exists" \
    "oc get application step-13-edge-ai -n openshift-gitops"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS passed, $FAIL failed (of $((PASS + FAIL)) checks)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    log_warn "Some checks failed. Troubleshoot with:"
    echo "  oc get pods -n $NAMESPACE"
    echo "  oc describe inferenceservice face-recognition-edge -n $NAMESPACE"
    echo "  oc logs deploy/edge-camera -n $NAMESPACE"
    exit 1
fi
