#!/usr/bin/env bash
# deploy.sh - Stage 240: Guardrails and Safety
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
require_cmd python3

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"
SAFETY_NS="${RHOAI_STAGE240_NAMESPACE:-ai-safety}"
RAG_NS="${RHOAI_STAGE230_NAMESPACE:-enterprise-rag}"
MAAS_NS="${RHOAI_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_SUBSCRIPTION="${RHOAI_STAGE240_MAAS_SUBSCRIPTION:-ai-safety-guardrails}"
MAAS_API_KEY_NAME="${RHOAI_STAGE240_MAAS_API_KEY_NAME:-stage240-guardrails-runtime}"
MAAS_GATEWAY_SERVICE="${RHOAI_STAGE240_MAAS_GATEWAY_SERVICE:-maas-default-gateway-data-science-gateway-class.openshift-ingress.svc.cluster.local}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
NEMO_CR="${RHOAI_STAGE240_NEMO_CR:-nemo-guardrails}"
NEMO_SECRET="${RHOAI_STAGE240_NEMO_SECRET:-nemo-guardrails-api-token}"
LSD_DEPLOYMENT="${RHOAI_STAGE230_LSD_DEPLOYMENT:-lsd-enterprise-rag}"

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
  # Guarded LLM calls need the local Nemotron model. Scaling the GPU
  # MachineSet costs money and is an env-manage-resources decision, so this
  # script only checks readiness and never scales infrastructure itself.
  local replicas endpoint
  replicas=$(jsonpath "llminferenceservice/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.replicas}")
  endpoint=$(jsonpath "maasmodelrefs.maas.opendatahub.io/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.status.endpoint}")
  if [[ -z "$replicas" || "$replicas" == "0" || -z "$endpoint" ]]; then
    cat >&2 <<INSTRUCTIONS
ERROR: Nemotron (${NEMOTRON_MODEL_RESOURCE}) is parked or not ready in ${MAAS_NS}.
Un-park the environment first (see .agents/skills/env-manage-resources):
  1. oc scale machineset <gpu-machineset> -n openshift-machine-api --replicas=1   (cluster-admin)
  2. wait for the GPU node to become Ready and NVIDIA operator pods to start
  3. oc patch llminferenceservice ${NEMOTRON_MODEL_RESOURCE} -n ${MAAS_NS} \\
       --type=merge -p '{"spec":{"replicas":1}}'
  4. wait for the model pod to become Ready, then re-run this script.
INSTRUCTIONS
    exit 1
  fi
  echo "✓ Nemotron is available (replicas=${replicas}, endpoint=${endpoint})"
}

apply_argocd_application() {
  local app_manifest
  app_manifest=$(mktemp)
  TMP_FILES+=("$app_manifest")

  sed \
    -e "s|repoURL: .*|repoURL: ${GIT_REPO_URL}|" \
    -e "s|targetRevision: .*|targetRevision: ${GIT_REPO_BRANCH}|" \
    "$ROOT_DIR/gitops/argocd/app-of-apps/stage-240-guardrails-and-safety.yaml" > "$app_manifest"

  oc apply -f "$app_manifest" --insecure-skip-tls-verify=true
  oc annotate applications.argoproj.io stage-240-guardrails-and-safety -n openshift-gitops \
    argocd.argoproj.io/refresh=hard --overwrite \
    --insecure-skip-tls-verify=true >/dev/null

  # Stage 240 also lands a MaaSSubscription through stage 220 and the NeMo
  # shield wiring through the stage 230 LSD config; refresh both so the
  # shared-owner changes sync from the same revision.
  for shared_app in stage-220-models-as-a-service stage-230-private-data-rag; do
    oc annotate applications.argoproj.io "$shared_app" -n openshift-gitops \
      argocd.argoproj.io/refresh=hard --overwrite \
      --insecure-skip-tls-verify=true >/dev/null 2>&1 || true
  done
}

