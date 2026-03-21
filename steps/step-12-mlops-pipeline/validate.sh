#!/usr/bin/env bash
# Step 12: MLOps Training Pipeline — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="private-ai"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 12: MLOps Training Pipeline — Validation                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- ArgoCD Application ---
log_step "ArgoCD Application"
check_argocd_app "step-12-mlops-pipeline"

# --- Pipeline Infrastructure ---
log_step "Pipeline Infrastructure"
check "face-pipeline-workspace PVC exists" \
    "oc get pvc face-pipeline-workspace -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "face-pipeline-workspace"

check "DSPA pipeline server" \
    "oc get dspa dspa-rag -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
    "True"

check "Pipeline RBAC (Role)" \
    "oc get role face-recognition-pipeline -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "face-recognition-pipeline"

# --- Pipeline Execution ---
log_step "Pipeline Execution"
COMPLETED_RUNS=$(oc get pods -n "$NAMESPACE" -l pipeline/runid --no-headers 2>/dev/null | grep -c "Completed" || echo "0")
if [ "$COMPLETED_RUNS" -ge 1 ]; then
    echo -e "${GREEN}[PASS]${NC} Pipeline has completed runs ($COMPLETED_RUNS pods)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} No completed pipeline runs found — run: ./steps/step-12-mlops-pipeline/run-training-pipeline.sh"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Model Registry ---
log_step "Model Registry Integration"
REGISTRY_ROUTE=$(oc get route private-ai-registry-https -n rhoai-model-registries -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -n "$REGISTRY_ROUTE" ]]; then
    TOKEN=$(oc whoami -t 2>/dev/null || echo "")
    FACE_MODEL=$(curl -sk -H "Authorization: Bearer $TOKEN" \
        "https://${REGISTRY_ROUTE}/api/model_registry/v1alpha3/registered_models" 2>/dev/null | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print(len([m for m in d.get('items',[]) if 'face' in m['name'].lower()]))" 2>/dev/null || echo "0")
    if [ "$FACE_MODEL" -ge 1 ]; then
        echo -e "${GREEN}[PASS]${NC} face-recognition model registered in Model Registry"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} face-recognition not found in Model Registry — pipeline may not have run yet"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
else
    echo -e "${YELLOW}[WARN]${NC} Model Registry route not available"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- face-recognition ISVC linked to registry ---
ISVC_RM_ID=$(oc get inferenceservice face-recognition -n "$NAMESPACE" \
    -o jsonpath='{.metadata.labels.modelregistry\.opendatahub\.io/registered-model-id}' 2>/dev/null || echo "")
if [[ -n "$ISVC_RM_ID" ]]; then
    echo -e "${GREEN}[PASS]${NC} face-recognition ISVC linked to Model Registry (model-id=$ISVC_RM_ID)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} face-recognition ISVC not linked to Model Registry"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- TrustyAI ---
log_step "TrustyAI Monitoring"
check_warn "TrustyAIService exists" \
    "oc get trustyaiservice trustyai-service -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "trustyai-service"

TRUSTYAI_POD=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=trustyai-service --no-headers 2>/dev/null | grep Running | head -1 | awk '{print $1}')
if [[ -n "$TRUSTYAI_POD" ]]; then
    echo -e "${GREEN}[PASS]${NC} TrustyAI service pod running"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} TrustyAI service pod not running"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Summary ---
echo ""
validation_summary
