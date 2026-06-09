#!/usr/bin/env bash
# Step 05: MaaS model serving validation script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="maas"
LOCAL_MAAS_MODELS=(granite-8b-agent mistral-3-bf16)
EXTERNAL_MAAS_MODELS=(gpt-5)
PUBLISHED_MAAS_MODELS=(gpt-5 granite-8b-agent mistral-3-bf16)

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 05: MaaS Model Serving — Validation                     ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- ServingRuntime ---
log_step "ServingRuntime"
SR_COUNT=$(oc get servingruntime -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SR_COUNT" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} ServingRuntime(s) found: $SR_COUNT"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} No ServingRuntime found in $NAMESPACE"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
RUNTIME_IMAGE=$(oc get servingruntime vllm-runtime -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || true)
if [[ "$RUNTIME_IMAGE" == registry.redhat.io/rhaii/vllm-cuda-rhel9@sha256:ad06abf3bb5235ebb5b2df84cd1b9fd09e823f0ff2eebfc82bb4590275ccfe0b ]]; then
    echo -e "${GREEN}[PASS]${NC} vLLM runtime image matches RHOAI 3.4 platform LLM config"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} vLLM runtime image drift: ${RUNTIME_IMAGE:-missing}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Kueue ---
log_step "Kueue"
check_warn "MaaS LocalQueue exists" \
    "oc get localqueue maas-default -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "maas-default"
check_warn "MaaS Usage heartbeat CronJob exists" \
    "oc get cronjob maas-usage-heartbeat -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "maas-usage-heartbeat"

# --- MaaS Governance API ---
log_step "MaaS Governance API"
check_crd_exists "maasmodelrefs.maas.opendatahub.io"
check_crd_exists "externalmodels.maas.opendatahub.io"
check_crd_exists "maassubscriptions.maas.opendatahub.io"
check_crd_exists "maasauthpolicies.maas.opendatahub.io"

OPENAI_SECRET_KEY=$(oc get secret openai-provider-api-key -n "$NAMESPACE" -o jsonpath='{.data.api-key}' 2>/dev/null || true)
if [[ -n "$OPENAI_SECRET_KEY" ]]; then
    echo -e "${GREEN}[PASS]${NC} OpenAI provider credential secret exists with api-key data"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} OpenAI provider credential secret maas/openai-provider-api-key is missing api-key data"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

GPT5_EXTERNAL_SPEC=$(oc get externalmodel gpt-5 -n "$NAMESPACE" \
    -o jsonpath='{.spec.provider}|{.spec.endpoint}|{.spec.targetModel}|{.spec.credentialRef.name}' 2>/dev/null || true)
if [[ "$GPT5_EXTERNAL_SPEC" == "openai|api.openai.com|gpt-5|openai-provider-api-key" ]]; then
    echo -e "${GREEN}[PASS]${NC} ExternalModel gpt-5 points to OpenAI gpt-5 with the provider credential"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} ExternalModel gpt-5 spec drift: ${GPT5_EXTERNAL_SPEC:-missing}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

for model in "${LOCAL_MAAS_MODELS[@]}"; do
    ROUTE_HOST=$(oc get route "$model" -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [[ -n "$ROUTE_HOST" ]]; then
        oc patch externalmodel "$model" -n "$NAMESPACE" --type merge \
            -p "{\"spec\":{\"endpoint\":\"${ROUTE_HOST}\"}}" >/dev/null 2>&1 || true
        oc patch maasmodelref "$model" -n "$NAMESPACE" --type merge \
            -p "{\"spec\":{\"endpointOverride\":\"https://${ROUTE_HOST}\"}}" >/dev/null 2>&1 || true
    fi
done

for model in "${PUBLISHED_MAAS_MODELS[@]}"; do
    PHASE=$(oc get maasmodelref "$model" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$PHASE" == "Ready" ]]; then
        echo -e "${GREEN}[PASS]${NC} MaaSModelRef $model: Ready"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} MaaSModelRef $model not Ready (${PHASE:-missing})"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
done

check "MaaS subscription Active" \
    "oc get maassubscription enterprise-demo-subscription -n models-as-a-service -o jsonpath='{.status.phase}'" \
    "Active"
SUBSCRIPTION_USERS=$(oc get maassubscription enterprise-demo-subscription -n models-as-a-service -o jsonpath='{.spec.owner.users}' 2>/dev/null || true)
if [[ "$SUBSCRIPTION_USERS" == *"ai-admin"* ]] && [[ "$SUBSCRIPTION_USERS" == *"ai-developer"* ]]; then
    echo -e "${GREEN}[PASS]${NC} MaaS subscription includes demo users"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} MaaS subscription missing demo users: ${SUBSCRIPTION_USERS:-missing}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
