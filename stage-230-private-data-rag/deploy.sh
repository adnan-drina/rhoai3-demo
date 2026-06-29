#!/usr/bin/env bash
# deploy.sh - Stage 230: Private Data RAG
# Deploys the RAG runtime through GitOps and seeds environment-local data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

echo "[OK] Cluster guard passed: $ACTUAL_SERVER"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  fi
}

require_cmd base64
require_cmd curl
require_cmd jq
require_cmd oc
require_cmd openssl
require_cmd python3

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"
PROJECT_NS="${RHOAI_STAGE230_PROJECT_NAMESPACE:-enterprise-rag}"
MAAS_NS="${RHOAI_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_SUBSCRIPTION="${RHOAI_STAGE230_MAAS_SUBSCRIPTION:-${RHOAI_MAAS_DEMO_SUBSCRIPTION:-${RHOAI_OPENAI_ACCESS_RESOURCE:-rhoai-developers-gpt-5-4-mini}}}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
RAG_INFERENCE_MODEL="${RHOAI_STAGE230_INFERENCE_MODEL_ID:-vllm-inference/nemotron-3-nano-30b-a3b}"
RAG_LSD_NAME="${RHOAI_STAGE230_LSD_NAME:-lsd-private-rag}"
RAG_DOCLING_DEPLOYMENT="${RHOAI_STAGE230_DOCLING_DEPLOYMENT:-private-rag-docling}"
RAG_DOCLING_SERVICE="${RHOAI_STAGE230_DOCLING_SERVICE:-private-rag-docling}"
RAG_CHATBOT_DEPLOYMENT="${RHOAI_STAGE230_CHATBOT_DEPLOYMENT:-private-rag-chatbot}"
RAG_DOCLING_LOCAL_PORT="${RHOAI_STAGE230_DOCLING_LOCAL_PORT:-15001}"
RAG_DOCLING_TIMEOUT="${RHOAI_STAGE230_DOCLING_TIMEOUT:-600}"
RAG_DSPA_NAME="${RHOAI_STAGE230_DSPA_NAME:-private-rag-pipelines}"
RAG_DSPA_OBC_NAME="${RHOAI_STAGE230_DSPA_OBC_NAME:-private-rag-pipelines-bucket}"
RAG_PIPELINE_LAST_RUN_CONFIGMAP="${RHOAI_STAGE230_LAST_RUN_CONFIGMAP:-private-rag-pipeline-last-run}"
RAG_POSTGRES_SECRET="${RHOAI_STAGE230_POSTGRES_SECRET:-private-rag-postgres-credentials}"
RAG_LS_SECRET="${RHOAI_STAGE230_LLAMASTACK_SECRET:-private-rag-llama-stack-secret}"
RAG_DOC_CONFIGMAP="${RHOAI_STAGE230_DOCUMENT_CONFIGMAP:-private-rag-documents}"
RAG_S3_CONNECTION_SECRET="${RHOAI_STAGE230_S3_CONNECTION_SECRET:-enterprise-rag-s3}"
RAG_VECTOR_DB="${RHOAI_STAGE230_VECTOR_DB:-whoami}"
RAG_EMBEDDING_MODEL="${RHOAI_STAGE230_EMBEDDING_MODEL:-sentence-transformers/all-MiniLM-L6-v2}"
RAG_EMBEDDING_DIMENSION="${RHOAI_STAGE230_EMBEDDING_DIMENSION:-384}"
RAG_CHUNK_SIZE="${RHOAI_STAGE230_CHUNK_SIZE:-512}"
RAG_MAX_TOKENS="${RHOAI_STAGE230_VLLM_MAX_TOKENS:-4096}"
RAG_API_KEY_NAME="${RHOAI_STAGE230_API_KEY_NAME:-private-rag-${PROJECT_NS}}"
OBC_NAME="${RHOAI_STAGE230_OBC_NAME:-enterprise-rag-bucket}"

