#!/usr/bin/env bash
# deploy.sh - Stage 210: Model Serving Foundation
# Reconciles the shared Stage 110 RHOAI owner, then ensures the demo registry,
# Nemotron registry metadata, and vLLM endpoint exist for fresh environments.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

REGISTRY_NS="${MODEL_REGISTRY_NAMESPACE:-rhoai-model-registries}"
REGISTRY_NAME="${MODEL_REGISTRY_NAME:-demo-registry}"
MODEL_NS="${RHOAI_MODEL_NAMESPACE:-demo-sandbox}"
MODEL_DEPLOYMENT_NAME="${RHOAI_NEMOTRON_DEPLOYMENT_NAME:-nvidia-nemotron-3-nano-30b-a3b}"
MODEL_DISPLAY_NAME="${RHOAI_NEMOTRON_DISPLAY_NAME:-NVIDIA-Nemotron-3-Nano-30B-A3B-FP8}"
MODEL_VERSION_NAME="${RHOAI_NEMOTRON_VERSION_NAME:-Version 1}"
MODEL_URI="${RHOAI_NEMOTRON_MODEL_URI:-oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0}"
MODEL_SOURCE_NAME="${RHOAI_NEMOTRON_SOURCE_NAME:-RedHatAI/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8}"
MODEL_PULL_SECRET="${RHOAI_NEMOTRON_PULL_SECRET:-nemotron-3-nano-30b}"
MODEL_RUNTIME_NAME="${RHOAI_NEMOTRON_RUNTIME_NAME:-vllm-cuda-runtime}"
MODEL_QUEUE_NAME="${RHOAI_NEMOTRON_QUEUE_NAME:-lq-gpu-reserved-demo}"
MODEL_HARDWARE_PROFILE="${RHOAI_NEMOTRON_HARDWARE_PROFILE:-gpu-reserved-demo}"

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
MODEL_SOURCE_NAME="${RHOAI_NEMOTRON_SOURCE_NAME:-$MODEL_SOURCE_NAME}"
MODEL_PULL_SECRET="${RHOAI_NEMOTRON_PULL_SECRET:-$MODEL_PULL_SECRET}"
MODEL_RUNTIME_NAME="${RHOAI_NEMOTRON_RUNTIME_NAME:-$MODEL_RUNTIME_NAME}"
MODEL_QUEUE_NAME="${RHOAI_NEMOTRON_QUEUE_NAME:-$MODEL_QUEUE_NAME}"
MODEL_HARDWARE_PROFILE="${RHOAI_NEMOTRON_HARDWARE_PROFILE:-$MODEL_HARDWARE_PROFILE}"

if [[ -z "${RHOAI_EXPECTED_API_SERVER:-}" ]]; then
  echo "ERROR: RHOAI_EXPECTED_API_SERVER is not set." >&2
  exit 1
fi

ACTUAL_SERVER=$(oc whoami --show-server 2>/dev/null || true)
if [[ "$ACTUAL_SERVER" != *"$RHOAI_EXPECTED_API_SERVER"* ]]; then
  echo "ERROR: Active cluster ($ACTUAL_SERVER) does not match RHOAI_EXPECTED_API_SERVER." >&2
  exit 1
fi

echo "✓ Cluster guard passed: $ACTUAL_SERVER"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd jq
require_cmd oc

wait_for_jsonpath() {
  local label="$1"
  local resource="$2"
  local namespace="$3"
  local jsonpath="$4"
  local expected="$5"
  local value=""

  echo "── Waiting for ${label} ──"
  for _ in $(seq 1 60); do
    if [[ -n "$namespace" ]]; then
      value=$(oc get "$resource" -n "$namespace" \
        -o jsonpath="$jsonpath" --insecure-skip-tls-verify=true 2>/dev/null || true)
    else
      value=$(oc get "$resource" \
        -o jsonpath="$jsonpath" --insecure-skip-tls-verify=true 2>/dev/null || true)
    fi
    if [[ "$value" == "$expected" ]]; then
      echo "✓ ${label}: ${value}"
      return 0
    fi
    sleep 10
  done

  echo "ERROR: ${label} did not reach ${expected} (last value: ${value:-missing})." >&2
  return 1
}

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"

APP_MANIFEST=$(mktemp)
TMP_FILES=("$APP_MANIFEST")
cleanup() {
  rm -f "${TMP_FILES[@]}"
}
trap cleanup EXIT

sed \
  -e "s|repoURL: .*|repoURL: ${GIT_REPO_URL}|" \
  -e "s|targetRevision: .*|targetRevision: ${GIT_REPO_BRANCH}|" \
  "$ROOT_DIR/gitops/argocd/app-of-apps/stage-110-rhoai-base-platform.yaml" \
  > "$APP_MANIFEST"

