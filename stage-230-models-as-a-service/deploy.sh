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

TMP_FILES=()
cleanup() {
  rm -f "${TMP_FILES[@]}"
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

ensure_maas_secrets

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

echo "✓ Stage 230 prerequisite rollout requested"
echo "  Run ./stage-230-models-as-a-service/validate.sh to check CRD readiness before authoring model subscriptions."
