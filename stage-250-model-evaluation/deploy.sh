#!/usr/bin/env bash
# deploy.sh - Stage 250: Model Evaluation (EvalHub + LMEval + MLflow)
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
EVAL_NS="${RHOAI_STAGE250_NAMESPACE:-model-evaluation}"
MAAS_NS="${RHOAI_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_SUBSCRIPTION="${RHOAI_STAGE250_MAAS_SUBSCRIPTION:-model-evaluation}"
MAAS_API_KEY_NAME="${RHOAI_STAGE250_MAAS_API_KEY_NAME:-stage250-evaluation-runtime}"
MAAS_GATEWAY_SERVICE="${RHOAI_STAGE250_MAAS_GATEWAY_SERVICE:-maas-default-gateway-data-science-gateway-class.openshift-ingress.svc.cluster.local}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
PG_SECRET="${RHOAI_STAGE250_PG_SECRET:-evaluation-postgres-credentials}"
PG_USER="${RHOAI_STAGE250_PG_USER:-evalhub}"
PG_DB="${RHOAI_STAGE250_PG_DATABASE:-evalhub}"
EVALHUB_DB_SECRET="${RHOAI_STAGE250_EVALHUB_DB_SECRET:-evalhub-db-credentials}"
MODEL_TOKEN_SECRET="${RHOAI_STAGE250_MODEL_TOKEN_SECRET:-model-evaluation-model-token}"
EVALHUB_CR="${RHOAI_STAGE250_EVALHUB_CR:-evalhub}"

