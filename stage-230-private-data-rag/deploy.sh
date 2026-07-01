#!/usr/bin/env bash
# deploy.sh - Stage 230: Private Data RAG
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

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
require_cmd openssl
require_cmd python3

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"
RAG_NS="${RHOAI_STAGE230_NAMESPACE:-enterprise-rag}"
POSTGRES_SECRET="${RHOAI_STAGE230_POSTGRES_SECRET:-private-rag-postgres-credentials}"
POSTGRES_USER="${RHOAI_STAGE230_POSTGRES_USER:-rag}"
POSTGRES_DB="${RHOAI_STAGE230_POSTGRES_DATABASE:-llamastack}"
MILVUS_SECRET="${RHOAI_STAGE230_MILVUS_SECRET:-private-rag-milvus-secret}"
LLAMA_SECRET="${RHOAI_STAGE230_LLAMA_STACK_SECRET:-private-rag-llama-stack-secret}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
MAAS_NS="${RHOAI_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_SUBSCRIPTION="${RHOAI_STAGE230_MAAS_SUBSCRIPTION:-${RHOAI_OPENAI_ACCESS_RESOURCE:-rhoai-developers-gpt-4o-mini}}"
MAAS_API_KEY_NAME="${RHOAI_STAGE230_MAAS_API_KEY_NAME:-stage230-rag-runtime}"
VLLM_MAX_TOKENS="${RHOAI_STAGE230_VLLM_MAX_TOKENS:-1024}"
VLLM_TLS_VERIFY="${RHOAI_STAGE230_VLLM_TLS_VERIFY:-false}"
INFERENCE_MODEL="${RHOAI_STAGE230_INFERENCE_MODEL:-$NEMOTRON_MODEL_RESOURCE}"