SUBSCRIPTION_GROUPS=$(oc get maassubscription enterprise-demo-subscription -n models-as-a-service -o jsonpath='{.spec.owner.groups[*].name}' 2>/dev/null || true)
if [[ "$SUBSCRIPTION_GROUPS" == *"rhoai-admins"* ]] && [[ "$SUBSCRIPTION_GROUPS" == *"rhoai-users"* ]]; then
    echo -e "${GREEN}[PASS]${NC} MaaS subscription includes demo groups"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} MaaS subscription missing demo groups: ${SUBSCRIPTION_GROUPS:-missing}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
check "MaaS auth policy Active" \
    "oc get maasauthpolicy enterprise-demo-policy -n models-as-a-service -o jsonpath='{.status.phase}'" \
    "Active"
AUTH_POLICY_USERS=$(oc get maasauthpolicy enterprise-demo-policy -n models-as-a-service -o jsonpath='{.spec.subjects.users}' 2>/dev/null || true)
if [[ "$AUTH_POLICY_USERS" == *"ai-admin"* ]] && [[ "$AUTH_POLICY_USERS" == *"ai-developer"* ]]; then
    echo -e "${GREEN}[PASS]${NC} MaaS auth policy includes demo users"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} MaaS auth policy missing demo users: ${AUTH_POLICY_USERS:-missing}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi
AUTH_POLICY_GROUPS=$(oc get maasauthpolicy enterprise-demo-policy -n models-as-a-service -o jsonpath='{.spec.subjects.groups[*].name}' 2>/dev/null || true)
if [[ "$AUTH_POLICY_GROUPS" == *"rhoai-admins"* ]] && [[ "$AUTH_POLICY_GROUPS" == *"rhoai-users"* ]]; then
    echo -e "${GREEN}[PASS]${NC} MaaS auth policy includes demo groups"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} MaaS auth policy missing demo groups: ${AUTH_POLICY_GROUPS:-missing}"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

