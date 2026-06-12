#!/usr/bin/env bash
# validate.sh - Stage 230: Models-as-a-Service
# Checks the MaaS prerequisite boundary before model publication/subscription CRs
# are authored.
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

MAAS_NS="${RHOAI_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_DB_NS="${RHOAI_MAAS_DATABASE_NAMESPACE:-models-as-a-service-db}"
MAAS_DB_CONFIG_SECRET="${RHOAI_MAAS_DB_CONFIG_SECRET:-maas-db-config}"
PINNED_RHCL_CSV="${RHOAI_PINNED_RHCL_CSV:-rhcl-operator.v1.3.3}"
OPENAI_MODEL_ID="${RHOAI_OPENAI_MODEL_ID:-gpt-5.4-mini}"
OPENAI_MODEL_RESOURCE="${RHOAI_OPENAI_MODEL_RESOURCE:-gpt-5-4-mini}"
OPENAI_PROVIDER_SECRET="${RHOAI_OPENAI_PROVIDER_SECRET:-openai-provider-api-key}"
OPENAI_ACCESS_RESOURCE="${RHOAI_OPENAI_ACCESS_RESOURCE:-rhoai-developers-gpt-5-4-mini}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
DIRECT_NEMOTRON_NAME="${RHOAI_NEMOTRON_DEPLOYMENT_NAME:-nvidia-nemotron-3-nano-30b-a3b}"
PROJECT_NS="${RHOAI_DEMO_PROJECT_NAMESPACE:-demo-sandbox}"

