#!/usr/bin/env bash
# Step 01: GPU Infrastructure & RHOAI Prerequisites — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 01: GPU Infrastructure & Prerequisites — Validation      ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Argo CD Application ---
log_step "Argo CD Application"
SYNC=$(oc get applications.argoproj.io step-01-gpu-and-prereq -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NOT_FOUND")
HEALTH=$(oc get applications.argoproj.io step-01-gpu-and-prereq -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "NOT_FOUND")
if [[ "$SYNC" == "Synced" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app 'step-01-gpu-and-prereq' sync: Synced"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} Argo CD app 'step-01-gpu-and-prereq' sync: $SYNC (self-heal is disabled for GPU and operator runtime changes)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi
if [[ "$HEALTH" == "Healthy" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app 'step-01-gpu-and-prereq' health: Healthy"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Argo CD app 'step-01-gpu-and-prereq' health: $HEALTH"
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

check_subscription_field() {
    local namespace="$1"
    local subscription="$2"
    local jsonpath="$3"
    local expected="$4"
    local label="$5"
    local actual

    actual=$(oc get subscription "$subscription" -n "$namespace" -o jsonpath="$jsonpath" 2>/dev/null || true)
    if [[ "$actual" == "$expected" ]]; then
        echo -e "${GREEN}[PASS]${NC} $label: $actual"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} $label (expected: $expected, got: ${actual:-missing})"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
}

check_subscription_absent() {
    local namespace="$1"
    local subscription="$2"
    local label="$3"

    if oc get subscription "$subscription" -n "$namespace" &>/dev/null; then
        echo -e "${RED}[FAIL]${NC} Legacy subscription still exists: $label ($subscription in $namespace)"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    else
        echo -e "${GREEN}[PASS]${NC} Legacy subscription absent: $label"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    fi
}

# --- CRDs ---
log_step "Required CRDs"
check_crd_exists "nodefeaturediscoveries.nfd.openshift.io"
check_crd_exists "clusterpolicies.nvidia.com"
check_crd_exists "knativeservings.operator.knative.dev"
check_crd_exists "monitoringstacks.monitoring.rhobs"
check_crd_exists "perses.perses.dev"
check_crd_exists "persesdashboards.perses.dev"
check_crd_exists "persesdatasources.perses.dev"
check_crd_exists "tempomonolithics.tempo.grafana.com"
check_crd_exists "opentelemetrycollectors.opentelemetry.io"
check_crd_exists "kueues.kueue.openshift.io"
check_crd_exists "authconfigs.authorino.kuadrant.io"
check_crd_exists "authorinos.operator.authorino.kuadrant.io"
check_crd_exists "kuadrants.kuadrant.io"
check_crd_exists "authpolicies.kuadrant.io"
check_crd_exists "tokenratelimitpolicies.kuadrant.io"

# --- Operator CSVs ---
log_step "Operator CSVs"
check_subscription_csv_succeeded "openshift-nfd" "nfd" "Node Feature Discovery"
check_subscription_csv_succeeded "nvidia-gpu-operator" "gpu-operator-certified" "NVIDIA GPU Operator"
check_subscription_csv_succeeded "openshift-serverless" "serverless-operator" "OpenShift Serverless"
check_subscription_csv_succeeded "openshift-cluster-observability-operator" "cluster-observability-operator" "Cluster Observability Operator"
check_subscription_csv_succeeded "openshift-tempo-operator" "tempo-product" "Tempo Operator"
check_subscription_csv_succeeded "openshift-opentelemetry-operator" "opentelemetry-product" "Red Hat build of OpenTelemetry"
check_subscription_csv_succeeded "openshift-kueue-operator" "kueue-operator" "Red Hat build of Kueue"
check_subscription_csv_succeeded "openshift-operators" "rhcl-operator" "Red Hat Connectivity Link"
check_subscription_csv_succeeded "openshift-operators" "authorino-operator-stable-redhat-operators-rhoai-openshift-marketplace" "RHCL Authorino dependency"
check_subscription_csv_succeeded "openshift-operators" "limitador-operator-stable-redhat-operators-rhoai-openshift-marketplace" "RHCL Limitador dependency"
check_subscription_csv_succeeded "openshift-operators" "dns-operator-stable-redhat-operators-rhoai-openshift-marketplace" "RHCL DNS dependency"

log_step "Operator Subscription Alignment"
check_subscription_field "openshift-operators" "rhcl-operator" "{.spec.source}" "redhat-operators-rhoai" "RHCL catalog source"
check_subscription_field "openshift-operators" "rhcl-operator" "{.spec.startingCSV}" "rhcl-operator.v1.3.4" "RHCL RHOAI 3.4 starting CSV"
check_subscription_absent "openshift-authorino" "authorino-operator" "standalone Authorino"
check_subscription_absent "openshift-limitador-operator" "limitador-operator" "standalone Limitador"
check_subscription_absent "openshift-dns-operator" "dns-operator" "standalone DNS Operator"

# --- Observability Operator Runtime Networking ---
log_step "Observability Operator Runtime Networking"
API_SERVICE_IP=$(oc get service kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
check "Tempo Operator egress to Kubernetes service IP" \
    "oc get networkpolicy tempo-operator-egress-to-kubernetes-service -n openshift-tempo-operator -o jsonpath='{.spec.egress[0].to[0].ipBlock.cidr}'" \
    "${API_SERVICE_IP}/32"
check "Tempo Operator deployment available" \
    "oc get deployment tempo-operator-controller -n openshift-tempo-operator -o jsonpath='{.status.availableReplicas}'" \
    "1"
check "Tempo Operator webhook endpoint exists" \
    "oc get endpoints tempo-operator-controller-service -n openshift-tempo-operator -o jsonpath='{.subsets[*].addresses[*].ip}'" \
    "."

# --- KnativeServing ---
log_step "KnativeServing"
check "KnativeServing ready" \
    "oc get knativeserving knative-serving -n knative-serving -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
    "True"

# --- Kuadrant / RHCL ---
log_step "Red Hat Connectivity Link"
check "Kuadrant ready" \
    "oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
    "True"
check "Kuadrant observability enabled" \
    "oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.spec.observability.enable}'" \
    "true"
check "Limitador detailed telemetry enabled" \
    "oc get limitador limitador -n kuadrant-system -o jsonpath='{.spec.telemetry}'" \
    "exhaustive"
check "Limitador PodMonitor exists" \
    "oc get podmonitor.monitoring.coreos.com kuadrant-limitador-monitor -n kuadrant-system -o jsonpath='{.metadata.name}'" \
    "kuadrant-limitador-monitor"
check "Authorino serving certificate annotation" \
    "oc get service authorino-authorino-authorization -n kuadrant-system -o jsonpath='{.metadata.annotations.service\\.beta\\.openshift\\.io/serving-cert-secret-name}'" \
    "authorino-server-cert"
check "Authorino TLS enabled" \
    "oc get authorino authorino -n kuadrant-system -o jsonpath='{.spec.listener.tls.enabled}'" \
    "true"

# --- GPU MachineSets ---
log_step "GPU MachineSets"
MS_COUNT=$(oc get machineset -n openshift-machine-api --no-headers 2>/dev/null \
    | grep -c "gpu" || echo "0")
if [[ "$MS_COUNT" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} GPU MachineSets found: $MS_COUNT"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} No GPU MachineSets found"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# GPU nodes may still be provisioning — warn only
GPU_NODES=$(oc get nodes -l node-role.kubernetes.io/gpu --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$GPU_NODES" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} GPU nodes available: $GPU_NODES"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} GPU nodes available: $GPU_NODES (may take 5-10 min to provision)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- NFD labels ---
log_step "NFD Labels"
KERNEL_LABELS=$(oc get nodes -o jsonpath='{.items[*].metadata.labels}' 2>/dev/null | grep -c "kernel-version" || echo "0")
if [[ "$KERNEL_LABELS" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} NFD kernel-version labels found on $KERNEL_LABELS nodes"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} NFD kernel-version labels not found (NFD may still be starting)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Summary ---
echo ""
validation_summary