wait_for_namespace() {
  for _ in $(seq 1 30); do
    if oc get namespace "$SAFETY_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  echo "ERROR: namespace ${SAFETY_NS} was not created by Argo CD." >&2
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
  echo "ERROR: MaaSSubscription ${MAAS_SUBSCRIPTION} did not appear in ${MAAS_NS}; check the stage-220 Application sync." >&2
  exit 1
}

get_maas_endpoint() {
  local model="${1:-$NEMOTRON_MODEL_RESOURCE}"
  local endpoint
  endpoint=$(jsonpath "maasmodelrefs.maas.opendatahub.io/${model}" "$MAAS_NS" "{.status.endpoint}")
  if [[ -z "$endpoint" ]]; then
    echo "ERROR: MaaS endpoint for ${model} is not ready in ${MAAS_NS}. Deploy and validate Stage 220 first." >&2
    exit 1
  fi
  printf '%s' "$endpoint"
}

get_demo_user_token() {
  local user="$1"
  local password="$2"
  local kubeconfig token

  [[ -n "$password" ]] || return 1
  kubeconfig=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage240-login.XXXXXX")
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

ensure_maas_proxy_config() {
  # In-cluster calls to the MaaS gateway's external hostname hairpin through
  # the cloud load balancer and drop a large share of fresh connections
  # (verified live in stage 230). The GitOps-managed maas-internal-proxy
  # reaches the gateway Service directly while presenting the public hostname
  # (SNI + Host), keeping MaaS auth and rate limiting enforced. The hostname
  # is environment-specific, so the nginx server config is generated here.
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
    proxy_read_timeout 180s;
    proxy_connect_timeout 10s;
    proxy_buffering off;
  }
}
EOF
  oc create configmap maas-internal-proxy-config \
    -n "$SAFETY_NS" \
    --from-file=maas-proxy.conf="$proxy_conf" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null
  oc label configmap maas-internal-proxy-config -n "$SAFETY_NS" --overwrite \
    app.kubernetes.io/part-of=guardrails \
    demo.rhoai.io/stage=240 \
    --insecure-skip-tls-verify=true >/dev/null
  oc rollout restart deployment/maas-internal-proxy -n "$SAFETY_NS" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1 || true
  echo "✓ MaaS internal proxy config targets ${gateway_host}"
}

ensure_maas_api_key() {
  local endpoint gateway_host user_token api_key_body status api_key api_key_id existing existing_subscription

  # Reuse the stored key only when it was minted against the currently
  # configured subscription; a subscription change requires a fresh key so
  # the new token rate limits apply.
  existing=$(jsonpath "secret/${NEMO_SECRET}" "$SAFETY_NS" "{.data.token}" | base64 --decode 2>/dev/null || true)
  existing_subscription=$(jsonpath "secret/${NEMO_SECRET}" "$SAFETY_NS" "{.data.MAAS_SUBSCRIPTION}" | base64 --decode 2>/dev/null || true)
  if [[ -n "$existing" && "$existing" == sk-oai-* && "$existing_subscription" == "$MAAS_SUBSCRIPTION" ]]; then
    printf '%s' "$existing"
    return 0
  fi

  if [[ -n "${RHOAI_STAGE240_MAAS_API_KEY:-}" ]]; then
    printf '%s' "$RHOAI_STAGE240_MAAS_API_KEY"
    return 0
  fi

  user_token=$(get_demo_user_token "ai-developer" "${AI_DEVELOPER_PASSWORD:-}" || true)
  if [[ -z "$user_token" ]]; then
    echo "ERROR: Set RHOAI_STAGE240_MAAS_API_KEY or AI_DEVELOPER_PASSWORD so deploy.sh can create a MaaS API key." >&2
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

  oc annotate namespace "$SAFETY_NS" "demo.rhoai.io/stage240-maas-api-key-id=${api_key_id}" \
    --overwrite --insecure-skip-tls-verify=true >/dev/null
  printf '%s' "$api_key"
}

