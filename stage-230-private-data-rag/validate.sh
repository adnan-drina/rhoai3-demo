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
RAG_BUCKET_OBC="${RHOAI_STAGE230_BUCKET_OBC:-enterprise-rag-bucket}"
RAG_S3_CONNECTION_SECRET="${RHOAI_STAGE230_S3_CONNECTION_SECRET:-enterprise-rag-s3}"
PIPELINE_S3_SECRET="${RHOAI_STAGE230_PIPELINE_S3_SECRET:-data-processing-docling-pipeline}"
RAG_PRODUCT_DOCS_PREFIX="${RHOAI_STAGE230_PRODUCT_DOCS_PREFIX:-raw/rhoai-product-docs}"
RHOAI_DOCS_PIPELINE_NAME="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_NAME:-stage-230-rhoai-product-docs-docling}"
RHOAI_DOCS_PIPELINE_DISPLAY_NAME="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_DISPLAY_NAME:-RHOAI Product Docs Docling Pipeline}"
RHOAI_DOCS_PIPELINE_EVIDENCE_CM="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_EVIDENCE_CM:-stage230-rhoai-docs-pipeline-evidence}"
RHOAI_DOCS_PIPELINE_OUTPUT_KEY="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_OUTPUT_KEY:-processed/rhoai-product-docs/rhoai-3.4-product-docs-docling-kfp-chunks.jsonl}"
RHOAI_DOCS_PIPELINE_TIMEOUT_SECONDS="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_TIMEOUT_SECONDS:-3600}"
DSPA_NAME="${RHOAI_STAGE230_DSPA_NAME:-dspa-enterprise-rag}"
POSTGRES_SECRET="${RHOAI_STAGE230_POSTGRES_SECRET:-private-rag-postgres-credentials}"
LLAMA_SECRET="${RHOAI_STAGE230_LLAMA_STACK_SECRET:-private-rag-llama-stack-secret}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
RERANKER_NAME="${RHOAI_STAGE230_RERANKER_NAME:-qwen3-reranker}"
RERANKER_MODEL="${RHOAI_STAGE230_RERANKER_MODEL:-vllm-reranker/qwen3-reranker}"
EMBEDDING_MODEL="${RHOAI_STAGE230_EMBEDDING_MODEL:-sentence-transformers/nomic-ai/nomic-embed-text-v1.5}"
WORKBENCH_NAME="${RHOAI_STAGE230_WORKBENCH_NAME:-enterprise-rag-workbench}"
CHATBOT_BUILD="${RHOAI_STAGE230_CHATBOT_BUILD:-private-rag-chatbot}"
CHATBOT_BUILD_NS="${RHOAI_STAGE230_CHATBOT_BUILD_NAMESPACE:-enterprise-rag-build}"
CHATBOT_DEPLOYMENT="${RHOAI_STAGE230_CHATBOT_DEPLOYMENT:-private-rag-chatbot}"
RHOAI_DASHBOARD_NS="${RHOAI_DASHBOARD_APPLICATIONS_NAMESPACE:-redhat-ods-applications}"
CHATBOT_DASHBOARD_APP="${RHOAI_STAGE230_CHATBOT_DASHBOARD_APP:-rhoai-demo-private-rag-chatbot}"

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
for secret in "$POSTGRES_SECRET" "$LLAMA_SECRET"; do
  resource_exists "secret/${secret}" "$RAG_NS" && check "${secret} Secret exists" "pass" || check "${secret} Secret exists" "missing"
done

obc_phase=$(jsonpath "obc/${RAG_BUCKET_OBC}" "$RAG_NS" "{.status.phase}")
[[ "$obc_phase" == "Bound" ]] \
  && check "Enterprise RAG ObjectBucketClaim is Bound" "pass" \
  || check "Enterprise RAG ObjectBucketClaim is Bound" "${obc_phase:-missing}"
resource_exists "secret/${RAG_BUCKET_OBC}" "$RAG_NS" \
  && check "Enterprise RAG OBC credential Secret exists" "pass" \
  || check "Enterprise RAG OBC credential Secret exists" "missing"
resource_exists "configmap/${RAG_BUCKET_OBC}" "$RAG_NS" \
  && check "Enterprise RAG OBC ConfigMap exists" "pass" \
  || check "Enterprise RAG OBC ConfigMap exists" "missing"
resource_exists "secret/${RAG_S3_CONNECTION_SECRET}" "$RAG_NS" \
  && check "Enterprise RAG dashboard S3 connection Secret exists" "pass" \
  || check "Enterprise RAG dashboard S3 connection Secret exists" "missing"
