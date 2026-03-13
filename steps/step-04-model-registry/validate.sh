#!/usr/bin/env bash
# Step 04: Enterprise Model Governance (Model Registry) — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 04: Model Registry — Validation                         ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Argo CD Application ---
log_step "Argo CD Application"
check_argocd_app "step-04-model-registry"

# --- MariaDB ---
log_step "Database"
check_pods_ready "rhoai-model-registries" "app=model-registry-db" 1

# --- ModelRegistry CR ---
log_step "Model Registry"
check "ModelRegistry CR exists" \
    "oc get modelregistry.modelregistry.opendatahub.io private-ai-registry -n rhoai-model-registries -o jsonpath='{.metadata.name}'" \
    "private-ai-registry"

MR_PODS=$(oc get pods -n rhoai-model-registries -l app=private-ai-registry --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [[ "$MR_PODS" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} Model Registry pods running: $MR_PODS"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Model Registry pods not running"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Seed Job ---
log_step "Seed Job"
check "Seed job completed" \
    "oc get job model-registry-seed -n rhoai-model-registries -o jsonpath='{.status.succeeded}'" \
    "1"

# --- Internal Service ---
log_step "Internal Service"
SVC_EXISTS=$(oc get svc private-ai-registry-internal -n rhoai-model-registries -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
if [[ "$SVC_EXISTS" == "private-ai-registry-internal" ]]; then
    echo -e "${GREEN}[PASS]${NC} Internal service exists"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Internal service private-ai-registry-internal not found"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Summary ---
echo ""
validation_summary