echo "── Applying shared Stage 110 Argo CD Application ──"
oc apply -f "$APP_MANIFEST" --insecure-skip-tls-verify=true

echo "── Requesting Argo CD refresh for shared RHOAI owner ──"
oc annotate application stage-110-rhoai-base-platform -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite \
  --insecure-skip-tls-verify=true >/dev/null

echo "✓ Application stage-110-rhoai-base-platform applied"
echo "  Argo CD will reconcile the Stage 210 KServe patch through the shared DSC owner."

wait_for_jsonpath "Stage 110 shared owner Application sync" \
  "application/stage-110-rhoai-base-platform" "openshift-gitops" \
  "{.status.sync.status}" "Synced"

wait_for_jsonpath "Stage 110 shared owner Application health" \
  "application/stage-110-rhoai-base-platform" "openshift-gitops" \
  "{.status.health.status}" "Healthy"

wait_for_jsonpath "DataScienceCluster readiness" \
  "datasciencecluster/default-dsc" "" "{.status.phase}" "Ready"

wait_for_jsonpath "DataScienceCluster KServe management" \
  "datasciencecluster/default-dsc" "" "{.spec.components.kserve.managementState}" "Managed"

wait_for_jsonpath "demo-registry availability" \
  "modelregistries.modelregistry.opendatahub.io/${REGISTRY_NAME}" "$REGISTRY_NS" \
  "{.status.conditions[?(@.type==\"Available\")].status}" "True"

registry_host() {
  oc get modelregistries.modelregistry.opendatahub.io "$REGISTRY_NAME" -n "$REGISTRY_NS" \
    -o jsonpath='{.status.hosts[0]}' --insecure-skip-tls-verify=true
}

MR_HOST="$(registry_host)"
if [[ -z "$MR_HOST" ]]; then
  echo "ERROR: ${REGISTRY_NAME} has no route host in status.hosts." >&2
  exit 1
fi
MR_BASE_URL="https://${MR_HOST}/api/model_registry/v1alpha3"
MR_TOKEN="$(oc whoami -t)"

mr_get() {
  local endpoint="$1"
  curl -sk -H "Authorization: Bearer ${MR_TOKEN}" \
    "${MR_BASE_URL}${endpoint}"
}