resource_exists "secret/${PIPELINE_S3_SECRET}" "$RAG_NS" \
  && check "Enterprise RAG pipeline S3 Secret exists" "pass" \
  || check "Enterprise RAG pipeline S3 Secret exists" "missing"

s3_connection_type=$(jsonpath "secret/${RAG_S3_CONNECTION_SECRET}" "$RAG_NS" "{.metadata.annotations.opendatahub\\.io/connection-type-ref}")
[[ "$s3_connection_type" == "s3" ]] \
  && check "Enterprise RAG S3 connection uses the dashboard S3 connection type" "pass" \
  || check "Enterprise RAG S3 connection uses the dashboard S3 connection type" "${s3_connection_type:-missing}"

pipeline_s3_prefix=$(jsonpath "secret/${PIPELINE_S3_SECRET}" "$RAG_NS" "{.data.S3_PREFIX}" | base64 --decode 2>/dev/null || true)
[[ "$pipeline_s3_prefix" == "$RAG_PRODUCT_DOCS_PREFIX" ]] \
  && check "Enterprise RAG pipeline S3 prefix targets RHOAI product docs" "pass" \
  || check "Enterprise RAG pipeline S3 prefix targets RHOAI product docs" "${pipeline_s3_prefix:-missing}"

obc_bucket_name=$(jsonpath "configmap/${RAG_BUCKET_OBC}" "$RAG_NS" "{.data.BUCKET_NAME}")
[[ "$obc_bucket_name" == "enterprise-rag" ]] \
  && check "Enterprise RAG OBC uses deterministic bucket name" "pass" \
  || check "Enterprise RAG OBC uses deterministic bucket name" "${obc_bucket_name:-missing}"

dsc_aipipelines=$(jsonpath "datasciencecluster/default-dsc" "" "{.spec.components.aipipelines.managementState}")
[[ "$dsc_aipipelines" == "Managed" ]] \
  && check "DataScienceCluster AI Pipelines component is Managed" "pass" \
  || check "DataScienceCluster AI Pipelines component is Managed" "${dsc_aipipelines:-missing}"

resource_exists "dspa/${DSPA_NAME}" "$RAG_NS" \
  && check "Enterprise RAG DSPA exists" "pass" \
  || check "Enterprise RAG DSPA exists" "missing"

dspa_ready=$(condition_status "dspa/${DSPA_NAME}" "$RAG_NS" "Ready")
if [[ "$dspa_ready" == "True" ]]; then
  check "Enterprise RAG DSPA reports Ready" "pass"
else
  warn "Enterprise RAG DSPA reports Ready" "${dspa_ready:-not reported yet}"
fi

dspa_object_storage=$(condition_status "dspa/${DSPA_NAME}" "$RAG_NS" "ObjectStoreAvailable")
if [[ "$dspa_object_storage" == "True" || -z "$dspa_object_storage" ]]; then
  [[ "$dspa_object_storage" == "True" ]] \
    && check "Enterprise RAG DSPA object storage is available" "pass" \
    || warn "Enterprise RAG DSPA object storage condition" "not reported yet"
else
  check "Enterprise RAG DSPA object storage is available" "$dspa_object_storage"
fi

dspa_route_host=$(jsonpath "route/ds-pipeline-${DSPA_NAME}" "$RAG_NS" "{.spec.host}")
[[ -n "$dspa_route_host" ]] \
  && check "Enterprise RAG DSPA route exists" "pass" \
  || check "Enterprise RAG DSPA route exists" "missing"

resource_exists "pipeline/${RHOAI_DOCS_PIPELINE_NAME}" "$RAG_NS" \
  && check "RHOAI product docs Docling Pipeline resource exists" "pass" \
  || warn "RHOAI product docs Docling Pipeline resource exists" "run stage-230-private-data-rag/run-rhoai-docs-pipeline.sh"

pipeline_display_name=$(jsonpath "pipeline/${RHOAI_DOCS_PIPELINE_NAME}" "$RAG_NS" "{.spec.displayName}")
[[ "$pipeline_display_name" == "$RHOAI_DOCS_PIPELINE_DISPLAY_NAME" ]] \
  && check "RHOAI product docs Docling Pipeline has dashboard display name" "pass" \
  || warn "RHOAI product docs Docling Pipeline has dashboard display name" "${pipeline_display_name:-missing}"

