#!/usr/bin/env bash
# validate.sh - Stage 210: Model Serving Foundation
# Proves KServe, vLLM, the demo registry metadata, and the Nemotron endpoint are
# ready for model-serving baseline work.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

REGISTRY_NS="${MODEL_REGISTRY_NAMESPACE:-rhoai-model-registries}"
REGISTRY_NAME="${MODEL_REGISTRY_NAME:-demo-registry}"
MODEL_NS="${RHOAI_MODEL_NAMESPACE:-demo-sandbox}"
MODEL_DEPLOYMENT_NAME="${RHOAI_NEMOTRON_DEPLOYMENT_NAME:-nvidia-nemotron-3-nano-30b-a3b}"
MODEL_DISPLAY_NAME="${RHOAI_NEMOTRON_DISPLAY_NAME:-NVIDIA-Nemotron-3-Nano-30B-A3B-FP8}"
MODEL_VERSION_NAME="${RHOAI_NEMOTRON_VERSION_NAME:-Version 1}"
MODEL_URI="${RHOAI_NEMOTRON_MODEL_URI:-oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0}"
GRAFANA_NS="${RHOAI_GRAFANA_NAMESPACE:-rhoai-demo-grafana}"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

REGISTRY_NS="${MODEL_REGISTRY_NAMESPACE:-$REGISTRY_NS}"
REGISTRY_NAME="${MODEL_REGISTRY_NAME:-$REGISTRY_NAME}"
MODEL_NS="${RHOAI_MODEL_NAMESPACE:-$MODEL_NS}"
MODEL_DEPLOYMENT_NAME="${RHOAI_NEMOTRON_DEPLOYMENT_NAME:-$MODEL_DEPLOYMENT_NAME}"
MODEL_DISPLAY_NAME="${RHOAI_NEMOTRON_DISPLAY_NAME:-$MODEL_DISPLAY_NAME}"
MODEL_VERSION_NAME="${RHOAI_NEMOTRON_VERSION_NAME:-$MODEL_VERSION_NAME}"
MODEL_URI="${RHOAI_NEMOTRON_MODEL_URI:-$MODEL_URI}"
GRAFANA_NS="${RHOAI_GRAFANA_NAMESPACE:-$GRAFANA_NS}"

if [[ -z "${RHOAI_EXPECTED_API_SERVER:-}" ]]; then
  echo "ERROR: RHOAI_EXPECTED_API_SERVER is not set. Set it in .env." >&2
  exit 1
fi

ACTUAL_SERVER=$(oc whoami --show-server 2>/dev/null || true)
if [[ "$ACTUAL_SERVER" != *"$RHOAI_EXPECTED_API_SERVER"* ]]; then
  echo "ERROR: Active cluster ($ACTUAL_SERVER) does not match guard." >&2
  exit 1
fi

check() {
  local label="$1"
  local result="$2"
  if [[ "$result" == "pass" ]]; then
    echo "✓ $label"
    (( PASS++ )) || true
  else
    echo "✗ $label  ($result)"
    (( FAIL++ )) || true
  fi
}

require_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  echo "ERROR: required command not found: $cmd" >&2
  exit 1
}

crd_exists() {
  local name="$1"
  oc get crd "$name" --insecure-skip-tls-verify=true >/dev/null 2>&1
}

resource_exists() {
  local resource="$1"
  local namespace="$2"
  if [[ -n "$namespace" ]]; then
    oc get "$resource" -n "$namespace" --insecure-skip-tls-verify=true >/dev/null 2>&1
  else
    oc get "$resource" --insecure-skip-tls-verify=true >/dev/null 2>&1
  fi
}

require_cmd curl
require_cmd jq

