#!/usr/bin/env bash
# Step 11: Face Recognition — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="private-ai"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 11: Face Recognition — Validation                        ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- ArgoCD Application ---
log_step "ArgoCD Application"
check_argocd_app "step-11-face-recognition"

# --- ServingRuntime ---
log_step "ServingRuntime"
check "kserve-ovms ServingRuntime exists" \
    "oc get servingruntime kserve-ovms -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "kserve-ovms"

# --- Model Upload ---
log_step "Model Upload"
check "upload-face-model job succeeded" \
    "oc get job upload-face-model -n minio-storage -o jsonpath='{.status.succeeded}'" \
    "1"

# --- InferenceService ---
log_step "InferenceService"
EXISTS=$(oc get inferenceservice face-recognition -n "$NAMESPACE" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
if [[ "$EXISTS" == "face-recognition" ]]; then
    READY=$(oc get inferenceservice face-recognition -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [[ "$READY" == "True" ]]; then
        echo -e "${GREEN}[PASS]${NC} InferenceService face-recognition: Ready"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} InferenceService face-recognition: exists but not Ready ($READY) — model upload may be pending"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
else
    echo -e "${RED}[FAIL]${NC} InferenceService face-recognition: not found"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Workbench ---
log_step "Workbench"
check_warn "face-recognition-wb Notebook exists" \
    "oc get notebook face-recognition-wb -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "face-recognition-wb"

check_pods_ready "$NAMESPACE" "app=face-recognition-wb" 1

# --- Model Server Health ---
log_step "Model Server Health"
HEALTH_STATUS=$(oc exec -n "$NAMESPACE" deploy/face-recognition-predictor -c kserve-container -- \
    bash -c 'curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/v2/health/ready 2>/dev/null' 2>/dev/null || echo "000")
if [[ "$HEALTH_STATUS" == "200" ]]; then
    echo -e "${GREEN}[PASS]${NC} Model server health: HTTP 200"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} Model server health: HTTP $HEALTH_STATUS (may still be starting)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Summary ---
echo ""
validation_summary