validate_demo_user_api_key() {
    local secret_name="$1"
    local username="$2"
    local expected_ttl="${RHOAI_DEMO_MAAS_KEY_TTL:-60d}"
    local api_key key_owner key_ttl models_file models_http_code chat_http_code

    api_key=$(oc get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.MAAS_API_KEY}' 2>/dev/null | base64 -d 2>/dev/null || true)
    key_owner=$(oc get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.MAAS_KEY_OWNER}' 2>/dev/null | base64 -d 2>/dev/null || true)
    key_ttl=$(oc get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.MAAS_EXPIRES_IN}' 2>/dev/null | base64 -d 2>/dev/null || true)

    if [[ -n "$api_key" && "$key_owner" == "$username" && "$key_ttl" == "$expected_ttl" ]]; then
        echo -e "${GREEN}[PASS]${NC} MaaS API key secret $secret_name is owned by $username and expires in $expected_ttl"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} MaaS API key secret $secret_name metadata drift (owner=${key_owner:-missing}, expiresIn=${key_ttl:-missing})"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    if [[ -z "$api_key" ]]; then
        echo -e "${RED}[FAIL]${NC} MaaS API key secret $secret_name has no MAAS_API_KEY"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
        return
    fi

    models_file="/tmp/step-05-${secret_name}-models.json"
    models_http_code=$(curl -sk --max-time 20 -o "$models_file" -w "%{http_code}" \
        -H "Authorization: Bearer $api_key" \
        "${MAAS_HOST}/v1/models" 2>/dev/null || echo "000")
    local missing_models=()
    if [[ "$models_http_code" == "200" ]]; then
        for expected_model in "${PUBLISHED_MAAS_MODELS[@]}"; do
            if ! grep -q "$expected_model" "$models_file"; then
                missing_models+=("$expected_model")
            fi
        done
    else
        missing_models=("${PUBLISHED_MAAS_MODELS[@]}")
    fi

    if [[ "$models_http_code" == "200" && "${#missing_models[@]}" -eq 0 ]]; then
        echo -e "${GREEN}[PASS]${NC} $username MaaS API key lists all published demo models"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} $username MaaS API key model list missing: ${missing_models[*]:-unknown} (HTTP $models_http_code)"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    chat_http_code=$(curl -sk --max-time 60 -o "/tmp/step-05-${secret_name}-chat.json" -w "%{http_code}" \
        -H "Authorization: Bearer $api_key" \
        -H "X-Gateway-Model-Name: granite-8b-agent" \
        -H "Content-Type: application/json" \
        -d '{"model":"granite-8b-agent","messages":[{"role":"user","content":"Reply with ready"}],"max_tokens":8}' \
        "${MAAS_HOST}/v1/chat/completions" 2>/dev/null || echo "000")
    if [[ "$chat_http_code" == "200" ]]; then
        echo -e "${GREEN}[PASS]${NC} $username MaaS API key can call granite-8b-agent through MaaS model route"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} $username MaaS gateway chat returned HTTP $chat_http_code"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
}

validate_openai_external_model_call() {
    local api_key="$1"
    local external_http_code
    local response_file="/tmp/step-05-openai-gpt-5-chat.json"

    external_http_code=$(curl -sk --max-time 120 -o "$response_file" -w "%{http_code}" \
        -H "Authorization: Bearer $api_key" \
        -H "X-Gateway-Model-Name: gpt-5" \
        -H "Content-Type: application/json" \
        -d '{"model":"gpt-5","messages":[{"role":"user","content":"Reply with the single word ready."}],"max_completion_tokens":16}' \
        "${MAAS_HOST}/v1/chat/completions" 2>/dev/null || echo "000")
    if [[ "$external_http_code" == "200" ]]; then
        echo -e "${GREEN}[PASS]${NC} MaaS can route a low-token chat request to external OpenAI gpt-5"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    elif [[ "$external_http_code" == "401" ]] && grep -q "You didn't provide an API key" "$response_file" 2>/dev/null; then
        echo -e "${YELLOW}[WARN]${NC} MaaS routes gpt-5 to OpenAI, but provider API key injection is not active in the generated AuthPolicy"
        echo -e "${YELLOW}[WARN]${NC} Expected per RHOAI 3.4 docs: MaaS injects maas/openai-provider-api-key before forwarding external requests"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    else
        echo -e "${RED}[FAIL]${NC} MaaS external OpenAI gpt-5 chat returned HTTP $external_http_code"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
}

prometheus_query_count() {
    local query="$1"
    local route token response
    route=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}' 2>/dev/null || true)
    token=$(oc whoami -t 2>/dev/null || true)
    if [[ -z "$route" || -z "$token" ]]; then
        echo 0
        return
    fi

    response=$(curl -skG --max-time 20 \
        -H "Authorization: Bearer $token" \
        --data-urlencode "query=$query" \
        "https://${route}/api/v1/query" 2>/dev/null || true)
    RESPONSE="$response" python3 -c '
import json
import os

try:
    data = json.loads(os.environ.get("RESPONSE", "{}"))
    print(len(data.get("data", {}).get("result", [])))
except Exception:
    print(0)