APP_SYNC=$(oc get application stage-110-rhoai-base-platform -n openshift-gitops \
  -o jsonpath='{.status.sync.status}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
APP_HEALTH=$(oc get application stage-110-rhoai-base-platform -n openshift-gitops \
  -o jsonpath='{.status.health.status}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$APP_SYNC" == "Synced" ]] && R="pass" || R="sync=${APP_SYNC:-not found}"
check "Stage 110 shared owner Application Synced" "$R"
[[ "$APP_HEALTH" == "Healthy" ]] && R="pass" || R="health=${APP_HEALTH:-not found}"
check "Stage 110 shared owner Application Healthy" "$R"

OBS_APP_SYNC=$(oc get application stage-210-model-serving-foundation -n openshift-gitops \
  -o jsonpath='{.status.sync.status}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
OBS_APP_HEALTH=$(oc get application stage-210-model-serving-foundation -n openshift-gitops \
  -o jsonpath='{.status.health.status}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$OBS_APP_SYNC" == "Synced" ]] && R="pass" || R="sync=${OBS_APP_SYNC:-not found}"
check "Stage 210 observability Application Synced" "$R"
[[ "$OBS_APP_HEALTH" == "Healthy" ]] && R="pass" || R="health=${OBS_APP_HEALTH:-not found}"
check "Stage 210 observability Application Healthy" "$R"

DSC_PHASE=$(oc get datasciencecluster default-dsc \
  -o jsonpath='{.status.phase}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$DSC_PHASE" == "Ready" ]] && R="pass" || R="phase=${DSC_PHASE:-not found}"
check "DataScienceCluster Ready" "$R"

DSC_KSERVE=$(oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.kserve.managementState}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$DSC_KSERVE" == "Managed" ]] && R="pass" || R="kserve=${DSC_KSERVE:-not found}"
check "DataScienceCluster KServe is Managed" "$R"

UWM_ENABLED=$(oc get configmap cluster-monitoring-config -n openshift-monitoring \
  -o jsonpath='{.data.config\.yaml}' --insecure-skip-tls-verify=true 2>/dev/null \
  | grep -E 'enableUserWorkload:[[:space:]]*true' || true)
[[ -n "$UWM_ENABLED" ]] && R="pass" || R="missing enableUserWorkload: true"
check "OpenShift user workload monitoring enabled" "$R"

if resource_exists "configmap/user-workload-monitoring-config" "openshift-user-workload-monitoring"; then
  R="pass"
else
  R="missing"
fi
check "User workload monitoring config present" "$R"

if crd_exists inferenceservices.serving.kserve.io; then
  R="pass"
else
  R="missing"
fi
check "InferenceService CRD present" "$R"

if crd_exists servingruntimes.serving.kserve.io; then
  R="pass"
else
  R="missing"
fi
check "ServingRuntime CRD present" "$R"

for crd in grafanas.grafana.integreatly.org grafanadatasources.grafana.integreatly.org grafanadashboards.grafana.integreatly.org; do
  if crd_exists "$crd"; then
    R="pass"
  else
    R="missing"
  fi
  check "Grafana CRD present: ${crd}" "$R"
done

if resource_exists "subscription/grafana" "$GRAFANA_NS"; then
  R="pass"
else
  R="missing"
fi
check "Grafana Operator subscription present" "$R"

GRAFANA_CSV_PHASE=$(oc get csv -n "$GRAFANA_NS" --no-headers \
  --insecure-skip-tls-verify=true 2>/dev/null \
  | awk '$1 ~ /^grafana-operator/ {print $NF; exit}')
[[ "$GRAFANA_CSV_PHASE" == "Succeeded" ]] && R="pass" || R="phase=${GRAFANA_CSV_PHASE:-not found}"
check "Grafana Operator CSV Succeeded" "$R"

if resource_exists "grafana/grafana" "$GRAFANA_NS"; then
  R="pass"
else
  R="missing"
fi
check "Grafana instance present" "$R"

if resource_exists "grafanadatasource/prometheus" "$GRAFANA_NS"; then
  R="pass"
else
  R="missing"
fi
check "Grafana Prometheus datasource present" "$R"

if resource_exists "grafanadashboard/vllm-model-serving-baseline" "$GRAFANA_NS"; then
  R="pass"
else
  R="missing"
fi
check "Grafana vLLM baseline dashboard present" "$R"

if resource_exists "route/grafana-route" "$GRAFANA_NS"; then
  R="pass"
else
  R="missing"
fi
check "Grafana OAuth route present" "$R"

VLLM_RUNTIME=$(oc get servingruntime -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{.metadata.annotations.openshift\.io/display-name}{"\n"}{end}' \
  --insecure-skip-tls-verify=true 2>/dev/null | grep -Ei 'vllm|vLLM' | head -1 || true)
[[ -n "$VLLM_RUNTIME" ]] && R="pass" || R="no vLLM runtime found"
check "vLLM ServingRuntime discoverable" "$R"

GPU_PROFILE=$(oc get hardwareprofile gpu-reserved-demo -n redhat-ods-applications \
  -o jsonpath='{.metadata.name}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$GPU_PROFILE" == "gpu-reserved-demo" ]] && R="pass" || R="missing"
check "Stage 120 GPU Reserved hardware profile present" "$R"

GPU_ALLOCATABLE=$(oc get node -l nvidia.com/gpu.present=true \
  -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' \
  --insecure-skip-tls-verify=true 2>/dev/null | awk '{sum += $1} END {print sum + 0}')
[[ "$GPU_ALLOCATABLE" -ge 4 ]] && R="pass" || R="allocatable=${GPU_ALLOCATABLE:-0}"
check "GPU node advertises at least 4 time-sliced GPU units" "$R"

REGISTRY_AVAILABLE=$(oc get modelregistries.modelregistry.opendatahub.io "$REGISTRY_NAME" -n "$REGISTRY_NS" \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$REGISTRY_AVAILABLE" == "True" ]] && R="pass" || R="available=${REGISTRY_AVAILABLE:-not found}"
check "demo-registry Available" "$R"

REGISTRY_HOST=$(oc get modelregistries.modelregistry.opendatahub.io "$REGISTRY_NAME" -n "$REGISTRY_NS" \
  -o jsonpath='{.status.hosts[0]}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
if [[ -n "$REGISTRY_HOST" ]]; then
  R="pass"
else
  R="missing route host"
fi
check "demo-registry route host present" "$R"

if [[ -n "$REGISTRY_HOST" ]]; then
  MR_BASE_URL="https://${REGISTRY_HOST}/api/model_registry/v1alpha3"
  MR_TOKEN=$(oc whoami -t)
  MR_MODELS=$(curl -sk -H "Authorization: Bearer ${MR_TOKEN}" \
    "${MR_BASE_URL}/registered_models" 2>/dev/null || echo "{}")
  MODEL_ID=$(jq -r --arg name "$MODEL_DISPLAY_NAME" \
    '.items[]? | select(.name == $name and (.state // "LIVE") != "ARCHIVED") | .id' <<<"$MR_MODELS" | head -1)
  [[ -n "$MODEL_ID" ]] && R="pass" || R="missing"
  check "Nemotron registered model metadata present" "$R"

  if [[ -n "$MODEL_ID" ]]; then
    MR_VERSIONS=$(curl -sk -H "Authorization: Bearer ${MR_TOKEN}" \
      "${MR_BASE_URL}/registered_models/${MODEL_ID}/versions" 2>/dev/null || echo "{}")
    MODEL_VERSION_ID=$(jq -r --arg name "$MODEL_VERSION_NAME" \
      '.items[]? | select(.name == $name and (.state // "LIVE") != "ARCHIVED") | .id' <<<"$MR_VERSIONS" | head -1)
    [[ -n "$MODEL_VERSION_ID" ]] && R="pass" || R="missing"
    check "Nemotron model version metadata present" "$R"
  else
    MODEL_VERSION_ID=""
    check "Nemotron model version metadata present" "registered model missing"
  fi

  if [[ -n "$MODEL_VERSION_ID" ]]; then
    MR_ARTIFACTS=$(curl -sk -H "Authorization: Bearer ${MR_TOKEN}" \
      "${MR_BASE_URL}/model_versions/${MODEL_VERSION_ID}/artifacts" 2>/dev/null || echo "{}")
    MODEL_ARTIFACT_ID=$(jq -r --arg uri "$MODEL_URI" \
      '.items[]? | select(.uri == $uri and (.state // "LIVE") != "DELETED") | .id' <<<"$MR_ARTIFACTS" | head -1)
    [[ -n "$MODEL_ARTIFACT_ID" ]] && R="pass" || R="missing"
    check "Nemotron OCI model artifact metadata present" "$R"
  else
    check "Nemotron OCI model artifact metadata present" "model version missing"
  fi
fi

ISVC_READY=$(oc get inferenceservice "$MODEL_DEPLOYMENT_NAME" -n "$MODEL_NS" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$ISVC_READY" == "True" ]] && R="pass" || R="ready=${ISVC_READY:-not found}"
check "Nemotron InferenceService Ready" "$R"

ISVC_RUNTIME=$(oc get inferenceservice "$MODEL_DEPLOYMENT_NAME" -n "$MODEL_NS" \
  -o jsonpath='{.spec.predictor.model.runtime}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ -n "$ISVC_RUNTIME" ]] && R="pass" || R="missing"
check "Nemotron InferenceService runtime selected" "$R"

ISVC_URI=$(oc get inferenceservice "$MODEL_DEPLOYMENT_NAME" -n "$MODEL_NS" \
  -o jsonpath='{.spec.predictor.model.storageUri}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$ISVC_URI" == "$MODEL_URI" ]] && R="pass" || R="uri=${ISVC_URI:-not found}"
check "Nemotron InferenceService uses expected OCI model" "$R"

if resource_exists "servicemonitor/${MODEL_DEPLOYMENT_NAME}-metrics" "$MODEL_NS"; then
  R="pass"
else
  R="missing"
fi
check "Nemotron ServiceMonitor present" "$R"

ISVC_URL=$(oc get inferenceservice "$MODEL_DEPLOYMENT_NAME" -n "$MODEL_NS" \
  -o jsonpath='{.status.url}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
if [[ -n "$ISVC_URL" ]] && curl -ks --max-time 15 "${ISVC_URL}/metrics" \
  | grep -q 'vllm:time_to_first_token_seconds_bucket'; then
  R="pass"
else
  R="missing vLLM metrics"
fi
check "Nemotron endpoint exposes vLLM metrics" "$R"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
