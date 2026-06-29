#!/usr/bin/env bash
# validate.sh - Stage 230: Private Data RAG
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

PROJECT_NS="${RHOAI_STAGE230_PROJECT_NAMESPACE:-enterprise-rag}"
MAAS_NS="${RHOAI_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_SUBSCRIPTION="${RHOAI_STAGE230_MAAS_SUBSCRIPTION:-${RHOAI_MAAS_DEMO_SUBSCRIPTION:-${RHOAI_OPENAI_ACCESS_RESOURCE:-rhoai-developers-gpt-5-4-mini}}}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
RAG_INFERENCE_MODEL="${RHOAI_STAGE230_INFERENCE_MODEL_ID:-vllm-inference/nemotron-3-nano-30b-a3b}"
RAG_LSD_NAME="${RHOAI_STAGE230_LSD_NAME:-lsd-private-rag}"
RAG_DOCLING_DEPLOYMENT="${RHOAI_STAGE230_DOCLING_DEPLOYMENT:-private-rag-docling}"
RAG_DSPA_NAME="${RHOAI_STAGE230_DSPA_NAME:-private-rag-pipelines}"
RAG_DSPA_OBC_NAME="${RHOAI_STAGE230_DSPA_OBC_NAME:-private-rag-pipelines-bucket}"
RAG_PIPELINE_LAST_RUN_CONFIGMAP="${RHOAI_STAGE230_LAST_RUN_CONFIGMAP:-private-rag-pipeline-last-run}"
RAG_VECTOR_DB="${RHOAI_STAGE230_VECTOR_DB:-whoami}"
RAG_DOC_CONFIGMAP="${RHOAI_STAGE230_DOCUMENT_CONFIGMAP:-private-rag-documents}"
OBC_NAME="${RHOAI_STAGE230_OBC_NAME:-enterprise-rag-bucket}"

PASS=0
FAIL=0

if [[ -z "${RHOAI_EXPECTED_API_SERVER:-}" ]]; then
  echo "ERROR: RHOAI_EXPECTED_API_SERVER is not set." >&2
  exit 1
fi

ACTUAL_SERVER=$(oc whoami --show-server 2>/dev/null || true)
if [[ "$ACTUAL_SERVER" != *"$RHOAI_EXPECTED_API_SERVER"* ]]; then
  echo "ERROR: Active cluster ($ACTUAL_SERVER) does not match RHOAI_EXPECTED_API_SERVER." >&2
  exit 1
fi

check() {
  local label="$1"
  local result="$2"
  if [[ "$result" == "pass" ]]; then
    echo "[OK] $label"
    (( PASS++ )) || true
  else
    echo "[FAIL] $label ($result)"
    (( FAIL++ )) || true
  fi
}

resource_exists() {
  local resource="$1"
  local namespace="$2"
  oc get "$resource" -n "$namespace" --insecure-skip-tls-verify=true >/dev/null 2>&1
}

jsonpath() {
  local resource="$1"
  local namespace="$2"
  local path="$3"
  oc get "$resource" -n "$namespace" -o jsonpath="$path" \
    --insecure-skip-tls-verify=true 2>/dev/null || true
}

app_sync=$(jsonpath "applications.argoproj.io/stage-230-private-data-rag" "openshift-gitops" '{.status.sync.status}')
app_health=$(jsonpath "applications.argoproj.io/stage-230-private-data-rag" "openshift-gitops" '{.status.health.status}')
[[ "$app_sync" == "Synced" && "$app_health" == "Healthy" ]] && R=pass || R="${app_sync:-missing}/${app_health:-missing}"
check "Stage 230 Argo CD Application is Synced/Healthy" "$R"

[[ "$(jsonpath "objectbucketclaim/${OBC_NAME}" "$PROJECT_NS" '{.status.phase}')" == "Bound" ]] && R=pass || R=missing
check "Enterprise RAG project ObjectBucketClaim is Bound" "$R"

dsc_aipipelines=$(oc get datasciencecluster default-dsc -n redhat-ods-applications \
  -o jsonpath='{.spec.components.aipipelines.managementState}' \
  --insecure-skip-tls-verify=true 2>/dev/null || true)
