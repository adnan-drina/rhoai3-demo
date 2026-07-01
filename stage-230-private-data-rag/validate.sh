#!/usr/bin/env bash
# validate.sh - Stage 230: Private Data RAG
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
WARN=0
FAIL=0

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

if [[ -z "${RHOAI_EXPECTED_API_SERVER:-}" ]]; then
  echo "ERROR: RHOAI_EXPECTED_API_SERVER is not set." >&2
  exit 1
fi

ACTUAL_SERVER=$(oc whoami --show-server 2>/dev/null || true)
if [[ "$ACTUAL_SERVER" != *"$RHOAI_EXPECTED_API_SERVER"* ]]; then
  echo "ERROR: Active cluster ($ACTUAL_SERVER) does not match RHOAI_EXPECTED_API_SERVER." >&2
  exit 1
fi

RAG_NS="${RHOAI_STAGE230_NAMESPACE:-enterprise-rag}"
POSTGRES_SECRET="${RHOAI_STAGE230_POSTGRES_SECRET:-private-rag-postgres-credentials}"
MILVUS_SECRET="${RHOAI_STAGE230_MILVUS_SECRET:-private-rag-milvus-secret}"
LLAMA_SECRET="${RHOAI_STAGE230_LLAMA_STACK_SECRET:-private-rag-llama-stack-secret}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
RERANKER_NAME="${RHOAI_STAGE230_RERANKER_NAME:-qwen3-reranker}"
RERANKER_MODEL="${RHOAI_STAGE230_RERANKER_MODEL:-vllm-reranker/qwen3-reranker}"
EMBEDDING_MODEL="${RHOAI_STAGE230_EMBEDDING_MODEL:-sentence-transformers/nomic-ai/nomic-embed-text-v1.5}"
WORKBENCH_NAME="${RHOAI_STAGE230_WORKBENCH_NAME:-enterprise-rag-workbench}"

check() {
  local label="$1"
  local result="$2"
  if [[ "$result" == "pass" ]]; then
    echo "✓ $label"
    (( PASS++ )) || true
  else
    echo "✗ $label  ($result)"
    (( FAIL++ )) || true
  fi
}

warn() {
  local label="$1"
  local result="$2"
  echo "! $label  ($result)"
  (( WARN++ )) || true
}

jsonpath() {
  local resource="$1"
  local namespace="$2"
  local path="$3"
  if [[ -n "$namespace" ]]; then
    oc get "$resource" -n "$namespace" -o jsonpath="$path" \
      --insecure-skip-tls-verify=true 2>/dev/null || true
  else
    oc get "$resource" -o jsonpath="$path" \
      --insecure-skip-tls-verify=true 2>/dev/null || true
  fi
}

resource_exists() {
  local resource="$1"
  local namespace="$2"
  if [[ -n "$namespace" ]]; then
    oc get "$resource" -n "$namespace" --insecure-skip-tls-verify=true >/dev/null 2>&1
  else
    oc get "$resource" --insecure-skip-tls-verify=true >/dev/null 2>&1
  fi
}

available_replicas() {
  local resource="$1"
  local namespace="$2"
  jsonpath "$resource" "$namespace" "{.status.availableReplicas}"
}

condition_status() {
  local resource="$1"
  local namespace="$2"
  local condition_type="$3"
  jsonpath "$resource" "$namespace" "{.status.conditions[?(@.type==\"${condition_type}\")].status}"
}

contains_word() {
  local haystack=" $1 "
  local needle="$2"
  [[ "$haystack" == *" ${needle} "* ]]
}

app_sync=$(jsonpath "applications.argoproj.io/stage-230-private-data-rag" "openshift-gitops" "{.status.sync.status}")
app_health=$(jsonpath "applications.argoproj.io/stage-230-private-data-rag" "openshift-gitops" "{.status.health.status}")
[[ "$app_sync" == "Synced" ]] && check "Stage 230 Argo CD Application is Synced" "pass" || check "Stage 230 Argo CD Application is Synced" "${app_sync:-missing}"
[[ "$app_health" == "Healthy" ]] && check "Stage 230 Argo CD Application is Healthy" "pass" || warn "Stage 230 Argo CD Application is Healthy" "${app_health:-missing}"

