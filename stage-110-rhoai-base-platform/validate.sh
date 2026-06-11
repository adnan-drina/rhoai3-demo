#!/usr/bin/env bash
# validate.sh — Stage 110: RHOAI Base Platform
# Proves all foundation components are healthy and the RHOAI dashboard is reachable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

# ── Load local environment ────────────────────────────────────────────────────
if [[ -f "$ROOT_DIR/.env" ]]; then
  # set -a so values like KUBECONFIG are exported to oc child processes,
  # not just set as local shell variables.
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

# ── OpenShift safety guard ────────────────────────────────────────────────────
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

# ── 1. OpenShift GitOps operator ─────────────────────────────────────────────
GITOPS_CSV=$(oc get csv -n openshift-operators \
  -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift GitOps")].status.phase}' \
  --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$GITOPS_CSV" == "Succeeded" ]] && R="pass" || R="phase=${GITOPS_CSV:-not found}"
check "OpenShift GitOps operator CSV Succeeded" "$R"

# ── 2. ArgoCD instance Available ─────────────────────────────────────────────
ARGOCD_PHASE=$(oc get argocd openshift-gitops -n openshift-gitops \
  -o jsonpath='{.status.phase}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$ARGOCD_PHASE" == "Available" ]] && R="pass" || R="phase=${ARGOCD_PHASE:-not found}"
check "ArgoCD instance Available" "$R"

# ── 3. ArgoCD Application Synced + Healthy ────────────────────────────────────
APP_SYNC=$(oc get application stage-110-rhoai-base-platform -n openshift-gitops \
  -o jsonpath='{.status.sync.status}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
APP_HEALTH=$(oc get application stage-110-rhoai-base-platform -n openshift-gitops \
  -o jsonpath='{.status.health.status}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$APP_SYNC" == "Synced" ]] && R="pass" || R="sync=${APP_SYNC:-not found}"
check "Argo CD Application Synced" "$R"
[[ "$APP_HEALTH" == "Healthy" ]] && R="pass" || R="health=${APP_HEALTH:-not found}"
check "Argo CD Application Healthy" "$R"

# ── 4. ODF operator ───────────────────────────────────────────────────────────
ODF_CSV=$(oc get csv -n openshift-storage \
  -o jsonpath='{.items[?(@.spec.displayName=="OpenShift Data Foundation")].status.phase}' \
  --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$ODF_CSV" == "Succeeded" ]] && R="pass" || R="phase=${ODF_CSV:-not found}"
check "ODF operator CSV Succeeded" "$R"

# ── 5. NooBaa Ready ───────────────────────────────────────────────────────────
NOOBAA_PHASE=$(oc get noobaa noobaa -n openshift-storage \
  -o jsonpath='{.status.phase}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$NOOBAA_PHASE" == "Ready" ]] && R="pass" || R="phase=${NOOBAA_PHASE:-not found}"
check "NooBaa phase Ready" "$R"

# ── 6. RHOAI operator ────────────────────────────────────────────────────────
RHOAI_CSV=$(oc get csv -n redhat-ods-operator \
  -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift AI")].status.phase}' \
  --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$RHOAI_CSV" == "Succeeded" ]] && R="pass" || R="phase=${RHOAI_CSV:-not found}"
check "RHOAI operator CSV Succeeded" "$R"

# ── 7. DSCInitialization Ready ────────────────────────────────────────────────
DSCI_PHASE=$(oc get dscinitialization default-dsci \
  -o jsonpath='{.status.phase}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$DSCI_PHASE" == "Ready" ]] && R="pass" || R="phase=${DSCI_PHASE:-not found}"
check "DSCInitialization phase Ready" "$R"

# ── 8. DataScienceCluster Ready ───────────────────────────────────────────────
DSC_PHASE=$(oc get datasciencecluster default-dsc \
  -o jsonpath='{.status.phase}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "$DSC_PHASE" == "Ready" ]] && R="pass" || R="phase=${DSC_PHASE:-not found}"
check "DataScienceCluster phase Ready" "$R"

# ── 9. Model Registry operator running ───────────────────────────────────────
MR_READY=$(oc get deployment model-registry-operator-controller-manager \
  -n redhat-ods-applications \
  -o jsonpath='{.status.readyReplicas}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
[[ "${MR_READY:-0}" -ge 1 ]] && R="pass" || R="readyReplicas=${MR_READY:-0}"
check "Model Registry operator running" "$R"

# ── 11. RHOAI Dashboard route responds ───────────────────────────────────────
DASHBOARD_HOST=$(oc get route rhods-dashboard -n redhat-ods-applications \
  -o jsonpath='{.spec.host}' --insecure-skip-tls-verify=true 2>/dev/null || echo "")
if [[ -n "$DASHBOARD_HOST" ]]; then
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$DASHBOARD_HOST" 2>/dev/null || echo "000")
  [[ "$HTTP_CODE" =~ ^(200|301|302|303)$ ]] && R="pass" || R="http=$HTTP_CODE"
  check "RHOAI Dashboard route reachable (https://$DASHBOARD_HOST)" "$R"
else
  check "RHOAI Dashboard route reachable" "route not found"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