if command -v jq >/dev/null 2>&1; then
  pipeline_version_summary=$(
    oc get pipelineversion -n "$RAG_NS" -o json --insecure-skip-tls-verify=true 2>/dev/null \
      | jq -r --arg pipeline "$RHOAI_DOCS_PIPELINE_NAME" --arg display "$RHOAI_DOCS_PIPELINE_DISPLAY_NAME" '
          [.items[] | select(.spec.pipelineName == $pipeline)] as $versions
          | if ($versions | length) == 0 then
              "0\t"
            else
              ($versions | sort_by(.metadata.creationTimestamp) | last) as $latest
              | "\($versions | length)\t\($latest.spec.displayName // "")"
            end
        ' || true
  )
  pipeline_version_count="${pipeline_version_summary%%$'\t'*}"
  latest_pipeline_version_display="${pipeline_version_summary#*$'\t'}"
  [[ "${pipeline_version_count:-0}" -ge 1 ]] \
    && check "RHOAI product docs Docling PipelineVersion exists" "pass" \
    || warn "RHOAI product docs Docling PipelineVersion exists" "run stage-230-private-data-rag/run-rhoai-docs-pipeline.sh"
  [[ "$latest_pipeline_version_display" == "$RHOAI_DOCS_PIPELINE_DISPLAY_NAME"* ]] \
    && check "Latest Docling PipelineVersion uses readable display name" "pass" \
    || warn "Latest Docling PipelineVersion uses readable display name" "${latest_pipeline_version_display:-missing}"
else
  warn "RHOAI product docs Docling PipelineVersion visibility check skipped" "install jq"
fi

rhoai_pdf_dir="$SCRIPT_DIR/data/rhoai-product-docs/source"
if [[ -d "$rhoai_pdf_dir" ]]; then
  rhoai_pdf_count=$(find "$rhoai_pdf_dir" -maxdepth 1 -type f -name '*.pdf' | wc -l | tr -d ' ')
else
  rhoai_pdf_count=0
fi
[[ "$rhoai_pdf_count" -ge 6 ]] \
  && check "Repo stores RHOAI product documentation source PDFs" "pass" \
  || check "Repo stores RHOAI product documentation source PDFs" "found=${rhoai_pdf_count}"

rhoai_chunks_file="$SCRIPT_DIR/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl"
if [[ -s "$rhoai_chunks_file" ]]; then
  rhoai_chunk_count=$(wc -l < "$rhoai_chunks_file" | tr -d ' ')
else
  rhoai_chunk_count=0
fi
[[ "$rhoai_chunk_count" -ge 1 ]] \
  && check "Repo stores prepared RHOAI product documentation chunks" "pass" \
  || check "Repo stores prepared RHOAI product documentation chunks" "${rhoai_chunk_count:-missing}"

vllm_url=$(jsonpath "secret/${LLAMA_SECRET}" "$RAG_NS" "{.data.VLLM_URL}" | base64 --decode 2>/dev/null || true)
[[ "$vllm_url" == */v1 ]] && check "Llama Stack MaaS base URL ends with /v1" "pass" || check "Llama Stack MaaS base URL ends with /v1" "${vllm_url:-missing}"

[[ "$(available_replicas statefulset/private-rag-postgres "$RAG_NS")" == "1" ]] \
  && check "PostgreSQL metadata store is available" "pass" \
  || check "PostgreSQL metadata store is available" "availableReplicas=$(available_replicas statefulset/private-rag-postgres "$RAG_NS")"

postgres_pod=$(oc get pods -n "$RAG_NS" -l "statefulset.kubernetes.io/pod-name=private-rag-postgres-0" \
  -o jsonpath='{.items[0].metadata.name}' --insecure-skip-tls-verify=true 2>/dev/null || true)
if [[ -n "$postgres_pod" ]]; then
  if oc --insecure-skip-tls-verify=true exec -n "$RAG_NS" "$postgres_pod" -- bash -lc \
    'export PGPASSWORD="$POSTGRESQL_PASSWORD"; psql -U "$POSTGRESQL_USER" -d "$POSTGRESQL_DATABASE" -tAc "select extversion from pg_extension where extname = '"'"'vector'"'"';" | grep -q .'; then
    check "PostgreSQL vector extension is installed" "pass"
  else
    check "PostgreSQL vector extension is installed" "missing"
  fi
else
  check "PostgreSQL pod exists for pgvector validation" "missing"
fi

lls_phase=$(jsonpath "llamastackdistribution/lsd-enterprise-rag" "$RAG_NS" "{.status.phase}")
[[ "$lls_phase" == "Ready" ]] && check "LlamaStackDistribution is Ready" "pass" || check "LlamaStackDistribution is Ready" "${lls_phase:-missing}"

