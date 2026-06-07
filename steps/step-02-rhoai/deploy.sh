#!/usr/bin/env bash
# Step 02: Red Hat OpenShift AI 3.4 - Deploy Script
# Deploys RHOAI 3.4 Platform Layer:
# - RHOAI Operator (stable-3.x channel)
# - DSCInitialization (Service Mesh: Managed)
# - DataScienceCluster with full 3.4 components
# - Auth resource for user/admin groups
# - GenAI Studio configuration
# - Hardware Profiles for AWS G6 GPU nodes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-02-rhoai"

load_env
check_oc_logged_in

configure_observability_exporters() {
    local patch

    patch="$(python3 - <<'PY'
import json
import os

monitoring = {}

metrics_endpoint = os.environ.get("RHOAI_OBSERVABILITY_METRICS_EXPORTER_ENDPOINT", "").strip()
if metrics_endpoint:
    monitoring["metrics"] = {
        "exporters": [
            {
                "name": os.environ.get("RHOAI_OBSERVABILITY_METRICS_EXPORTER_NAME", "external-metrics"),
                "type": os.environ.get("RHOAI_OBSERVABILITY_METRICS_EXPORTER_TYPE", "otlp"),
                "endpoint": metrics_endpoint,
            }
        ]
    }

traces_endpoint = os.environ.get("RHOAI_OBSERVABILITY_TRACES_EXPORTER_ENDPOINT", "").strip()
if traces_endpoint:
    monitoring["traces"] = {
        "exporters": [
            {
                "name": os.environ.get("RHOAI_OBSERVABILITY_TRACES_EXPORTER_NAME", "external-traces"),
                "type": os.environ.get("RHOAI_OBSERVABILITY_TRACES_EXPORTER_TYPE", "otlp"),
                "endpoint": traces_endpoint,
            }
        ]
    }

print(json.dumps({"spec": {"monitoring": monitoring}} if monitoring else {}))
PY
)"

    if [[ "$patch" == "{}" ]]; then
        log_info "No external observability exporters configured; set RHOAI_OBSERVABILITY_*_EXPORTER_ENDPOINT to opt in"
        return 0
    fi

    oc patch dscinitializations default-dsci --type merge -p "$patch" >/dev/null \
        && log_success "Optional DSCI external observability exporters configured" \
        || log_warn "Optional DSCI external observability exporter patch failed"
}

configure_observability_alerting() {
    if [[ "${RHOAI_OBSERVABILITY_ENABLE_ALERTING:-false}" == "true" ]]; then
        oc patch dscinitializations default-dsci --type merge \
            -p '{"spec":{"monitoring":{"alerting":{}}}}' >/dev/null \
            && log_success "Optional DSCI monitoring alerting branch enabled" \
            || log_warn "Optional DSCI monitoring alerting patch failed"
        return 0
    fi

    if [[ "$(oc get dscinitialization default-dsci -o jsonpath='{.spec.monitoring.alerting}' 2>/dev/null || true)" == "{}" ]]; then
        oc patch dscinitializations default-dsci --type=json \
            -p='[{"op":"remove","path":"/spec/monitoring/alerting"}]' 2>/dev/null \
            && log_success "Removed optional DSCI monitoring alerting branch" \
            || log_warn "Could not remove optional DSCI monitoring alerting branch"
    else
        log_info "DSCI monitoring alerting remains deferred; set RHOAI_OBSERVABILITY_ENABLE_ALERTING=true to opt in after verifying the MLflow alert rules issue is resolved"
    fi
}

log_step "Step 02: Red Hat OpenShift AI 3.4"

log_step "Checking prerequisites..."

if ! oc get applications.argoproj.io -n openshift-gitops step-01-gpu-and-prereq &>/dev/null; then
    log_error "step-01-gpu-and-prereq Argo CD Application not found!"
    log_info "Please run: ./steps/step-01-gpu-and-prereq/deploy.sh first"
    exit 1
fi

# Check Serverless is ready (required for KServe)
if ! oc get knativeserving -n knative-serving knative-serving &>/dev/null; then
    log_error "KnativeServing not found - required for KServe"
    log_info "Please ensure step-01-gpu-and-prereq is fully synced"
    exit 1
fi

