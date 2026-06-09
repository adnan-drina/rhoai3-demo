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

check_subscription_csv_succeeded() {
    local namespace="$1"
    local subscription="$2"
    local label="$3"
    local installed_csv phase

    installed_csv=$(oc get subscription "$subscription" -n "$namespace" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
    if [[ -z "$installed_csv" ]]; then
        echo -e "${RED}[FAIL]${NC} Subscription missing installed CSV: $label ($subscription in $namespace)"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
        return
    fi

    phase=$(oc get csv "$installed_csv" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Succeeded" ]]; then
        echo -e "${GREEN}[PASS]${NC} CSV succeeded: $label (${installed_csv} in ${namespace})"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} CSV not succeeded: $label (${installed_csv} in ${namespace}, phase: ${phase:-missing})"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
}

# --- RHOAI Operator ---
log_step "RHOAI Operator"
check_subscription_csv_succeeded "redhat-ods-operator" "rhods-operator" "Red Hat OpenShift AI"

RHOAI_CHANNEL=$(oc get subscription rhods-operator -n redhat-ods-operator -o jsonpath='{.spec.channel}' 2>/dev/null || true)
if [[ "$RHOAI_CHANNEL" == "stable-3.x" ]]; then
    echo -e "${GREEN}[PASS]${NC} RHOAI subscription channel: stable-3.x"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} RHOAI subscription channel (expected: stable-3.x, got: ${RHOAI_CHANNEL:-missing})"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Service Mesh 3 side-effect Operator ---
log_step "Service Mesh 3 Operator"
check_subscription_csv_succeeded "openshift-operators" "servicemeshoperator3" "Red Hat OpenShift Service Mesh 3"

SM_CURRENT_CSV=$(oc get subscription servicemeshoperator3 -n openshift-operators -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
SM_STARTING_CSV=$(oc get subscription servicemeshoperator3 -n openshift-operators -o jsonpath='{.spec.startingCSV}' 2>/dev/null || true)
if [[ "$SM_CURRENT_CSV" == servicemeshoperator3.v* && "$SM_STARTING_CSV" == "$SM_CURRENT_CSV" ]]; then
    echo -e "${GREEN}[PASS]${NC} Service Mesh startingCSV is aligned: $SM_STARTING_CSV"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
elif [[ "$SM_CURRENT_CSV" == servicemeshoperator3.v* ]]; then
    echo -e "${YELLOW}[WARN]${NC} Service Mesh startingCSV differs from currentCSV (starting: ${SM_STARTING_CSV:-unset}, current: $SM_CURRENT_CSV)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
else
    echo -e "${YELLOW}[WARN]${NC} Service Mesh currentCSV is not populated yet"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- DSCInitialization ---
log_step "DSCInitialization"
check "DSCInitialization exists" \
    "oc get dscinitializations --no-headers 2>/dev/null | wc -l | tr -d ' '" \
    "1"
check "DSCI monitoring metrics storage configured" \
    "oc get dscinitialization default-dsci -o jsonpath='{.spec.monitoring.metrics.storage.size}'" \
    "5Gi"
check "DSCI monitoring traces backend configured" \
    "oc get dscinitialization default-dsci -o jsonpath='{.spec.monitoring.traces.storage.backend}'" \
    "pv"

METRICS_EXPORTER_COUNT=$(oc get dscinitialization default-dsci -o json 2>/dev/null | jq -r '(.spec.monitoring.metrics.exporters // []) | length' 2>/dev/null || echo "0")
if [[ "$METRICS_EXPORTER_COUNT" -gt 0 ]]; then
    echo -e "${GREEN}[PASS]${NC} DSCI external metrics exporters configured: $METRICS_EXPORTER_COUNT"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${GREEN}[PASS]${NC} DSCI external metrics exporters are not configured by default"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
fi

TRACES_EXPORTER_COUNT=$(oc get dscinitialization default-dsci -o json 2>/dev/null | jq -r '(.spec.monitoring.traces.exporters // []) | length' 2>/dev/null || echo "0")
if [[ "$TRACES_EXPORTER_COUNT" -gt 0 ]]; then
    echo -e "${GREEN}[PASS]${NC} DSCI external traces exporters configured: $TRACES_EXPORTER_COUNT"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${GREEN}[PASS]${NC} DSCI external traces exporters are not configured by default"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
fi

if oc get dscinitialization default-dsci -o json 2>/dev/null | jq -e '.spec.monitoring | has("alerting")' >/dev/null; then
    ALERTMANAGER_PODS=$(oc get pods -n redhat-ods-monitoring -o name 2>/dev/null | grep -c 'alertmanager' || true)
    ALERTMANAGER_SVC=$(oc get svc -n redhat-ods-monitoring -o name 2>/dev/null | grep -c 'alertmanager' || true)
    if [[ "$ALERTMANAGER_PODS" -gt 0 && "$ALERTMANAGER_SVC" -gt 0 ]]; then
        echo -e "${GREEN}[PASS]${NC} DSCI alerting enabled and Alertmanager pods/service exist"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} DSCI alerting enabled but Alertmanager pods/service are missing"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