[[ "$dsc_aipipelines" == "Managed" ]] && R=pass || R="${dsc_aipipelines:-missing}"
check "OpenShift AI AI Pipelines component is Managed" "$R"

aipipelines_ready=$(oc get datasciencecluster default-dsc -n redhat-ods-applications \
  -o jsonpath='{.status.conditions[?(@.type=="AIPipelinesReady")].status}' \
  --insecure-skip-tls-verify=true 2>/dev/null || true)
[[ "$aipipelines_ready" == "True" ]] && R=pass || R="${aipipelines_ready:-missing}"
check "OpenShift AI AI Pipelines component reports Ready" "$R"

[[ "$(jsonpath "objectbucketclaim/${RAG_DSPA_OBC_NAME}" "$PROJECT_NS" '{.status.phase}')" == "Bound" ]] && R=pass || R=missing
check "Private RAG DSPA artifact ObjectBucketClaim is Bound" "$R"

dspa_ready=$(jsonpath "dspa/${RAG_DSPA_NAME}" "$PROJECT_NS" '{.status.conditions[?(@.type=="Ready")].status}')
[[ "$dspa_ready" == "True" ]] && R=pass || R="${dspa_ready:-missing}"
check "Private RAG DSPA pipeline server is Ready" "$R"

dspa_route=$(jsonpath "route/ds-pipeline-${RAG_DSPA_NAME}" "$PROJECT_NS" '{.spec.host}')
[[ -n "$dspa_route" ]] && R=pass || R=missing
check "Private RAG DSPA route exists" "$R"

[[ "$(jsonpath "maasmodelref/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" '{.status.phase}')" == "Ready" ]] && R=pass || R=missing
check "Stage 220 Nemotron MaaSModelRef is Ready" "$R"

[[ "$(jsonpath "maassubscription/${MAAS_SUBSCRIPTION}" "$MAAS_NS" '{.status.phase}')" == "Active" ]] && R=pass || R=missing
check "Stage 220 MaaS subscription is Active" "$R"

sub_models=$(jsonpath "maassubscription/${MAAS_SUBSCRIPTION}" "$MAAS_NS" '{.spec.modelRefs[*].name}')
[[ " $sub_models " == *" ${NEMOTRON_MODEL_RESOURCE} "* ]] && R=pass || R="models=${sub_models:-missing}"
check "Stage 220 MaaS subscription grants Nemotron access" "$R"

resource_exists "secret/private-rag-postgres-credentials" "$PROJECT_NS" && R=pass || R=missing
check "pgvector credential Secret exists" "$R"

token_value=$(jsonpath "secret/private-rag-llama-stack-secret" "$PROJECT_NS" '{.data.VLLM_API_TOKEN}' | base64 --decode 2>/dev/null || true)
[[ "$token_value" == sk-oai-* ]] && R=pass || R="missing or invalid MaaS API key"
check "Llama Stack Secret contains MaaS API token" "$R"

if resource_exists "statefulset/private-rag-postgres" "$PROJECT_NS"; then
  ready=$(jsonpath "statefulset/private-rag-postgres" "$PROJECT_NS" '{.status.readyReplicas}')
  [[ "$ready" == "1" ]] && R=pass || R="readyReplicas=${ready:-0}"
else
  R=missing
fi
check "pgvector StatefulSet is ready" "$R"

if resource_exists "deployment/${RAG_DOCLING_DEPLOYMENT}" "$PROJECT_NS"; then
  ready=$(jsonpath "deployment/${RAG_DOCLING_DEPLOYMENT}" "$PROJECT_NS" '{.status.readyReplicas}')
  [[ "$ready" == "1" ]] && R=pass || R="readyReplicas=${ready:-0}"
else
  R=missing
fi
check "Private RAG Docling deployment is ready" "$R"

if resource_exists "deployment/${RAG_LSD_NAME}" "$PROJECT_NS"; then
  ready=$(jsonpath "deployment/${RAG_LSD_NAME}" "$PROJECT_NS" '{.status.readyReplicas}')
  [[ "$ready" == "1" ]] && R=pass || R="readyReplicas=${ready:-0}"
else
  R=missing
fi
check "Private RAG Llama Stack deployment is ready" "$R"

