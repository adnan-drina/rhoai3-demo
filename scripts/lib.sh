#!/usr/bin/env bash
# Shared helper functions for RHOAI demo scripts

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BLUE}▶ $*${NC}"; }

load_env() {
    local env_file="${REPO_ROOT:-.}/.env"
    if [[ -f "$env_file" ]]; then
        set -a; source "$env_file"; set +a
    fi
}

check_oc_logged_in() {
    oc whoami &>/dev/null || { log_error "Not logged in. Run: oc login <cluster>"; exit 1; }

    local server expected
    server="$(oc whoami --show-server 2>/dev/null || true)"
    expected="${RHOAI_EXPECTED_API_SERVER:-${RHOAI_EXPECTED_CLUSTER:-}}"

    if [[ -n "$expected" && "$server" != *"$expected"* ]]; then
        log_error "OpenShift API server guard failed"
        log_error "  expected: $expected"
        log_error "  actual:   $server"
        exit 42
    fi

    if [[ -n "$server" ]]; then
        log_info "OpenShift API: $server"
    fi
}

ensure_namespace() {
    local ns="$1"
    oc get namespace "$ns" &>/dev/null || oc create namespace "$ns"
}

ensure_secret_from_env() {
    local name="$1" ns="$2"; shift 2
    oc create secret generic "$name" -n "$ns" "${@/#/--from-literal=}" \
        --dry-run=client -o yaml | oc apply -f -
}

wait_for_crd() {
    local crd="$1" timeout="${2:-120}" elapsed=0
    log_info "Waiting for CRD $crd (timeout ${timeout}s)..."
    until oc get crd "$crd" &>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $elapsed -ge $timeout ]; then
            log_error "Timeout waiting for CRD $crd after ${timeout}s"
            return 1
        fi
    done
}

find_machineset_for_instance_type() {
    local instance_type="$1"
    oc get machineset -n openshift-machine-api -o json 2>/dev/null | python3 -c '
import json
import sys

instance_type = sys.argv[1]
data = json.load(sys.stdin)
for item in data.get("items", []):
    provider = (
        item.get("spec", {})
        .get("template", {})
        .get("spec", {})
        .get("providerSpec", {})
        .get("value", {})
    )
    if provider.get("instanceType") == instance_type:
        print(item["metadata"]["name"])
        break
' "$instance_type"
}

gpu_ready_node_count() {
    local instance_type="$1" required_gpus="$2"
    oc get nodes -l "node.kubernetes.io/instance-type=${instance_type}" -o json 2>/dev/null | python3 -c '
import json
import sys

required = int(sys.argv[1])
data = json.load(sys.stdin)
count = 0
for node in data.get("items", []):
    ready = any(
        condition.get("type") == "Ready" and condition.get("status") == "True"
        for condition in node.get("status", {}).get("conditions", [])
    )
    raw_gpu = node.get("status", {}).get("allocatable", {}).get("nvidia.com/gpu", "0")
    try:
        gpus = int(raw_gpu)
    except ValueError:
        gpus = 0
    if ready and gpus >= required:
        count += 1
print(count)
' "$required_gpus"
}

ensure_gpu_machineset_ready() {
    local instance_type="$1" required_gpus="$2" timeout="${3:-1200}" elapsed=0
    local machineset desired ready_count

    machineset="$(find_machineset_for_instance_type "$instance_type")"
    if [[ -z "$machineset" ]]; then
        log_warn "No GPU MachineSet found for ${instance_type}; run Step 01 before serving MaaS models"
        return 1
    fi

    desired="$(oc get machineset "$machineset" -n openshift-machine-api -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")"
    if [[ "${desired:-0}" -lt 1 ]]; then
        log_info "Scaling MachineSet ${machineset} (${instance_type}) to 1 replica"
        oc scale machineset "$machineset" -n openshift-machine-api --replicas=1 >/dev/null
    fi

    log_info "Waiting for ${instance_type} node to report ${required_gpus} GPU(s)"
    while [[ $elapsed -le $timeout ]]; do
        ready_count="$(gpu_ready_node_count "$instance_type" "$required_gpus")"
        if [[ "${ready_count:-0}" -ge 1 ]]; then
            log_success "${instance_type} GPU node is ready"
            return 0
        fi
        sleep 20
        elapsed=$((elapsed + 20))
        if (( elapsed % 120 == 0 )); then
            log_info "  Waiting for ${instance_type} GPU readiness... (${elapsed}s elapsed)"
        fi
    done

    log_warn "${instance_type} did not report ${required_gpus} GPU(s) within ${timeout}s"
    return 1
}

get_apps_domain() {
    oc get ingresscontroller default -n openshift-ingress-operator \
        -o jsonpath='{.status.domain}' 2>/dev/null
}

get_service_ca_bundle() {
    oc get configmap openshift-service-ca.crt -n openshift-ingress \
        -o jsonpath='{.data.service-ca\.crt}' 2>/dev/null \
        || oc get configmap service-ca-bundle -n openshift-ingress \
            -o jsonpath='{.data.service-ca\.crt}' 2>/dev/null
}