else
    echo -e "${GREEN}[PASS]${NC} DSCI monitoring alerting branch is deferred and unset"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
fi

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

# --- Dashboard Auth ---
log_step "Dashboard Auth"
AUTH_ADMIN_GROUPS=$(oc get auth auth -o jsonpath='{.spec.adminGroups}' 2>/dev/null || true)
if [[ "$AUTH_ADMIN_GROUPS" == *"rhoai-admins"* ]]; then
    echo -e "${GREEN}[PASS]${NC} RHOAI Auth adminGroups includes rhoai-admins"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} RHOAI Auth adminGroups missing rhoai-admins: ${AUTH_ADMIN_GROUPS:-missing}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

AUTH_ALLOWED_GROUPS=$(oc get auth auth -o jsonpath='{.spec.allowedGroups}' 2>/dev/null || true)
if [[ "$AUTH_ALLOWED_GROUPS" == *"rhoai-users"* ]] && [[ "$AUTH_ALLOWED_GROUPS" == *"system:authenticated"* ]]; then
    echo -e "${GREEN}[PASS]${NC} RHOAI Auth allowedGroups includes rhoai-users and system:authenticated"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} RHOAI Auth allowedGroups drift: ${AUTH_ALLOWED_GROUPS:-missing}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- GenAI Studio ---
log_step "GenAI Studio"
check "GenAI Studio enabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.genAiStudio}'" \
    "true"
check "GenAI internal custom endpoints enabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.aiAssetCustomEndpoints}'" \
    "true"
check "External custom endpoint providers disabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.genAiStudioConfig.aiAssetCustomEndpoints.externalProviders}'" \
    "false"

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
check "Observability dashboard enabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.observabilityDashboard}'" \
    "true"
check "OpenShift AI monitoring service Ready" \
    "oc get monitoring default-monitoring -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
    "True"
check "OpenShift AI MonitoringStack available" \
    "oc get monitoringstack data-science-monitoringstack -n redhat-ods-monitoring -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}'" \
    "True"
check "Perses observability service created" \
    "oc get service data-science-perses -n redhat-ods-monitoring -o jsonpath='{.metadata.name}'" \
    "data-science-perses"
check "Perses Cluster dashboard created" \
    "oc get persesdashboard dashboard-0-cluster-admin -n redhat-ods-monitoring -o jsonpath='{.metadata.name}'" \
    "dashboard-0-cluster-admin"
check "Perses Models dashboard created" \
    "oc get persesdashboard dashboard-1-model -n redhat-ods-monitoring -o jsonpath='{.metadata.name}'" \
    "dashboard-1-model"
check "Perses MaaS Usage dashboard created" \
    "oc get persesdashboard dashboard-3-maas-usage-admin -n redhat-ods-applications -o jsonpath='{.metadata.name}'" \
    "dashboard-3-maas-usage-admin"
check "OpenShift AI Tempo ready" \
    "oc get tempomonolithic data-science-tempomonolithic -n redhat-ods-monitoring -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
    "True"
check "OpenShift AI OpenTelemetryCollector created" \
    "oc get opentelemetrycollector data-science-collector -n redhat-ods-monitoring -o jsonpath='{.metadata.name}'" \
    "data-science-collector"
COLLECTOR_RUNNING=$(oc get pods -n redhat-ods-monitoring --no-headers 2>/dev/null \
    | awk '/data-science-collector-collector/ && $3 == "Running" {count++} END {print count + 0}')