resource_exists "configmap/${RAG_DOC_CONFIGMAP}" "$PROJECT_NS" && R=pass || R=missing
check "Private demo document ConfigMap exists" "$R"

if resource_exists "job/private-rag-s3-seed" "$PROJECT_NS"; then
  succeeded=$(jsonpath "job/private-rag-s3-seed" "$PROJECT_NS" '{.status.succeeded}')
  [[ "$succeeded" == "1" ]] && R=pass || R="succeeded=${succeeded:-0}"
else
  R=missing
fi
check "Private documents were uploaded to object storage" "$R"

if resource_exists "configmap/${RAG_PIPELINE_LAST_RUN_CONFIGMAP}" "$PROJECT_NS"; then
  pipeline_status=$(jsonpath "configmap/${RAG_PIPELINE_LAST_RUN_CONFIGMAP}" "$PROJECT_NS" '{.data.status}')
  [[ "$pipeline_status" == "SUCCEEDED" || "$pipeline_status" == "SUCCESS" ]] && R=pass || R="${pipeline_status:-missing}"
else
  R=missing
fi
check "Latest whoami ingestion pipeline run succeeded" "$R"

if resource_exists "deployment/${RAG_LSD_NAME}" "$PROJECT_NS"; then
  output=$(oc exec -i "deployment/${RAG_LSD_NAME}" -n "$PROJECT_NS" \
    --insecure-skip-tls-verify=true \
    -- env RAG_VECTOR_DB="$RAG_VECTOR_DB" RAG_INFERENCE_MODEL="$RAG_INFERENCE_MODEL" python3 - <<'PY' 2>&1 || true
from llama_stack_client import LlamaStackClient

client = LlamaStackClient(base_url="http://127.0.0.1:8321")
vector_store_name = __import__("os").environ["RAG_VECTOR_DB"]
preferred_model = __import__("os").environ["RAG_INFERENCE_MODEL"]

def ident(obj):
    return getattr(obj, "identifier", None) or getattr(obj, "id", None) or getattr(obj, "provider_id", None)

providers = [getattr(p, "provider_id", "") for p in client.providers.list() if "vector" in str(getattr(p, "api", "")).lower()]
if not any("pgvector" in p for p in providers):
    raise SystemExit(f"missing pgvector vector provider: {providers}")

stores = list(client.vector_stores.list())
store = next(
    (
        item for item in stores
        if getattr(item, "name", None) == vector_store_name or ident(item) == vector_store_name
    ),
    None,
)
if store is None:
    known = [f"{getattr(item, 'name', '')}:{ident(item)}" for item in stores]
    raise SystemExit(f"missing vector store {vector_store_name}: {known}")
vector_store_id = ident(store)

rag_response = client.vector_stores.search(
    vector_store_id=vector_store_id,
    query="Who is Adnan Drina and what is his current role?",
    max_num_results=5,
)
context = str(getattr(rag_response, "content", rag_response))
if not any(term in context.lower() for term in ["adnan", "red hat", "principal", "solution architect"]):
    raise SystemExit(f"unexpected RAG context: {context[:400]}")

model_ids = [ident(m) for m in client.models.list()]
model_ids = [mid for mid in model_ids if mid]
model_id = preferred_model
if model_ids and model_id not in model_ids:
    model_id = next((mid for mid in model_ids if preferred_model in mid or "nemotron" in mid.lower()), model_ids[0])

completion = client.chat.completions.create(
    model=model_id,
    messages=[
        {"role": "system", "content": "Answer from the context only."},
        {"role": "user", "content": f"Context:\n{context}\n\nQuestion: Who is Adnan Drina and what is his current role?"},
    ],
    temperature=0.1,
)
answer = completion.choices[0].message.content
if not answer:
    raise SystemExit("empty answer")
print("RAG_RUNTIME_OK")
PY
)
  if grep -q "RAG_RUNTIME_OK" <<<"$output"; then
    R=pass
  else
    R="$output"
  fi
else
  R=missing
fi
check "Llama Stack RAG query and Nemotron answer work" "$R"

echo
echo "Stage 230 validation summary: ${PASS} passed, ${FAIL} failed"
if (( FAIL > 0 )); then
  exit 1
fi