mr_post() {
  local endpoint="$1"
  local payload="$2"
  local response_file
  response_file=$(mktemp)

  local code
  code=$(curl -sk -o "$response_file" -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${MR_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "$payload" \
    "${MR_BASE_URL}${endpoint}")

  if [[ "$code" != "200" && "$code" != "201" && "$code" != "409" ]]; then
    echo "ERROR: model registry POST ${endpoint} failed with HTTP ${code}." >&2
    sed -n '1,20p' "$response_file" >&2
    rm -f "$response_file"
    exit 1
  fi
  cat "$response_file"
  rm -f "$response_file"
}

metadata_string() {
  jq -n --arg value "$1" '{metadataType: "MetadataStringValue", string_value: $value}'
}

ensure_registered_model() {
  local id
  id=$(mr_get "/registered_models" | jq -r --arg name "$MODEL_DISPLAY_NAME" \
    '.items[]? | select(.name == $name and (.state // "LIVE") != "ARCHIVED") | .id' | head -1)
  if [[ -n "$id" ]]; then
    echo "✓ Registered model already present: ${MODEL_DISPLAY_NAME} (id=${id})"
    echo "$id"
    return 0
  fi

  echo "── Creating registered model metadata ──"
  local payload
  payload=$(jq -n \
    --arg name "$MODEL_DISPLAY_NAME" \
    --arg description "NVIDIA Nemotron 3 Nano 30B A3B FP8 model used by the RHOAI demo vLLM serving baseline." \
    --arg owner "rhoai3-demo" \
    --arg provider "NVIDIA" \
    --arg license "NVIDIA Open Model License" \
    --arg licenseLink "https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/" \
    '{
      name: $name,
      description: $description,
      owner: $owner,
      provider: $provider,
      license: $license,
      licenseLink: $licenseLink,
      tasks: ["text-generation", "text-to-text"],
      customProperties: {
        nvidia: {metadataType: "MetadataStringValue", string_value: ""},
        "text-generation": {metadataType: "MetadataStringValue", string_value: ""},
        "text-to-text": {metadataType: "MetadataStringValue", string_value: ""},
        validated: {metadataType: "MetadataStringValue", string_value: ""}
      }
    }')
  id=$(mr_post "/registered_models" "$payload" | jq -r '.id // empty')
  if [[ -z "$id" ]]; then
    id=$(mr_get "/registered_models" | jq -r --arg name "$MODEL_DISPLAY_NAME" \
      '.items[]? | select(.name == $name and (.state // "LIVE") != "ARCHIVED") | .id' | head -1)
  fi
  [[ -n "$id" ]] || { echo "ERROR: unable to create registered model metadata." >&2; exit 1; }
  echo "✓ Registered model created: ${MODEL_DISPLAY_NAME} (id=${id})"
  echo "$id"
}

ensure_model_version() {
  local registered_model_id="$1"
  local id
  id=$(mr_get "/registered_models/${registered_model_id}/versions" | jq -r --arg name "$MODEL_VERSION_NAME" \
    '.items[]? | select(.name == $name and (.state // "LIVE") != "ARCHIVED") | .id' | head -1)
  if [[ -n "$id" ]]; then
    echo "✓ Model version already present: ${MODEL_VERSION_NAME} (id=${id})"
    echo "$id"
    return 0
  fi

  echo "── Creating model version metadata ──"
  local payload
  payload=$(jq -n \
    --arg name "$MODEL_VERSION_NAME" \
    --arg registeredModelId "$registered_model_id" \
    --arg author "rhoai3-demo" \
    '{
      name: $name,
      registeredModelId: $registeredModelId,
      author: $author,
      customProperties: {
        Provider: {metadataType: "MetadataStringValue", string_value: "NVIDIA"},
        License: {metadataType: "MetadataStringValue", string_value: "https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/"},
        model_type: {metadataType: "MetadataStringValue", string_value: "generative"},
        size: {metadataType: "MetadataStringValue", string_value: "30B"},
        tensor_type: {metadataType: "MetadataStringValue", string_value: "FP8"},
        nvidia: {metadataType: "MetadataStringValue", string_value: ""},
        "text-generation": {metadataType: "MetadataStringValue", string_value: ""},
        "text-to-text": {metadataType: "MetadataStringValue", string_value: ""},
        "tool-calling": {metadataType: "MetadataStringValue", string_value: ""},
        reasoning: {metadataType: "MetadataStringValue", string_value: ""},
        validated: {metadataType: "MetadataStringValue", string_value: ""}
      }
    }')
  id=$(mr_post "/model_versions" "$payload" | jq -r '.id // empty')
  [[ -n "$id" ]] || { echo "ERROR: unable to create model version metadata." >&2; exit 1; }
  echo "✓ Model version created: ${MODEL_VERSION_NAME} (id=${id})"
  echo "$id"
}

ensure_model_artifact() {
  local model_version_id="$1"
  local id
  id=$(mr_get "/model_versions/${model_version_id}/artifacts" | jq -r --arg uri "$MODEL_URI" \
    '.items[]? | select(.uri == $uri and (.state // "LIVE") != "DELETED") | .id' | head -1)
  if [[ -n "$id" ]]; then
    echo "✓ Model artifact already present: ${MODEL_URI} (id=${id})"
    echo "$id"
    return 0
  fi

  echo "── Creating model artifact metadata ──"
  local payload
  payload=$(jq -n \
    --arg name "$MODEL_VERSION_NAME" \
    --arg uri "$MODEL_URI" \
    --arg modelSourceName "$MODEL_SOURCE_NAME" \
    '{
      name: $name,
      artifactType: "model-artifact",
      uri: $uri,
      state: "LIVE",
      modelSourceKind: "catalog",
      modelSourceClass: "redhat_ai_validated_models",
      modelSourceName: $modelSourceName
    }')
  id=$(mr_post "/model_versions/${model_version_id}/artifacts" "$payload" | jq -r '.id // empty')
  [[ -n "$id" ]] || { echo "ERROR: unable to create model artifact metadata." >&2; exit 1; }
  echo "✓ Model artifact created: ${MODEL_URI} (id=${id})"
  echo "$id"
}

ensure_serving_environment_metadata() {
  local id
  id=$(mr_get "/serving_environments" | jq -r --arg name "$MODEL_NS" \
    '.items[]? | select(.name == $name) | .id' | head -1)
  if [[ -n "$id" ]]; then
    echo "✓ Serving environment metadata already present: ${MODEL_NS} (id=${id})"
    echo "$id"
    return 0
  fi

  local payload
  payload=$(jq -n --arg name "$MODEL_NS" --arg description "RHOAI demo project for model serving baseline." \
    '{name: $name, description: $description}')
  id=$(mr_post "/serving_environments" "$payload" | jq -r '.id // empty')
  [[ -n "$id" ]] || { echo "ERROR: unable to create serving environment metadata." >&2; exit 1; }
  echo "✓ Serving environment metadata created: ${MODEL_NS} (id=${id})"
  echo "$id"
}

ensure_registry_metadata() {
  echo "── Ensuring Nemotron registry metadata ──"
  local registered_model_id model_version_id artifact_id serving_environment_id
  registered_model_id=$(ensure_registered_model | tail -1)
  model_version_id=$(ensure_model_version "$registered_model_id" | tail -1)
  artifact_id=$(ensure_model_artifact "$model_version_id" | tail -1)
  serving_environment_id=$(ensure_serving_environment_metadata | tail -1)

  echo "✓ Registry metadata ready: model=${registered_model_id}, version=${model_version_id}, artifact=${artifact_id}, environment=${serving_environment_id}"
}

ensure_pull_secret() {
  if oc get secret "$MODEL_PULL_SECRET" -n "$MODEL_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "✓ Model pull secret already present: ${MODEL_NS}/${MODEL_PULL_SECRET}"
    return 0
  fi

  echo "── Creating model pull secret from cluster pull-secret ──"
  oc get secret pull-secret -n openshift-config -o json --insecure-skip-tls-verify=true \
    | jq --arg name "$MODEL_PULL_SECRET" --arg namespace "$MODEL_NS" \
      '{
        apiVersion: "v1",
        kind: "Secret",
        metadata: {name: $name, namespace: $namespace},
        type: .type,
        data: {".dockerconfigjson": .data[".dockerconfigjson"]}
      }' \
    | oc apply -f - --insecure-skip-tls-verify=true >/dev/null
  echo "✓ Model pull secret created: ${MODEL_NS}/${MODEL_PULL_SECRET}"
}

