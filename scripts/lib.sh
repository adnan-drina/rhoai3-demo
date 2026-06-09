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
    local request_timeout="${RHOAI_OC_REQUEST_TIMEOUT:-10s}"

    oc --request-timeout="$request_timeout" whoami &>/dev/null || {
        log_error "Not logged in or OpenShift API did not respond within ${request_timeout}."
        log_error "Run: oc login <cluster>"
        exit 1
    }

    local server expected
    server="$(oc --request-timeout="$request_timeout" whoami --show-server 2>/dev/null || true)"
    expected="${RHOAI_EXPECTED_API_SERVER:-${RHOAI_EXPECTED_CLUSTER:-}}"

    if [[ -z "$expected" && "${RHOAI_ALLOW_UNGUARDED_CLUSTER:-false}" != "true" ]]; then
        log_error "OpenShift API server guard is not configured"
        log_error "  Set RHOAI_EXPECTED_API_SERVER in .env to a unique target API-server substring."
        log_error "  Current API: ${server:-unknown}"
        log_error "  To bypass intentionally, set RHOAI_ALLOW_UNGUARDED_CLUSTER=true."
        exit 43
    fi

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

repair_maas_authconfig_for_authorino_upgrade() {
    if ! oc get crd authconfigs.authorino.kuadrant.io &>/dev/null; then
        return 0
    fi

    local authconfigs authconfig yaml
    authconfigs="$(
        oc get authconfig -n kuadrant-system \
            -o jsonpath='{range .items[?(@.metadata.annotations.HTTPRouteRule\.gateway\.networking\.k8s\.io=="httproute.gateway.networking.k8s.io:redhat-ods-applications/maas-api-route#rule-2")]}{.metadata.name}{"\n"}{end}' \
            2>/dev/null || true
    )"

    if [[ -z "$authconfigs" ]]; then
        return 0
    fi

    while IFS= read -r authconfig; do
        [[ -z "$authconfig" ]] && continue
        yaml="$(oc get authconfig "$authconfig" -n kuadrant-system -o yaml 2>/dev/null || true)"
        if [[ "$yaml" != *"predicate:"* ]]; then
            continue
        fi

        log_info "Repairing MaaS AuthConfig ${authconfig} for Authorino v1beta2 schema compatibility"
        oc patch authconfig "$authconfig" -n kuadrant-system --type=json -p='[
          {"op":"replace","path":"/spec/authentication/openshift-identities/when/0","value":{"operator":"matches","selector":"request.headers.authorization","value":"^Bearer (sha256~|eyJ).*"}},
          {"op":"replace","path":"/spec/response/success/headers/X-MaaS-Group-OC/when/0","value":{"operator":"matches","selector":"request.headers.authorization","value":"^Bearer (sha256~|eyJ).*"}},
          {"op":"replace","path":"/spec/response/success/headers/X-MaaS-Username-OC/when/0","value":{"operator":"matches","selector":"request.headers.authorization","value":"^Bearer (sha256~|eyJ).*"}}
        ]' \
            && log_success "MaaS AuthConfig ${authconfig} is Authorino-upgrade compatible" \
            || log_warn "Could not patch MaaS AuthConfig ${authconfig}; inspect RHCL install plans if Authorino upgrade is blocked"
    done <<< "$authconfigs"
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

maas_gateway_service_name() {
    local gateway_class expected_service
    gateway_class="$(oc get gateway maas-default-gateway -n openshift-ingress \
        -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null || true)"
    if [[ -n "$gateway_class" ]]; then
        expected_service="maas-default-gateway-${gateway_class}"
        if oc get service "$expected_service" -n openshift-ingress &>/dev/null; then
            printf '%s' "$expected_service"
            return 0
        fi
    fi

    oc get service -n openshift-ingress -o json 2>/dev/null | python3 -c '
import json
import sys

data = json.load(sys.stdin)
for item in data.get("items", []):
    name = item.get("metadata", {}).get("name", "")
    ports = item.get("spec", {}).get("ports", [])
    has_https = any(str(port.get("port")) == "443" or str(port.get("targetPort")) == "443" for port in ports)
    if name.startswith("maas-default-gateway-") and has_https:
        print(name)
        break
' || true
}

