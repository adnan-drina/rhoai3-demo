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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

OPERATOR_APP_NAME="step-13b-edge-ai-microshift-operator"
PIPELINE_APP_NAME="step-13b-edge-ai-microshift"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-openshift-gitops}"
MLOPS_NAMESPACE="${MLOPS_NAMESPACE:-enterprise-mlops}"

PASS=0
FAIL=0

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

pipelines_subscription_succeeded() {
    local csv
    csv=$(oc get subscription openshift-pipelines-operator-rh -n openshift-operators -o jsonpath='{.status.installedCSV}' 2>/dev/null)
    [[ -n "$csv" ]] || return 1
    [[ "$(oc get csv "$csv" -n openshift-operators -o jsonpath='{.status.phase}' 2>/dev/null)" == "Succeeded" ]]
}

argocd_app_synced() {
    local app_name="$1"
    [[ "$(oc get applications.argoproj.io "$app_name" -n "$ARGO_NAMESPACE" -o jsonpath='{.status.sync.status}' 2>/dev/null)" == "Synced" ]]
}

argocd_app_healthy() {
    local app_name="$1"
    [[ "$(oc get applications.argoproj.io "$app_name" -n "$ARGO_NAMESPACE" -o jsonpath='{.status.health.status}' 2>/dev/null)" == "Healthy" ]]
}

tekton_crds_available() {
    oc get crd tasks.tekton.dev pipelines.tekton.dev &>/dev/null
}

central_release_resources_exist() {
    oc get task.tekton.dev build-modelcar -n "$MLOPS_NAMESPACE" &>/dev/null \
        && oc get task.tekton.dev update-gitops -n "$MLOPS_NAMESPACE" &>/dev/null \
        && oc get pipeline.tekton.dev modelcar-release -n "$MLOPS_NAMESPACE" &>/dev/null
}

release_prerequisites_documented() {
    grep -q "quay-push-credentials" "$SCRIPT_DIR/README.md" \
        && grep -q "github-push-credentials" "$SCRIPT_DIR/README.md"
}

run_central_validation() {
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║  Step 13b Validation: Central ModelCar Release Pipeline             ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""

    check "OpenShift API access" \
        "oc whoami"

    check "OpenShift Pipelines ArgoCD Application exists" \
        "oc get applications.argoproj.io '$OPERATOR_APP_NAME' -n '$ARGO_NAMESPACE'"

    check "OpenShift Pipelines ArgoCD Application is Synced" \
        "argocd_app_synced '$OPERATOR_APP_NAME'"

    check "OpenShift Pipelines ArgoCD Application is Healthy" \
        "argocd_app_healthy '$OPERATOR_APP_NAME'"

    check "ModelCar release ArgoCD Application exists" \
        "oc get applications.argoproj.io '$PIPELINE_APP_NAME' -n '$ARGO_NAMESPACE'"

    check "ModelCar release ArgoCD Application is Synced" \
        "argocd_app_synced '$PIPELINE_APP_NAME'"

    check "ModelCar release ArgoCD Application is Healthy" \
        "argocd_app_healthy '$PIPELINE_APP_NAME'"

    check "OpenShift Pipelines subscription is installed" \
        "pipelines_subscription_succeeded"

    check "Tekton CRDs are available" \
        "tekton_crds_available"

    check "ModelCar release Task/Pipeline resources exist" \
        "central_release_resources_exist"

    check "MinIO training artifact secret exists" \
        "oc get secret dspa-minio-credentials -n '$MLOPS_NAMESPACE'"

    check "Release credential secrets are external run prerequisites" \
        "release_prerequisites_documented"
}

print_results() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Results: $PASS passed, $FAIL failed (of $((PASS + FAIL)) checks)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

if [[ -z "${EDGE_HOST:-}" || -z "${EDGE_PASS:-}" ]]; then
    run_central_validation
    echo ""
    echo -e "${YELLOW}[WARN]${NC} MicroShift host checks skipped because EDGE_HOST or EDGE_PASS is not set."
    print_results
    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
    exit 0
fi

EDGE_USER="${EDGE_USER:-dev}"

run_remote() {
    sshpass -p "$EDGE_PASS" ssh -o StrictHostKeyChecking=no "${EDGE_USER}@${EDGE_HOST}" "$1" 2>/dev/null
}

run_central_validation
echo ""

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
print_results

if [[ -n "$ROUTE_HOST" ]]; then
    echo ""
    echo "  Edge Camera URL: https://${ROUTE_HOST}"
fi

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