resource_exists "namespace/${RAG_NS}" "" && check "enterprise-rag namespace exists" "pass" || check "enterprise-rag namespace exists" "missing"
namespace_kueue=$(jsonpath "namespace/${RAG_NS}" "" "{.metadata.labels.kueue\\.openshift\\.io/managed}")
[[ "$namespace_kueue" == "true" ]] \
  && check "enterprise-rag namespace is Kueue-managed" "pass" \
  || check "enterprise-rag namespace is Kueue-managed" "${namespace_kueue:-missing}"
resource_exists "localqueue/lq-cpu-default" "$RAG_NS" \
  && check "enterprise-rag CPU LocalQueue exists" "pass" \
  || check "enterprise-rag CPU LocalQueue exists" "missing"
for secret in "$POSTGRES_SECRET" "$MILVUS_SECRET" "$LLAMA_SECRET"; do
  resource_exists "secret/${secret}" "$RAG_NS" && check "${secret} Secret exists" "pass" || check "${secret} Secret exists" "missing"
done

vllm_url=$(jsonpath "secret/${LLAMA_SECRET}" "$RAG_NS" "{.data.VLLM_URL}" | base64 --decode 2>/dev/null || true)
[[ "$vllm_url" == */v1 ]] && check "Llama Stack MaaS base URL ends with /v1" "pass" || check "Llama Stack MaaS base URL ends with /v1" "${vllm_url:-missing}"

[[ "$(available_replicas statefulset/private-rag-postgres "$RAG_NS")" == "1" ]] \
  && check "PostgreSQL metadata store is available" "pass" \
  || check "PostgreSQL metadata store is available" "availableReplicas=$(available_replicas statefulset/private-rag-postgres "$RAG_NS")"

[[ "$(available_replicas deployment/private-rag-etcd "$RAG_NS")" == "1" ]] \
  && check "Milvus etcd dependency is available" "pass" \
  || check "Milvus etcd dependency is available" "availableReplicas=$(available_replicas deployment/private-rag-etcd "$RAG_NS")"

[[ "$(available_replicas deployment/private-rag-milvus "$RAG_NS")" == "1" ]] \
  && check "Milvus vector store service is available" "pass" \
  || check "Milvus vector store service is available" "availableReplicas=$(available_replicas deployment/private-rag-milvus "$RAG_NS")"

lls_phase=$(jsonpath "llamastackdistribution/lsd-enterprise-rag" "$RAG_NS" "{.status.phase}")
[[ "$lls_phase" == "Ready" ]] && check "LlamaStackDistribution is Ready" "pass" || check "LlamaStackDistribution is Ready" "${lls_phase:-missing}"

reranker_ready=$(condition_status "inferenceservice/${RERANKER_NAME}" "$RAG_NS" "Ready")
[[ "$reranker_ready" == "True" ]] \
  && check "Qwen3 reranker InferenceService is Ready" "pass" \
  || check "Qwen3 reranker InferenceService is Ready" "${reranker_ready:-missing}"

reranker_queue=$(jsonpath "inferenceservice/${RERANKER_NAME}" "$RAG_NS" "{.metadata.labels.kueue\\.x-k8s\\.io/queue-name}")
[[ "$reranker_queue" == "lq-cpu-default" ]] \
  && check "Qwen3 reranker uses CPU LocalQueue" "pass" \
  || check "Qwen3 reranker uses CPU LocalQueue" "${reranker_queue:-missing}"

reranker_route_host=$(jsonpath "route/${RERANKER_NAME}" "$RAG_NS" "{.spec.host}")
[[ -n "$reranker_route_host" ]] \
  && check "Qwen3 reranker route exists" "pass" \
  || check "Qwen3 reranker route exists" "missing"

resource_exists "serviceaccount/${WORKBENCH_NAME}" "$RAG_NS" \
  && check "Enterprise RAG Workbench ServiceAccount exists" "pass" \
  || check "Enterprise RAG Workbench ServiceAccount exists" "missing"