TMP_FILES=()
cleanup() {
  if ((${#TMP_FILES[@]} > 0)); then
    rm -f "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

apply_argocd_application() {
  local app_manifest
  app_manifest=$(mktemp)
  TMP_FILES+=("$app_manifest")

  sed \
    -e "s|repoURL: .*|repoURL: ${GIT_REPO_URL}|" \
    -e "s|targetRevision: .*|targetRevision: ${GIT_REPO_BRANCH}|" \
    "$ROOT_DIR/gitops/argocd/app-of-apps/stage-230-private-data-rag.yaml" > "$app_manifest"

  oc apply -f "$app_manifest" --insecure-skip-tls-verify=true
  oc annotate applications.argoproj.io stage-230-private-data-rag -n openshift-gitops \
    argocd.argoproj.io/refresh=hard --overwrite \
    --insecure-skip-tls-verify=true >/dev/null
}

wait_for_namespace() {
  for _ in $(seq 1 30); do
    if oc get namespace "$RAG_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  echo "ERROR: namespace ${RAG_NS} was not created by Argo CD." >&2
  exit 1
}

jsonpath() {
  local resource="$1"
  local namespace="$2"
  local path="$3"
  oc get "$resource" -n "$namespace" -o jsonpath="$path" \
    --insecure-skip-tls-verify=true 2>/dev/null || true
}

get_maas_endpoint() {
  local endpoint
  endpoint=$(jsonpath "maasmodelrefs.maas.opendatahub.io/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.status.endpoint}")
  if [[ -z "$endpoint" ]]; then
    echo "ERROR: MaaS endpoint for ${NEMOTRON_MODEL_RESOURCE} is not ready in ${MAAS_NS}. Deploy and validate Stage 220 first." >&2
    exit 1
  fi
  printf '%s' "$endpoint"
}

get_demo_user_token() {
  local user="$1"
  local password="$2"
  local kubeconfig token

  [[ -n "$password" ]] || return 1
  kubeconfig=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-login.XXXXXX")
  TMP_FILES+=("$kubeconfig")

  oc login "$ACTUAL_SERVER" -u "$user" -p "$password" \
    --kubeconfig "$kubeconfig" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1 || return 1
  token=$(oc --kubeconfig "$kubeconfig" whoami -t \
    --insecure-skip-tls-verify=true 2>/dev/null || true)
  [[ -n "$token" ]] || return 1
  printf '%s' "$token"
}

get_gateway_host_from_endpoint() {
  ENDPOINT="$1" python3 - <<'PY'
import os
from urllib.parse import urlparse

print(urlparse(os.environ["ENDPOINT"]).netloc)
PY
}

normalize_openai_base_url() {
  ENDPOINT="$1" python3 - <<'PY'
import os

endpoint = os.environ["ENDPOINT"].rstrip("/")
if not endpoint.endswith("/v1"):
    endpoint = f"{endpoint}/v1"
print(endpoint)
PY
}

ensure_maas_api_key() {
  local endpoint gateway_host user_token api_key_body status api_key api_key_id existing

  existing=$(jsonpath "secret/${LLAMA_SECRET}" "$RAG_NS" "{.data.VLLM_API_TOKEN}" | base64 --decode 2>/dev/null || true)
  if [[ -n "$existing" && "$existing" == sk-oai-* ]]; then
    printf '%s' "$existing"
    return 0
  fi

  if [[ -n "${RHOAI_STAGE230_MAAS_API_KEY:-}" ]]; then
    printf '%s' "$RHOAI_STAGE230_MAAS_API_KEY"
    return 0
  fi

  user_token=$(get_demo_user_token "ai-developer" "${AI_DEVELOPER_PASSWORD:-}" || true)
  if [[ -z "$user_token" ]]; then
    echo "ERROR: Set RHOAI_STAGE230_MAAS_API_KEY or AI_DEVELOPER_PASSWORD so deploy.sh can create a MaaS API key." >&2
    exit 1
  fi

  endpoint=$(get_maas_endpoint)
  gateway_host=$(get_gateway_host_from_endpoint "$endpoint")
  api_key_body=$(mktemp)
  TMP_FILES+=("$api_key_body")

  status=$(curl -sk --max-time 30 -o "$api_key_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${user_token}" \
    -H "Content-Type: application/json" \
    "https://${gateway_host}/maas-api/v1/api-keys" \
    --data-binary "{\"name\":\"${MAAS_API_KEY_NAME}\",\"subscriptionName\":\"${MAAS_SUBSCRIPTION}\"}" \
    2>/dev/null || true)

  api_key=$(jq -r '.key // empty' "$api_key_body")
  api_key_id=$(jq -r '.id // empty' "$api_key_body")
  if [[ "$status" != "201" || "$api_key" != sk-oai-* ]]; then
    echo "ERROR: failed to create MaaS API key (status=${status}, body=$(head -c 200 "$api_key_body" | tr '\n' ' '))." >&2
    exit 1
  fi

  oc annotate namespace "$RAG_NS" "demo.rhoai.io/stage230-maas-api-key-id=${api_key_id}" \
    --overwrite --insecure-skip-tls-verify=true >/dev/null
  printf '%s' "$api_key"
}

ensure_runtime_secrets() {
  local postgres_password milvus_password maas_endpoint maas_token

  postgres_password=$(jsonpath "secret/${POSTGRES_SECRET}" "$RAG_NS" "{.data.POSTGRESQL_PASSWORD}" | base64 --decode 2>/dev/null || true)
  if [[ -z "$postgres_password" ]]; then
    postgres_password="${RHOAI_STAGE230_POSTGRES_PASSWORD:-$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32)}"
  fi

  oc create secret generic "$POSTGRES_SECRET" \
    -n "$RAG_NS" \
    --from-literal=POSTGRESQL_USER="$POSTGRES_USER" \
    --from-literal=POSTGRESQL_PASSWORD="$postgres_password" \
    --from-literal=POSTGRESQL_DATABASE="$POSTGRES_DB" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  milvus_password=$(jsonpath "secret/${MILVUS_SECRET}" "$RAG_NS" "{.data.root-password}" | base64 --decode 2>/dev/null || true)
  if [[ -z "$milvus_password" ]]; then
    milvus_password="${RHOAI_STAGE230_MILVUS_PASSWORD:-$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32)}"
  fi

  oc create secret generic "$MILVUS_SECRET" \
    -n "$RAG_NS" \
    --from-literal=root-password="$milvus_password" \
    --from-literal=MILVUS_ENDPOINT="tcp://private-rag-milvus.${RAG_NS}.svc.cluster.local:19530" \
    --from-literal=MILVUS_TOKEN="root:${milvus_password}" \
    --from-literal=MILVUS_CONSISTENCY_LEVEL=Bounded \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  maas_endpoint="$(normalize_openai_base_url "${RHOAI_STAGE230_VLLM_URL:-$(get_maas_endpoint)}")"
  maas_token="$(ensure_maas_api_key)"

  oc create secret generic "$LLAMA_SECRET" \
    -n "$RAG_NS" \
    --from-literal=INFERENCE_MODEL="$INFERENCE_MODEL" \
    --from-literal=VLLM_URL="$maas_endpoint" \
    --from-literal=VLLM_API_TOKEN="$maas_token" \
    --from-literal=VLLM_TLS_VERIFY="$VLLM_TLS_VERIFY" \
    --from-literal=VLLM_MAX_TOKENS="$VLLM_MAX_TOKENS" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  oc label secret "$POSTGRES_SECRET" "$MILVUS_SECRET" "$LLAMA_SECRET" -n "$RAG_NS" --overwrite \
    app.kubernetes.io/part-of=rag \
    demo.rhoai.io/stage=230 \
    --insecure-skip-tls-verify=true >/dev/null
  echo "✓ Stage 230 runtime Secrets are present in ${RAG_NS}"
}

apply_argocd_application
wait_for_namespace
ensure_runtime_secrets

oc annotate applications.argoproj.io stage-230-private-data-rag -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite \
  --insecure-skip-tls-verify=true >/dev/null

echo "✓ Stage 230 Application applied. Run ./stage-230-private-data-rag/validate.sh after Argo CD sync completes."
