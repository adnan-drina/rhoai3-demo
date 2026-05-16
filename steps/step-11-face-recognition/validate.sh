#!/usr/bin/env bash
# Step 11: Face Recognition — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="enterprise-mlops"

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

PLATFORM_OVMS_IMAGE=$(oc process -n redhat-ods-applications kserve-ovms \
    -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || echo "")
RUNTIME_OVMS_IMAGE=$(oc get servingruntime kserve-ovms -n "$NAMESPACE" \
    -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || echo "")
if [[ -n "$PLATFORM_OVMS_IMAGE" && "$RUNTIME_OVMS_IMAGE" == "$PLATFORM_OVMS_IMAGE" ]]; then
    echo -e "${GREEN}[PASS]${NC} kserve-ovms image matches the RHOAI 3.4 platform template"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} kserve-ovms image drift: ${RUNTIME_OVMS_IMAGE:-missing}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Model Upload ---
log_step "Model Upload"
UPLOAD_JOB_SUCCEEDED=$(oc get job upload-face-model -n minio-storage \
    -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "")
UPLOAD_JOB_CREATED=$(oc get job upload-face-model -n minio-storage \
    -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "")
if [[ "$UPLOAD_JOB_SUCCEEDED" == "1" ]]; then
    echo -e "${GREEN}[PASS]${NC} upload-face-model job succeeded"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
    check_recent_timestamp "upload-face-model job" "$UPLOAD_JOB_CREATED" "${DEMO_FRESHNESS_HOURS:-24}" "warn"
else
    echo -e "${BLUE}[INFO]${NC} upload-face-model job not found or cleaned up — checking model artifact"
fi

MODEL_INFO=$(oc exec deploy/minio -n minio-storage -- \
    sh -c 'mc alias set demo http://localhost:9000 rhoai-access-key rhoai-secret-key-12345 >/dev/null && mc stat --json demo/models/face-recognition/1/model.onnx' 2>/dev/null | \
    python3 -c "
import json, sys
for line in sys.stdin:
    try:
        item = json.loads(line)
    except Exception:
        continue
    if item.get('name') == 'model.onnx':
        print(str(item.get('size', 0)) + '|' + item.get('lastModified', ''))
        break
" 2>/dev/null || echo "")
MODEL_SIZE="${MODEL_INFO%%|*}"
MODEL_LAST_MODIFIED="${MODEL_INFO#*|}"
if [[ "$MODEL_SIZE" =~ ^[0-9]+$ ]] && [ "$MODEL_SIZE" -gt 0 ]; then
    echo -e "${GREEN}[PASS]${NC} face-recognition model artifact exists in MinIO ($MODEL_SIZE bytes)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
    if [[ "$UPLOAD_JOB_SUCCEEDED" != "1" ]]; then
        check_recent_timestamp "face-recognition model artifact" "$MODEL_LAST_MODIFIED" "${DEMO_FRESHNESS_HOURS:-24}" "warn"
    fi
else
    echo -e "${RED}[FAIL]${NC} face-recognition model artifact missing in MinIO"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

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