TMP_FILES=()
cleanup() {
  if ((${#TMP_FILES[@]} > 0)); then
    rm -f "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

if [[ -z "${RHOAI_EXPECTED_API_SERVER:-}" ]]; then
  echo "ERROR: RHOAI_EXPECTED_API_SERVER is not set." >&2
  exit 1
fi

ACTUAL_SERVER=$(oc whoami --show-server 2>/dev/null || true)
if [[ "$ACTUAL_SERVER" != *"$RHOAI_EXPECTED_API_SERVER"* ]]; then
  echo "ERROR: Active cluster ($ACTUAL_SERVER) does not match RHOAI_EXPECTED_API_SERVER." >&2
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

resource_exists() {
  local resource="$1"
  local namespace="$2"
  if [[ -n "$namespace" ]]; then
    oc get "$resource" -n "$namespace" --insecure-skip-tls-verify=true >/dev/null 2>&1
  else
    oc get "$resource" --insecure-skip-tls-verify=true >/dev/null 2>&1
  fi
}

crd_exists() {
  oc get crd "$1" --insecure-skip-tls-verify=true >/dev/null 2>&1
}

jsonpath() {
  local resource="$1"
  local namespace="$2"
  local path="$3"
  if [[ -n "$namespace" ]]; then
    oc get "$resource" -n "$namespace" -o jsonpath="$path" \
      --insecure-skip-tls-verify=true 2>/dev/null || true
  else
    oc get "$resource" -o jsonpath="$path" \
      --insecure-skip-tls-verify=true 2>/dev/null || true
  fi
}

contains_word() {
  local list="$1"
  local item="$2"
  [[ " ${list} " == *" ${item} "* ]]
}

body_contains_model() {
  local body_file="$1"
  local model

  for model in "$OPENAI_MODEL_RESOURCE" "$OPENAI_MODEL_ID" "$NEMOTRON_MODEL_RESOURCE"; do
    if grep -Fq "$model" "$body_file"; then
      return 0
    fi
  done

  return 1
}

can_i_as() {
  local user="$1"
  local verb="$2"
  local resource="$3"
  local namespace="$4"
  local group="${5:-}"
  local group_args=()
  if [[ -n "$group" ]]; then
    group_args+=(--as-group="$group")
  fi
  oc auth can-i "$verb" "$resource" -n "$namespace" --as="$user" "${group_args[@]}" \
    --insecure-skip-tls-verify=true 2>/dev/null || true
}

get_demo_user_token() {
  local user="$1"
  local password="$2"
  local kubeconfig token

  [[ -n "$password" ]] || return 1

  kubeconfig=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-validate.XXXXXX")
  TMP_FILES+=("$kubeconfig")

  if ! oc login "$ACTUAL_SERVER" -u "$user" -p "$password" \
    --kubeconfig "$kubeconfig" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    return 1
  fi

  token=$(oc --kubeconfig "$kubeconfig" whoami -t \
    --insecure-skip-tls-verify=true 2>/dev/null || true)
  [[ -n "$token" ]] || return 1
  printf '%s' "$token"
}

http_get() {
  local url="$1"
  local token="$2"
  local body_file="$3"

  URL="$url" TOKEN="$token" BODY_FILE="$body_file" python3 - <<'PY'
import os
import ssl
import sys
import urllib.error
import urllib.request

url = os.environ["URL"]
token = os.environ["TOKEN"]
body_file = os.environ["BODY_FILE"]

ctx = ssl._create_unverified_context()
req = urllib.request.Request(
    url,
    headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    },
)

try:
    with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
        status = resp.getcode()
        body = resp.read()
except urllib.error.HTTPError as exc:
    status = exc.code
    body = exc.read()
except Exception as exc:
    status = "000"
    body = str(exc).encode()

with open(body_file, "wb") as handle:
    handle.write(body)

print(status)
PY
}

APP_SYNC=$(jsonpath "application/stage-230-models-as-a-service" "openshift-gitops" "{.status.sync.status}")
[[ "$APP_SYNC" == "Synced" ]] && R="pass" || R="sync=${APP_SYNC:-not found}"
check "Stage 230 Application Synced" "$R"

STAGE110_SYNC=$(jsonpath "application/stage-110-rhoai-base-platform" "openshift-gitops" "{.status.sync.status}")
[[ "$STAGE110_SYNC" == "Synced" ]] && R="pass" || R="sync=${STAGE110_SYNC:-not found}"
check "Stage 110 shared owner Application Synced" "$R"

DSC_PHASE=$(jsonpath "datasciencecluster/default-dsc" "" "{.status.phase}")
[[ "$DSC_PHASE" == "Ready" ]] && R="pass" || R="phase=${DSC_PHASE:-not found}"
check "DataScienceCluster Ready" "$R"

DSC_MAAS=$(jsonpath "datasciencecluster/default-dsc" "" "{.spec.components.kserve.modelsAsService.managementState}")
[[ "$DSC_MAAS" == "Managed" ]] && R="pass" || R="modelsAsService=${DSC_MAAS:-not found}"
check "DataScienceCluster MaaS is Managed" "$R"

DSC_LLAMA=$(jsonpath "datasciencecluster/default-dsc" "" "{.spec.components.llamastackoperator.managementState}")
[[ "$DSC_LLAMA" == "Managed" ]] && R="pass" || R="llamastackoperator=${DSC_LLAMA:-not found}"
check "DataScienceCluster Llama Stack Operator is Managed" "$R"

for flag in modelAsService vLLMDeploymentOnMaaS genAiStudio maasAuthPolicies observabilityDashboard; do
  value=$(jsonpath "odhdashboardconfig/odh-dashboard-config" "redhat-ods-applications" "{.spec.dashboardConfig.${flag}}")
  [[ "$value" == "true" ]] && R="pass" || R="${flag}=${value:-missing}"
  check "Dashboard flag enabled: ${flag}" "$R"
done

if resource_exists "certmanager/cluster" ""; then
  R="pass"
else
  R="missing"
fi
check "cert-manager cluster resource present" "$R"

CERT_READY=0
for deploy in cert-manager cert-manager-cainjector cert-manager-webhook; do
  ready=$(jsonpath "deployment/${deploy}" "cert-manager" "{.status.readyReplicas}")
  if [[ "${ready:-0}" == "1" ]]; then
    (( CERT_READY++ )) || true
  fi
done
[[ "$CERT_READY" == "3" ]] && R="pass" || R="readyDeployments=${CERT_READY}/3"
check "cert-manager deployments available" "$R"

RHCL_CSV=$(jsonpath "subscription/rhcl-operator" "openshift-operators" "{.status.installedCSV}")
RHCL_APPROVAL=$(jsonpath "subscription/rhcl-operator" "openshift-operators" "{.spec.installPlanApproval}")
RHCL_STARTING_CSV=$(jsonpath "subscription/rhcl-operator" "openshift-operators" "{.spec.startingCSV}")
if [[ "$RHCL_CSV" == "$PINNED_RHCL_CSV" &&
  "$RHCL_APPROVAL" == "Manual" &&
  "$RHCL_STARTING_CSV" == "$PINNED_RHCL_CSV" ]]; then
  R="pass"
else
  R="installedCSV=${RHCL_CSV:-missing},approval=${RHCL_APPROVAL:-missing},startingCSV=${RHCL_STARTING_CSV:-missing},expected=${PINNED_RHCL_CSV}"
fi
check "Red Hat Connectivity Link Operator is pinned to the MaaS-compatible CSV" "$R"

for crd in \
  kuadrants.kuadrant.io \
  authorinos.operator.authorino.kuadrant.io \
  gateways.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io \
  leaderworkersetoperators.operator.openshift.io \
  leaderworkersets.leaderworkerset.x-k8s.io \
  llamastackdistributions.llamastack.io; do
  if crd_exists "$crd"; then
    R="pass"
  else
    R="missing"
  fi
  check "Prerequisite CRD present: ${crd}" "$R"
done

for crd in \
  tenants.maas.opendatahub.io \
  maasmodelrefs.maas.opendatahub.io \
  maassubscriptions.maas.opendatahub.io \
  maasauthpolicies.maas.opendatahub.io \
  externalmodels.maas.opendatahub.io; do
  if crd_exists "$crd"; then
    R="pass"
  else
    R="missing"
  fi
  check "MaaS CRD present: ${crd}" "$R"
done

DB_READY=$(jsonpath "statefulset/maas-postgres" "$MAAS_DB_NS" "{.status.readyReplicas}")
[[ "$DB_READY" == "1" ]] && R="pass" || R="readyReplicas=${DB_READY:-0}"
check "MaaS PostgreSQL StatefulSet ready" "$R"

if resource_exists "secret/${MAAS_DB_CONFIG_SECRET}" "redhat-ods-applications"; then
  R="pass"
else
  R="missing"
fi
check "maas-db-config secret present" "$R"

if resource_exists "secret/${OPENAI_PROVIDER_SECRET}" "$MAAS_NS"; then
  if oc get "secret/${OPENAI_PROVIDER_SECRET}" -n "$MAAS_NS" -o jsonpath='{.data}' \
    --insecure-skip-tls-verify=true 2>/dev/null | grep -q 'api-key'; then
    R="pass"
  else
    R="missing data key api-key"
  fi
else
  R="missing"
fi
check "OpenAI provider Secret present with api-key data key" "$R"

if resource_exists "rolebinding/rhods-admins-maas-admin" "$MAAS_NS"; then
  R="pass"
else
  R="missing"
fi
check "rhods-admins has MaaS namespace admin RoleBinding" "$R"

MAAS_PROJECT_LABEL=$(jsonpath "namespace/${MAAS_NS}" "" "{.metadata.labels.opendatahub\\.io/dashboard}")
[[ "$MAAS_PROJECT_LABEL" == "true" ]] && R="pass" || R="opendatahub.io/dashboard=${MAAS_PROJECT_LABEL:-missing}"
check "MaaS namespace is visible as an OpenShift AI project" "$R"

MAAS_KUEUE_LABEL=$(jsonpath "namespace/${MAAS_NS}" "" "{.metadata.labels.kueue\\.openshift\\.io/managed}")
[[ "$MAAS_KUEUE_LABEL" == "true" ]] && R="pass" || R="kueue.openshift.io/managed=${MAAS_KUEUE_LABEL:-missing}"
check "MaaS namespace is managed by Kueue" "$R"

AI_ADMIN_CAN=$(can_i_as "ai-admin" "get" "pods" "$MAAS_NS" "rhods-admins")
[[ "$AI_ADMIN_CAN" == "yes" ]] && R="pass" || R="can-i=${AI_ADMIN_CAN:-unknown}"
check "ai-admin can administer the MaaS namespace" "$R"

AI_DEVELOPER_CAN=$(can_i_as "ai-developer" "get" "pods" "$MAAS_NS" "rhoai-developers")
[[ "$AI_DEVELOPER_CAN" == "no" ]] && R="pass" || R="can-i=${AI_DEVELOPER_CAN:-unknown}"
check "ai-developer has no direct MaaS namespace access" "$R"

GATEWAY_HOST=$(jsonpath "gateway/maas-default-gateway" "openshift-ingress" "{.spec.listeners[0].hostname}")
if [[ "$GATEWAY_HOST" == maas.* && "$GATEWAY_HOST" != "maas.placeholder.example.com" ]]; then
  R="pass"
else
  R="hostname=${GATEWAY_HOST:-missing}"
fi
check "MaaS Gateway hostname patched" "$R"

GATEWAY_TLS=$(jsonpath "gateway/maas-default-gateway" "openshift-ingress" "{.metadata.annotations.security\\.opendatahub\\.io/authorino-tls-bootstrap}")
[[ "$GATEWAY_TLS" == "true" ]] && R="pass" || R="annotation=${GATEWAY_TLS:-missing}"
check "MaaS Gateway Authorino TLS annotation present" "$R"

if crd_exists kuadrants.kuadrant.io; then
  KUADRANT_READY=$(jsonpath "kuadrant/kuadrant" "kuadrant-system" "{.status.conditions[?(@.type==\"Ready\")].status}")
  [[ "$KUADRANT_READY" == "True" ]] && R="pass" || R="ready=${KUADRANT_READY:-missing}"
else
  R="CRD missing"
fi
check "Kuadrant Ready" "$R"

if crd_exists authorinos.operator.authorino.kuadrant.io; then
  AUTHORINO_TLS=$(jsonpath "authorino/authorino" "kuadrant-system" "{.spec.listener.tls.enabled}")
  [[ "$AUTHORINO_TLS" == "true" ]] && R="pass" || R="tls=${AUTHORINO_TLS:-missing}"
else
  R="CRD missing"
fi
check "Authorino TLS enabled" "$R"

if crd_exists tenants.maas.opendatahub.io && resource_exists "tenant/default-tenant" "$MAAS_NS"; then
  TENANT_READY=$(jsonpath "tenant/default-tenant" "$MAAS_NS" "{.status.conditions[?(@.type==\"Ready\")].status}")
  [[ "$TENANT_READY" == "True" ]] && R="pass" || R="ready=${TENANT_READY:-missing}"
else
  R="missing"
fi
check "MaaS Tenant Ready" "$R"

if resource_exists "inferenceservice/${DIRECT_NEMOTRON_NAME}" "$PROJECT_NS"; then
  R="direct InferenceService still exists in ${PROJECT_NS}"
else
  R="pass"
fi
check "direct demo-sandbox Nemotron deployment has been removed" "$R"

STALE_LLMIS=""
for stale_llmis_name in "$NEMOTRON_MODEL_RESOURCE" "$DIRECT_NEMOTRON_NAME"; do
  if resource_exists "llminferenceservice/${stale_llmis_name}" "$PROJECT_NS"; then
    STALE_LLMIS="${STALE_LLMIS} ${stale_llmis_name}"
  fi
done
if [[ -z "$STALE_LLMIS" ]]; then
  R="pass"
else
  R="stale LLMInferenceService still exists in ${PROJECT_NS}:${STALE_LLMIS}"
fi
check "no stale demo-sandbox Nemotron LLMInferenceService remains" "$R"

if resource_exists "localqueue/lq-gpu-reserved-demo" "$MAAS_NS"; then
  LQ_CLUSTER_QUEUE=$(jsonpath "localqueue/lq-gpu-reserved-demo" "$MAAS_NS" "{.spec.clusterQueue}")
  [[ "$LQ_CLUSTER_QUEUE" == "cq-gpu-reserved-demo" ]] && R="pass" || R="clusterQueue=${LQ_CLUSTER_QUEUE:-missing}"
else
  R="missing"
fi
check "MaaS namespace has the GPU reserved LocalQueue" "$R"

if resource_exists "llminferenceservices.serving.kserve.io/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS"; then
  NEMOTRON_URI=$(jsonpath "llminferenceservices.serving.kserve.io/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.model.uri}")
  NEMOTRON_READY=$(jsonpath "llminferenceservices.serving.kserve.io/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.status.conditions[?(@.type==\"Ready\")].status}")
  if [[ "$NEMOTRON_URI" == "oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0" &&
    "$NEMOTRON_READY" == "True" ]]; then
    R="pass"
  else
    R="uri=${NEMOTRON_URI:-missing},ready=${NEMOTRON_READY:-missing}"
  fi
else
  R="missing"
fi
check "local Nemotron LLMInferenceService is ready in MaaS namespace" "$R"

NEMOTRON_MODELREF_KIND=$(jsonpath "maasmodelrefs.maas.opendatahub.io/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.modelRef.kind}")
NEMOTRON_MODELREF_NAME=$(jsonpath "maasmodelrefs.maas.opendatahub.io/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.modelRef.name}")
if [[ "$NEMOTRON_MODELREF_KIND" == "LLMInferenceService" && "$NEMOTRON_MODELREF_NAME" == "$NEMOTRON_MODEL_RESOURCE" ]]; then
  R="pass"
else
  R="kind=${NEMOTRON_MODELREF_KIND:-missing},name=${NEMOTRON_MODELREF_NAME:-missing}"
fi
check "MaaSModelRef points to the local Nemotron LLMInferenceService" "$R"

EXTERNAL_PROVIDER=$(jsonpath "externalmodels.maas.opendatahub.io/${OPENAI_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.provider}")
EXTERNAL_ENDPOINT=$(jsonpath "externalmodels.maas.opendatahub.io/${OPENAI_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.endpoint}")
EXTERNAL_TARGET=$(jsonpath "externalmodels.maas.opendatahub.io/${OPENAI_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.targetModel}")
EXTERNAL_SECRET=$(jsonpath "externalmodels.maas.opendatahub.io/${OPENAI_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.credentialRef.name}")
if [[ "$EXTERNAL_PROVIDER" == "openai" && "$EXTERNAL_ENDPOINT" == "api.openai.com" && "$EXTERNAL_TARGET" == "$OPENAI_MODEL_ID" && "$EXTERNAL_SECRET" == "$OPENAI_PROVIDER_SECRET" ]]; then
  R="pass"
else
  R="provider=${EXTERNAL_PROVIDER:-missing},endpoint=${EXTERNAL_ENDPOINT:-missing},target=${EXTERNAL_TARGET:-missing},secret=${EXTERNAL_SECRET:-missing}"
fi
check "External OpenAI model is registered through MaaS schema" "$R"

MODELREF_KIND=$(jsonpath "maasmodelrefs.maas.opendatahub.io/${OPENAI_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.modelRef.kind}")
MODELREF_NAME=$(jsonpath "maasmodelrefs.maas.opendatahub.io/${OPENAI_MODEL_RESOURCE}" "$MAAS_NS" "{.spec.modelRef.name}")
if [[ "$MODELREF_KIND" == "ExternalModel" && "$MODELREF_NAME" == "$OPENAI_MODEL_RESOURCE" ]]; then
  R="pass"
else
  R="kind=${MODELREF_KIND:-missing},name=${MODELREF_NAME:-missing}"
fi
check "MaaSModelRef points to the external OpenAI model" "$R"

SUB_OWNER_GROUPS=$(jsonpath "maassubscriptions.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.owner.groups[*].name}")
SUB_OWNER_USERS=$(jsonpath "maassubscriptions.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.owner.users[*]}")
SUB_MODELS=$(jsonpath "maassubscriptions.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.modelRefs[*].name}")
SUB_OPENAI_LIMIT=$(jsonpath "maassubscriptions.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.modelRefs[?(@.name==\"${OPENAI_MODEL_RESOURCE}\")].tokenRateLimits[0].limit}")
SUB_OPENAI_WINDOW=$(jsonpath "maassubscriptions.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.modelRefs[?(@.name==\"${OPENAI_MODEL_RESOURCE}\")].tokenRateLimits[0].window}")
SUB_NEMOTRON_LIMIT=$(jsonpath "maassubscriptions.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.modelRefs[?(@.name==\"${NEMOTRON_MODEL_RESOURCE}\")].tokenRateLimits[0].limit}")
SUB_NEMOTRON_WINDOW=$(jsonpath "maassubscriptions.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.modelRefs[?(@.name==\"${NEMOTRON_MODEL_RESOURCE}\")].tokenRateLimits[0].window}")
if contains_word "$SUB_OWNER_GROUPS" "rhoai-developers" &&
  contains_word "$SUB_OWNER_GROUPS" "rhods-admins" &&
  contains_word "$SUB_OWNER_USERS" "kube:admin" &&
  contains_word "$SUB_MODELS" "$OPENAI_MODEL_RESOURCE" &&
  contains_word "$SUB_MODELS" "$NEMOTRON_MODEL_RESOURCE" &&
  [[ "$SUB_OPENAI_LIMIT" == "20000" && "$SUB_OPENAI_WINDOW" == "1h" &&
    "$SUB_NEMOTRON_LIMIT" == "100000" && "$SUB_NEMOTRON_WINDOW" == "1h" ]]; then
  R="pass"
else
  R="groups=${SUB_OWNER_GROUPS:-missing},users=${SUB_OWNER_USERS:-missing},models=${SUB_MODELS:-missing},openaiLimit=${SUB_OPENAI_LIMIT:-missing}/${SUB_OPENAI_WINDOW:-missing},nemotronLimit=${SUB_NEMOTRON_LIMIT:-missing}/${SUB_NEMOTRON_WINDOW:-missing}"
fi
check "demo users have MaaS subscription quota for local and external models" "$R"

AUTH_SUBJECT_GROUPS=$(jsonpath "maasauthpolicies.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.subjects.groups[*].name}")
AUTH_SUBJECT_USERS=$(jsonpath "maasauthpolicies.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.subjects.users[*]}")
AUTH_MODELS=$(jsonpath "maasauthpolicies.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.modelRefs[*].name}")
AUTH_ORG=$(jsonpath "maasauthpolicies.maas.opendatahub.io/${OPENAI_ACCESS_RESOURCE}" "$MAAS_NS" "{.spec.meteringMetadata.organizationId}")
if contains_word "$AUTH_SUBJECT_GROUPS" "rhoai-developers" &&
  contains_word "$AUTH_SUBJECT_GROUPS" "rhods-admins" &&
  contains_word "$AUTH_SUBJECT_USERS" "kube:admin" &&
  contains_word "$AUTH_MODELS" "$OPENAI_MODEL_RESOURCE" &&
  contains_word "$AUTH_MODELS" "$NEMOTRON_MODEL_RESOURCE" &&
  [[ "$AUTH_ORG" == "rhoai3-demo" ]]; then
  R="pass"
else
  R="groups=${AUTH_SUBJECT_GROUPS:-missing},users=${AUTH_SUBJECT_USERS:-missing},models=${AUTH_MODELS:-missing},org=${AUTH_ORG:-missing}"
fi
check "demo users have MaaS auth policy for local and external models" "$R"

GATEWAY_FILTERS=$(oc get envoyfilter -n openshift-ingress -o name \
  --insecure-skip-tls-verify=true 2>/dev/null || true)
GATEWAY_READY=$(oc get pods -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
  -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{" "}{end}' \
  --insecure-skip-tls-verify=true 2>/dev/null || true)
GATEWAY_LOG_ERRORS=$(oc logs -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
  --since=3m --tail=500 --insecure-skip-tls-verify=true 2>/dev/null \
  | grep -E 'allow_on_headers_stop_iteration|Proto constraint validation failed|unknown field|Error adding/updating listener' \
  || true)
OPENAI_AUTH_ENFORCED=$(jsonpath "authpolicy/maas-auth-gpt-5-4-mini" "$MAAS_NS" "{.status.conditions[?(@.type==\"Enforced\")].status}")
NEMOTRON_AUTH_ENFORCED=$(jsonpath "authpolicy/maas-auth-nemotron-3-nano-30b-a3b" "$MAAS_NS" "{.status.conditions[?(@.type==\"Enforced\")].status}")
OPENAI_TRLP_ENFORCED=$(jsonpath "tokenratelimitpolicy/maas-trlp-gpt-5-4-mini" "$MAAS_NS" "{.status.conditions[?(@.type==\"Enforced\")].status}")
NEMOTRON_TRLP_ENFORCED=$(jsonpath "tokenratelimitpolicy/maas-trlp-nemotron-3-nano-30b-a3b" "$MAAS_NS" "{.status.conditions[?(@.type==\"Enforced\")].status}")
if [[ -n "$GATEWAY_LOG_ERRORS" ]]; then
  R="gateway Envoy log reports recent generated filter rejection"
elif ! contains_word "$GATEWAY_READY" "True"; then
  R="gateway pod Ready conditions=${GATEWAY_READY:-missing}"
elif ! grep -q 'kuadrant-auth-maas-default-gateway' <<<"$GATEWAY_FILTERS" ||
  ! grep -q 'kuadrant-ratelimiting-maas-default-gateway' <<<"$GATEWAY_FILTERS"; then
  R="generated Kuadrant auth/rate-limit EnvoyFilters missing"
elif [[ "$OPENAI_AUTH_ENFORCED" != "True" ||
  "$NEMOTRON_AUTH_ENFORCED" != "True" ||
  "$OPENAI_TRLP_ENFORCED" != "True" ||
  "$NEMOTRON_TRLP_ENFORCED" != "True" ]]; then
  R="policy enforcement openaiAuth=${OPENAI_AUTH_ENFORCED:-missing},nemotronAuth=${NEMOTRON_AUTH_ENFORCED:-missing},openaiLimit=${OPENAI_TRLP_ENFORCED:-missing},nemotronLimit=${NEMOTRON_TRLP_ENFORCED:-missing}"
else
  R="pass"
fi
check "MaaS Gateway generated policy filters are healthy" "$R"

if command -v python3 >/dev/null 2>&1; then
  DASHBOARD_HOST=$(jsonpath "route/rhods-dashboard" "redhat-ods-applications" "{.spec.host}")
  AI_DEVELOPER_TOKEN=$(get_demo_user_token "ai-developer" "${AI_DEVELOPER_PASSWORD:-}" || true)
  if [[ -n "$AI_DEVELOPER_TOKEN" ]]; then
    BODY=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-dashboard.XXXXXX")
    TMP_FILES+=("$BODY")
    STATUS=$(http_get "https://${DASHBOARD_HOST}/gen-ai/api/v1/maas/models?namespace=${PROJECT_NS}" "$AI_DEVELOPER_TOKEN" "$BODY")
    if [[ "$STATUS" == "200" ]] && body_contains_model "$BODY"; then
      R="pass"
    else
      R="status=${STATUS},body=$(head -c 180 "$BODY" | tr '\n' ' ')"
    fi
    check "ai-developer dashboard AI asset endpoints can load MaaS models" "$R"

    BODY=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-maas-api.XXXXXX")
    TMP_FILES+=("$BODY")
    STATUS=$(http_get "https://${GATEWAY_HOST}/maas-api/v1/subscriptions" "$AI_DEVELOPER_TOKEN" "$BODY")
    if [[ "$STATUS" == "200" ]] && grep -q "$OPENAI_ACCESS_RESOURCE" "$BODY"; then
      R="pass"
    else
      R="status=${STATUS},body=$(head -c 180 "$BODY" | tr '\n' ' ')"
    fi
    check "ai-developer MaaS API subscription discovery works through Gateway" "$R"
  else
    check "ai-developer dashboard/API validation token available" "AI_DEVELOPER_PASSWORD missing or login failed"
  fi

  AI_ADMIN_TOKEN=$(get_demo_user_token "ai-admin" "${AI_ADMIN_PASSWORD:-}" || true)
  if [[ -n "$AI_ADMIN_TOKEN" ]]; then
    BODY=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-dashboard-admin.XXXXXX")
    TMP_FILES+=("$BODY")
    STATUS=$(http_get "https://${DASHBOARD_HOST}/gen-ai/api/v1/maas/models?namespace=${MAAS_NS}" "$AI_ADMIN_TOKEN" "$BODY")
    if [[ "$STATUS" == "200" ]] && body_contains_model "$BODY"; then
      R="pass"
    else
      R="status=${STATUS},body=$(head -c 180 "$BODY" | tr '\n' ' ')"
    fi
    check "ai-admin dashboard can load MaaS models from the MaaS project" "$R"
  else
    check "ai-admin dashboard validation token available" "AI_ADMIN_PASSWORD missing or login failed"
  fi
else
  check "Dashboard and MaaS API HTTP validation can run" "python3 missing"
fi

echo
echo "Stage 230 validation summary: ${PASS} passed, ${FAIL} failed"
if (( FAIL > 0 )); then
  exit 1
fi