TMP_FILES=()
TMP_DIRS=()
BG_PIDS=()
cleanup() {
  if ((${#TMP_FILES[@]} > 0)); then
    rm -f "${TMP_FILES[@]}"
  fi
  if ((${#TMP_DIRS[@]} > 0)); then
    rm -rf "${TMP_DIRS[@]}"
  fi
  if ((${#BG_PIDS[@]} > 0)); then
    for pid in "${BG_PIDS[@]}"; do
      kill "$pid" >/dev/null 2>&1 || true
    done
  fi
}
trap cleanup EXIT

jsonpath() {
  local resource="$1"
  local namespace="$2"
  local path="$3"
  oc get "$resource" -n "$namespace" -o jsonpath="$path" \
    --insecure-skip-tls-verify=true 2>/dev/null || true
}

ensure_prerequisites() {
  echo "-- Checking Stage 230 prerequisites --"

  local lsd_crd dsc_state model_phase sub_phase sub_models gateway_host
  lsd_crd=$(oc get crd llamastackdistributions.llamastack.io \
    --insecure-skip-tls-verify=true >/dev/null 2>&1 && echo yes || echo no)
  [[ "$lsd_crd" == "yes" ]] || { echo "ERROR: LlamaStackDistribution CRD is missing." >&2; exit 1; }

  dsc_state=$(oc get datasciencecluster default-dsc -n redhat-ods-applications \
    -o jsonpath='{.spec.components.llamastackoperator.managementState}' \
    --insecure-skip-tls-verify=true 2>/dev/null || true)
  [[ "$dsc_state" == "Managed" ]] || { echo "ERROR: llamastackoperator is not Managed in default-dsc." >&2; exit 1; }

  model_phase=$(jsonpath "maasmodelref/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" '{.status.phase}')
  [[ "$model_phase" == "Ready" ]] || { echo "ERROR: MaaSModelRef ${NEMOTRON_MODEL_RESOURCE} is not Ready." >&2; exit 1; }

  sub_phase=$(jsonpath "maassubscription/${MAAS_SUBSCRIPTION}" "$MAAS_NS" '{.status.phase}')
  [[ "$sub_phase" == "Active" ]] || { echo "ERROR: MaaSSubscription ${MAAS_SUBSCRIPTION} is not Active." >&2; exit 1; }

  sub_models=$(jsonpath "maassubscription/${MAAS_SUBSCRIPTION}" "$MAAS_NS" '{.spec.modelRefs[*].name}')
  [[ " $sub_models " == *" ${NEMOTRON_MODEL_RESOURCE} "* ]] || {
    echo "ERROR: MaaSSubscription ${MAAS_SUBSCRIPTION} does not grant access to ${NEMOTRON_MODEL_RESOURCE}." >&2
    exit 1
  }

  gateway_host=$(oc get gateway maas-default-gateway -n openshift-ingress \
    -o jsonpath='{.spec.listeners[0].hostname}' --insecure-skip-tls-verify=true 2>/dev/null || true)
  [[ -n "$gateway_host" ]] || { echo "ERROR: MaaS Gateway hostname is missing." >&2; exit 1; }

  echo "[OK] Prerequisites ready: Llama Stack, MaaS Nemotron, and MaaS subscription"
}

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

gateway_host() {
  oc get gateway maas-default-gateway -n openshift-ingress \
    -o jsonpath='{.spec.listeners[0].hostname}' \
    --insecure-skip-tls-verify=true
}

get_demo_user_token() {
  local kubeconfig token

  if [[ -z "${AI_DEVELOPER_PASSWORD:-}" ]]; then
    echo "ERROR: AI_DEVELOPER_PASSWORD is required in .env to create a MaaS API key." >&2
    return 1
  fi

  kubeconfig=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-login.XXXXXX")
  TMP_FILES+=("$kubeconfig")

  oc login "$ACTUAL_SERVER" -u ai-developer -p "$AI_DEVELOPER_PASSWORD" \
    --kubeconfig "$kubeconfig" \
    --insecure-skip-tls-verify=true >/dev/null

  token=$(oc --kubeconfig "$kubeconfig" whoami -t \
    --insecure-skip-tls-verify=true 2>/dev/null || true)
  [[ -n "$token" ]] || return 1
  printf '%s' "$token"
}

existing_maas_api_key_id() {
  if ! oc get secret "$RAG_LS_SECRET" -n "$PROJECT_NS" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    return 0
  fi

  oc get secret "$RAG_LS_SECRET" -n "$PROJECT_NS" \
    -o jsonpath='{.data.MAAS_API_KEY_ID}' \
    --insecure-skip-tls-verify=true 2>/dev/null |
    base64 --decode 2>/dev/null || true
}

create_maas_api_key() {
  local token="$1"
  local host="$2"
  local body status key key_id

  body=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-api-key.XXXXXX")
  TMP_FILES+=("$body")

  status=$(curl -sk --max-time 30 -o "$body" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    "https://${host}/maas-api/v1/api-keys" \
    --data-binary "{\"name\":\"${RAG_API_KEY_NAME}\",\"subscriptionName\":\"${MAAS_SUBSCRIPTION}\"}" \
    2>/dev/null || true)

  key=$(jq -r '.key // empty' "$body" 2>/dev/null || true)
  key_id=$(jq -r '.id // empty' "$body" 2>/dev/null || true)

  if [[ "$status" != "201" || "$key" != sk-oai-* || -z "$key_id" ]]; then
    echo "ERROR: failed to create MaaS API key for Stage 230 (status=${status})." >&2
    head -c 240 "$body" >&2 || true
    echo >&2
    return 1
  fi

  printf '%s\n%s\n' "$key_id" "$key"
}

revoke_maas_api_key() {
  local token="$1"
  local host="$2"
  local key_id="$3"
  local status

  [[ -n "$key_id" ]] || return 0

  status=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' \
    -X DELETE \
    -H "Authorization: Bearer ${token}" \
    "https://${host}/maas-api/v1/api-keys/${key_id}" \
    2>/dev/null || true)

  if [[ "$status" == "200" || "$status" == "204" || "$status" == "404" ]]; then
    echo "[OK] Revoked stale MaaS API key ${key_id}"
    return 0
  fi

  echo "WARN: failed to revoke stale MaaS API key ${key_id} (status=${status})" >&2
}

cleanup_duplicate_maas_api_keys() {
  local token="$1"
  local host="$2"
  local keep_id="$3"
  local body status duplicate_ids key_id

  body=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-key-search.XXXXXX")
  TMP_FILES+=("$body")

  status=$(curl -sk --max-time 30 -o "$body" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    "https://${host}/maas-api/v1/api-keys/search" \
    --data-binary "{\"name\":\"${RAG_API_KEY_NAME}\"}" \
    2>/dev/null || true)

  [[ "$status" == "200" ]] || return 0

  duplicate_ids=$(jq -r --arg name "$RAG_API_KEY_NAME" --arg keep "$keep_id" '
    .data[]? |
    select(.name == $name and .status == "active" and .id != $keep) |
    .id
  ' "$body" 2>/dev/null || true)

  while IFS= read -r key_id; do
    [[ -n "$key_id" ]] || continue
    revoke_maas_api_key "$token" "$host" "$key_id" || true
  done <<<"$duplicate_ids"
}

ensure_runtime_secrets() {
  echo "-- Ensuring Stage 230 runtime Secrets --"

  local postgres_password encoded_password user_token host old_key_id key_material new_key_id new_key
  postgres_password=$(oc get secret "$RAG_POSTGRES_SECRET" -n "$PROJECT_NS" \
    -o jsonpath='{.data.POSTGRES_PASSWORD}' --insecure-skip-tls-verify=true 2>/dev/null \
    | base64 --decode 2>/dev/null || true)
  if [[ -z "$postgres_password" ]]; then
    postgres_password="${RHOAI_STAGE230_POSTGRES_PASSWORD:-$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32)}"
  fi

  oc create secret generic "$RAG_POSTGRES_SECRET" \
    -n "$PROJECT_NS" \
    --from-literal=POSTGRES_USER=rag \
    --from-literal=POSTGRES_PASSWORD="$postgres_password" \
    --from-literal=POSTGRES_DB=rag \
    --from-literal=PGVECTOR_HOST="private-rag-postgres.${PROJECT_NS}.svc.cluster.local" \
    --from-literal=PGVECTOR_PORT=5432 \
    --from-literal=PGVECTOR_DB=rag \
    --from-literal=PGVECTOR_USER=rag \
    --from-literal=PGVECTOR_PASSWORD="$postgres_password" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  host=$(gateway_host)
  old_key_id=$(existing_maas_api_key_id)
  user_token=$(get_demo_user_token)
  key_material=$(create_maas_api_key "$user_token" "$host")
  new_key_id=$(sed -n '1p' <<<"$key_material")
  new_key=$(sed -n '2p' <<<"$key_material")

  oc create secret generic "$RAG_LS_SECRET" \
    -n "$PROJECT_NS" \
    --from-literal=INFERENCE_MODEL="$NEMOTRON_MODEL_RESOURCE" \
    --from-literal=VLLM_URL="https://${host}/models-as-a-service/${NEMOTRON_MODEL_RESOURCE}/v1" \
    --from-literal=VLLM_TLS_VERIFY=false \
    --from-literal=VLLM_API_TOKEN="$new_key" \
    --from-literal=VLLM_MAX_TOKENS="$RAG_MAX_TOKENS" \
    --from-literal=EMBEDDING_MODEL="$RAG_EMBEDDING_MODEL" \
    --from-literal=EMBEDDING_PROVIDER_MODEL_ID="$RAG_EMBEDDING_MODEL" \
    --from-literal=MAAS_API_KEY_ID="$new_key_id" \
    --from-literal=MAAS_SUBSCRIPTION="$MAAS_SUBSCRIPTION" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  oc label secret "$RAG_POSTGRES_SECRET" "$RAG_LS_SECRET" -n "$PROJECT_NS" --overwrite \
    app.kubernetes.io/part-of=rhoai3-demo \
    demo.rhoai.io/stage=230 \
    --insecure-skip-tls-verify=true >/dev/null

  if [[ -n "$old_key_id" && "$old_key_id" != "$new_key_id" ]]; then
    revoke_maas_api_key "$user_token" "$host" "$old_key_id" || true
  fi
  cleanup_duplicate_maas_api_keys "$user_token" "$host" "$new_key_id"

  encoded_password=$(urlencode "$postgres_password")
  echo "[OK] Runtime secrets ready (pgvector URI password encoded length=${#encoded_password}, MaaS key id=${new_key_id})"
}

grant_pgvector_scc() {
  echo "-- Granting pgvector service account anyuid SCC --"
  oc adm policy add-scc-to-user anyuid -z private-rag-postgres -n "$PROJECT_NS" \
    --insecure-skip-tls-verify=true >/dev/null
  echo "[OK] anyuid SCC granted to ${PROJECT_NS}/private-rag-postgres"
}

apply_argocd_application() {
  local app_name="stage-230-private-data-rag"
  local manifest_path="$ROOT_DIR/gitops/argocd/app-of-apps/${app_name}.yaml"
  local app_manifest
  app_manifest=$(mktemp)
  TMP_FILES+=("$app_manifest")

  sed \
    -e "s|repoURL: .*|repoURL: ${GIT_REPO_URL}|" \
    -e "s|targetRevision: .*|targetRevision: ${GIT_REPO_BRANCH}|" \
    "$manifest_path" > "$app_manifest"

  oc apply -f "$app_manifest" --insecure-skip-tls-verify=true
  oc annotate applications.argoproj.io "$app_name" -n openshift-gitops \
    argocd.argoproj.io/refresh=hard --overwrite \
    --insecure-skip-tls-verify=true >/dev/null
  echo "[OK] Applied Argo CD Application ${app_name}"
}

wait_for_project_bootstrap() {
  echo "-- Waiting for Enterprise RAG project bootstrap --"

  local ns_phase source_obc_phase
  for _ in $(seq 1 90); do
    ns_phase=$(oc get namespace "$PROJECT_NS" \
      -o jsonpath='{.status.phase}' --insecure-skip-tls-verify=true 2>/dev/null || true)
    source_obc_phase=$(jsonpath "objectbucketclaim/${OBC_NAME}" "$PROJECT_NS" '{.status.phase}')
    if [[ "$ns_phase" == "Active" && "$source_obc_phase" == "Bound" ]]; then
      echo "[OK] ${PROJECT_NS} project is Active and ${OBC_NAME} is Bound"
      return 0
    fi
    sleep 10
  done

  echo "ERROR: Enterprise RAG project bootstrap did not complete." >&2
  echo "namespace=${ns_phase:-missing} source_obc=${source_obc_phase:-missing}" >&2
  oc get namespace "$PROJECT_NS" --insecure-skip-tls-verify=true >&2 || true
  oc get objectbucketclaim "$OBC_NAME" -n "$PROJECT_NS" \
    --insecure-skip-tls-verify=true >&2 || true
  return 1
}

ensure_project_s3_connection() {
  echo "-- Ensuring Enterprise RAG S3 dashboard connection --"

  local access_key secret_key bucket host port endpoint connection_file
  access_key=$(oc get secret "$OBC_NAME" -n "$PROJECT_NS" \
    -o go-template='{{.data.AWS_ACCESS_KEY_ID | base64decode}}' \
    --insecure-skip-tls-verify=true)
  secret_key=$(oc get secret "$OBC_NAME" -n "$PROJECT_NS" \
    -o go-template='{{.data.AWS_SECRET_ACCESS_KEY | base64decode}}' \
    --insecure-skip-tls-verify=true)
  bucket=$(jsonpath "configmap/${OBC_NAME}" "$PROJECT_NS" '{.data.BUCKET_NAME}')
  host=$(jsonpath "configmap/${OBC_NAME}" "$PROJECT_NS" '{.data.BUCKET_HOST}')
  port=$(jsonpath "configmap/${OBC_NAME}" "$PROJECT_NS" '{.data.BUCKET_PORT}')

  if [[ -z "$access_key" || -z "$secret_key" || -z "$bucket" || -z "$host" || -z "$port" ]]; then
    echo "ERROR: ${PROJECT_NS}/${OBC_NAME} is missing generated S3 connection data." >&2
    return 1
  fi

  endpoint="https://${host}:${port}"
  connection_file=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-s3-connection.XXXXXX")
  TMP_FILES+=("$connection_file")
  cat >"$connection_file" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${RAG_S3_CONNECTION_SECRET}
  namespace: ${PROJECT_NS}
  labels:
    opendatahub.io/dashboard: "true"
    app.kubernetes.io/part-of: rhoai3-demo
    demo.rhoai.io/stage: "230"
  annotations:
    opendatahub.io/connection-type-ref: s3
    openshift.io/display-name: "Enterprise RAG object storage"
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "${access_key}"
  AWS_SECRET_ACCESS_KEY: "${secret_key}"
  AWS_S3_ENDPOINT: "${endpoint}"
  AWS_S3_BUCKET: "${bucket}"
  AWS_DEFAULT_REGION: "us-east-1"
EOF
  oc apply -f "$connection_file" --insecure-skip-tls-verify=true >/dev/null
  echo "[OK] ${PROJECT_NS}/${RAG_S3_CONNECTION_SECRET} connection is ready"
}

wait_for_application() {
  local app_name="stage-230-private-data-rag"
  local sync health

  echo "-- Waiting for ${app_name} to become Synced --"
  for _ in $(seq 1 90); do
    sync=$(oc get applications.argoproj.io "$app_name" -n openshift-gitops \
      -o jsonpath='{.status.sync.status}' --insecure-skip-tls-verify=true 2>/dev/null || true)
    health=$(oc get applications.argoproj.io "$app_name" -n openshift-gitops \
      -o jsonpath='{.status.health.status}' --insecure-skip-tls-verify=true 2>/dev/null || true)
    if [[ "$sync" == "Synced" && ( "$health" == "Healthy" || "$health" == "Progressing" ) ]]; then
      echo "[OK] ${app_name}: ${sync}/${health}"
      return 0
    fi
    if [[ "$health" == "Degraded" ]]; then
      echo "ERROR: ${app_name} is Degraded." >&2
      oc get applications.argoproj.io "$app_name" -n openshift-gitops -o yaml \
        --insecure-skip-tls-verify=true | sed -n '/status:/,$p' >&2 || true
      return 1
    fi
    sleep 10
  done

  echo "ERROR: ${app_name} did not become Synced." >&2
  oc get applications.argoproj.io "$app_name" -n openshift-gitops -o yaml \
    --insecure-skip-tls-verify=true | sed -n '/status:/,$p' >&2 || true
  return 1
}

refresh_llamastack_runtime() {
  echo "-- Refreshing Llama Stack runtime after Secret updates --"

  if oc get deployment "$RAG_LSD_NAME" -n "$PROJECT_NS" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    oc rollout restart "deployment/${RAG_LSD_NAME}" -n "$PROJECT_NS" \
      --insecure-skip-tls-verify=true >/dev/null
  fi
}

wait_for_runtime() {
  echo "-- Waiting for private RAG runtime --"
  oc rollout status "statefulset/private-rag-postgres" -n "$PROJECT_NS" \
    --timeout=10m --insecure-skip-tls-verify=true
  oc rollout status "deployment/${RAG_DOCLING_DEPLOYMENT}" -n "$PROJECT_NS" \
    --timeout=15m --insecure-skip-tls-verify=true
  oc rollout status "deployment/${RAG_LSD_NAME}" -n "$PROJECT_NS" \
    --timeout=10m --insecure-skip-tls-verify=true
  oc rollout status "deployment/${RAG_CHATBOT_DEPLOYMENT}" -n "$PROJECT_NS" \
    --timeout=10m --insecure-skip-tls-verify=true
  echo "[OK] pgvector, Docling, Llama Stack, and Streamlit chatbot are ready"
}

wait_for_pipeline_server() {
  echo "-- Waiting for private RAG pipeline server --"

  local state crd_ready dspa_ready route_host dspa_obc_phase
  for _ in $(seq 1 90); do
    state=$(oc get datasciencecluster default-dsc -n redhat-ods-applications \
      -o jsonpath='{.spec.components.aipipelines.managementState}' \
      --insecure-skip-tls-verify=true 2>/dev/null || true)
    crd_ready=$(oc get crd datasciencepipelinesapplications.datasciencepipelinesapplications.opendatahub.io \
      --insecure-skip-tls-verify=true >/dev/null 2>&1 && echo yes || echo no)
    dspa_obc_phase=$(jsonpath "objectbucketclaim/${RAG_DSPA_OBC_NAME}" "$PROJECT_NS" '{.status.phase}')
    dspa_ready=$(jsonpath "dspa/${RAG_DSPA_NAME}" "$PROJECT_NS" '{.status.conditions[?(@.type=="Ready")].status}')
    route_host=$(jsonpath "route/ds-pipeline-${RAG_DSPA_NAME}" "$PROJECT_NS" '{.spec.host}')

    if [[ "$state" == "Managed" && "$crd_ready" == "yes" && "$dspa_obc_phase" == "Bound" && "$dspa_ready" == "True" && -n "$route_host" ]]; then
      echo "[OK] DSPA ${PROJECT_NS}/${RAG_DSPA_NAME} is Ready (${route_host})"
      return 0
    fi
    sleep 10
  done

  echo "ERROR: private RAG DSPA did not become ready." >&2
  echo "aipipelines=${state:-missing} crd=${crd_ready:-missing} dspa_obc=${dspa_obc_phase:-missing} dspa_ready=${dspa_ready:-missing} route=${route_host:-missing}" >&2
  oc get dspa "$RAG_DSPA_NAME" -n "$PROJECT_NS" -o yaml \
    --insecure-skip-tls-verify=true | sed -n '/status:/,$p' >&2 || true
  return 1
}

ensure_document_configmap() {
  echo "-- Publishing whoami source documents into a project ConfigMap --"
  oc create configmap "$RAG_DOC_CONFIGMAP" -n "$PROJECT_NS" \
    --from-file="$SCRIPT_DIR/documents" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null
  oc label configmap "$RAG_DOC_CONFIGMAP" -n "$PROJECT_NS" --overwrite \
    app.kubernetes.io/name="$RAG_DOC_CONFIGMAP" \
    app.kubernetes.io/component=private-rag-documents \
    app.kubernetes.io/part-of=rhoai3-demo \
    demo.rhoai.io/stage=230 \
    --insecure-skip-tls-verify=true >/dev/null
  echo "[OK] ${PROJECT_NS}/${RAG_DOC_CONFIGMAP} contains the whoami source corpus"
}

seed_object_bucket() {
  echo "-- Uploading whoami source documents to the Enterprise RAG S3 bucket --"

  local job_file
  job_file=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-s3-job.XXXXXX.yaml")
  TMP_FILES+=("$job_file")

  cat >"$job_file" <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: private-rag-s3-seed
  namespace: ${PROJECT_NS}
  labels:
    app.kubernetes.io/name: private-rag-s3-seed
    app.kubernetes.io/component: private-rag-documents
    app.kubernetes.io/part-of: rhoai3-demo
    demo.rhoai.io/stage: "230"
    kueue.x-k8s.io/queue-name: default
spec:
  backoffLimit: 1
  activeDeadlineSeconds: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: private-rag-s3-seed
        kueue.x-k8s.io/queue-name: default
    spec:
      restartPolicy: Never
      containers:
        - name: s3-upload
          image: registry.redhat.io/rhai/base-image-cpu-rhel9:3.4.0
          imagePullPolicy: IfNotPresent
          envFrom:
            - configMapRef:
                name: ${OBC_NAME}
            - secretRef:
                name: ${OBC_NAME}
          command:
            - /bin/bash
            - -c
            - |
              set -euo pipefail
              python3 - <<'PY'
              import os
              import pathlib
              import subprocess
              import sys

              try:
                  import boto3
                  from botocore.client import Config
              except ImportError:
                  target = "/tmp/boto3"
                  subprocess.check_call([
                      sys.executable,
                      "-m",
                      "pip",
                      "install",
                      "--target",
                      target,
                      "boto3>=1.34.0",
                  ])
                  sys.path.insert(0, target)
                  import boto3
                  from botocore.client import Config

              endpoint = f"https://{os.environ['BUCKET_HOST']}:{os.environ['BUCKET_PORT']}"
              bucket = os.environ["BUCKET_NAME"]
              prefix = "private-rag/whoami/"
              root = pathlib.Path("/documents")

              s3 = boto3.client(
                  "s3",
                  endpoint_url=endpoint,
                  aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
                  aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
                  config=Config(signature_version="s3v4"),
                  verify=False,
              )

              uploaded = 0
              for path in sorted(p for p in root.iterdir() if p.is_file()):
                  key = prefix + path.name
                  s3.upload_file(str(path), bucket, key)
                  print(f"uploaded s3://{bucket}/{key}")
                  uploaded += 1

              if uploaded == 0:
                  raise SystemExit("no source documents found under /documents")

              response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
              for item in response.get("Contents", []):
                  print(f"object {item['Key']} {item['Size']} bytes")
              PY
          volumeMounts:
            - name: documents
              mountPath: /documents
              readOnly: true
      volumes:
        - name: documents
          configMap:
            name: ${RAG_DOC_CONFIGMAP}
EOF

  oc delete job private-rag-s3-seed -n "$PROJECT_NS" \
    --ignore-not-found=true --wait=true --insecure-skip-tls-verify=true >/dev/null
  oc apply -f "$job_file" --insecure-skip-tls-verify=true >/dev/null

  if ! oc wait --for=condition=complete "job/private-rag-s3-seed" -n "$PROJECT_NS" \
    --timeout=10m --insecure-skip-tls-verify=true >/dev/null; then
    oc logs "job/private-rag-s3-seed" -n "$PROJECT_NS" \
      --insecure-skip-tls-verify=true >&2 || true
    echo "ERROR: private document S3 upload failed." >&2
    return 1
  fi

  oc logs "job/private-rag-s3-seed" -n "$PROJECT_NS" \
    --insecure-skip-tls-verify=true | tail -n 10
  echo "[OK] Whoami documents uploaded to object storage prefix private-rag/whoami/"
}

start_docling_port_forward() {
  echo "-- Opening local port-forward to Docling --"

  oc port-forward "svc/${RAG_DOCLING_SERVICE}" -n "$PROJECT_NS" \
    "${RAG_DOCLING_LOCAL_PORT}:5001" \
    --insecure-skip-tls-verify=true >/tmp/rhoai-stage230-docling-port-forward.log 2>&1 &
  BG_PIDS+=("$!")

  for _ in $(seq 1 60); do
    if curl -sf --max-time 2 "http://127.0.0.1:${RAG_DOCLING_LOCAL_PORT}/health" >/dev/null 2>&1; then
      echo "[OK] Docling is reachable on localhost:${RAG_DOCLING_LOCAL_PORT}"
      return 0
    fi
    sleep 2
  done

  echo "ERROR: Docling port-forward did not become ready." >&2
  tail -n 20 /tmp/rhoai-stage230-docling-port-forward.log >&2 || true
  return 1
}

convert_pdfs_with_docling() {
  local output_dir="$1"
  local pdf response_file out_file status chars base

  shopt -s nullglob
  for pdf in "$SCRIPT_DIR"/documents/*.pdf; do
    base="$(basename "$pdf" .pdf)"
    response_file=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-docling.XXXXXX.json")
    TMP_FILES+=("$response_file")
    out_file="${output_dir}/${base}.md"

    echo "   Docling converting $(basename "$pdf")"
    status=$(curl -sS --max-time "$RAG_DOCLING_TIMEOUT" -o "$response_file" \
      -w '%{http_code}' \
      -F "files=@${pdf};type=application/pdf" \
      -F "to_formats=md" \
      -F "image_export_mode=placeholder" \
      "http://127.0.0.1:${RAG_DOCLING_LOCAL_PORT}/v1/convert/file" \
      2>/dev/null || true)

    if [[ "$status" != 2* ]]; then
      echo "ERROR: Docling conversion failed for ${pdf} (status=${status})." >&2
      head -c 500 "$response_file" >&2 || true
      echo >&2
      return 1
    fi

    jq -r '.document.md_content // .document.md // .document.text_content // empty' \
      "$response_file" > "$out_file"
    chars=$(wc -c < "$out_file" | tr -d ' ')
    if [[ "$chars" == "0" ]]; then
      echo "ERROR: Docling returned no Markdown for ${pdf}." >&2
      head -c 500 "$response_file" >&2 || true
      echo >&2
      return 1
    fi
    echo "   [OK] ${pdf} -> ${out_file} (${chars} bytes)"
  done
  shopt -u nullglob
}

build_docs_payload() {
  local converted_dir="$1"
  python3 - "$SCRIPT_DIR/documents" "$converted_dir" <<'PY'
import json
import pathlib
import sys

roots = [pathlib.Path(arg) for arg in sys.argv[1:]]
docs = []
for root in roots:
    if not root.exists():
        continue
    for path in sorted(root.glob("*.md")):
        docs.append({
            "document_id": path.stem,
            "content": path.read_text(),
            "mime_type": "text/plain",
            "metadata": {
                "source": path.name,
                "stage": "230",
                "scenario": "whoami",
            },
        })

if not docs:
    raise SystemExit("No Markdown documents were prepared for ingestion")

print(json.dumps(docs))
PY
}

ingest_documents() {
  echo "-- Converting whoami documents with Docling and ingesting into Llama Stack --"

  local converted_dir docs_payload docs_b64
  converted_dir=$(mktemp -d "${TMPDIR:-/tmp}/rhoai-stage230-docs.XXXXXX")
  TMP_DIRS+=("$converted_dir")

  start_docling_port_forward
  convert_pdfs_with_docling "$converted_dir"

  docs_payload=$(build_docs_payload "$converted_dir")
  docs_b64=$(printf '%s' "$docs_payload" | base64 | tr -d '\n')

  for attempt in $(seq 1 12); do
    if oc exec -i "deployment/${RAG_LSD_NAME}" -n "$PROJECT_NS" \
      --insecure-skip-tls-verify=true \
      -- env \
        RAG_DOCS_B64="$docs_b64" \
        RAG_VECTOR_DB="$RAG_VECTOR_DB" \
        RAG_EMBEDDING_MODEL="$RAG_EMBEDDING_MODEL" \
        RAG_EMBEDDING_DIMENSION="$RAG_EMBEDDING_DIMENSION" \
        RAG_CHUNK_SIZE="$RAG_CHUNK_SIZE" \
        RAG_INFERENCE_MODEL="$RAG_INFERENCE_MODEL" \
        python3 - <<'PY'
import base64
import json
import os
import sys
import time
from llama_stack_client import LlamaStackClient

client = LlamaStackClient(base_url="http://127.0.0.1:8321")
vector_store_name = os.environ["RAG_VECTOR_DB"]
embedding_model = os.environ["RAG_EMBEDDING_MODEL"]
embedding_dimension = int(os.environ["RAG_EMBEDDING_DIMENSION"])
chunk_size = int(os.environ["RAG_CHUNK_SIZE"])
preferred_model = os.environ["RAG_INFERENCE_MODEL"]
documents = json.loads(base64.b64decode(os.environ["RAG_DOCS_B64"]).decode())

def ident(obj):
    return getattr(obj, "identifier", None) or getattr(obj, "id", None) or getattr(obj, "provider_id", None)

providers = list(client.providers.list())
provider_id = None
for provider in providers:
    if getattr(provider, "api", None) == "vector_io" and "pgvector" in (getattr(provider, "provider_id", "") or ""):
        provider_id = provider.provider_id
        break
if provider_id is None:
    for provider in providers:
        if getattr(provider, "api", None) == "vector_io":
            provider_id = provider.provider_id
            break
if provider_id is None:
    raise SystemExit("No vector_io provider is registered in Llama Stack")

try:
    for store in client.vector_stores.list():
        store_id = getattr(store, "id", None)
        store_name = getattr(store, "name", None)
        if store_id == vector_store_name or store_name == vector_store_name:
            client.vector_stores.delete(vector_store_id=store_id)
except Exception as exc:
    print(f"WARN: vector store cleanup skipped: {exc}", file=sys.stderr)

vector_store = client.vector_stores.create(
    name=vector_store_name,
    metadata={
        "stage": "230",
        "scenario": "whoami",
        "embedding_model": embedding_model,
        "embedding_dimension": str(embedding_dimension),
        "vector_provider": provider_id,
        "chunk_size_tokens": str(chunk_size),
    },
)
vector_store_id = getattr(vector_store, "id", None)
if not vector_store_id:
    raise SystemExit(f"Vector store {vector_store_name} did not return an id")

for doc in documents:
    source_name = doc["metadata"]["source"]
    uploaded_file = client.files.create(
        file=(source_name, doc["content"].encode("utf-8"), doc["mime_type"]),
        purpose="assistants",
    )
    file_id = getattr(uploaded_file, "id", None)
    if not file_id:
        raise SystemExit(f"Llama Stack file upload did not return an id for {source_name}")
    store_file = client.vector_stores.files.create(
        vector_store_id=vector_store_id,
        file_id=file_id,
        attributes={
            "source": source_name,
            "stage": "230",
            "scenario": "whoami",
            "chunk_size_tokens": str(chunk_size),
        },
    )
    status = getattr(store_file, "status", "")
    for _ in range(60):
        if status in ("completed", "failed", "cancelled"):
            break
        time.sleep(2)
        store_file = client.vector_stores.files.retrieve(
            vector_store_id=vector_store_id,
            file_id=file_id,
        )
        status = getattr(store_file, "status", "")
    if status and status != "completed":
        raise SystemExit(f"Vector store file {file_id} ended with status {status}")

query = "Who is Adnan Drina and what is his current role?"
rag_response = client.vector_stores.search(
    vector_store_id=vector_store_id,
    query=query,
    max_num_results=5,
)
context = str(getattr(rag_response, "content", rag_response))
if not any(term in context.lower() for term in ["adnan", "red hat", "principal", "solution architect"]):
    raise SystemExit(f"RAG query returned unexpected context: {context[:500]}")

model_ids = []
try:
    for model in client.models.list():
        model_id = ident(model)
        if model_id:
            model_ids.append(model_id)
except Exception as exc:
    print(f"WARN: could not list models: {exc}", file=sys.stderr)

model_id = preferred_model
if model_ids and model_id not in model_ids:
    model_id = next((mid for mid in model_ids if preferred_model in mid or "nemotron" in mid.lower()), model_ids[0])

completion = client.chat.completions.create(
    model=model_id,
    messages=[
        {"role": "system", "content": "Answer only from the provided context. Be concise."},
        {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {query}"},
    ],
    temperature=0.1,
)
answer = completion.choices[0].message.content
if not answer:
    raise SystemExit("Nemotron returned an empty answer")

print(f"RAG_VECTOR_DB={vector_store_name}")
print(f"RAG_VECTOR_STORE_ID={vector_store_id}")
print(f"RAG_PROVIDER={provider_id}")
print(f"RAG_MODEL={model_id}")
print(f"RAG_ANSWER={answer[:400]}")
print("RAG_VALIDATION_OK")
PY
    then
      echo "[OK] Llama Stack vector database seeded and validated"
      return 0
    fi

    echo "WARN: ingestion attempt ${attempt} failed; retrying after Llama Stack settles..." >&2
    sleep 20
  done

  echo "ERROR: Llama Stack document ingestion failed." >&2
  return 1
}

run_pipeline_ingestion() {
  echo "-- Running whoami ingestion through DSPA/KFP --"

  if "$SCRIPT_DIR/run-whoami-ingestion-pipeline.sh" --wait; then
    echo "[OK] DSPA/KFP whoami ingestion completed"
    return 0
  fi

  if [[ "${RHOAI_STAGE230_ALLOW_DIRECT_INGEST_FALLBACK:-false}" == "true" ]]; then
    echo "WARN: DSPA ingestion failed; falling back to direct Llama Stack ingestion because RHOAI_STAGE230_ALLOW_DIRECT_INGEST_FALLBACK=true" >&2
    ingest_documents
    oc create configmap "$RAG_PIPELINE_LAST_RUN_CONFIGMAP" -n "$PROJECT_NS" \
      --from-literal=run_id=direct-fallback \
      --from-literal=run_name=direct-fallback \
      --from-literal=status=DIRECT_FALLBACK \
      --from-literal=vector_db="$RAG_VECTOR_DB" \
      --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null
    return 0
  fi

  echo "ERROR: DSPA/KFP whoami ingestion failed. Set RHOAI_STAGE230_ALLOW_DIRECT_INGEST_FALLBACK=true only for break-glass recovery." >&2
  return 1
}

ensure_prerequisites
apply_argocd_application
wait_for_project_bootstrap
ensure_runtime_secrets
ensure_project_s3_connection
grant_pgvector_scc
wait_for_application
refresh_llamastack_runtime
wait_for_runtime
wait_for_pipeline_server
ensure_document_configmap
seed_object_bucket
run_pipeline_ingestion

echo "Stage 230 deploy complete."