configure_maas_gateway_route() {
    local apps_domain maas_host service_ca ca_json http_code token maas_service

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

    maas_service="$(maas_gateway_service_name)"
    if [[ -z "$maas_service" ]]; then
        log_warn "Could not find the live MaaS Gateway service in openshift-ingress"
        return 1
    fi

    maas_host="maas.${apps_domain}"
    ca_json="$(printf '%s' "$service_ca" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"

    if ! oc get route maas-gateway -n openshift-ingress &>/dev/null; then
        oc create route reencrypt maas-gateway -n openshift-ingress \
            --service="$maas_service" \
            --port=443 \
            --hostname="$maas_host" \
            --insecure-policy=Redirect \
            --dry-run=client -o yaml | oc apply -f - >/dev/null
    fi

    oc patch route maas-gateway -n openshift-ingress --type merge \
        -p "{\"spec\":{\"host\":\"${maas_host}\",\"to\":{\"kind\":\"Service\",\"name\":\"${maas_service}\",\"weight\":100},\"port\":{\"targetPort\":\"443\"},\"tls\":{\"termination\":\"reencrypt\",\"insecureEdgeTerminationPolicy\":\"Redirect\",\"destinationCACertificate\":${ca_json}}}}" >/dev/null
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
    local service_name
    service_name="$(maas_gateway_service_name)"
    if [[ -z "$service_name" ]]; then
        service_name="maas-default-gateway-data-science-gateway-class"
    fi
    printf 'https://%s.openshift-ingress.svc/v1' "$service_name"
}

ensure_maas_api_key() {
    local namespace="$1"
    local secret_name="$2"
    local key_name="$3"
    local subscription="${4:-enterprise-demo-subscription}"
    local expires_in="${5:-24h}"

    local external_url internal_url existing_key existing_expires_in http_code response api_key api_key_id key_owner
    external_url="$(maas_external_url)" || {
        log_error "MaaS route openshift-ingress/maas-gateway not found. Deploy step-02 first."
        return 1
    }
    internal_url="$(maas_internal_base_url)"

    key_owner="$(oc whoami 2>/dev/null || echo unknown)"
    existing_key="$(oc get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.MAAS_API_KEY}' 2>/dev/null | base64 -d 2>/dev/null || true)"
    existing_expires_in="$(oc get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.MAAS_EXPIRES_IN}' 2>/dev/null | base64 -d 2>/dev/null || true)"
    if [[ -n "$existing_key" && "$existing_expires_in" == "$expires_in" ]]; then
        http_code="$(curl -sk -o /dev/null -w '%{http_code}' \
            -H "Authorization: Bearer $existing_key" \
            "${external_url}/v1/models" 2>/dev/null || echo "000")"
        if [[ "$http_code" == "200" ]]; then
            patch_secret_literal "$namespace" "$secret_name" "MAAS_KEY_OWNER" "$key_owner"
            patch_secret_literal "$namespace" "$secret_name" "MAAS_BASE_URL" "$internal_url"
            patch_secret_literal "$namespace" "$secret_name" "MAAS_EXTERNAL_URL" "${external_url}/v1"
            patch_secret_literal "$namespace" "$secret_name" "MAAS_SUBSCRIPTION" "$subscription"
            log_success "MaaS API key secret $namespace/$secret_name is valid"
            return 0
        fi
        log_warn "Existing MaaS API key secret $namespace/$secret_name did not validate (HTTP $http_code); rotating"
    elif [[ -n "$existing_key" ]]; then
        log_warn "Existing MaaS API key secret $namespace/$secret_name has expiry '${existing_expires_in:-unknown}' (expected ${expires_in}); rotating"
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
        --from-literal=MAAS_KEY_OWNER="$key_owner" \
        --from-literal=MAAS_BASE_URL="$internal_url" \
        --from-literal=MAAS_EXTERNAL_URL="${external_url}/v1" \
        --from-literal=MAAS_SUBSCRIPTION="$subscription" \
        --from-literal=MAAS_EXPIRES_IN="$expires_in" \
        --dry-run=client -o yaml | oc apply -f - >/dev/null

    log_success "Created MaaS API key secret $namespace/$secret_name"
}

