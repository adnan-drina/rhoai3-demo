#!/usr/bin/env bash
# Step 12: MLOps Training Pipeline — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="enterprise-mlops"

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
    "oc get dspa dspa-mlops -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
    "True"

check "Pipeline RBAC (Role)" \
    "oc get role face-pipeline-controller -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "face-pipeline-controller"

# --- MLflow ---
log_step "MLflow"
MLFLOW_FLAG=$(oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
    -o jsonpath='{.spec.dashboardConfig.mlflow}' 2>/dev/null || echo "")
if [[ "$MLFLOW_FLAG" == "true" ]]; then
    echo -e "${GREEN}[PASS]${NC} RHOAI Dashboard MLflow feature flag enabled"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} MLflow dashboard flag not confirmed; verify OdhDashboardConfig schema on this cluster"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

if oc api-resources 2>/dev/null | grep -qi mlflow; then
    echo -e "${GREEN}[PASS]${NC} MLflow API resources discovered"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} No documented MLflow CRD discovered; create MLflow server through RHOAI dashboard until a supported GitOps API is confirmed"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Pipeline Execution ---
log_step "Pipeline Execution"
COMPLETED_RUNS=$(oc get pods -n "$NAMESPACE" -l pipeline/runid --no-headers 2>/dev/null | grep -c "Completed" || true)
if [ "$COMPLETED_RUNS" -ge 1 ]; then
    echo -e "${GREEN}[PASS]${NC} Pipeline has completed runs ($COMPLETED_RUNS pods)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} No completed pipeline pods found — checking KFP run history"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

TRAIN_RUN_INFO=""
if [[ -x "$REPO_ROOT/.venv-kfp/bin/python3" ]]; then
    DSPA_ROUTE=$(oc get route ds-pipeline-dspa-mlops -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    OC_TOKEN=$(oc whoami -t 2>/dev/null || echo "")
    if [[ -n "$DSPA_ROUTE" && -n "$OC_TOKEN" ]]; then
        set +e
        TRAIN_RUN_INFO=$(DSPA_ROUTE="$DSPA_ROUTE" OC_TOKEN="$OC_TOKEN" "$REPO_ROOT/.venv-kfp/bin/python3" - 2>/dev/null <<'PY'
import os
from kfp import client

c = client.Client(
    host="https://" + os.environ["DSPA_ROUTE"],
    namespace="enterprise-mlops",
    existing_token=os.environ["OC_TOKEN"],
)
runs = c.list_runs(page_size=50, sort_by="created_at desc").runs or []
for run in runs:
    name = getattr(run, "display_name", "") or ""
    if name.startswith("train-"):
        state = getattr(run, "state", "") or ""
        created = getattr(run, "created_at", "") or ""
        print(f"{state}|{created}|{name}")
        break
PY
)
        set -e
    fi
else
    echo -e "${YELLOW}[WARN]${NC} KFP client venv not found — run ./steps/step-12-mlops-pipeline/run-training-pipeline.sh first"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

if [[ -n "$TRAIN_RUN_INFO" ]]; then
    TRAIN_STATE="${TRAIN_RUN_INFO%%|*}"
    REST="${TRAIN_RUN_INFO#*|}"
    TRAIN_CREATED="${REST%%|*}"
    TRAIN_NAME="${REST#*|}"
    if [[ "$TRAIN_STATE" == "SUCCEEDED" ]]; then
        echo -e "${GREEN}[PASS]${NC} Latest KFP training run succeeded: $TRAIN_NAME"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} Latest KFP training run $TRAIN_NAME state: $TRAIN_STATE"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
    check_recent_timestamp "Latest KFP training run" "$TRAIN_CREATED" "${DEMO_FRESHNESS_HOURS:-24}" "warn"
else
    echo -e "${YELLOW}[WARN]${NC} No KFP training run found — run: ./steps/step-12-mlops-pipeline/run-training-pipeline.sh"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Model Registry ---
log_step "Model Registry Integration"
REGISTRY_ROUTE=$(oc get route enterprise-ai-registry-https -n rhoai-model-registries -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
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
