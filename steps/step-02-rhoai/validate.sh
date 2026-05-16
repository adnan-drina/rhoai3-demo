#!/usr/bin/env bash
# Step 02: Red Hat OpenShift AI 3.4 — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 02: Red Hat OpenShift AI 3.4 — Validation                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Argo CD Application ---
log_step "Argo CD Application"
# Note: Operator-managed resources may show transient OutOfSync.
# Treat sync as warn-only for step-02 since the operator owns the reconciliation.
SYNC=$(oc get applications.argoproj.io step-02-rhoai -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NOT_FOUND")
HEALTH=$(oc get applications.argoproj.io step-02-rhoai -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "NOT_FOUND")
if [[ "$SYNC" == "Synced" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app 'step-02-rhoai' sync: Synced"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} Argo CD app 'step-02-rhoai' sync: $SYNC (operator-managed resources may drift)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi
if [[ "$HEALTH" == "Healthy" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app 'step-02-rhoai' health: Healthy"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Argo CD app 'step-02-rhoai' health: $HEALTH"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- RHOAI Operator ---
log_step "RHOAI Operator"
check_csv_succeeded "redhat-ods-operator" "Red Hat OpenShift AI"

# --- DSCInitialization ---
log_step "DSCInitialization"
check "DSCInitialization exists" \
    "oc get dscinitializations --no-headers 2>/dev/null | wc -l | tr -d ' '" \
    "1"

# --- DataScienceCluster ---
log_step "DataScienceCluster"
check "DataScienceCluster phase Ready" \
    "oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'" \
    "Ready"
check "MLflow Operator managed" \
    "oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.mlflowoperator.managementState}'" \
    "Managed"

# --- Hardware Profiles ---
log_step "Hardware Profiles"
HP_COUNT=$(oc get hardwareprofiles -n redhat-ods-applications --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$HP_COUNT" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} Hardware Profiles found: $HP_COUNT"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} No Hardware Profiles found in redhat-ods-applications"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- GenAI Studio ---
log_step "GenAI Studio"
check "GenAI Studio enabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.genAiStudio}'" \
    "true"

# --- Models-as-a-Service ---
log_step "Models-as-a-Service"
check "MaaS component enabled" \
    "oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.kserve.modelsAsService.managementState}'" \
    "Managed"
check "MaaS dashboard enabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.modelAsService}'" \
    "true"
check "MaaS vLLM dashboard flag enabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.vLLMDeploymentOnMaaS}'" \
    "true"
check "MaaS admin policies enabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.maasAuthPolicies}'" \
    "true"
MAAS_DB_URL=$(oc get secret maas-db-config -n redhat-ods-applications -o jsonpath='{.data.DB_CONNECTION_URL}' 2>/dev/null || true)
if [[ -n "$MAAS_DB_URL" ]]; then
    echo -e "${GREEN}[PASS]${NC} MaaS DB connection secret exists"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} MaaS DB connection secret missing"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
check_pods_ready "redhat-ods-applications" "app=maas-postgres" 1
check "MaaS Gateway programmed" \
    "oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type==\"Programmed\")].status}'" \
    "True"
check "MaaS Gateway Authorino TLS bootstrap" \
    "oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.metadata.annotations.security\\.opendatahub\\.io/authorino-tls-bootstrap}'" \
    "true"

# --- Dashboard Access ---
log_step "Dashboard Access"
# RHOAI 3.4 uses Gateway API (HTTPRoute), not OpenShift Routes
DASHBOARD_HTTPROUTE=$(oc get httproute rhods-dashboard -n redhat-ods-applications -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
DASHBOARD_ROUTE=$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -n "$DASHBOARD_HTTPROUTE" ]]; then
    echo -e "${GREEN}[PASS]${NC} Dashboard HTTPRoute exists (RHOAI 3.4 Gateway API)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
elif [[ -n "$DASHBOARD_ROUTE" ]]; then
    echo -e "${GREEN}[PASS]${NC} Dashboard Route exists"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Dashboard not accessible (no HTTPRoute or Route found)"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Summary ---
echo ""
validation_summary