reranker_ready=$(condition_status "inferenceservice/${RERANKER_NAME}" "$RAG_NS" "Ready")
[[ "$reranker_ready" == "True" ]] \
  && check "Qwen3 reranker InferenceService is Ready" "pass" \
  || check "Qwen3 reranker InferenceService is Ready" "${reranker_ready:-missing}"

reranker_runtime_version=$(jsonpath "servingruntime/${RERANKER_NAME}" "$RAG_NS" "{.metadata.annotations.opendatahub\\.io/runtime-version}")
template_runtime_version=$(jsonpath "template/vllm-cpu-x86-runtime-template" "redhat-ods-applications" "{.objects[0].metadata.annotations.opendatahub\\.io/runtime-version}")
[[ -n "$template_runtime_version" && "$reranker_runtime_version" == "$template_runtime_version" ]] \
  && check "Qwen3 reranker ServingRuntime matches installed RHOAI CPU vLLM template version" "pass" \
  || check "Qwen3 reranker ServingRuntime matches installed RHOAI CPU vLLM template version" "runtime=${reranker_runtime_version:-missing},template=${template_runtime_version:-missing}"

reranker_runtime_image=$(jsonpath "servingruntime/${RERANKER_NAME}" "$RAG_NS" "{.spec.containers[0].image}")
template_runtime_image=$(jsonpath "template/vllm-cpu-x86-runtime-template" "redhat-ods-applications" "{.objects[0].spec.containers[0].image}")
[[ -n "$template_runtime_image" && "$reranker_runtime_image" == "$template_runtime_image" ]] \
  && check "Qwen3 reranker ServingRuntime uses installed RHOAI CPU vLLM image" "pass" \
  || check "Qwen3 reranker ServingRuntime uses installed RHOAI CPU vLLM image" "runtime=${reranker_runtime_image:-missing},template=${template_runtime_image:-missing}"

reranker_queue=$(jsonpath "inferenceservice/${RERANKER_NAME}" "$RAG_NS" "{.metadata.labels.kueue\\.x-k8s\\.io/queue-name}")
[[ "$reranker_queue" == "lq-cpu-default" ]] \
  && check "Qwen3 reranker uses CPU LocalQueue" "pass" \
  || check "Qwen3 reranker uses CPU LocalQueue" "${reranker_queue:-missing}"

reranker_route_host=$(jsonpath "route/${RERANKER_NAME}" "$RAG_NS" "{.spec.host}")
[[ -n "$reranker_route_host" ]] \
  && check "Qwen3 reranker route exists" "pass" \
  || check "Qwen3 reranker route exists" "missing"

if resource_exists "inferenceservice/docling" "$RAG_NS" || resource_exists "inferenceservice/docling-standard" "$RAG_NS"; then
  warn "Docling is represented as AI Pipelines tasks, not a model Deployment" "unexpected Docling InferenceService exists"
else
  check "Docling is represented as AI Pipelines tasks, not a model Deployment" "pass"
fi

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

workbench_connection=$(jsonpath "notebook/${WORKBENCH_NAME}" "$RAG_NS" "{.metadata.annotations.opendatahub\\.io/connections}")
[[ "$workbench_connection" == *"$RAG_S3_CONNECTION_SECRET"* ]] \
  && check "Enterprise RAG Workbench references the S3 connection" "pass" \
  || check "Enterprise RAG Workbench references the S3 connection" "${workbench_connection:-missing}"

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
     test -f /opt/app-root/src/workspace/Docling_data_preparation_rhoai_docs.ipynb &&
     test -f /opt/app-root/src/workspace/Ingestion_pipeline_rhoai_docs.ipynb &&
     test -f /opt/app-root/src/workspace/Retrieval_pipeline_rhoai_docs.ipynb &&
     test -d /opt/app-root/src/workspace/.stage230 &&
     test -d /opt/app-root/src/workspace/.stage230/python &&
     test -d /opt/app-root/src/workspace/.stage230/docling-models &&
     test -d /opt/app-root/src/workspace/.stage230/hf-cache &&
     test -f /opt/app-root/src/workspace/.stage230/scripts/rhoai_product_docs_prepare.py &&
     test -f /opt/app-root/src/workspace/.stage230/scripts/rhoai_product_docs_rag_smoke.py &&
     test -f /opt/app-root/src/workspace/.stage230/data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json &&
     test -f /opt/app-root/src/workspace/.stage230/data/rhoai-product-docs/source/Red_Hat_OpenShift_AI_Self-Managed-3.4-Working_with_Llama_Stack-en-US.pdf &&
     test -f /opt/app-root/src/workspace/.stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl &&
     test ! -d /opt/app-root/src/workspace/rhoai3-demo &&
     test ! -d /opt/app-root/src/rhoai3-demo' >/dev/null 2>&1; then
    check "Enterprise RAG Workbench exposes curated notebook workspace" "pass"
  else
    check "Enterprise RAG Workbench exposes curated notebook workspace" "expected AG News notebooks, RHOAI product docs notebook, and hidden .stage230 helper content"
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
  if oc --insecure-skip-tls-verify=true exec -n "$RAG_NS" "$workbench_pod" -c "$WORKBENCH_NAME" -- bash -lc \
    'python - <<'"'"'PY'"'"'