configure_maas_gateway_route() {
    local apps_domain maas_host service_ca ca_json http_code token

    apps_domain="$(get_apps_domain)"
    if [[ -z "$apps_domain" ]]; then
        log_warn "Could not determine OpenShift apps domain; MaaS route host was not patched"
        return 1
    fi

    service_ca="$(get_service_ca_bundle)"
    if [[ -z "$service_ca" ]]; then
        log_warn "Could not read OpenShift service CA bundle; MaaS route TLS was not patched"
        return 1
    fi

    if ! oc get route maas-gateway -n openshift-ingress &>/dev/null; then
        log_warn "MaaS route openshift-ingress/maas-gateway is not available yet"
        return 1
    fi

    maas_host="maas.${apps_domain}"
    ca_json="$(printf '%s' "$service_ca" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"

    oc patch route maas-gateway -n openshift-ingress --type merge \
        -p "{\"spec\":{\"host\":\"${maas_host}\",\"tls\":{\"termination\":\"reencrypt\",\"insecureEdgeTerminationPolicy\":\"Redirect\",\"destinationCACertificate\":${ca_json}}}}" >/dev/null
    oc annotate route maas-gateway -n openshift-ingress openshift.io/host.generated- >/dev/null 2>&1 || true

    token="$(oc whoami -t 2>/dev/null || true)"
    if [[ -n "$token" ]]; then
        http_code="$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' \
            -H "Authorization: Bearer ${token}" \
            "https://${maas_host}/maas-api/health" 2>/dev/null || echo "000")"
        if [[ "$http_code" == "200" ]]; then
            log_success "MaaS gateway route configured: https://${maas_host}/maas-api"
            return 0
        fi
        log_warn "MaaS gateway route patched, but health returned HTTP ${http_code}"
        return 1
    fi

    log_success "MaaS gateway route configured: https://${maas_host}/maas-api"
}

maas_external_url() {
    local host
    host="$(oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.host}' 2>/dev/null || true)"
    if [[ -z "$host" ]]; then
        return 1
    fi
    printf 'https://%s' "$host"
}

maas_internal_base_url() {
    printf 'https://maas-default-gateway-data-science-gateway-class.openshift-ingress.svc/v1'
}

ensure_maas_api_key() {
    local namespace="$1"
    local secret_name="$2"
    local key_name="$3"
    local subscription="${4:-enterprise-demo-subscription}"
    local expires_in="${5:-24h}"

    local external_url internal_url existing_key http_code response api_key api_key_id
    external_url="$(maas_external_url)" || {
        log_error "MaaS route openshift-ingress/maas-gateway not found. Deploy step-02 first."
        return 1
    }
    internal_url="$(maas_internal_base_url)"

    existing_key="$(oc get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.MAAS_API_KEY}' 2>/dev/null | base64 -d 2>/dev/null || true)"
    if [[ -n "$existing_key" ]]; then
        http_code="$(curl -sk -o /dev/null -w '%{http_code}' \
            -H "Authorization: Bearer $existing_key" \
            "${external_url}/v1/models" 2>/dev/null || echo "000")"
        if [[ "$http_code" == "200" ]]; then
            log_success "MaaS API key secret $namespace/$secret_name is valid"
            return 0
        fi
        log_warn "Existing MaaS API key secret $namespace/$secret_name did not validate (HTTP $http_code); rotating"
    fi

    response="$(curl -sk \
        -H "Authorization: Bearer $(oc whoami -t)" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "{\"name\":\"${key_name}\",\"description\":\"RHOAI demo system access for ${namespace}\",\"expiresIn\":\"${expires_in}\",\"subscription\":\"${subscription}\"}" \
        "${external_url}/maas-api/v1/api-keys")"

    api_key="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))' 2>/dev/null || true)"
    api_key_id="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)"
    if [[ -z "$api_key" ]]; then
        log_error "MaaS API key creation failed for ${key_name}"
        log_error "$response"
        return 1
    fi

    oc create secret generic "$secret_name" -n "$namespace" \
        --from-literal=MAAS_API_KEY="$api_key" \
        --from-literal=MAAS_API_KEY_ID="$api_key_id" \
        --from-literal=MAAS_BASE_URL="$internal_url" \
        --from-literal=MAAS_EXTERNAL_URL="${external_url}/v1" \
        --from-literal=MAAS_SUBSCRIPTION="$subscription" \
        --dry-run=client -o yaml | oc apply -f - >/dev/null

    log_success "Created MaaS API key secret $namespace/$secret_name"
}

patch_secret_literal() {
    local namespace="$1" secret_name="$2" key="$3" value="$4"
    local encoded
    encoded="$(printf '%s' "$value" | base64 | tr -d '\n')"
    oc patch secret "$secret_name" -n "$namespace" --type merge \
        -p "{\"data\":{\"${key}\":\"${encoded}\"}}" >/dev/null
}
