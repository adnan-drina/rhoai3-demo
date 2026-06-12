#!/usr/bin/env bash
# deploy.sh - Stage 230: Models-as-a-Service
# Enables MaaS prerequisites through GitOps, while generating environment-local
# secrets that must never be committed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

if [[ -n "${RHOAI_OPENAI_ENV_FILE:-}" ]]; then
  if [[ ! -f "$RHOAI_OPENAI_ENV_FILE" ]]; then
    echo "ERROR: RHOAI_OPENAI_ENV_FILE points to a missing file." >&2
    exit 1
  fi
  set -a
  # shellcheck source=/dev/null
  source "$RHOAI_OPENAI_ENV_FILE"
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

require_cmd jq
require_cmd oc
require_cmd openssl

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"
MAAS_NS="${RHOAI_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_POSTGRES_SECRET="${RHOAI_MAAS_POSTGRES_SECRET:-maas-postgres-credentials}"
MAAS_POSTGRES_USER="${RHOAI_MAAS_POSTGRES_USER:-maas}"
MAAS_POSTGRES_DATABASE="${RHOAI_MAAS_POSTGRES_DATABASE:-maas}"
MAAS_DB_CONFIG_SECRET="${RHOAI_MAAS_DB_CONFIG_SECRET:-maas-db-config}"
OPENAI_MODEL_ID="${RHOAI_OPENAI_MODEL_ID:-gpt-5.4-nano}"
OPENAI_PROVIDER_SECRET="${RHOAI_OPENAI_PROVIDER_SECRET:-openai-provider-api-key}"
OPENAI_API_KEY_VALUE="${RHOAI_OPENAI_API_KEY:-${OPENAI_API_KEY:-}}"