resource_exists "pvc/${WORKBENCH_NAME}" "$RAG_NS" \
  && check "Enterprise RAG Workbench PVC exists" "pass" \
  || check "Enterprise RAG Workbench PVC exists" "missing"

resource_exists "notebook/${WORKBENCH_NAME}" "$RAG_NS" \
  && check "Enterprise RAG Workbench Notebook exists" "pass" \
  || check "Enterprise RAG Workbench Notebook exists" "missing"

workbench_queue=$(jsonpath "notebook/${WORKBENCH_NAME}" "$RAG_NS" "{.metadata.labels.kueue\\.x-k8s\\.io/queue-name}")
[[ "$workbench_queue" == "lq-cpu-default" ]] \
  && check "Enterprise RAG Workbench uses CPU LocalQueue" "pass" \
  || check "Enterprise RAG Workbench uses CPU LocalQueue" "${workbench_queue:-missing}"

workbench_auth=$(jsonpath "notebook/${WORKBENCH_NAME}" "$RAG_NS" "{.metadata.annotations.notebooks\\.opendatahub\\.io/inject-auth}")
[[ "$workbench_auth" == "true" ]] \
  && check "Enterprise RAG Workbench uses RHOAI inject-auth" "pass" \
  || check "Enterprise RAG Workbench uses RHOAI inject-auth" "${workbench_auth:-missing}"

workbench_oauth=$(jsonpath "notebook/${WORKBENCH_NAME}" "$RAG_NS" "{.metadata.annotations.notebooks\\.opendatahub\\.io/inject-oauth}")
[[ -z "$workbench_oauth" ]] \
  && check "Enterprise RAG Workbench does not use legacy inject-oauth" "pass" \
  || check "Enterprise RAG Workbench does not use legacy inject-oauth" "$workbench_oauth"

workbench_image_commit=$(jsonpath "notebook/${WORKBENCH_NAME}" "$RAG_NS" "{.metadata.annotations.notebooks\\.opendatahub\\.io/last-image-version-git-commit-selection}")
imagestream_commit=$(jsonpath "imagestream/s2i-generic-data-science-notebook" "redhat-ods-applications" "{.spec.tags[?(@.name==\"3.4\")].annotations.opendatahub\\.io/notebook-build-commit}")
[[ -n "$workbench_image_commit" && "$workbench_image_commit" == "$imagestream_commit" ]] \
  && check "Enterprise RAG Workbench image commit matches RHOAI 3.4 ImageStream" "pass" \
  || check "Enterprise RAG Workbench image commit matches RHOAI 3.4 ImageStream" "workbench=${workbench_image_commit:-missing},imagestream=${imagestream_commit:-missing}"

resource_exists "service/${WORKBENCH_NAME}-kube-rbac-proxy" "$RAG_NS" \
  && check "Enterprise RAG Workbench auth-proxy Service exists" "pass" \
  || check "Enterprise RAG Workbench auth-proxy Service exists" "missing"

workbench_backend=$(jsonpath "httproute/nb-${RAG_NS}-${WORKBENCH_NAME}" "redhat-ods-applications" "{.spec.rules[0].backendRefs[0].name}:{.spec.rules[0].backendRefs[0].port}")
[[ "$workbench_backend" == "${WORKBENCH_NAME}-kube-rbac-proxy:8443" ]] \
  && check "Enterprise RAG Workbench HTTPRoute targets auth proxy" "pass" \
  || check "Enterprise RAG Workbench HTTPRoute targets auth proxy" "${workbench_backend:-missing}"

workbench_notebook_containers=$(jsonpath "notebook/${WORKBENCH_NAME}" "$RAG_NS" "{.spec.template.spec.containers[*].name}")
contains_word "$workbench_notebook_containers" "kube-rbac-proxy" \
  && check "Enterprise RAG Workbench Notebook template includes auth proxy sidecar" "pass" \
  || check "Enterprise RAG Workbench Notebook template includes auth proxy sidecar" "${workbench_notebook_containers:-missing}"