import os
required = [
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_S3_ENDPOINT",
    "AWS_S3_BUCKET",
    "RHOAI_STAGE230_PRODUCT_DOCS_PREFIX",
]
missing = [name for name in required if not os.environ.get(name)]
if missing:
    raise SystemExit(f"missing S3 environment variables: {missing}")
PY' >/dev/null 2>&1; then
    check "Enterprise RAG Workbench exposes S3 connection environment" "pass"
  else
    check "Enterprise RAG Workbench exposes S3 connection environment" "missing required S3 environment variables"
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

if python3 -m compileall -q "$SCRIPT_DIR/chatbot" >/dev/null 2>&1; then
  check "Stage 230 chatbot source compiles" "pass"
else
  check "Stage 230 chatbot source compiles" "compileall failed"
fi

resource_exists "namespace/${CHATBOT_BUILD_NS}" "" \
  && check "Stage 230 chatbot build namespace exists" "pass" \
  || check "Stage 230 chatbot build namespace exists" "missing"

resource_exists "imagestream/${CHATBOT_BUILD}" "$CHATBOT_BUILD_NS" \
  && check "Stage 230 chatbot ImageStream exists" "pass" \
  || check "Stage 230 chatbot ImageStream exists" "missing"

resource_exists "buildconfig/${CHATBOT_BUILD}" "$CHATBOT_BUILD_NS" \
  && check "Stage 230 chatbot BuildConfig exists" "pass" \
  || check "Stage 230 chatbot BuildConfig exists" "missing"

resource_exists "imagestreamtag/${CHATBOT_BUILD}:latest" "$CHATBOT_BUILD_NS" \
  && check "Stage 230 chatbot image tag exists" "pass" \
  || check "Stage 230 chatbot image tag exists" "run deploy.sh to start the binary build"

chatbot_config_endpoint=$(jsonpath "configmap/private-rag-chatbot-config" "$RAG_NS" "{.data.LLAMA_STACK_ENDPOINT}")
[[ "$chatbot_config_endpoint" == "http://lsd-enterprise-rag-service.${RAG_NS}.svc.cluster.local:8321" ]] \
  && check "Stage 230 chatbot points at the Enterprise RAG Llama Stack service" "pass" \
  || check "Stage 230 chatbot points at the Enterprise RAG Llama Stack service" "${chatbot_config_endpoint:-missing}"

chatbot_config_model=$(jsonpath "configmap/private-rag-chatbot-config" "$RAG_NS" "{.data.INFERENCE_MODEL}")
[[ "$chatbot_config_model" == "$NEMOTRON_MODEL_RESOURCE" ]] \
  && check "Stage 230 chatbot defaults to Nemotron" "pass" \
  || check "Stage 230 chatbot defaults to Nemotron" "${chatbot_config_model:-missing}"

chatbot_config_store=$(jsonpath "configmap/private-rag-chatbot-config" "$RAG_NS" "{.data.DEFAULT_VECTOR_STORE}")
[[ "$chatbot_config_store" == "stage230-rhoai-34-product-docs-kfp" ]] \
  && check "Stage 230 chatbot defaults to the product-document vector store" "pass" \
  || check "Stage 230 chatbot defaults to the product-document vector store" "${chatbot_config_store:-missing}"

chatbot_config_rag=$(jsonpath "configmap/private-rag-chatbot-config" "$RAG_NS" "{.data.RAG_RERANK_ENABLED}")
[[ "$chatbot_config_rag" == "true" ]] \
  && check "Stage 230 chatbot enables reranking by default" "pass" \
  || check "Stage 230 chatbot enables reranking by default" "${chatbot_config_rag:-missing}"

[[ "$(available_replicas deployment/${CHATBOT_DEPLOYMENT} "$RAG_NS")" == "1" ]] \
  && check "Stage 230 chatbot Deployment is available" "pass" \
  || check "Stage 230 chatbot Deployment is available" "availableReplicas=$(available_replicas deployment/${CHATBOT_DEPLOYMENT} "$RAG_NS")"