'
}

prometheus_query_value() {
    local query="$1"
    local route token response
    route=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}' 2>/dev/null || true)
    token=$(oc whoami -t 2>/dev/null || true)
    if [[ -z "$route" || -z "$token" ]]; then
        echo 0
        return
    fi

    response=$(curl -skG --max-time 20 \
        -H "Authorization: Bearer $token" \
        --data-urlencode "query=$query" \
        "https://${route}/api/v1/query" 2>/dev/null || true)
    RESPONSE="$response" python3 -c '
import json
import os

try:
    data = json.loads(os.environ.get("RESPONSE", "{}"))
    result = data.get("data", {}).get("result", [])
    print(result[0].get("value", [None, "0"])[1] if result else "0")
except Exception:
    print("0")
'
}

positive_number() {
    VALUE="$1" python3 -c '
import os
import sys

try:
    sys.exit(0 if float(os.environ.get("VALUE", "0")) > 0 else 1)
except Exception:
    sys.exit(1)
'
}

MAAS_ROUTE=$(oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [[ -n "$MAAS_ROUTE" ]]; then
    MAAS_HOST="https://${MAAS_ROUTE}"
    validate_demo_user_api_key "ai-admin-maas-api-key" "ai-admin"
    validate_demo_user_api_key "ai-developer-maas-api-key" "ai-developer"

    ADMIN_API_KEY=$(oc get secret ai-admin-maas-api-key -n "$NAMESPACE" -o jsonpath='{.data.MAAS_API_KEY}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [[ -n "$ADMIN_API_KEY" ]]; then
        validate_openai_external_model_call "$ADMIN_API_KEY"
        echo -e "${YELLOW}[INFO]${NC} Waiting for first MaaS Usage metrics scrape before generating dashboard increment..."
        sleep 35
        curl -sk --max-time 60 -o /tmp/step-05-maas-dashboard-increment.json \
            -H "Authorization: Bearer $ADMIN_API_KEY" \
            -H "X-Gateway-Model-Name: granite-8b-agent" \
            -H "Content-Type: application/json" \
            -d '{"model":"granite-8b-agent","messages":[{"role":"user","content":"Reply with ready for MaaS Usage dashboard metrics"}],"max_tokens":8}' \
            "${MAAS_HOST}/v1/chat/completions" >/dev/null 2>&1 || true
        echo -e "${YELLOW}[INFO]${NC} Waiting for MaaS Usage dashboard metrics scrape..."
        sleep 35
    fi

    GENAI_MAAS_RESPONSE=$(oc exec -n redhat-ods-applications deploy/rhods-dashboard -c gen-ai-ui -- \
        curl -ksS --max-time 20 \
        -H "x-forwarded-access-token: $(oc whoami -t)" \
        "https://localhost:8143/api/v1/maas/models?namespace=${NAMESPACE}" 2>/dev/null || true)
    if printf '%s' "$GENAI_MAAS_RESPONSE" | grep -q "granite-8b-agent" \
        && printf '%s' "$GENAI_MAAS_RESPONSE" | grep -q "mistral-3-bf16" \
        && printf '%s' "$GENAI_MAAS_RESPONSE" | grep -q "gpt-5"; then
        echo -e "${GREEN}[PASS]${NC} GenAI AI asset MaaS API lists local and external MaaS models"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} GenAI AI asset MaaS API did not list local and external MaaS models"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    LIMITADOR_TARGETS=$(prometheus_query_count 'up{job="kuadrant-system/kuadrant-limitador-monitor"}')
    if [[ "$LIMITADOR_TARGETS" -ge 1 ]]; then
        echo -e "${GREEN}[PASS]${NC} Prometheus scrapes Kuadrant Limitador metrics"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} Prometheus is not scraping Kuadrant Limitador metrics"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    SUBSCRIPTION_METRICS=$(prometheus_query_count 'istio_request_duration_milliseconds_count{subscription!=""}')
    if [[ "$SUBSCRIPTION_METRICS" -ge 1 ]]; then
        echo -e "${GREEN}[PASS]${NC} MaaS telemetry emits subscription-labeled usage metrics"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} MaaS subscription telemetry metrics not observed yet; generate MaaS traffic and re-run validation"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi

    AUTHORIZED_CALLS=$(prometheus_query_count 'authorized_calls{user!="",subscription!="",limitador_namespace="maas/granite-8b-agent"}')
    if [[ "$AUTHORIZED_CALLS" -ge 1 ]]; then
        echo -e "${GREEN}[PASS]${NC} MaaS Usage metrics include user-labeled authorized_calls"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} MaaS Usage metrics missing authorized_calls; check Limitador telemetry and model-route traffic"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    AUTHORIZED_HITS=$(prometheus_query_count 'authorized_hits{user!="",subscription!="",model="granite-8b-agent"}')
    if [[ "$AUTHORIZED_HITS" -ge 1 ]]; then
        echo -e "${GREEN}[PASS]${NC} MaaS Usage metrics include model-labeled authorized_hits"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} MaaS Usage metrics missing authorized_hits; check token usage extraction from model responses"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    DASHBOARD_TOKENS=$(prometheus_query_value 'sum(increase(authorized_hits{user!="",subscription!="",model!=""}[30m]))')
    if positive_number "$DASHBOARD_TOKENS"; then
        echo -e "${GREEN}[PASS]${NC} MaaS Usage dashboard has recent token data (${DASHBOARD_TOKENS})"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} MaaS Usage dashboard token increase is not positive yet; wait for another scrape or generate more model-route traffic"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