workbench_update_pending=$(jsonpath "notebook/${WORKBENCH_NAME}" "$RAG_NS" "{.metadata.annotations.notebooks\\.opendatahub\\.io/update-pending}")
[[ -z "$workbench_update_pending" ]] \
  && check "Enterprise RAG Workbench has no pending controller migration" "pass" \
  || check "Enterprise RAG Workbench has no pending controller migration" "$workbench_update_pending"

workbench_statefulset_containers=$(jsonpath "statefulset/${WORKBENCH_NAME}" "$RAG_NS" "{.spec.template.spec.containers[*].name}")
contains_word "$workbench_statefulset_containers" "kube-rbac-proxy" \
  && check "Enterprise RAG Workbench StatefulSet includes auth proxy sidecar" "pass" \
  || check "Enterprise RAG Workbench StatefulSet includes auth proxy sidecar" "${workbench_statefulset_containers:-missing}"

workbench_pod=$(oc get pods -n "$RAG_NS" -l "statefulset=${WORKBENCH_NAME}" \
  -o jsonpath='{.items[0].metadata.name}' --insecure-skip-tls-verify=true 2>/dev/null || true)
if [[ -n "$workbench_pod" ]]; then
  workbench_pod_containers=$(jsonpath "pod/${workbench_pod}" "$RAG_NS" "{.spec.containers[*].name}")
  workbench_pod_ready=$(jsonpath "pod/${workbench_pod}" "$RAG_NS" "{.status.containerStatuses[*].ready}")
  contains_word "$workbench_pod_containers" "kube-rbac-proxy" \
    && check "Enterprise RAG Workbench pod includes auth proxy sidecar" "pass" \
    || check "Enterprise RAG Workbench pod includes auth proxy sidecar" "${workbench_pod_containers:-missing}"
  [[ -n "$workbench_pod_ready" && "$workbench_pod_ready" != *"false"* ]] \
    && check "Enterprise RAG Workbench pod has ready containers" "pass" \
    || check "Enterprise RAG Workbench pod has ready containers" "${workbench_pod_ready:-missing}"
  if oc --insecure-skip-tls-verify=true exec -n "$RAG_NS" "$workbench_pod" -c "$WORKBENCH_NAME" -- bash -lc \
    'test -f /opt/app-root/src/workspace/Ingestion_pipeline_ag_news.ipynb &&
     test -f /opt/app-root/src/workspace/retrieval_pipeline_ag_news.ipynb &&
     test -d /opt/app-root/src/workspace/.stage230 &&
     test -d /opt/app-root/src/workspace/.stage230/python &&
     test ! -d /opt/app-root/src/workspace/rhoai3-demo &&
     test ! -d /opt/app-root/src/rhoai3-demo' >/dev/null 2>&1; then
    check "Enterprise RAG Workbench exposes curated notebook workspace" "pass"
  else
    check "Enterprise RAG Workbench exposes curated notebook workspace" "expected two visible notebooks and hidden .stage230 helper content"
  fi
  if oc --insecure-skip-tls-verify=true exec -n "$RAG_NS" "$workbench_pod" -c "$WORKBENCH_NAME" -- bash -lc \
    'python - <<'"'"'PY'"'"'
from llama_stack_client import LlamaStackClient
print(LlamaStackClient.__name__)
PY' >/dev/null 2>&1; then
    check "Enterprise RAG Workbench can import llama-stack-client" "pass"
  else
    check "Enterprise RAG Workbench can import llama-stack-client" "missing from active notebook Python environment"
  fi
else
  check "Enterprise RAG Workbench pod exists" "missing"
fi

workbench_proxy_endpoint=$(oc get endpointslice -n "$RAG_NS" \
  -l "kubernetes.io/service-name=${WORKBENCH_NAME}-kube-rbac-proxy" \
  -o jsonpath='{range .items[*]}{range .endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{" "}{end}{range .ports[?(@.port==8443)]}{.port}{" "}{end}{end}' \
  --insecure-skip-tls-verify=true 2>/dev/null || true)
