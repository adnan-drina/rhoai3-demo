#!/usr/bin/env bash
# validate.sh - Stage 210: Model Serving Foundation
# Proves the KServe model serving platform is enabled through the shared DSC.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

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

crd_exists() {
  local name="$1"
  oc get crd "$name" --insecure-skip-tls-verify=true >/dev/null 2>&1
}

APP_SYNC=$(oc get application stage-110-rhoai-base-platform -n openshift-gitops \
  -o jsonpath='{.status.sync.status}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
APP_HEALTH=$(oc get application stage-110-rhoai-base-platform -n openshift-gitops \
  -o jsonpath='{.status.health.status}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$APP_SYNC" == "Synced" ]] && R="pass" || R="sync=${APP_SYNC:-not found}"
check "Stage 110 shared owner Application Synced" "$R"
[[ "$APP_HEALTH" == "Healthy" ]] && R="pass" || R="health=${APP_HEALTH:-not found}"
check "Stage 110 shared owner Application Healthy" "$R"

DSC_PHASE=$(oc get datasciencecluster default-dsc \
  -o jsonpath='{.status.phase}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$DSC_PHASE" == "Ready" ]] && R="pass" || R="phase=${DSC_PHASE:-not found}"
check "DataScienceCluster Ready" "$R"

DSC_KSERVE=$(oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.kserve.managementState}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$DSC_KSERVE" == "Managed" ]] && R="pass" || R="kserve=${DSC_KSERVE:-not found}"
check "DataScienceCluster KServe is Managed" "$R"

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

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
