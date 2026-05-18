#!/usr/bin/env bash
# Step 05: MaaS model serving validation script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="maas"

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

# --- MaaS Governance API ---
log_step "MaaS Governance API"
check_crd_exists "maasmodelrefs.maas.opendatahub.io"
check_crd_exists "maassubscriptions.maas.opendatahub.io"
check_crd_exists "maasauthpolicies.maas.opendatahub.io"

for model in granite-8b-agent mistral-3-bf16; do
    ROUTE_HOST=$(oc get route "$model" -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [[ -n "$ROUTE_HOST" ]]; then
        oc patch externalmodel "$model" -n "$NAMESPACE" --type merge \
            -p "{\"spec\":{\"endpoint\":\"${ROUTE_HOST}\"}}" >/dev/null 2>&1 || true
        oc patch maasmodelref "$model" -n "$NAMESPACE" --type merge \
            -p "{\"spec\":{\"endpointOverride\":\"https://${ROUTE_HOST}\"}}" >/dev/null 2>&1 || true
    fi

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
check "MaaS auth policy Active" \
    "oc get maasauthpolicy enterprise-demo-policy -n models-as-a-service -o jsonpath='{.status.phase}'" \
    "Active"

MAAS_ROUTE=$(oc get route maas-gateway -n openshift-ingress -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [[ -n "$MAAS_ROUTE" ]]; then
    MAAS_HOST="https://${MAAS_ROUTE}"
    RESP=$(curl -sk --max-time 20 \
        -H "Authorization: Bearer $(oc whoami -t)" \
        -H "Content-Type: application/json" \
        -X POST \
        -d '{"name":"step-05-validation","description":"temporary validation key","expiresIn":"10m","subscription":"enterprise-demo-subscription"}' \
        "${MAAS_HOST}/maas-api/v1/api-keys" 2>/dev/null || true)
    API_KEY=$(printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))' 2>/dev/null || true)
    API_KEY_ID=$(printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)
    if [[ -n "$API_KEY" ]]; then
        MODELS_HTTP_CODE=$(curl -sk --max-time 20 -o /tmp/step-05-maas-models.json -w "%{http_code}" \
            -H "Authorization: Bearer $API_KEY" \
            "${MAAS_HOST}/v1/models" 2>/dev/null || echo "000")
        if [[ "$MODELS_HTTP_CODE" == "200" ]] \
            && grep -q "granite-8b-agent" /tmp/step-05-maas-models.json \
            && grep -q "mistral-3-bf16" /tmp/step-05-maas-models.json; then
            echo -e "${GREEN}[PASS]${NC} MaaS /v1/models lists both published demo models"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${RED}[FAIL]${NC} MaaS /v1/models did not list both demo models (HTTP $MODELS_HTTP_CODE)"
            VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
        fi

        HTTP_CODE=$(curl -sk --max-time 60 -o /tmp/step-05-maas-chat.json -w "%{http_code}" \
            -H "Authorization: Bearer $API_KEY" \
            -H "Content-Type: application/json" \
            -d '{"model":"granite-8b-agent","messages":[{"role":"user","content":"Reply with ready"}],"max_tokens":8}' \
            "${MAAS_HOST}/v1/chat/completions" 2>/dev/null || echo "000")
        if [[ "$HTTP_CODE" == "200" ]]; then
            echo -e "${GREEN}[PASS]${NC} MaaS API key can call granite-8b-agent through gateway"
            VALIDATE_PASS=$((VALIDATE_PASS + 1))
        else
            echo -e "${RED}[FAIL]${NC} MaaS gateway chat returned HTTP $HTTP_CODE"
            VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
        fi
        if [[ -n "$API_KEY_ID" ]]; then
            curl -sk --max-time 20 -H "Authorization: Bearer $(oc whoami -t)" \
                -X DELETE "${MAAS_HOST}/maas-api/v1/api-keys/${API_KEY_ID}" >/dev/null 2>&1 || true
        fi
    else
        echo -e "${RED}[FAIL]${NC} Could not create temporary MaaS API key"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi

    GENAI_MAAS_RESPONSE=$(oc exec -n redhat-ods-applications deploy/rhods-dashboard -c gen-ai-ui -- \
        curl -ksS --max-time 20 \
        -H "x-forwarded-access-token: $(oc whoami -t)" \
        "https://localhost:8143/api/v1/maas/models?namespace=${NAMESPACE}" 2>/dev/null || true)
    if printf '%s' "$GENAI_MAAS_RESPONSE" | grep -q "granite-8b-agent" \
        && printf '%s' "$GENAI_MAAS_RESPONSE" | grep -q "mistral-3-bf16"; then
        echo -e "${GREEN}[PASS]${NC} GenAI AI asset MaaS API lists both MaaS models"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} GenAI AI asset MaaS API did not list both MaaS models"
        VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
    fi
else
    echo -e "${RED}[FAIL]${NC} MaaS Gateway route missing"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- InferenceServices ---
log_step "InferenceServices"
for isvc in granite-8b-agent mistral-3-bf16; do
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