chatbot_route_host=$(jsonpath "route/${CHATBOT_DEPLOYMENT}" "$RAG_NS" "{.spec.host}")
if [[ -n "$chatbot_route_host" ]]; then
  check "Stage 230 chatbot route exists" "pass"
  chatbot_health=$(curl -sk --max-time 15 -o /dev/null -w '%{http_code}' "https://${chatbot_route_host}/_stcore/health" 2>/dev/null || true)
  [[ "$chatbot_health" == "200" ]] \
    && check "Stage 230 chatbot health route responds" "pass" \
    || check "Stage 230 chatbot health route responds" "status=${chatbot_health:-missing}"
else
  check "Stage 230 chatbot route exists" "missing"
fi

resource_exists "odhapplication/${CHATBOT_DASHBOARD_APP}" "$RHOAI_DASHBOARD_NS" \
  && check "Stage 230 RHOAI dashboard chatbot tile exists" "pass" \
  || check "Stage 230 RHOAI dashboard chatbot tile exists" "missing"

chatbot_dashboard_route=$(jsonpath "odhapplication/${CHATBOT_DASHBOARD_APP}" "$RHOAI_DASHBOARD_NS" "{.spec.route}")
[[ "$chatbot_dashboard_route" == "$CHATBOT_DEPLOYMENT" ]] \
  && check "Stage 230 RHOAI dashboard chatbot tile points at the chatbot route" "pass" \
  || check "Stage 230 RHOAI dashboard chatbot tile points at the chatbot route" "${chatbot_dashboard_route:-missing}"

chatbot_dashboard_route_ns=$(jsonpath "odhapplication/${CHATBOT_DASHBOARD_APP}" "$RHOAI_DASHBOARD_NS" "{.spec.routeNamespace}")
[[ "$chatbot_dashboard_route_ns" == "$RAG_NS" ]] \
  && check "Stage 230 RHOAI dashboard chatbot tile points at enterprise-rag" "pass" \
  || check "Stage 230 RHOAI dashboard chatbot tile points at enterprise-rag" "${chatbot_dashboard_route_ns:-missing}"

chatbot_dashboard_label=$(jsonpath "odhapplication/${CHATBOT_DASHBOARD_APP}" "$RHOAI_DASHBOARD_NS" "{.metadata.labels.app\\.kubernetes\\.io/part-of}")
[[ "$chatbot_dashboard_label" == "odh-dashboard" ]] \
  && check "Stage 230 RHOAI dashboard chatbot tile keeps dashboard label" "pass" \
  || check "Stage 230 RHOAI dashboard chatbot tile keeps dashboard label" "${chatbot_dashboard_label:-missing}"

generation_base_url=$(jsonpath "secret/${LLAMA_SECRET}" "$RAG_NS" "{.data.VLLM_URL}" | base64 --decode 2>/dev/null || true)
generation_api_key=$(jsonpath "secret/${LLAMA_SECRET}" "$RAG_NS" "{.data.VLLM_API_TOKEN}" | base64 --decode 2>/dev/null || true)

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

if python3 -m py_compile "$SCRIPT_DIR/scripts/rhoai_product_docs_prepare.py" >/dev/null 2>&1; then
  check "RHOAI product docs preparation script compiles" "pass"
else
  check "RHOAI product docs preparation script compiles" "py_compile failed"
fi

if python3 -m py_compile "$SCRIPT_DIR/scripts/rhoai_product_docs_rag_smoke.py" >/dev/null 2>&1; then
  check "RHOAI product docs RAG smoke script compiles" "pass"
else
  check "RHOAI product docs RAG smoke script compiles" "py_compile failed"
fi