ensure_nemo_secret() {
  local previous token
  previous=$(jsonpath "secret/${NEMO_SECRET}" "$SAFETY_NS" "{.data.token}")
  token="$(ensure_maas_api_key)"

  oc create secret generic "$NEMO_SECRET" \
    -n "$SAFETY_NS" \
    --from-literal=token="$token" \
    --from-literal=MAAS_SUBSCRIPTION="$MAAS_SUBSCRIPTION" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null
  oc label secret "$NEMO_SECRET" -n "$SAFETY_NS" --overwrite \
    app.kubernetes.io/part-of=guardrails \
    demo.rhoai.io/stage=240 \
    --insecure-skip-tls-verify=true >/dev/null

  if [[ "$(jsonpath "secret/${NEMO_SECRET}" "$SAFETY_NS" "{.data.token}")" != "$previous" ]]; then
    oc rollout restart "deployment/${NEMO_CR}" -n "$SAFETY_NS" \
      --insecure-skip-tls-verify=true >/dev/null 2>&1 || true
  fi
  echo "✓ NeMo model API token Secret is present in ${SAFETY_NS}"
}

wait_for_guardrails() {
  local state phase
  echo "   Waiting for the TrustyAI component and the NeMo Guardrails service …"

  for _ in $(seq 1 60); do
    state=$(oc get datasciencecluster default-dsc \
      -o jsonpath='{.spec.components.trustyai.managementState}' \
      --insecure-skip-tls-verify=true 2>/dev/null || true)
    [[ "$state" == "Managed" ]] && break
    sleep 5
  done
  if [[ "$state" != "Managed" ]]; then
    echo "ERROR: DataScienceCluster trustyai is not Managed (state=${state:-unset}); check the stage-240 DSC patch Job." >&2
    exit 1
  fi
  echo "✓ DataScienceCluster trustyai is Managed"

  for _ in $(seq 1 90); do
    if oc get crd nemoguardrails.trustyai.opendatahub.io \
      --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      break
    fi
    sleep 10
  done
  if ! oc get crd nemoguardrails.trustyai.opendatahub.io \
    --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "ERROR: the NemoGuardrails CRD did not appear; check the TrustyAI operator rollout." >&2
    exit 1
  fi
  echo "✓ NemoGuardrails CRD is available"

  for _ in $(seq 1 90); do
    phase=$(jsonpath "nemoguardrails/${NEMO_CR}" "$SAFETY_NS" "{.status.phase}")
    [[ "$phase" == "Ready" ]] && break
    sleep 10
  done
  if [[ "$phase" != "Ready" ]]; then
    echo "ERROR: NemoGuardrails ${NEMO_CR} is not Ready (phase=${phase:-missing})." >&2
    exit 1
  fi
  echo "✓ NemoGuardrails ${NEMO_CR} is Ready"
}

restart_lsd_for_shields() {
  # The Stage 230 LSD mounts its run config from a ConfigMap; the operator
  # does not roll the Deployment on ConfigMap content changes, so restart it
  # to pick up the NeMo shield provider and registration.
  if oc get "deployment/${LSD_DEPLOYMENT}" -n "$RAG_NS" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    if oc get configmap lsd-enterprise-rag-config -n "$RAG_NS" \
      -o jsonpath='{.data.config\.yaml}' --insecure-skip-tls-verify=true 2>/dev/null \
      | grep -q 'nemo-guardrails'; then
      oc rollout restart "deployment/${LSD_DEPLOYMENT}" -n "$RAG_NS" \
        --insecure-skip-tls-verify=true >/dev/null 2>&1 || true
      echo "✓ Stage 230 Llama Stack restarted to load the NeMo shield"
    else
      echo "! Stage 230 LSD config does not contain the NeMo shield yet; re-run after the stage-230 sync completes." >&2
    fi
  fi
}

ensure_nemotron_available
apply_argocd_application
wait_for_namespace
wait_for_maas_subscription
ensure_maas_proxy_config
ensure_nemo_secret
wait_for_guardrails
restart_lsd_for_shields

oc annotate applications.argoproj.io stage-240-guardrails-and-safety -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite \
  --insecure-skip-tls-verify=true >/dev/null

echo "✓ Stage 240 Application applied. Run ./stage-240-guardrails-and-safety/validate.sh after Argo CD sync completes."