GPU_NODES=$(oc get nodes -l node-role.kubernetes.io/gpu --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$GPU_NODES" -eq 0 ]]; then
    log_warn "No GPU nodes found with label 'node-role.kubernetes.io/gpu'"
    log_info "Hardware Profiles will be ready but won't schedule until GPU nodes are available"
fi

log_success "Prerequisites verified"

log_step "Creating Argo CD Application for RHOAI"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

log_step "Waiting for RHOAI Operator..."

until oc get namespace redhat-ods-operator &>/dev/null; do
    log_info "Waiting for namespace redhat-ods-operator..."
    sleep 10
done

log_info "Waiting for RHOAI Operator CSV (this may take a few minutes)..."
until oc get csv -n redhat-ods-operator -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift AI")].status.phase}' 2>/dev/null | grep -q "Succeeded"; do
    sleep 15
done
log_success "RHOAI Operator installed"

log_info "Waiting for DSCInitialization CRD..."
until oc get crd dscinitializations.dscinitialization.opendatahub.io &>/dev/null; do
    sleep 5
done
log_success "DSCInitialization CRD available"

log_info "Waiting for DataScienceCluster CRD..."
until oc get crd datascienceclusters.datasciencecluster.opendatahub.io &>/dev/null; do
    sleep 5
done
log_success "DataScienceCluster CRD available"

# Approve Service Mesh 3 install plans (RHOAI forces Manual approval)
# The RHOAI operator auto-creates the servicemeshoperator3 Subscription with
# installPlanApproval: Manual and reconciles it back if changed. We must
# approve pending install plans explicitly to avoid the gateway getting stuck.
log_step "Checking Service Mesh 3 operator..."

log_info "Waiting for servicemeshoperator3 Subscription..."
until oc get subscription servicemeshoperator3 -n openshift-operators &>/dev/null; do
    sleep 10
done

SM_PLANS_APPROVED=0
while IFS='|' read -r plan approved csvs; do
    [[ -z "$plan" || "$approved" == "true" ]] && continue
    if [[ "${csvs,,}" == *"servicemeshoperator3"* ]]; then
        log_info "Approving Service Mesh 3 install plan: $plan"
        oc patch installplan "$plan" -n openshift-operators \
            --type merge -p '{"spec":{"approved":true}}'
        SM_PLANS_APPROVED=$((SM_PLANS_APPROVED + 1))
    fi
done < <(oc get installplan -n openshift-operators -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.approved}{"|"}{.spec.clusterServiceVersionNames}{"\n"}{end}' 2>/dev/null || true)

if [[ "$SM_PLANS_APPROVED" -eq 0 ]]; then
    log_success "No pending Service Mesh 3 install plans require approval"
else
    log_success "Approved Service Mesh 3 install plans: $SM_PLANS_APPROVED"
fi

SM_CSV=$(oc get subscription servicemeshoperator3 -n openshift-operators \
    -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
if [[ -n "$SM_CSV" ]]; then
    log_info "Waiting for Service Mesh CSV ($SM_CSV) to succeed..."
    until [[ "$(oc get csv "$SM_CSV" -n openshift-operators -o jsonpath='{.status.phase}' 2>/dev/null)" == "Succeeded" ]]; do
        sleep 15
    done
    log_success "Service Mesh 3 operator ready"
fi

log_info "Waiting for DataScienceCluster to be created..."
until oc get datasciencecluster default-dsc &>/dev/null; do
    sleep 10
done
log_success "DataScienceCluster created"

log_info "Waiting for DataScienceCluster to become Ready (this may take several minutes)..."
until [[ "$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null)" == "Ready" ]]; do
    PHASE=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    log_info "Current phase: $PHASE"
    sleep 30
done
log_success "DataScienceCluster is Ready"

log_step "Verifying Hardware Profiles..."

until oc get hardwareprofiles -n redhat-ods-applications --no-headers 2>/dev/null | grep -q .; do
    sleep 5
done

PROFILES=$(oc get hardwareprofiles -n redhat-ods-applications -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
log_success "Hardware Profiles available: $PROFILES"

# Patch DSCI with cluster CA bundle (required for LlamaStack TLS)
log_step "Patching DSCI with cluster CA bundle..."

CA_BUNDLE=$(oc get configmap kube-root-ca.crt -n openshift-config -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)
if [[ -n "$CA_BUNDLE" ]]; then
    CA_JSON=$(echo "$CA_BUNDLE" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
    oc patch dscinitializations default-dsci --type merge \
        -p "{\"spec\":{\"trustedCABundle\":{\"managementState\":\"Managed\",\"customCABundle\":${CA_JSON}}}}" 2>/dev/null \
        && log_success "DSCI CA bundle patched" \
        || log_warn "DSCI CA bundle patch failed (may not exist yet)"
else
    log_warn "Could not read cluster CA bundle"
fi

log_step "Ensuring OpenShift AI observability stack is configured..."
oc patch dscinitializations default-dsci --type merge \
    -p '{"spec":{"monitoring":{"managementState":"Managed","namespace":"redhat-ods-monitoring","metrics":{"storage":{"size":"5Gi","retention":"24h"}},"traces":{"sampleRatio":"1.0","storage":{"backend":"pv","size":"5Gi","retention":"24h"}}}}}' 2>/dev/null \
    && log_success "DSCI monitoring configured for the RHOAI observability dashboard" \
    || log_warn "DSCI monitoring patch failed; Step 02 validation will report any drift"
configure_observability_exporters
configure_observability_alerting

for attempt in $(seq 1 60); do
    MONITORING_READY=$(oc get monitoring default-monitoring -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "$MONITORING_READY" == "True" ]]; then
        log_success "OpenShift AI observability stack ready"
        break
    fi
    if [[ "$attempt" -eq 60 ]]; then
        log_warn "OpenShift AI observability stack not Ready yet; continuing with dashboard setup"
        break
    fi
    log_info "Waiting for OpenShift AI observability stack..."
    sleep 10
done

log_step "Ensuring GenAI Studio is enabled..."

until oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications &>/dev/null; do
    sleep 5
done
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
    --type merge -p '{"spec":{"dashboardConfig":{"genAiStudio":true,"aiAssetCustomEndpoints":true,"modelAsService":true,"vLLMDeploymentOnMaaS":true,"maasAuthPolicies":true,"observabilityDashboard":true},"genAiStudioConfig":{"aiAssetCustomEndpoints":{"externalProviders":false,"clusterDomains":[]}}}}' 2>/dev/null \
    && log_success "GenAI Studio, internal custom endpoints, MaaS, and observability dashboard flags enabled" \
    || log_warn "Dashboard feature-flag patch failed"

log_step "Configuring RHOAI dashboard auth groups..."
for attempt in $(seq 1 24); do
    if oc get auth auth &>/dev/null; then
        break
    fi
    sleep 5
done
oc patch auth auth --type merge \
    -p '{"spec":{"adminGroups":["rhoai-admins","system:cluster-admins"],"allowedGroups":["rhoai-users","system:authenticated"]}}' 2>/dev/null \
    && log_success "RHOAI Auth groups aligned for ai-admin and ai-developer demo access" \
    || log_warn "RHOAI Auth group patch failed; Step 02 validation will report any drift"

log_step "Configuring MaaS gateway route for dashboard integration..."
configure_maas_gateway_route || log_warn "MaaS gateway route will be retried by Step 05"

log_step "Enabling MaaS telemetry for usage observability..."
for attempt in $(seq 1 36); do
    if oc get tenant default-tenant -n models-as-a-service &>/dev/null; then
        break
    fi
    sleep 5
done
oc patch tenant default-tenant -n models-as-a-service --type merge \
    -p '{"spec":{"telemetry":{"enabled":true,"metrics":{"captureOrganization":true,"captureUser":true,"captureGroup":false,"captureModelUsage":true}}}}' 2>/dev/null \
    && log_success "MaaS Tenant telemetry enabled" \
    || log_warn "MaaS Tenant telemetry patch failed; Step 02 validation will report any drift"

log_step "Deployment Complete"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "RHOAI 3.4 Platform Deployed Successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Enabled Components:"
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components}' 2>/dev/null | \
  jq -r 'to_entries | .[] | "  • \(.key): \(.value.managementState)"' 2>/dev/null || \
  echo "  (use 'oc get datasciencecluster default-dsc -o yaml' to view)"
echo ""
echo "Hardware Profiles:"
oc get hardwareprofiles -n redhat-ods-applications \
  -o custom-columns=NAME:.metadata.name,DISPLAY:.metadata.annotations."opendatahub\.io/display-name" 2>/dev/null || \
  echo "  (use 'oc get hardwareprofiles -n redhat-ods-applications' to view)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Argo CD Application status:"
echo "  oc get applications.argoproj.io -n openshift-gitops ${STEP_NAME}"
echo ""
log_info "RHOAI status:"
echo "  oc get datasciencecluster default-dsc"
echo "  oc get pods -n redhat-ods-applications"
echo ""
log_info "Dashboard URL:"
DASHBOARD_URL=$(oc get route -n openshift-ingress data-science-gateway -o jsonpath='{.spec.host}' 2>/dev/null \
    || oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null \
    || echo 'loading...')
echo "  https://${DASHBOARD_URL}"
echo ""