if python3 -m py_compile \
  "$SCRIPT_DIR"/kfp/components/*.py \
  "$SCRIPT_DIR/kfp/rhoai_product_docs_docling_pipeline.py" >/dev/null 2>&1; then
  check "RHOAI product docs Docling KFP source compiles" "pass"
else
  check "RHOAI product docs Docling KFP source compiles" "py_compile failed"
fi

kfp_python="python3"
if [[ -x "$ROOT_DIR/.venv-kfp/bin/python" ]]; then
  kfp_python="$ROOT_DIR/.venv-kfp/bin/python"
fi

if "$kfp_python" - <<'PY' >/dev/null 2>&1
from kfp import compiler, dsl, kubernetes  # noqa: F401
PY
then
  kfp_compile_dir=$(mktemp -d)
  if "$kfp_python" "$SCRIPT_DIR/kfp/rhoai_product_docs_docling_pipeline.py" \
    --output "$kfp_compile_dir/stage-230-rhoai-product-docs-docling.yaml" >/dev/null 2>&1 \
    && [[ -s "$kfp_compile_dir/stage-230-rhoai-product-docs-docling.yaml" ]]; then
    check "RHOAI product docs Docling KFP pipeline compiles locally" "pass"
    if grep -Eq "docling-convert-standard|docling-chunk|publish-docling-split-outputs|normalize-rhoai-product-doc-chunks" \
      "$kfp_compile_dir/stage-230-rhoai-product-docs-docling.yaml"; then
      check "RHOAI product docs Docling KFP pipeline exposes modular dashboard tasks" "pass"
    else
      check "RHOAI product docs Docling KFP pipeline exposes modular dashboard tasks" "missing"
    fi
  else
    check "RHOAI product docs Docling KFP pipeline compiles locally" "compiler failed"
  fi
  rm -rf "$kfp_compile_dir"
else
  warn "RHOAI product docs Docling KFP pipeline local compile skipped" "install kfp==2.14.6 and kfp-kubernetes==2.14.6"
fi

if [[ "${RHOAI_STAGE230_RUN_RHOAI_DOCS_PIPELINE:-false}" == "true" ]]; then
  if "$SCRIPT_DIR/run-rhoai-docs-pipeline.sh" --timeout-seconds="$RHOAI_DOCS_PIPELINE_TIMEOUT_SECONDS"; then
    check "RHOAI product docs Docling DSPA/KFP run passes" "pass"
  else
    check "RHOAI product docs Docling DSPA/KFP run passes" "pipeline runner failed"
  fi
else
  if resource_exists "configmap/${RHOAI_DOCS_PIPELINE_EVIDENCE_CM}" "$RAG_NS"; then
    check "RHOAI product docs Docling DSPA/KFP run evidence is reusable" "pass"
  else
    warn "RHOAI product docs Docling DSPA/KFP run was not run" "set RHOAI_STAGE230_RUN_RHOAI_DOCS_PIPELINE=true"
  fi
fi

if resource_exists "configmap/${RHOAI_DOCS_PIPELINE_EVIDENCE_CM}" "$RAG_NS"; then
  pipeline_review=$(jsonpath "configmap/${RHOAI_DOCS_PIPELINE_EVIDENCE_CM}" "$RAG_NS" "{.data.artifact-review\\.json}")
  if [[ "$pipeline_review" == *'"status": "pass"'* ]]; then
    check "RHOAI product docs Docling pipeline evidence is present" "pass"
  else
    check "RHOAI product docs Docling pipeline evidence is present" "artifact review did not report pass"
  fi
else
  warn "RHOAI product docs Docling pipeline evidence is present" "missing ${RHOAI_DOCS_PIPELINE_EVIDENCE_CM}"
fi

if [[ "${RHOAI_STAGE230_RUN_ACCEPTANCE:-false}" == "true" ]]; then
  if [[ -n "${workbench_pod:-}" ]]; then
    acceptance_out=$(mktemp)
    acceptance_err=$(mktemp)
    if oc --insecure-skip-tls-verify=true exec -n "$RAG_NS" "$workbench_pod" -c "$WORKBENCH_NAME" -- bash -lc \
      'cd /opt/app-root/src/workspace &&
       python .stage230/scripts/agnews_rag_acceptance.py \
         --reset \
         --vector-store stage230-agnews-demo \
         --search-mode hybrid' >"$acceptance_out" 2>"$acceptance_err"; then
      check "AG News full RAG acceptance passes" "pass"
    else
      check "AG News full RAG acceptance passes" "$(head -c 300 "$acceptance_err" | tr '\n' ' ')"
    fi
    rm -f "$acceptance_out" "$acceptance_err"
  else
    check "AG News full RAG acceptance passes" "missing ready Enterprise RAG Workbench pod"
  fi
else
  warn "AG News full RAG acceptance was not run" "set RHOAI_STAGE230_RUN_ACCEPTANCE=true"
fi

if [[ "${RHOAI_STAGE230_RUN_RHOAI_DOCS_SMOKE:-false}" == "true" ]]; then
  if [[ -n "${workbench_pod:-}" ]]; then
    rhoai_docs_out=$(mktemp)
    rhoai_docs_err=$(mktemp)
    rhoai_docs_command=""
    if [[ -n "${RHOAI_STAGE230_RHOAI_DOCS_LOCAL_SAMPLE:-}" ]]; then
      if [[ ! -s "$RHOAI_STAGE230_RHOAI_DOCS_LOCAL_SAMPLE" ]]; then
        check "RHOAI product documentation RAG smoke passes" "local sample not found: $RHOAI_STAGE230_RHOAI_DOCS_LOCAL_SAMPLE"
      else
        oc --insecure-skip-tls-verify=true exec -n "$RAG_NS" "$workbench_pod" -c "$WORKBENCH_NAME" -- \
          mkdir -p /opt/app-root/src/workspace/.stage230/data/rhoai-product-docs/processed >/dev/null
        oc --insecure-skip-tls-verify=true cp \
          "$RHOAI_STAGE230_RHOAI_DOCS_LOCAL_SAMPLE" \
          "${RAG_NS}/${workbench_pod}:/opt/app-root/src/workspace/.stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl" \
          -c "$WORKBENCH_NAME" >/dev/null
        rhoai_docs_command='cd /opt/app-root/src/workspace &&
         python .stage230/scripts/rhoai_product_docs_rag_smoke.py \
           --reset \
           --manifest .stage230/data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json \
           --sample .stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl \
           --vector-store stage230-rhoai-34-product-docs \
           --max-questions 3 \
           --search-mode hybrid'
      fi
    elif [[ "${RHOAI_STAGE230_RHOAI_DOCS_USE_PIPELINE_OUTPUT:-${RHOAI_STAGE230_RUN_RHOAI_DOCS_PIPELINE:-false}}" == "true" ]]; then
      rhoai_docs_command=$(cat <<EOF
cd /opt/app-root/src/workspace &&
RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_OUTPUT_KEY='${RHOAI_DOCS_PIPELINE_OUTPUT_KEY}' python - <<'PY'
import os
from pathlib import Path

import boto3
from botocore.config import Config
from urllib3 import disable_warnings
from urllib3.exceptions import InsecureRequestWarning

required = [
    "AWS_S3_ENDPOINT",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_S3_BUCKET",
    "RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_OUTPUT_KEY",
]
missing = [name for name in required if not os.environ.get(name)]
if missing:
    raise SystemExit(f"missing S3 environment variables: {missing}")

disable_warnings(InsecureRequestWarning)
key = os.environ["RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_OUTPUT_KEY"].strip("/")
client = boto3.client(
    "s3",
    endpoint_url=os.environ["AWS_S3_ENDPOINT"],
    aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
    region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
    verify=False,
    config=Config(signature_version="s3v4"),
)
target = Path(".stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl")
target.parent.mkdir(parents=True, exist_ok=True)
body = client.get_object(Bucket=os.environ["AWS_S3_BUCKET"], Key=key)["Body"].read()
if not body.strip():
    raise SystemExit(f"s3://{os.environ['AWS_S3_BUCKET']}/{key} is empty")
target.write_bytes(body)
print(f"downloaded s3://{os.environ['AWS_S3_BUCKET']}/{key} to {target}")
PY
python .stage230/scripts/rhoai_product_docs_rag_smoke.py \
  --reset \
  --manifest .stage230/data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json \
  --sample .stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl \
  --vector-store stage230-rhoai-34-product-docs-kfp \
  --max-questions 3 \
  --search-mode hybrid
EOF
)
    else
      rhoai_docs_command='cd /opt/app-root/src/workspace &&
       python .stage230/scripts/rhoai_product_docs_prepare.py \
         --manifest .stage230/data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json \
         --source-dir .stage230/data/rhoai-product-docs/source \
         --output .stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl &&
       python .stage230/scripts/rhoai_product_docs_rag_smoke.py \
         --reset \
         --manifest .stage230/data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json \
         --sample .stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl \
         --vector-store stage230-rhoai-34-product-docs \
         --max-questions 3 \
         --search-mode hybrid'
    fi
    if [[ -n "$rhoai_docs_command" ]]; then
      if oc --insecure-skip-tls-verify=true exec -n "$RAG_NS" "$workbench_pod" -c "$WORKBENCH_NAME" -- \
        bash -lc "$rhoai_docs_command" >"$rhoai_docs_out" 2>"$rhoai_docs_err"; then
        check "RHOAI product documentation RAG smoke passes" "pass"
      else
        check "RHOAI product documentation RAG smoke passes" "$(head -c 300 "$rhoai_docs_err" | tr '\n' ' ')"
      fi
    fi
    rm -f "$rhoai_docs_out" "$rhoai_docs_err"
  else
    check "RHOAI product documentation RAG smoke passes" "missing ready Enterprise RAG Workbench pod"
  fi
else
  warn "RHOAI product documentation RAG smoke was not run" "set RHOAI_STAGE230_RUN_RHOAI_DOCS_SMOKE=true"
fi

echo
echo "Stage 230 validation summary: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
if (( FAIL > 0 )); then
  exit 1
fi
