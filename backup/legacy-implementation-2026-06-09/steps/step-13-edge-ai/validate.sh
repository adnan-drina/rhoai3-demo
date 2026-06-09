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

check_inferenceservice_scrape_label() {
    local isvc="$1"
    local desired deploy_name deploy_label selector pod_labels bad_labels

    desired=$(oc get inferenceservice "$isvc" -n "$NAMESPACE" \
        -o jsonpath='{.spec.predictor.labels.monitoring\.opendatahub\.io/scrape}' 2>/dev/null || true)
    if [[ "$desired" == "true" ]]; then
        log_success "InferenceService $isvc opts predictor pods into RHOAI metrics scraping"
        PASS=$((PASS + 1))
    else
        log_error "FAIL: InferenceService $isvc missing RHOAI metrics scrape opt-in"
        FAIL=$((FAIL + 1))
        return
    fi

    deploy_name=$(oc get deploy -n "$NAMESPACE" -l "serving.kserve.io/inferenceservice=$isvc" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -z "$deploy_name" ]] && oc get deploy "${isvc}-predictor" -n "$NAMESPACE" &>/dev/null; then
        deploy_name="${isvc}-predictor"
    fi
    if [[ -z "$deploy_name" ]]; then
        log_warn "Predictor Deployment for $isvc not found; generated pod scrape label cannot be checked yet"
        return
    fi

    deploy_label=$(oc get deploy "$deploy_name" -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.metadata.labels.monitoring\.opendatahub\.io/scrape}' 2>/dev/null || true)
    if [[ "$deploy_label" == "true" ]]; then
        log_success "Predictor Deployment $deploy_name propagates RHOAI scrape label"
        PASS=$((PASS + 1))
    else
        log_error "FAIL: Predictor Deployment $deploy_name missing RHOAI scrape label"
        FAIL=$((FAIL + 1))
    fi

    selector=$(oc get deploy "$deploy_name" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '
        .spec.selector.matchLabels
        | to_entries
        | map("\(.key)=\(.value)")
        | join(",")
    ' 2>/dev/null || true)
    if [[ -z "$selector" || "$selector" == "null" ]]; then
        selector="serving.kserve.io/inferenceservice=$isvc"
    fi

    pod_labels=$(oc get pods -n "$NAMESPACE" -l "$selector" -o json 2>/dev/null | jq -r '
        .items[]
        | "\(.metadata.name)=\(.metadata.labels["monitoring.opendatahub.io/scrape"] // "")"
    ' 2>/dev/null || true)
    if [[ -z "$pod_labels" ]]; then
        log_warn "No generated predictor pods found for $isvc; scrape label will be checked after rollout"
        return
    fi

    bad_labels=$(printf '%s\n' "$pod_labels" | awk -F= '$2 != "true" {print}')
    if [[ -z "$bad_labels" ]]; then
        log_success "Generated predictor pods for $isvc carry RHOAI scrape label"
        PASS=$((PASS + 1))
    else
        log_error "FAIL: Generated predictor pods for $isvc missing RHOAI scrape label: $bad_labels"
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

check_inferenceservice_scrape_label "face-recognition-edge"

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
    "oc get applications.argoproj.io step-13-edge-ai -n openshift-gitops"

check "ArgoCD Application is Synced" \
    "test \$(oc get applications.argoproj.io step-13-edge-ai -n openshift-gitops -o jsonpath='{.status.sync.status}') = 'Synced'"

check "ArgoCD Application is Healthy" \
    "test \$(oc get applications.argoproj.io step-13-edge-ai -n openshift-gitops -o jsonpath='{.status.health.status}') = 'Healthy'"

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
