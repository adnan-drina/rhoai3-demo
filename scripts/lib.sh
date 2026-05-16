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