if [[ "$workbench_proxy_endpoint" == *"8443"* && "$workbench_proxy_endpoint" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  check "Enterprise RAG Workbench auth-proxy Service has a ready 8443 endpoint" "pass"
else
  check "Enterprise RAG Workbench auth-proxy Service has a ready 8443 endpoint" "${workbench_proxy_endpoint:-missing}"
fi

workbench_ready=$(condition_status "notebook/${WORKBENCH_NAME}" "$RAG_NS" "Ready")
if [[ "$workbench_ready" == "True" ]]; then
  check "Enterprise RAG Workbench reports Ready" "pass"
else
  warn "Enterprise RAG Workbench reports Ready" "${workbench_ready:-not reported yet}"
fi

route_host=$(jsonpath "route/lsd-enterprise-rag" "$RAG_NS" "{.spec.host}")
if [[ -n "$route_host" ]]; then
  check "Llama Stack route exists" "pass"
  models_body=$(mktemp)
  status=$(curl -sk --max-time 30 -o "$models_body" -w '%{http_code}' "https://${route_host}/v1/models" 2>/dev/null || true)
  if [[ "$status" == "200" ]] && grep -q "$NEMOTRON_MODEL_RESOURCE" "$models_body"; then
    check "Llama Stack lists MaaS-backed Nemotron model" "pass"
  else
    check "Llama Stack lists MaaS-backed Nemotron model" "status=${status},body=$(head -c 180 "$models_body" | tr '\n' ' ')"
  fi
  if [[ "$status" == "200" ]] && grep -q "$EMBEDDING_MODEL" "$models_body"; then
    check "Llama Stack lists Nomic embedding model" "pass"
  else
    check "Llama Stack lists Nomic embedding model" "status=${status},model=${EMBEDDING_MODEL},body=$(head -c 180 "$models_body" | tr '\n' ' ')"
  fi
  if [[ "$status" == "200" ]] && grep -q "$RERANKER_MODEL" "$models_body"; then
    check "Llama Stack lists Qwen3 reranker model" "pass"
  else
    check "Llama Stack lists Qwen3 reranker model" "status=${status},model=${RERANKER_MODEL},body=$(head -c 180 "$models_body" | tr '\n' ' ')"
  fi
  rm -f "$models_body"
else
  check "Llama Stack route exists" "missing"
fi

if python3 -m py_compile "$SCRIPT_DIR/scripts/agnews_rag_smoke.py" >/dev/null 2>&1; then
  check "AG News RAG smoke script compiles" "pass"
else
  check "AG News RAG smoke script compiles" "py_compile failed"
fi

if python3 -m py_compile "$SCRIPT_DIR/scripts/agnews_rag_acceptance.py" >/dev/null 2>&1; then
  check "AG News RAG acceptance script compiles" "pass"
else
  check "AG News RAG acceptance script compiles" "py_compile failed"
fi

if [[ "${RHOAI_STAGE230_RUN_ACCEPTANCE:-false}" == "true" ]]; then
  if [[ -n "$route_host" && -n "$reranker_route_host" ]]; then
    if python3 "$SCRIPT_DIR/scripts/agnews_rag_acceptance.py" \
      --base-url "https://${route_host}" \
      --reranker-base-url "https://${route_host}" \
      --reranker-model "$RERANKER_MODEL" \
      --reset >/tmp/stage230-agnews-acceptance.json 2>/tmp/stage230-agnews-acceptance.err; then
      check "AG News full RAG acceptance passes" "pass"
    else
      check "AG News full RAG acceptance passes" "$(head -c 300 /tmp/stage230-agnews-acceptance.err | tr '\n' ' ')"
    fi
  else
    check "AG News full RAG acceptance passes" "missing Llama Stack or reranker route"
  fi
else
  warn "AG News full RAG acceptance was not run" "set RHOAI_STAGE230_RUN_ACCEPTANCE=true"
fi

echo
echo "Stage 230 validation summary: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
if (( FAIL > 0 )); then
  exit 1
fi