TMP_FILES=()
cleanup() {
  if ((${#TMP_FILES[@]} > 0)); then
    rm -f "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

jsonpath() {
  local resource="$1"
  local namespace="$2"
  local path="$3"
  oc get "$resource" -n "$namespace" -o jsonpath="$path" \
    --insecure-skip-tls-verify=true 2>/dev/null || true
}

ensure_nemotron_available() {
  # Evaluation jobs call the governed Nemotron model. Scaling GPU is an
  # env-manage-resources decision, so this script only checks readiness.
  local replicas endpoint
  replicas=$(jsonpath "llminferenceservice/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.replicas}")
  if [[ -z "$replicas" || "$replicas" == "0" ]]; then
    cat >&2 <<INSTRUCTIONS
ERROR: Nemotron (${NEMOTRON_MODEL_RESOURCE}) is parked in ${MAAS_NS}.
Un-park the environment first (see .agents/skills/env-manage-resources):
  oc scale machineset <gpu-machineset> -n openshift-machine-api --replicas=1  (cluster-admin)
  wait for the GPU node Ready + NVIDIA operator pods
  oc patch llminferenceservice ${NEMOTRON_MODEL_RESOURCE} -n ${MAAS_NS} --type=merge -p '{"spec":{"replicas":1}}'
  re-run this script.
INSTRUCTIONS
    exit 1
  fi
  echo "   Nemotron is scaled up (replicas=${replicas}); waiting for its MaaS endpoint …"
  for _ in $(seq 1 120); do
    endpoint=$(jsonpath "maasmodelrefs.maas.opendatahub.io/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.status.endpoint}")
    if [[ -n "$endpoint" ]]; then
      echo "✓ Nemotron is available (replicas=${replicas}, endpoint=${endpoint})"
      return 0
    fi
    sleep 30
  done
  echo "ERROR: Nemotron MaaS endpoint did not publish within 60m." >&2
  exit 1
}

apply_argocd_application() {
  local app_manifest
  app_manifest=$(mktemp)
  TMP_FILES+=("$app_manifest")
  sed \
    -e "s|repoURL: .*|repoURL: ${GIT_REPO_URL}|" \
    -e "s|targetRevision: .*|targetRevision: ${GIT_REPO_BRANCH}|" \
    "$ROOT_DIR/gitops/argocd/app-of-apps/stage-250-model-evaluation.yaml" > "$app_manifest"
  oc apply -f "$app_manifest" --insecure-skip-tls-verify=true
  oc annotate applications.argoproj.io stage-250-model-evaluation -n openshift-gitops \
    argocd.argoproj.io/refresh=hard --overwrite --insecure-skip-tls-verify=true >/dev/null
  # Stage 250 lands a MaaSSubscription through stage-220 and the mlflowoperator
  # ignoreDifferences guard through stage-110; refresh both.
  for shared_app in stage-220-models-as-a-service stage-110-rhoai-base-platform; do
    oc annotate applications.argoproj.io "$shared_app" -n openshift-gitops \
      argocd.argoproj.io/refresh=hard --overwrite --insecure-skip-tls-verify=true >/dev/null 2>&1 || true
  done
}

wait_for_namespace() {
  for _ in $(seq 1 30); do
    if oc get namespace "$EVAL_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  echo "ERROR: namespace ${EVAL_NS} was not created by Argo CD." >&2
  exit 1
}

wait_for_maas_subscription() {
  for _ in $(seq 1 36); do
    if oc get maassubscription "$MAAS_SUBSCRIPTION" -n "$MAAS_NS" \
      --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      echo "✓ MaaSSubscription ${MAAS_SUBSCRIPTION} is present in ${MAAS_NS}"
      return 0
    fi
    sleep 5
  done
  echo "ERROR: MaaSSubscription ${MAAS_SUBSCRIPTION} did not appear; check the stage-220 sync." >&2
  exit 1
}

get_maas_endpoint() {
  local model="${1:-$NEMOTRON_MODEL_RESOURCE}"
  local endpoint
  endpoint=$(jsonpath "maasmodelrefs.maas.opendatahub.io/${model}" "$MAAS_NS" "{.status.endpoint}")
  if [[ -z "$endpoint" ]]; then
    echo "ERROR: MaaS endpoint for ${model} is not ready in ${MAAS_NS}." >&2
    exit 1
  fi
  printf '%s' "$endpoint"
}

get_demo_user_token() {
  local user="$1"
  local password="$2"
  local kubeconfig token
  [[ -n "$password" ]] || return 1
  kubeconfig=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage250-login.XXXXXX")
  TMP_FILES+=("$kubeconfig")
  oc login "$ACTUAL_SERVER" -u "$user" -p "$password" \
    --kubeconfig "$kubeconfig" --insecure-skip-tls-verify=true >/dev/null 2>&1 || return 1
  token=$(oc --kubeconfig "$kubeconfig" whoami -t --insecure-skip-tls-verify=true 2>/dev/null || true)
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

ensure_db_secrets() {
  # PostgreSQL backs the EvalHub server. The StatefulSet consumes discrete
  # POSTGRESQL_* keys; EvalHub consumes a single pre-composed db-url key. Both
  # Secrets share one generated password and are never committed.
  local pg_password
  pg_password=$(jsonpath "secret/${PG_SECRET}" "$EVAL_NS" "{.data.POSTGRESQL_PASSWORD}" | base64 --decode 2>/dev/null || true)
  if [[ -z "$pg_password" ]]; then
    pg_password="${RHOAI_STAGE250_PG_PASSWORD:-$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32)}"
  fi

  oc create secret generic "$PG_SECRET" \
    -n "$EVAL_NS" \
    --from-literal=POSTGRESQL_USER="$PG_USER" \
    --from-literal=POSTGRESQL_PASSWORD="$pg_password" \
    --from-literal=POSTGRESQL_DATABASE="$PG_DB" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  local db_url="postgresql://${PG_USER}:${pg_password}@evaluation-postgres.${EVAL_NS}.svc.cluster.local:5432/${PG_DB}?sslmode=disable"
  oc create secret generic "$EVALHUB_DB_SECRET" \
    -n "$EVAL_NS" \
    --from-literal=db-url="$db_url" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  oc label secret "$PG_SECRET" "$EVALHUB_DB_SECRET" -n "$EVAL_NS" --overwrite \
    app.kubernetes.io/part-of=evaluation demo.rhoai.io/stage=250 \
    --insecure-skip-tls-verify=true >/dev/null
  echo "✓ EvalHub database Secrets are present in ${EVAL_NS}"
}

ensure_maas_proxy_config() {
  local gateway_host proxy_conf
  gateway_host=$(get_gateway_host_from_endpoint "$(get_maas_endpoint "$NEMOTRON_MODEL_RESOURCE")")
  proxy_conf=$(mktemp)
  TMP_FILES+=("$proxy_conf")
  cat > "$proxy_conf" <<EOF
server {
  listen 8081;
  location = /healthz {
    return 200 'ok';
  }
  location / {
    proxy_pass https://${MAAS_GATEWAY_SERVICE}:443;
    proxy_ssl_server_name on;
    proxy_ssl_name ${gateway_host};
    proxy_set_header Host ${gateway_host};
    proxy_ssl_verify off;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_read_timeout 300s;
    proxy_connect_timeout 10s;
    proxy_buffering off;
  }
}
EOF
  oc create configmap maas-internal-proxy-config \
    -n "$EVAL_NS" \
    --from-file=maas-proxy.conf="$proxy_conf" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null
  oc label configmap maas-internal-proxy-config -n "$EVAL_NS" --overwrite \
    app.kubernetes.io/part-of=evaluation demo.rhoai.io/stage=250 \
    --insecure-skip-tls-verify=true >/dev/null
  oc rollout restart deployment/maas-internal-proxy -n "$EVAL_NS" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1 || true
  echo "✓ MaaS internal proxy config targets ${gateway_host}"
}

ensure_model_token() {
  # Mint (or reuse) a governed MaaS API key for the evaluation subscription
  # and store it for EvalHub jobs and the LMEvalJob to authenticate to
  # Nemotron. Never committed.
  local existing existing_subscription user_token endpoint gateway_host api_key_body status api_key api_key_id token
  existing=$(jsonpath "secret/${MODEL_TOKEN_SECRET}" "$EVAL_NS" "{.data.token}" | base64 --decode 2>/dev/null || true)
  existing_subscription=$(jsonpath "secret/${MODEL_TOKEN_SECRET}" "$EVAL_NS" "{.data.MAAS_SUBSCRIPTION}" | base64 --decode 2>/dev/null || true)
  if [[ -n "$existing" && "$existing" == sk-oai-* && "$existing_subscription" == "$MAAS_SUBSCRIPTION" ]]; then
    token="$existing"
  elif [[ -n "${RHOAI_STAGE250_MAAS_API_KEY:-}" ]]; then
    token="$RHOAI_STAGE250_MAAS_API_KEY"
  else
    user_token=$(get_demo_user_token "ai-developer" "${AI_DEVELOPER_PASSWORD:-}" || true)
    if [[ -z "$user_token" ]]; then
      echo "ERROR: Set RHOAI_STAGE250_MAAS_API_KEY or AI_DEVELOPER_PASSWORD so deploy.sh can create a MaaS API key." >&2
      exit 1
    fi
    endpoint=$(get_maas_endpoint)
    gateway_host=$(get_gateway_host_from_endpoint "$endpoint")
    api_key_body=$(mktemp)
    TMP_FILES+=("$api_key_body")
    status=$(curl -sk --max-time 30 -o "$api_key_body" -w '%{http_code}' \
      -H "Authorization: Bearer ${user_token}" -H "Content-Type: application/json" \
      "https://${gateway_host}/maas-api/v1/api-keys" \
      --data-binary "{\"name\":\"${MAAS_API_KEY_NAME}\",\"subscriptionName\":\"${MAAS_SUBSCRIPTION}\"}" \
      2>/dev/null || true)
    api_key=$(jq -r '.key // empty' "$api_key_body")
    api_key_id=$(jq -r '.id // empty' "$api_key_body")
    if [[ "$status" != "201" || "$api_key" != sk-oai-* ]]; then
      echo "ERROR: failed to create MaaS API key (status=${status}, body=$(head -c 200 "$api_key_body" | tr '\n' ' '))." >&2
      exit 1
    fi
    oc annotate namespace "$EVAL_NS" "demo.rhoai.io/stage250-maas-api-key-id=${api_key_id}" \
      --overwrite --insecure-skip-tls-verify=true >/dev/null
    token="$api_key"
  fi

  # Keys: `token` (LMEvalJob OPENAI_API_KEY env), `api-key` (EvalHub
  # model.auth.secret_ref for garak-kfp target/judge models), and
  # MAAS_SUBSCRIPTION (reuse gate). One key covers Nemotron + gpt-4o-mini
  # on this subscription.
  oc create secret generic "$MODEL_TOKEN_SECRET" \
    -n "$EVAL_NS" \
    --from-literal=token="$token" \
    --from-literal=api-key="$token" \
    --from-literal=MAAS_SUBSCRIPTION="$MAAS_SUBSCRIPTION" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null
  oc label secret "$MODEL_TOKEN_SECRET" -n "$EVAL_NS" --overwrite \
    app.kubernetes.io/part-of=evaluation demo.rhoai.io/stage=250 \
    --insecure-skip-tls-verify=true >/dev/null
  echo "✓ Model API token Secret is present in ${EVAL_NS}"
}

wait_for_object_bucket() {
  # The garak-kfp pipeline server (DSPA) and risk-assessment artifacts use
  # the NooBaa-generated S3 bucket. NooBaa creates the Secret/ConfigMap
  # named model-evaluation-bucket; the DSPA references it directly.
  local phase
  for _ in $(seq 1 60); do
    phase=$(jsonpath "obc/model-evaluation-bucket" "$EVAL_NS" "{.status.phase}")
    [[ "$phase" == "Bound" ]] && { echo "✓ ObjectBucketClaim model-evaluation-bucket is Bound"; return 0; }
    sleep 5
  done
  echo "! ObjectBucketClaim model-evaluation-bucket is not Bound (phase=${phase:-missing}); garak-kfp risk assessment will not run until it binds." >&2
}

wait_for_dspa() {
  # garak-kfp submits to the DSPA KFP API server. aipipelines is already
  # Managed; wait for the pipeline server to come up.
  local ready
  for _ in $(seq 1 60); do
    ready=$(jsonpath "datasciencepipelinesapplications/dspa-model-evaluation" "$EVAL_NS" "{.status.conditions[?(@.type=='APIServerReady')].status}")
    [[ "$ready" == "True" ]] && { echo "✓ DSPA pipeline server (dspa-model-evaluation) is ready"; return 0; }
    sleep 10
  done
  echo "! DSPA pipeline server is not ready yet; garak-kfp risk assessment needs it (see submit-risk-assessment.sh)." >&2
}

wait_for_mlflow() {
  local state
  echo "   Waiting for the MLflow component …"
  for _ in $(seq 1 60); do
    state=$(jsonpath "datasciencecluster/default-dsc" "" "{.spec.components.mlflowoperator.managementState}")
    [[ "$state" == "Managed" ]] && break
    sleep 5
  done
  if [[ "$state" != "Managed" ]]; then
    echo "ERROR: DataScienceCluster mlflowoperator is not Managed; check the stage-250 DSC patch Job." >&2
    exit 1
  fi
  echo "✓ DataScienceCluster mlflowoperator is Managed"

  local avail
  for _ in $(seq 1 60); do
    avail=$(jsonpath "mlflow/mlflow" "" "{.status.conditions[?(@.type=='Available')].status}")
    [[ "$avail" == "True" ]] && break
    sleep 10
  done
  if [[ "$avail" == "True" ]]; then
    echo "✓ MLflow is Available"
  else
    echo "! MLflow is not Available yet; continuing (tracking may lag)." >&2
  fi
}

wait_for_evalhub() {
  local phase
  echo "   Waiting for the EvalHub service …"
  for _ in $(seq 1 90); do
    phase=$(jsonpath "evalhub/${EVALHUB_CR}" "$EVAL_NS" "{.status.conditions[?(@.type=='Available')].status}")
    [[ "$phase" == "True" ]] && break
    # Some builds report readiness under .status.phase; accept either.
    phase=$(jsonpath "evalhub/${EVALHUB_CR}" "$EVAL_NS" "{.status.phase}")
    [[ "$phase" == "Ready" || "$phase" == "Running" ]] && break
    sleep 10
  done
  if oc rollout status deployment/evalhub -n "$EVAL_NS" --timeout=300s --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "✓ EvalHub deployment is available"
  else
    echo "! EvalHub deployment is not ready yet; check the EvalHub CR and DB Secret." >&2
  fi
}

ensure_nemotron_available
apply_argocd_application
wait_for_namespace
wait_for_maas_subscription
ensure_db_secrets
ensure_maas_proxy_config
ensure_model_token
wait_for_object_bucket
wait_for_dspa
wait_for_mlflow
wait_for_evalhub

oc annotate applications.argoproj.io stage-250-model-evaluation -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite --insecure-skip-tls-verify=true >/dev/null

echo "✓ Stage 250 Application applied. Run ./stage-250-model-evaluation/validate.sh after Argo CD sync completes."
