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
MAAS_DB_CONFIG_SECRET="${RHOAI_MAAS_DB_CONFIG_SECRET:-maas-db-config}"

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
[[ "$RHCL_CSV" == rhcl-operator.* ]] && R="pass" || R="installedCSV=${RHCL_CSV:-missing}"
check "Red Hat Connectivity Link Operator subscription installed" "$R"

for crd in \
  kuadrants.kuadrant.io \
  authorinos.operator.authorino.kuadrant.io \
  gateways.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io \
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

DB_READY=$(jsonpath "statefulset/maas-postgres" "$MAAS_NS" "{.status.readyReplicas}")
[[ "$DB_READY" == "1" ]] && R="pass" || R="readyReplicas=${DB_READY:-0}"
check "MaaS PostgreSQL StatefulSet ready" "$R"

if resource_exists "secret/${MAAS_DB_CONFIG_SECRET}" "redhat-ods-applications"; then
  R="pass"
else
  R="missing"
fi
check "maas-db-config secret present" "$R"

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

echo
echo "Stage 230 validation summary: ${PASS} passed, ${FAIL} failed"
if (( FAIL > 0 )); then
  exit 1
fi