TMP_FILES=()
cleanup() {
  if ((${#TMP_FILES[@]} > 0)); then
    rm -f "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

wait_for_jsonpath() {
  local label="$1"
  local resource="$2"
  local namespace="$3"
  local jsonpath="$4"
  local expected="$5"
  local attempts="${6:-60}"
  local value=""

  echo "── Waiting for ${label} ──"
  for _ in $(seq 1 "$attempts"); do
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

patch_stage_230_application() {
  local domain hostname patch_body patch_json

  domain="$(oc get ingresscontroller default -n openshift-ingress-operator \
    -o jsonpath='{.status.domain}' --insecure-skip-tls-verify=true)"
  hostname="maas.${domain}"

  patch_body=$(jq -rn \
    --arg hostname "$hostname" \
    '[
      {"op":"replace","path":"/spec/listeners/0/hostname","value":$hostname},
      {"op":"replace","path":"/spec/listeners/1/hostname","value":$hostname},
      {"op":"replace","path":"/spec/listeners/1/tls/certificateRefs/0/name","value":"maas-gateway-tls"}
    ] | map("- op: \(.op)\n  path: \(.path)\n  value: \(.value)") | join("\n")')

  patch_json=$(jq -n --arg patch_body "$patch_body" '{
    spec: {
      source: {
        kustomize: {
          patches: [
            {
              target: {
                group: "gateway.networking.k8s.io",
                version: "v1",
                kind: "Gateway",
                name: "maas-default-gateway",
                namespace: "openshift-ingress"
              },
              patch: $patch_body
            }
          ]
        }
      }
    }
  }')

  oc patch application stage-230-models-as-a-service -n openshift-gitops \
    --type=merge -p "$patch_json" --insecure-skip-tls-verify=true >/dev/null

  echo "✓ Stage 230 Application uses MaaS Gateway hostname=${hostname}, tlsCertificate=maas-gateway-tls"
}

apply_argocd_application() {
  local app_name="$1"
  local manifest_path="$2"
  local app_manifest
  app_manifest=$(mktemp)
  TMP_FILES+=("$app_manifest")

  sed \
    -e "s|repoURL: .*|repoURL: ${GIT_REPO_URL}|" \
    -e "s|targetRevision: .*|targetRevision: ${GIT_REPO_BRANCH}|" \
    "$manifest_path" > "$app_manifest"

  oc apply -f "$app_manifest" --insecure-skip-tls-verify=true

  if [[ "$app_name" == "stage-230-models-as-a-service" ]]; then
    patch_stage_230_application
    oc patch application "$app_name" -n openshift-gitops --type=merge \
      -p '{"operation":null}' \
      --insecure-skip-tls-verify=true >/dev/null 2>&1 || true
  fi

  oc annotate application "$app_name" -n openshift-gitops \
    argocd.argoproj.io/refresh=hard --overwrite \
    --insecure-skip-tls-verify=true >/dev/null
}

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

ensure_maas_secrets() {
  echo "── Ensuring environment-local MaaS database secrets ──"

  oc create namespace "$MAAS_NS" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  local password
  password="$(oc get secret "$MAAS_POSTGRES_SECRET" -n "$MAAS_NS" \
    -o jsonpath='{.data.POSTGRESQL_PASSWORD}' --insecure-skip-tls-verify=true 2>/dev/null \
    | base64 --decode 2>/dev/null || true)"

  if [[ -z "$password" ]]; then
    password="${RHOAI_MAAS_POSTGRES_PASSWORD:-$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32)}"
  fi

  oc create secret generic "$MAAS_POSTGRES_SECRET" \
    -n "$MAAS_NS" \
    --from-literal=POSTGRESQL_USER="$MAAS_POSTGRES_USER" \
    --from-literal=POSTGRESQL_PASSWORD="$password" \
    --from-literal=POSTGRESQL_DATABASE="$MAAS_POSTGRES_DATABASE" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  local encoded_password connection_url
  encoded_password="$(urlencode "$password")"
  connection_url="postgresql://${MAAS_POSTGRES_USER}:${encoded_password}@maas-postgres.${MAAS_NS}.svc.cluster.local:5432/${MAAS_POSTGRES_DATABASE}?sslmode=disable"

  oc create secret generic "$MAAS_DB_CONFIG_SECRET" \
    -n redhat-ods-applications \
    --from-literal=DB_CONNECTION_URL="$connection_url" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  echo "✓ MaaS database credentials and maas-db-config are present"
}

ensure_openai_provider_secret() {
  echo "── Ensuring environment-local OpenAI provider Secret ──"

  oc create namespace "$MAAS_NS" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  if [[ -n "$OPENAI_API_KEY_VALUE" ]]; then
    oc create secret generic "$OPENAI_PROVIDER_SECRET" \
      -n "$MAAS_NS" \
      --from-literal=api-key="$OPENAI_API_KEY_VALUE" \
      --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

    oc label secret "$OPENAI_PROVIDER_SECRET" -n "$MAAS_NS" --overwrite \
      app.kubernetes.io/name="$OPENAI_PROVIDER_SECRET" \
      app.kubernetes.io/component=external-model-provider \
      app.kubernetes.io/part-of=rhoai3-demo \
      demo.rhoai.io/stage=230 \
      demo.rhoai.io/provider=openai \
      --insecure-skip-tls-verify=true >/dev/null

    echo "✓ OpenAI provider Secret is present for ${OPENAI_MODEL_ID}"
    return 0
  fi

  if oc get secret "$OPENAI_PROVIDER_SECRET" -n "$MAAS_NS" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "✓ Existing OpenAI provider Secret found for ${OPENAI_MODEL_ID}"
    return 0
  fi

  echo "ERROR: Missing OpenAI provider Secret ${OPENAI_PROVIDER_SECRET} in ${MAAS_NS}." >&2
  echo "Set OPENAI_API_KEY or RHOAI_OPENAI_API_KEY locally before deploying Stage 230 model publication." >&2
  exit 1
}

if ! oc get crd certificates.cert-manager.io --insecure-skip-tls-verify=true >/dev/null 2>&1; then
  echo "ERROR: cert-manager CRDs are missing. Install cert-manager Operator for Red Hat OpenShift before Stage 230." >&2
  exit 1
fi

if ! oc get certmanager cluster --insecure-skip-tls-verify=true >/dev/null 2>&1; then
  echo "ERROR: cert-manager cluster resource is missing. Configure the cert-manager operand before Stage 230." >&2
  exit 1
fi

ensure_maas_secrets
ensure_openai_provider_secret

echo "── Applying shared Stage 110 Argo CD Application ──"
apply_argocd_application \
  "stage-110-rhoai-base-platform" \
  "$ROOT_DIR/gitops/argocd/app-of-apps/stage-110-rhoai-base-platform.yaml"

echo "── Applying Stage 230 Argo CD Application ──"
apply_argocd_application \
  "stage-230-models-as-a-service" \
  "$ROOT_DIR/gitops/argocd/app-of-apps/stage-230-models-as-a-service.yaml"

wait_for_jsonpath "Stage 110 shared owner Application sync" \
  "application/stage-110-rhoai-base-platform" "openshift-gitops" \
  "{.status.sync.status}" "Synced" 90

wait_for_jsonpath "DataScienceCluster readiness" \
  "datasciencecluster/default-dsc" "" "{.status.phase}" "Ready" 90

wait_for_jsonpath "DataScienceCluster MaaS management" \
  "datasciencecluster/default-dsc" "" \
  "{.spec.components.kserve.modelsAsService.managementState}" "Managed" 60

wait_for_jsonpath "DataScienceCluster Llama Stack Operator management" \
  "datasciencecluster/default-dsc" "" \
  "{.spec.components.llamastackoperator.managementState}" "Managed" 60

wait_for_jsonpath "MaaS PostgreSQL StatefulSet availability" \
  "statefulset/maas-postgres" "$MAAS_NS" \
  "{.status.readyReplicas}" "1" 90

echo "✓ Stage 230 rollout requested"
echo "  Run ./stage-230-models-as-a-service/validate.sh to check MaaS prerequisites, external model publication, and access policy."
