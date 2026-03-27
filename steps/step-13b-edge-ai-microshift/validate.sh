#!/bin/bash
# =============================================================================
# Step 13b Validation: Edge AI on MicroShift
# =============================================================================
# Runs from your LOCAL machine, SSHes into the edge host.
#
# Usage:
#   EDGE_HOST=rhaiis.example.com EDGE_USER=dev EDGE_PASS=password ./validate.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

EDGE_HOST="${EDGE_HOST:?Set EDGE_HOST}"
EDGE_USER="${EDGE_USER:-dev}"
EDGE_PASS="${EDGE_PASS:?Set EDGE_PASS}"

PASS=0
FAIL=0

run_remote() {
    sshpass -p "$EDGE_PASS" ssh -o StrictHostKeyChecking=no "${EDGE_USER}@${EDGE_HOST}" "$1" 2>/dev/null
}

check() {
    local desc="$1"
    shift
    if eval "$@" &>/dev/null; then
        echo -e "${GREEN}[OK]${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 13b Validation: Edge AI on MicroShift                         ║"
echo "║  Host: ${EDGE_HOST}                                                 ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

check "SSH connectivity" \
    "run_remote 'echo ok'"

check "MicroShift service is active" \
    "run_remote 'systemctl is-active microshift'"

check "Node is Ready" \
    "run_remote 'oc get nodes --no-headers | grep -q Ready'"

check "KServe controller running" \
    "run_remote 'oc get pods -n redhat-ods-applications --no-headers | grep -q Running'"

check "Namespace edge-ai exists" \
    "run_remote 'oc get ns edge-ai'"

check "ServingRuntime kserve-ovms exists" \
    "run_remote 'oc get servingruntime kserve-ovms -n edge-ai'"

check "InferenceService face-recognition-edge exists" \
    "run_remote 'oc get isvc face-recognition-edge -n edge-ai'"

check "InferenceService is Ready" \
    "run_remote 'oc get isvc face-recognition-edge -n edge-ai -o jsonpath=\"{.status.conditions[?(@.type==\\\"Ready\\\")].status}\" | grep -q True'"

check "Predictor pod is Running (2/2)" \
    "run_remote 'oc get pods -n edge-ai --no-headers | grep face-recognition | grep -q \"2/2.*Running\"'"

check "edge-camera pod is Running" \
    "run_remote 'oc get pods -n edge-ai --no-headers | grep edge-camera | grep -q \"1/1.*Running\"'"

check "edge-camera Route exists" \
    "run_remote 'oc get route edge-camera -n edge-ai'"

ROUTE_HOST=$(run_remote "oc get route edge-camera -n edge-ai -o jsonpath='{.spec.host}'" 2>/dev/null || echo "")
PUBLIC_IP=$(run_remote "curl -s http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || echo "")
if [[ -n "$ROUTE_HOST" && -n "$PUBLIC_IP" ]]; then
    check "Streamlit health endpoint responds" \
        "curl -sk --connect-to '${ROUTE_HOST}::${PUBLIC_IP}:' 'https://${ROUTE_HOST}/_stcore/health' | grep -q ok"
fi

check "Model metadata accessible" \
    "run_remote 'oc exec -n edge-ai deploy/face-recognition-edge-predictor -c kserve-container -- curl -s localhost:8888/v2/models/face-recognition-edge | grep -q onnx'"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS passed, $FAIL failed (of $((PASS + FAIL)) checks)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -n "$ROUTE_HOST" ]]; then
    echo ""
    echo "  Edge Camera URL: https://${ROUTE_HOST}"
fi

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