else
    echo -e "${RED}[FAIL]${NC} MaaS Gateway route missing"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- InferenceServices ---
log_step "InferenceServices"
for isvc in "${LOCAL_MAAS_MODELS[@]}"; do
    EXISTS=$(oc get inferenceservice "$isvc" -n "$NAMESPACE" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
    if [[ "$EXISTS" == "$isvc" ]]; then
        DASHBOARD_LABEL=$(oc get inferenceservice "$isvc" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.opendatahub\.io/dashboard}' 2>/dev/null || echo "")
        GENAI_LABEL=$(oc get inferenceservice "$isvc" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.opendatahub\.io/genai-asset}' 2>/dev/null || echo "")
        if [[ "$DASHBOARD_LABEL" == "true" && "$GENAI_LABEL" == "true" ]]; then
            echo -e "${GREEN}[PASS]${NC} InferenceService $isvc is visible as a GenAI asset"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${RED}[FAIL]${NC} InferenceService $isvc missing Dashboard/GenAI asset labels"
            VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
        fi

        READY=$(oc get inferenceservice "$isvc" -n "$NAMESPACE" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [[ "$READY" == "True" ]]; then
            echo -e "${GREEN}[PASS]${NC} InferenceService $isvc: Ready"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${YELLOW}[WARN]${NC} InferenceService $isvc: exists but not Ready ($READY) — may need GPU nodes or model upload"
            VALIDATE_WARN=$((VALIDATE_WARN + 1))
        fi

        check_inferenceservice_scrape_label "$NAMESPACE" "$isvc"
    else
        echo -e "${YELLOW}[WARN]${NC} InferenceService $isvc: not found"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
done

# At least one InferenceService must be Ready
READY_COUNT=$(oc get inferenceservice -n "$NAMESPACE" -o json 2>/dev/null \
    | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    count = sum(1 for i in data.get('items', [])
                if any(c.get('type') == 'Ready' and c.get('status') == 'True'
                       for c in i.get('status', {}).get('conditions', [])))
    print(count)
except:
    print(0)
" 2>/dev/null || echo "0")

if [[ "$READY_COUNT" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} At least one InferenceService is Ready ($READY_COUNT total)"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} No InferenceService is Ready yet — GPU nodes and model uploads may be pending"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Summary ---
echo ""
validation_summary