ensure_serving_runtime() {
  if oc get servingruntime "$MODEL_RUNTIME_NAME" -n "$MODEL_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "✓ ServingRuntime already present: ${MODEL_NS}/${MODEL_RUNTIME_NAME}"
    echo "$MODEL_RUNTIME_NAME"
    return 0
  fi

  if oc get template vllm-cuda-runtime-template -n redhat-ods-applications --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "── Creating vLLM ServingRuntime from Red Hat OpenShift AI template ──"
    oc process vllm-cuda-runtime-template -n redhat-ods-applications --insecure-skip-tls-verify=true \
      | oc apply -n "$MODEL_NS" -f - --insecure-skip-tls-verify=true >/dev/null
    echo "✓ ServingRuntime created: ${MODEL_NS}/${MODEL_RUNTIME_NAME}"
    echo "$MODEL_RUNTIME_NAME"
    return 0
  fi

  echo "ERROR: vllm-cuda-runtime-template not found in redhat-ods-applications." >&2
  exit 1
}

ensure_inference_service() {
  if oc get inferenceservice "$MODEL_DEPLOYMENT_NAME" -n "$MODEL_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "✓ InferenceService already present: ${MODEL_NS}/${MODEL_DEPLOYMENT_NAME}"
    return 0
  fi

  local runtime_name="$1"

  ensure_pull_secret

  echo "── Creating Nemotron InferenceService ──"
  oc apply -f - --insecure-skip-tls-verify=true <<EOF
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: ${MODEL_DEPLOYMENT_NAME}
  namespace: ${MODEL_NS}
  labels:
    opendatahub.io/dashboard: "true"
    networking.kserve.io/visibility: exposed
    kueue.x-k8s.io/queue-name: ${MODEL_QUEUE_NAME}
  annotations:
    openshift.io/display-name: "${MODEL_DISPLAY_NAME} - ${MODEL_VERSION_NAME}"
    openshift.io/description: "Nemotron vLLM endpoint for the Stage 210 model serving baseline."
    opendatahub.io/model-type: generative
    opendatahub.io/hardware-profile-name: ${MODEL_HARDWARE_PROFILE}
    opendatahub.io/hardware-profile-namespace: redhat-ods-applications
    modelFormat: vLLM
    serving.kserve.io/deploymentMode: Standard
    security.opendatahub.io/enable-auth: "false"
spec:
  predictor:
    automountServiceAccountToken: false
    deploymentStrategy:
      type: Recreate
    imagePullSecrets:
      - name: ${MODEL_PULL_SECRET}
    minReplicas: 1
    maxReplicas: 1
    model:
      args:
        - --trust-remote-code
      modelFormat:
        name: vLLM
      resources:
        requests:
          cpu: "2"
          memory: 8Gi
          nvidia.com/gpu: "1"
        limits:
          cpu: "2"
          memory: 8Gi
          nvidia.com/gpu: "1"
      runtime: ${runtime_name}
      storageUri: ${MODEL_URI}
    timeout: 30
EOF
  echo "✓ InferenceService created: ${MODEL_NS}/${MODEL_DEPLOYMENT_NAME}"
}

ensure_registry_metadata
runtime_name=$(ensure_serving_runtime | tail -1)
ensure_inference_service "$runtime_name"

wait_for_jsonpath "Nemotron InferenceService readiness" \
  "inferenceservice/${MODEL_DEPLOYMENT_NAME}" "$MODEL_NS" \
  "{.status.conditions[?(@.type==\"Ready\")].status}" "True"

echo "✓ Stage 210 deployment baseline is ready"
echo "  Run ./stage-210-model-serving-foundation/validate.sh to confirm readiness."