if [[ "$COLLECTOR_RUNNING" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} OpenTelemetry Collector pods running: $COLLECTOR_RUNNING"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} OpenTelemetry Collector pods not running"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
TEMPO_QUERY_SVC=$(oc get svc -n redhat-ods-monitoring -o name 2>/dev/null | grep -E 'tempo.*query|query.*tempo' | head -1 || true)
if [[ -n "$TEMPO_QUERY_SVC" ]]; then
    echo -e "${GREEN}[PASS]${NC} Tempo query service available: $TEMPO_QUERY_SVC"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Tempo query service missing"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
check "User Workload Monitoring enabled" \
    "oc get configmap cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\\.yaml}'" \
    "enableUserWorkload: true"
MAAS_DB_URL=$(oc get secret maas-db-config -n redhat-ods-applications -o jsonpath='{.data.DB_CONNECTION_URL}' 2>/dev/null || true)
if [[ -n "$MAAS_DB_URL" ]]; then
    echo -e "${GREEN}[PASS]${NC} MaaS DB connection secret exists"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} MaaS DB connection secret missing"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
check "MaaS PostgreSQL PVC uses gp3-csi" \
    "oc get pvc maas-postgres-data -n redhat-ods-applications -o jsonpath='{.spec.storageClassName}'" \
    "gp3-csi"
check "MaaS PostgreSQL PVC bound" \
    "oc get pvc maas-postgres-data -n redhat-ods-applications -o jsonpath='{.status.phase}'" \
    "Bound"
check_pods_ready "redhat-ods-applications" "app=maas-postgres" 1
check "MaaS Gateway programmed" \
    "oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type==\"Programmed\")].status}'" \
    "True"
check "MaaS Gateway Authorino TLS bootstrap" \
    "oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.metadata.annotations.security\\.opendatahub\\.io/authorino-tls-bootstrap}'" \
    "true"
check "MaaS Tenant Ready" \
    "oc get tenant default-tenant -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
    "True"
check "MaaS Tenant telemetry enabled" \
    "oc get tenant default-tenant -n models-as-a-service -o jsonpath='{.spec.telemetry.enabled}'" \
    "true"
check "MaaS telemetry captures organization" \
    "oc get tenant default-tenant -n models-as-a-service -o jsonpath='{.spec.telemetry.metrics.captureOrganization}'" \
    "true"
check "MaaS telemetry captures model usage" \
    "oc get tenant default-tenant -n models-as-a-service -o jsonpath='{.spec.telemetry.metrics.captureModelUsage}'" \
    "true"
check "MaaS telemetry captures user for Usage dashboard demo" \
    "oc get tenant default-tenant -n models-as-a-service -o jsonpath='{.spec.telemetry.metrics.captureUser}'" \
    "true"
check "MaaS telemetry avoids group-cardinality by default" \
    "oc get tenant default-tenant -n models-as-a-service -o jsonpath='{.spec.telemetry.metrics.captureGroup}'" \
    "false"
check "MaaS Istio Telemetry resource created" \
    "oc get telemetry latency-per-subscription -n openshift-ingress -o jsonpath='{.metadata.name}'" \
    "latency-per-subscription"
MAAS_GATEWAY_ROUTE=$(oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [[ -n "$MAAS_GATEWAY_ROUTE" ]]; then
    APPS_DOMAIN=$(get_apps_domain)
    EXPECTED_MAAS_ROUTE="maas.${APPS_DOMAIN}"
    if [[ "$MAAS_GATEWAY_ROUTE" == "$EXPECTED_MAAS_ROUTE" ]]; then
        echo -e "${GREEN}[PASS]${NC} MaaS Gateway route uses product host: $MAAS_GATEWAY_ROUTE"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} MaaS Gateway route host drift (expected: $EXPECTED_MAAS_ROUTE, got: $MAAS_GATEWAY_ROUTE)"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
    check "MaaS Gateway route uses re-encrypt TLS" \
        "oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.tls.termination}'" \
        "reencrypt"
    HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $(oc whoami -t)" \
        "https://${MAAS_GATEWAY_ROUTE}/maas-api/health" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo -e "${GREEN}[PASS]${NC} MaaS Gateway route health responds with verified TLS"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} MaaS Gateway route health returned HTTP $HTTP_CODE"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
else
    echo -e "${RED}[FAIL]${NC} MaaS Gateway route missing"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

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