ensure_maas_user_api_key() {
    local username="$1"
    local password="$2"
    local namespace="$3"
    local secret_name="$4"
    local key_name="$5"
    local subscription="${6:-enterprise-demo-subscription}"
    local expires_in="${7:-60d}"

    local external_url internal_url existing_key existing_key_owner existing_expires_in http_code api_server kubeconfig token response api_key api_key_id
    external_url="$(maas_external_url)" || {
        log_error "MaaS route openshift-ingress/maas-gateway not found. Deploy step-02 first."
        return 1
    }
    internal_url="$(maas_internal_base_url)"

    existing_key="$(oc get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.MAAS_API_KEY}' 2>/dev/null | base64 -d 2>/dev/null || true)"
    existing_key_owner="$(oc get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.MAAS_KEY_OWNER}' 2>/dev/null | base64 -d 2>/dev/null || true)"
    existing_expires_in="$(oc get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.MAAS_EXPIRES_IN}' 2>/dev/null | base64 -d 2>/dev/null || true)"
    if [[ -n "$existing_key" && "$existing_key_owner" == "$username" && "$existing_expires_in" == "$expires_in" ]]; then
        http_code="$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' \
            -H "Authorization: Bearer $existing_key" \
            "${external_url}/v1/models" 2>/dev/null || echo "000")"
        if [[ "$http_code" == "200" ]]; then
            patch_secret_literal "$namespace" "$secret_name" "MAAS_BASE_URL" "$internal_url"
            patch_secret_literal "$namespace" "$secret_name" "MAAS_EXTERNAL_URL" "${external_url}/v1"
            patch_secret_literal "$namespace" "$secret_name" "MAAS_SUBSCRIPTION" "$subscription"
            log_success "MaaS user API key secret $namespace/$secret_name is valid for $username"
            return 0
        fi
        log_warn "Existing MaaS user API key secret $namespace/$secret_name did not validate (HTTP $http_code); rotating"
    elif [[ -n "$existing_key" ]]; then
        log_warn "Existing MaaS user API key secret $namespace/$secret_name has owner '${existing_key_owner:-unknown}' and expiry '${existing_expires_in:-unknown}' (expected ${username}/${expires_in}); rotating"
    fi

    api_server="$(oc whoami --show-server 2>/dev/null || true)"
    if [[ -z "$api_server" ]]; then
        log_error "Could not determine current OpenShift API server"
        return 1
    fi

    kubeconfig="$(mktemp)"
    if ! KUBECONFIG="$kubeconfig" oc login "$api_server" \
        -u "$username" -p "$password" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
        rm -f "$kubeconfig"
        log_error "Could not log in as $username to create a user-owned MaaS API key"
        return 1
    fi

    token="$(KUBECONFIG="$kubeconfig" oc whoami -t 2>/dev/null || true)"
    rm -f "$kubeconfig"
    if [[ -z "$token" ]]; then
        log_error "Could not get OpenShift token for $username"
        return 1
    fi

    response="$(curl -sk --max-time 30 \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "{\"name\":\"${key_name}\",\"description\":\"RHOAI demo persistent user key for ${username}\",\"expiresIn\":\"${expires_in}\",\"subscription\":\"${subscription}\"}" \
        "${external_url}/maas-api/v1/api-keys")"

    api_key="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))' 2>/dev/null || true)"
    api_key_id="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)"
    if [[ -z "$api_key" ]]; then
        log_error "MaaS user API key creation failed for ${username}/${key_name}"
        log_error "$response"
        return 1
    fi

    http_code="$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer $api_key" \
        "${external_url}/v1/models" 2>/dev/null || echo "000")"
    if [[ "$http_code" != "200" ]]; then
        log_error "Created MaaS user API key for ${username}, but /v1/models returned HTTP ${http_code}"
        return 1
    fi

    oc create secret generic "$secret_name" -n "$namespace" \
        --from-literal=MAAS_API_KEY="$api_key" \
        --from-literal=MAAS_API_KEY_ID="$api_key_id" \
        --from-literal=MAAS_KEY_OWNER="$username" \
        --from-literal=MAAS_BASE_URL="$internal_url" \
        --from-literal=MAAS_EXTERNAL_URL="${external_url}/v1" \
        --from-literal=MAAS_SUBSCRIPTION="$subscription" \
        --from-literal=MAAS_EXPIRES_IN="$expires_in" \
        --dry-run=client -o yaml | oc apply -f - >/dev/null

    log_success "Created MaaS user API key secret $namespace/$secret_name for $username (${expires_in})"
}

patch_secret_literal() {
    local namespace="$1" secret_name="$2" key="$3" value="$4"
    local encoded
    encoded="$(printf '%s' "$value" | base64 | tr -d '\n')"
    oc patch secret "$secret_name" -n "$namespace" --type merge \
        -p "{\"data\":{\"${key}\":\"${encoded}\"}}" >/dev/null
}
