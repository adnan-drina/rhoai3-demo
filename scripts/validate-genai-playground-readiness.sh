#!/usr/bin/env bash
# Product-native Gen AI Playground readiness checks.
#
# This script does not drive the authenticated Dashboard UI. It verifies the
# cluster-side prerequisites that the RHOAI 3.4 Playground uses for the demo:
# GenAI Studio flags, internal custom endpoints, AI asset models, MCP server
# discovery, RAG project storage, Llama Stack vector stores, and MLflow support.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

RAG_NAMESPACE="${RAG_NAMESPACE:-enterprise-rag}"
MODEL_NAMESPACE="${MODEL_NAMESPACE:-maas}"
MCP_CONFIGMAP="${MCP_CONFIGMAP:-gen-ai-aa-mcp-servers}"

echo "=================================================================="
echo "  Gen AI Playground Readiness"
echo "=================================================================="
echo ""

log_step "Dashboard Feature Flags"
check "GenAI Studio enabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.genAiStudio}'" \
    "true"
check "AI asset custom endpoints enabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.aiAssetCustomEndpoints}'" \
    "true"
check "External custom endpoint providers disabled" \
    "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.genAiStudioConfig.aiAssetCustomEndpoints.externalProviders}'" \
    "false"
check "Llama Stack operator managed" \
    "oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.llamastackoperator.managementState}'" \
    "Managed"
check_warn "MLflow operator managed" \
    "oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.mlflowoperator.managementState}'" \
    "Managed"

log_step "AI Asset Models"
for model in granite-8b-agent mistral-3-bf16; do
    check "InferenceService $model exists" \
        "oc get inferenceservice $model -n $MODEL_NAMESPACE -o jsonpath='{.metadata.name}'" \
        "$model"
    check "InferenceService $model visible in Dashboard" \
        "oc get inferenceservice $model -n $MODEL_NAMESPACE -o jsonpath='{.metadata.labels.opendatahub\\.io/dashboard}'" \
        "true"
    check "InferenceService $model marked as GenAI asset" \
        "oc get inferenceservice $model -n $MODEL_NAMESPACE -o jsonpath='{.metadata.labels.opendatahub\\.io/genai-asset}'" \
        "true"
    check_warn "InferenceService $model Ready" \
        "oc get inferenceservice $model -n $MODEL_NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" \
        "True"
done

log_step "MCP Asset Endpoints"
check "MCP ConfigMap exists" \
    "oc get configmap $MCP_CONFIGMAP -n redhat-ods-applications -o jsonpath='{.metadata.name}'" \
    "$MCP_CONFIGMAP"

MCP_CONFIG_JSON=$(oc get configmap "$MCP_CONFIGMAP" -n redhat-ods-applications -o json 2>/dev/null || true)
MCP_JSON_STATUS=$(
    MCP_CONFIG_JSON="$MCP_CONFIG_JSON" python3 - <<'PY' 2>/dev/null || true
import json
import os
import sys

try:
    data = json.loads(os.environ["MCP_CONFIG_JSON"]).get("data", {})
except Exception as exc:
    print(f"invalid configmap json: {exc}")
    sys.exit(1)

required = {
    "Database-MCP": "sse",
    "OpenShift-MCP": "",
    "Slack-MCP": "sse",
}
errors = []
for key, required_transport in required.items():
    if key not in data:
        errors.append(f"{key}: missing")
        continue
    try:
        payload = json.loads(data[key])
    except Exception as exc:
        errors.append(f"{key}: invalid JSON ({exc})")
        continue
    if not payload.get("url"):
        errors.append(f"{key}: missing url")
    if required_transport and payload.get("transport") != required_transport:
        errors.append(f"{key}: expected transport={required_transport}")

if errors:
    print("; ".join(errors))
    sys.exit(1)

print("ok")
PY
)
if [[ "$MCP_JSON_STATUS" == "ok" ]]; then
    echo -e "${GREEN}[PASS]${NC} MCP ConfigMap entries are valid for Dashboard discovery"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} MCP ConfigMap entries invalid (${MCP_JSON_STATUS:-no output})"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

log_step "RAG and Prompt/Evidence Workspace"
check "RAG project data connection visible in Dashboard" \
    "oc get secret minio-connection -n $RAG_NAMESPACE -o jsonpath='{.metadata.labels.opendatahub\\.io/dashboard}'" \
    "true"
check "RAG project data connection uses S3 protocol annotation" \
    "oc get secret minio-connection -n $RAG_NAMESPACE -o jsonpath='{.metadata.annotations.opendatahub\\.io/connection-type-protocol}'" \
    "s3"
check_warn "enterprise-rag MLflowConfig exists" \
    "oc get mlflowconfig mlflow -n $RAG_NAMESPACE -o jsonpath='{.metadata.name}'" \
    "mlflow"
check_warn "RAG project MaaS API key exists for internal custom endpoint" \
    "oc get secret rag-maas-api-key -n $RAG_NAMESPACE -o jsonpath='{.metadata.name}'" \
    "rag-maas-api-key"
check_warn "Cluster MLflow server exists for saved prompts" \
    "oc get mlflow mlflow -o jsonpath='{.metadata.name}'" \
    "mlflow"
check_warn "Cluster MLflow server available" \
    "oc get mlflow mlflow -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}'" \
    "True"

LSD_POD=$(oc get pods -n "$RAG_NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep "^lsd-rag" | head -1 || true)
if [[ -n "$LSD_POD" ]]; then
    VECTOR_STORES=$(oc exec "$LSD_POD" -n "$RAG_NAMESPACE" -- curl -sf --max-time 20 http://localhost:8321/v1/vector_stores 2>/dev/null || true)
    VECTOR_NAMES=$(VECTOR_STORES="$VECTOR_STORES" python3 - <<'PY' 2>/dev/null || true
import json
import os

try:
    payload = json.loads(os.environ["VECTOR_STORES"])
except Exception:
    payload = {}

for item in payload.get("data", []):
    name = item.get("name")
    if name:
        print(name)
PY
)
    if echo "$VECTOR_NAMES" | grep -qx "acme_corporate"; then
        echo -e "${GREEN}[PASS]${NC} acme_corporate vector store is available"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} acme_corporate vector store not found; run Step 07 ingestion before RAG Playground demos"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
else
    echo -e "${YELLOW}[WARN]${NC} lsd-rag pod not found; skipping vector store readiness"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

echo ""
validation_summary
