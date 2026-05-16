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
check "RHOAI MLflow operator component managed" \
    "oc get dsc default-dsc -o jsonpath='{.spec.components.mlflowoperator.managementState}'" \
    "Managed"

check_crd_exists "mlflows.mlflow.opendatahub.io"
check_crd_exists "mlflowconfigs.mlflow.kubeflow.org"

check "MLflow server exists" \
    "oc get mlflow mlflow -o jsonpath='{.metadata.name}'" \
    "mlflow"

check "MLflow server available" \
    "oc get mlflow mlflow -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}'" \
    "True"

check "MLflow server selects demo MLflow workspaces" \
    "oc get mlflow mlflow -o json | python3 -c \"import json,sys; print(json.load(sys.stdin).get('spec', {}).get('workspaceLabelSelector', {}).get('matchLabels', {}).get('rhoai-demo/mlflow-workspace', ''))\"" \
    "true"

check "enterprise-mlops MLflowConfig exists" \
    "oc get mlflowconfig mlflow -n $NAMESPACE -o jsonpath='{.spec.artifactRootSecret}'" \
    "mlflow-artifact-connection"

check "MLflow artifact connection secret exists" \
    "oc get secret mlflow-artifact-connection -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "mlflow-artifact-connection"

check "Pipeline ServiceAccount uses MLflow integration RoleBinding" \
    "oc get rolebinding face-pipeline-mlflow-integration-client -n $NAMESPACE -o jsonpath='{.roleRef.name}'" \
    "mlflow-operator-mlflow-integration"

# --- MLflow Run Evidence ---
log_step "MLflow Run Evidence"
MLFLOW_URL=$(oc get mlflow mlflow -o jsonpath='{.status.url}' 2>/dev/null || true)
OC_TOKEN=$(oc whoami -t 2>/dev/null || true)
MLFLOW_RUN_INFO=""
if [[ -n "$MLFLOW_URL" && -n "$OC_TOKEN" ]]; then
    EXPERIMENT_JSON=$(curl -sk --max-time 20 -X POST "$MLFLOW_URL/api/2.0/mlflow/experiments/search" \
        -H "Authorization: Bearer $OC_TOKEN" \
        -H "x-mlflow-workspace: $NAMESPACE" \
        -H "Content-Type: application/json" \
        -d '{"filter":"name = '\''face-recognition'\''","max_results":1}' 2>/dev/null || true)
    EXPERIMENT_ID=$(echo "$EXPERIMENT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); ex=d.get('experiments') or []; print(ex[0].get('experiment_id','') if ex else '')" 2>/dev/null || true)

    if [[ -n "$EXPERIMENT_ID" ]]; then
        RUN_JSON=$(curl -sk --max-time 20 -X POST "$MLFLOW_URL/api/2.0/mlflow/runs/search" \
            -H "Authorization: Bearer $OC_TOKEN" \
            -H "x-mlflow-workspace: $NAMESPACE" \
            -H "Content-Type: application/json" \
            -d "{\"experiment_ids\":[\"$EXPERIMENT_ID\"],\"max_results\":5,\"order_by\":[\"attributes.start_time DESC\"]}" 2>/dev/null || true)
        MLFLOW_RUN_INFO=$(echo "$RUN_JSON" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
for run in data.get("runs", []):
    info = run.get("info", {})
    tags = {tag.get("key"): tag.get("value") for tag in run.get("data", {}).get("tags", [])}
    if tags.get("rhoai.demo.step") == "12" or (info.get("run_name") or "").startswith("face-recognition"):
        start = str(int(info.get("start_time", 0)) // 1000)
        print("|".join([
            info.get("status", ""),
            start,
            info.get("run_id", ""),
            info.get("run_name", ""),
        ]))
        break
' 2>/dev/null || true)
    fi
fi

if [[ -n "$MLFLOW_RUN_INFO" ]]; then
    MLFLOW_STATE="${MLFLOW_RUN_INFO%%|*}"
    REST="${MLFLOW_RUN_INFO#*|}"
    MLFLOW_START="${REST%%|*}"
    REST="${REST#*|}"
    MLFLOW_RUN_ID="${REST%%|*}"
    MLFLOW_RUN_NAME="${REST#*|}"
    if [[ "$MLFLOW_STATE" == "FINISHED" ]]; then
        echo -e "${GREEN}[PASS]${NC} Latest Step 12 MLflow run finished: $MLFLOW_RUN_NAME ($MLFLOW_RUN_ID)"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} Latest Step 12 MLflow run $MLFLOW_RUN_NAME state: $MLFLOW_STATE"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
    check_recent_timestamp "Latest Step 12 MLflow run" "$MLFLOW_START" "${DEMO_FRESHNESS_HOURS:-24}" "warn"
else
    echo -e "${YELLOW}[WARN]${NC} No Step 12 MLflow run found — run: ./steps/step-12-mlops-pipeline/run-training-pipeline.sh"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Pipeline Execution ---
log_step "Pipeline Execution"
COMPLETED_RUNS=$(oc get pods -n "$NAMESPACE" -l pipeline/runid --no-headers 2>/dev/null | grep -c "Completed" || true)
if [ "$COMPLETED_RUNS" -ge 1 ]; then
    echo -e "${GREEN}[PASS]${NC} Pipeline has completed runs ($COMPLETED_RUNS pods)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    log_info "No completed pipeline pods found — checking KFP run history"
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
