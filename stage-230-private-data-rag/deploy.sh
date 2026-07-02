#!/usr/bin/env bash
# deploy.sh - Stage 230: Private Data RAG
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

echo "✓ Cluster guard passed: $ACTUAL_SERVER"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd jq
require_cmd oc
require_cmd openssl
require_cmd python3

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"
RAG_NS="${RHOAI_STAGE230_NAMESPACE:-enterprise-rag}"
RAG_BUCKET_OBC="${RHOAI_STAGE230_BUCKET_OBC:-enterprise-rag-bucket}"
RAG_S3_CONNECTION_SECRET="${RHOAI_STAGE230_S3_CONNECTION_SECRET:-enterprise-rag-s3}"
PIPELINE_S3_SECRET="${RHOAI_STAGE230_PIPELINE_S3_SECRET:-data-processing-docling-pipeline}"
SOURCE_UPLOAD_JOB="${RHOAI_STAGE230_SOURCE_UPLOAD_JOB:-stage230-source-upload}"
RAG_PRODUCT_DOCS_PREFIX="${RHOAI_STAGE230_PRODUCT_DOCS_PREFIX:-raw/rhoai-product-docs}"
CHATBOT_BUILD="${RHOAI_STAGE230_CHATBOT_BUILD:-private-rag-chatbot}"
CHATBOT_DEPLOYMENT="${RHOAI_STAGE230_CHATBOT_DEPLOYMENT:-private-rag-chatbot}"
POSTGRES_SECRET="${RHOAI_STAGE230_POSTGRES_SECRET:-private-rag-postgres-credentials}"
POSTGRES_USER="${RHOAI_STAGE230_POSTGRES_USER:-rag}"
POSTGRES_DB="${RHOAI_STAGE230_POSTGRES_DATABASE:-llamastack}"
LLAMA_SECRET="${RHOAI_STAGE230_LLAMA_STACK_SECRET:-private-rag-llama-stack-secret}"
NEMOTRON_MODEL_RESOURCE="${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}"
MAAS_NS="${RHOAI_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_SUBSCRIPTION="${RHOAI_STAGE230_MAAS_SUBSCRIPTION:-${RHOAI_OPENAI_ACCESS_RESOURCE:-rhoai-developers-gpt-4o-mini}}"
MAAS_API_KEY_NAME="${RHOAI_STAGE230_MAAS_API_KEY_NAME:-stage230-rag-runtime}"
VLLM_MAX_TOKENS="${RHOAI_STAGE230_VLLM_MAX_TOKENS:-1024}"
VLLM_TLS_VERIFY="${RHOAI_STAGE230_VLLM_TLS_VERIFY:-false}"
INFERENCE_MODEL="${RHOAI_STAGE230_INFERENCE_MODEL:-$NEMOTRON_MODEL_RESOURCE}"

TMP_FILES=()
cleanup() {
  if ((${#TMP_FILES[@]} > 0)); then
    rm -f "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

apply_argocd_application() {
  local app_manifest
  app_manifest=$(mktemp)
  TMP_FILES+=("$app_manifest")

  sed \
    -e "s|repoURL: .*|repoURL: ${GIT_REPO_URL}|" \
    -e "s|targetRevision: .*|targetRevision: ${GIT_REPO_BRANCH}|" \
    "$ROOT_DIR/gitops/argocd/app-of-apps/stage-230-private-data-rag.yaml" > "$app_manifest"

  oc apply -f "$app_manifest" --insecure-skip-tls-verify=true
  oc annotate applications.argoproj.io stage-230-private-data-rag -n openshift-gitops \
    argocd.argoproj.io/refresh=hard --overwrite \
    --insecure-skip-tls-verify=true >/dev/null
}

wait_for_namespace() {
  for _ in $(seq 1 30); do
    if oc get namespace "$RAG_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  echo "ERROR: namespace ${RAG_NS} was not created by Argo CD." >&2
  exit 1
}

wait_for_object_bucket() {
  echo "   Waiting for ObjectBucketClaim ${RAG_BUCKET_OBC} to bind …"
  local phase
  for _ in $(seq 1 60); do
    phase=$(oc get obc "$RAG_BUCKET_OBC" -n "$RAG_NS" -o jsonpath='{.status.phase}' \
      --insecure-skip-tls-verify=true 2>/dev/null || true)
    [[ "$phase" == "Bound" ]] && return 0
    sleep 5
  done
  echo "ERROR: ObjectBucketClaim ${RAG_BUCKET_OBC} is not Bound (phase=${phase:-missing})." >&2
  exit 1
}

jsonpath() {
  local resource="$1"
  local namespace="$2"
  local path="$3"
  oc get "$resource" -n "$namespace" -o jsonpath="$path" \
    --insecure-skip-tls-verify=true 2>/dev/null || true
}

ensure_object_storage() {
  local akid sak bucket host port endpoint pipeline_endpoint

  wait_for_object_bucket

  akid=$(oc get secret "$RAG_BUCKET_OBC" -n "$RAG_NS" \
    -o go-template='{{.data.AWS_ACCESS_KEY_ID | base64decode}}' \
    --insecure-skip-tls-verify=true)
  sak=$(oc get secret "$RAG_BUCKET_OBC" -n "$RAG_NS" \
    -o go-template='{{.data.AWS_SECRET_ACCESS_KEY | base64decode}}' \
    --insecure-skip-tls-verify=true)
  bucket=$(oc get configmap "$RAG_BUCKET_OBC" -n "$RAG_NS" \
    -o jsonpath='{.data.BUCKET_NAME}' --insecure-skip-tls-verify=true)
  host=$(oc get configmap "$RAG_BUCKET_OBC" -n "$RAG_NS" \
    -o jsonpath='{.data.BUCKET_HOST}' --insecure-skip-tls-verify=true)
  port=$(oc get configmap "$RAG_BUCKET_OBC" -n "$RAG_NS" \
    -o jsonpath='{.data.BUCKET_PORT}' --insecure-skip-tls-verify=true)
  endpoint="https://${host}:${port}"
  pipeline_endpoint="http://${host}:80"

  oc apply -f - --insecure-skip-tls-verify=true <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${RAG_S3_CONNECTION_SECRET}
  namespace: ${RAG_NS}
  labels:
    opendatahub.io/dashboard: "true"
    app.kubernetes.io/part-of: rag
    demo.rhoai.io/stage: "230"
  annotations:
    opendatahub.io/connection-type-ref: s3
    openshift.io/display-name: "enterprise-rag object storage"
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "${akid}"
  AWS_SECRET_ACCESS_KEY: "${sak}"
  AWS_S3_ENDPOINT: "${endpoint}"
  AWS_S3_BUCKET: "${bucket}"
  AWS_DEFAULT_REGION: "us-east-1"
  S3_ENDPOINT_URL: "${endpoint}"
  S3_ACCESS_KEY: "${akid}"
  S3_SECRET_KEY: "${sak}"
  S3_BUCKET: "${bucket}"
  S3_PREFIX: "${RAG_PRODUCT_DOCS_PREFIX}"
  RHOAI_STAGE230_PRODUCT_DOCS_PREFIX: "${RAG_PRODUCT_DOCS_PREFIX}"
EOF

  oc apply -f - --insecure-skip-tls-verify=true <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${PIPELINE_S3_SECRET}
  namespace: ${RAG_NS}
  labels:
    app.kubernetes.io/part-of: rag
    demo.rhoai.io/stage: "230"
type: Opaque
stringData:
  S3_ENDPOINT_URL: "${pipeline_endpoint}"
  S3_ACCESS_KEY: "${akid}"
  S3_SECRET_KEY: "${sak}"
  S3_BUCKET: "${bucket}"
  S3_PREFIX: "${RAG_PRODUCT_DOCS_PREFIX}"
  AWS_ACCESS_KEY_ID: "${akid}"
  AWS_SECRET_ACCESS_KEY: "${sak}"
  AWS_S3_ENDPOINT: "${pipeline_endpoint}"
  AWS_S3_BUCKET: "${bucket}"
  AWS_DEFAULT_REGION: "us-east-1"
  RHOAI_STAGE230_PRODUCT_DOCS_PREFIX: "${RAG_PRODUCT_DOCS_PREFIX}"
EOF

  oc delete job "$SOURCE_UPLOAD_JOB" -n "$RAG_NS" --ignore-not-found \
    --insecure-skip-tls-verify=true >/dev/null
  for _ in $(seq 1 30); do
    if ! oc get job "$SOURCE_UPLOAD_JOB" -n "$RAG_NS" \
      --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  oc apply -f - --insecure-skip-tls-verify=true <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${SOURCE_UPLOAD_JOB}
  namespace: ${RAG_NS}
  labels:
    app.kubernetes.io/part-of: rag
    demo.rhoai.io/stage: "230"
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: upload
          image: image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/s2i-generic-data-science-notebook:3.4
          imagePullPolicy: Always
          command:
            - /bin/bash
            - -ec
          args:
            - |
              python - <<'PY'
              import os
              import shutil
              import subprocess
              from pathlib import Path

              import boto3
              from botocore.config import Config
              from urllib3 import disable_warnings
              from urllib3.exceptions import InsecureRequestWarning

              disable_warnings(InsecureRequestWarning)

              repo = Path("/tmp/rhoai3-demo")
              if repo.exists():
                  shutil.rmtree(repo)
              subprocess.run(
                  [
                      "git",
                      "clone",
                      "--depth",
                      "1",
                      "--filter=blob:none",
                      "--sparse",
                      "--single-branch",
                      "--branch",
                      os.environ["GIT_REPO_BRANCH"],
                      os.environ["GIT_REPO_URL"],
                      str(repo),
                  ],
                  check=True,
              )
              subprocess.run(
                  [
                      "git",
                      "-C",
                      str(repo),
                      "sparse-checkout",
                      "set",
                      "stage-230-private-data-rag/data/rhoai-product-docs/source",
                  ],
                  check=True,
              )

              stage_dir = repo / "stage-230-private-data-rag"
              bucket = os.environ["AWS_S3_BUCKET"]
              client = boto3.client(
                  "s3",
                  endpoint_url=os.environ["AWS_S3_ENDPOINT"],
                  aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
                  aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
                  region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
                  verify=False,
                  config=Config(signature_version="s3v4"),
              )

              uploads = [
                  (
                      stage_dir / "data/rhoai-product-docs/source",
                      os.environ["RHOAI_STAGE230_PRODUCT_DOCS_PREFIX"],
                  ),
              ]
              uploaded = 0
              for source_dir, prefix in uploads:
                  if not source_dir.exists():
                      continue
                  for path in sorted(source_dir.glob("*.pdf")):
                      key = f"{prefix.rstrip('/')}/{path.name}"
                      client.upload_file(str(path), bucket, key)
                      client.head_object(Bucket=bucket, Key=key)
                      uploaded += 1
                      print(f"uploaded s3://{bucket}/{key}", flush=True)
              if uploaded == 0:
                  raise SystemExit("no source PDFs found to upload from checked-out stage data")
              print(f"uploaded {uploaded} source PDFs", flush=True)
              PY
          env:
            - name: GIT_REPO_URL
              value: "${GIT_REPO_URL}"
            - name: GIT_REPO_BRANCH
              value: "${GIT_REPO_BRANCH}"
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: ${RAG_S3_CONNECTION_SECRET}
                  key: AWS_ACCESS_KEY_ID
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: ${RAG_S3_CONNECTION_SECRET}
                  key: AWS_SECRET_ACCESS_KEY
            - name: AWS_S3_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: ${RAG_S3_CONNECTION_SECRET}
                  key: AWS_S3_ENDPOINT
            - name: AWS_S3_BUCKET
              valueFrom:
                secretKeyRef:
                  name: ${RAG_S3_CONNECTION_SECRET}
                  key: AWS_S3_BUCKET
            - name: AWS_DEFAULT_REGION
              valueFrom:
                secretKeyRef:
                  name: ${RAG_S3_CONNECTION_SECRET}
                  key: AWS_DEFAULT_REGION
            - name: RHOAI_STAGE230_PRODUCT_DOCS_PREFIX
              valueFrom:
                secretKeyRef:
                  name: ${RAG_S3_CONNECTION_SECRET}
                  key: RHOAI_STAGE230_PRODUCT_DOCS_PREFIX
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 2Gi
EOF

  if ! oc wait -n "$RAG_NS" --for=condition=complete "job/${SOURCE_UPLOAD_JOB}" \
    --timeout=10m --insecure-skip-tls-verify=true >/dev/null; then
    oc logs -n "$RAG_NS" "job/${SOURCE_UPLOAD_JOB}" --insecure-skip-tls-verify=true >&2 || true
    echo "ERROR: source PDF upload Job did not complete." >&2
    exit 1
  fi
  oc logs -n "$RAG_NS" "job/${SOURCE_UPLOAD_JOB}" --insecure-skip-tls-verify=true || true

  echo "✓ Stage 230 object storage is ready and source PDFs are uploaded to bucket ${bucket}"
}

get_maas_endpoint() {
  local endpoint
  endpoint=$(jsonpath "maasmodelrefs.maas.opendatahub.io/${NEMOTRON_MODEL_RESOURCE}" "$MAAS_NS" "{.status.endpoint}")
  if [[ -z "$endpoint" ]]; then
    echo "ERROR: MaaS endpoint for ${NEMOTRON_MODEL_RESOURCE} is not ready in ${MAAS_NS}. Deploy and validate Stage 220 first." >&2
    exit 1
  fi
  printf '%s' "$endpoint"
}

get_demo_user_token() {
  local user="$1"
  local password="$2"
  local kubeconfig token

  [[ -n "$password" ]] || return 1
  kubeconfig=$(mktemp "${TMPDIR:-/tmp}/rhoai-stage230-login.XXXXXX")
  TMP_FILES+=("$kubeconfig")

  oc login "$ACTUAL_SERVER" -u "$user" -p "$password" \
    --kubeconfig "$kubeconfig" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1 || return 1
  token=$(oc --kubeconfig "$kubeconfig" whoami -t \
    --insecure-skip-tls-verify=true 2>/dev/null || true)
  [[ -n "$token" ]] || return 1
  printf '%s' "$token"
}

get_gateway_host_from_endpoint() {
  ENDPOINT="$1" python3 - <<'PY'
import os
from urllib.parse import urlparse

print(urlparse(os.environ["ENDPOINT"]).netloc)
PY
}

normalize_openai_base_url() {
  ENDPOINT="$1" python3 - <<'PY'
import os

endpoint = os.environ["ENDPOINT"].rstrip("/")
if not endpoint.endswith("/v1"):
    endpoint = f"{endpoint}/v1"
print(endpoint)
PY
}

ensure_maas_api_key() {
  local endpoint gateway_host user_token api_key_body status api_key api_key_id existing

  existing=$(jsonpath "secret/${LLAMA_SECRET}" "$RAG_NS" "{.data.VLLM_API_TOKEN}" | base64 --decode 2>/dev/null || true)
  if [[ -n "$existing" && "$existing" == sk-oai-* ]]; then
    printf '%s' "$existing"
    return 0
  fi

  if [[ -n "${RHOAI_STAGE230_MAAS_API_KEY:-}" ]]; then
    printf '%s' "$RHOAI_STAGE230_MAAS_API_KEY"
    return 0
  fi

  user_token=$(get_demo_user_token "ai-developer" "${AI_DEVELOPER_PASSWORD:-}" || true)
  if [[ -z "$user_token" ]]; then
    echo "ERROR: Set RHOAI_STAGE230_MAAS_API_KEY or AI_DEVELOPER_PASSWORD so deploy.sh can create a MaaS API key." >&2
    exit 1
  fi

  endpoint=$(get_maas_endpoint)
  gateway_host=$(get_gateway_host_from_endpoint "$endpoint")
  api_key_body=$(mktemp)
  TMP_FILES+=("$api_key_body")

  status=$(curl -sk --max-time 30 -o "$api_key_body" -w '%{http_code}' \
    -H "Authorization: Bearer ${user_token}" \
    -H "Content-Type: application/json" \
    "https://${gateway_host}/maas-api/v1/api-keys" \
    --data-binary "{\"name\":\"${MAAS_API_KEY_NAME}\",\"subscriptionName\":\"${MAAS_SUBSCRIPTION}\"}" \
    2>/dev/null || true)

  api_key=$(jq -r '.key // empty' "$api_key_body")
  api_key_id=$(jq -r '.id // empty' "$api_key_body")
  if [[ "$status" != "201" || "$api_key" != sk-oai-* ]]; then
    echo "ERROR: failed to create MaaS API key (status=${status}, body=$(head -c 200 "$api_key_body" | tr '\n' ' '))." >&2
    exit 1
  fi

  oc annotate namespace "$RAG_NS" "demo.rhoai.io/stage230-maas-api-key-id=${api_key_id}" \
    --overwrite --insecure-skip-tls-verify=true >/dev/null
  printf '%s' "$api_key"
}

ensure_runtime_secrets() {
  local postgres_password maas_endpoint maas_token

  postgres_password=$(jsonpath "secret/${POSTGRES_SECRET}" "$RAG_NS" "{.data.POSTGRESQL_PASSWORD}" | base64 --decode 2>/dev/null || true)
  if [[ -z "$postgres_password" ]]; then
    postgres_password="${RHOAI_STAGE230_POSTGRES_PASSWORD:-$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32)}"
  fi

  oc create secret generic "$POSTGRES_SECRET" \
    -n "$RAG_NS" \
    --from-literal=POSTGRESQL_USER="$POSTGRES_USER" \
    --from-literal=POSTGRESQL_PASSWORD="$postgres_password" \
    --from-literal=POSTGRESQL_DATABASE="$POSTGRES_DB" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  maas_endpoint="$(normalize_openai_base_url "${RHOAI_STAGE230_VLLM_URL:-$(get_maas_endpoint)}")"
  maas_token="$(ensure_maas_api_key)"

  oc create secret generic "$LLAMA_SECRET" \
    -n "$RAG_NS" \
    --from-literal=INFERENCE_MODEL="$INFERENCE_MODEL" \
    --from-literal=VLLM_URL="$maas_endpoint" \
    --from-literal=VLLM_API_TOKEN="$maas_token" \
    --from-literal=VLLM_TLS_VERIFY="$VLLM_TLS_VERIFY" \
    --from-literal=VLLM_MAX_TOKENS="$VLLM_MAX_TOKENS" \
    --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null

  oc label secret "$POSTGRES_SECRET" "$LLAMA_SECRET" -n "$RAG_NS" --overwrite \
    app.kubernetes.io/part-of=rag \
    demo.rhoai.io/stage=230 \
    --insecure-skip-tls-verify=true >/dev/null
  echo "✓ Stage 230 runtime Secrets are present in ${RAG_NS}"
}

ensure_chatbot_build() {
  if [[ ! -f "$SCRIPT_DIR/chatbot/Containerfile" ]]; then
    echo "ERROR: Stage 230 chatbot source is missing: ${SCRIPT_DIR}/chatbot/Containerfile" >&2
    exit 1
  fi

  echo "   Waiting for chatbot BuildConfig ${CHATBOT_BUILD} …"
  for _ in $(seq 1 60); do
    if oc get buildconfig "$CHATBOT_BUILD" -n "$RAG_NS" \
      --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done
  if ! oc get buildconfig "$CHATBOT_BUILD" -n "$RAG_NS" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "ERROR: chatbot BuildConfig ${CHATBOT_BUILD} was not created by Argo CD." >&2
    exit 1
  fi

  oc start-build "$CHATBOT_BUILD" -n "$RAG_NS" \
    --from-dir="$SCRIPT_DIR/chatbot" \
    --wait \
    --follow \
    --insecure-skip-tls-verify=true

  echo "   Waiting for chatbot Deployment ${CHATBOT_DEPLOYMENT} …"
  for _ in $(seq 1 60); do
    if oc get deployment "$CHATBOT_DEPLOYMENT" -n "$RAG_NS" \
      --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done
  if ! oc get deployment "$CHATBOT_DEPLOYMENT" -n "$RAG_NS" \
    --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "ERROR: chatbot Deployment ${CHATBOT_DEPLOYMENT} was not created by Argo CD." >&2
    exit 1
  fi

  oc rollout restart "deployment/${CHATBOT_DEPLOYMENT}" -n "$RAG_NS" \
    --insecure-skip-tls-verify=true >/dev/null
  oc rollout status "deployment/${CHATBOT_DEPLOYMENT}" -n "$RAG_NS" \
    --timeout=5m \
    --insecure-skip-tls-verify=true
  echo "✓ Stage 230 chatbot image is built and the Deployment is available"
}

apply_argocd_application
wait_for_namespace
ensure_object_storage
ensure_runtime_secrets
ensure_chatbot_build

oc annotate applications.argoproj.io stage-230-private-data-rag -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite \
  --insecure-skip-tls-verify=true >/dev/null

echo "✓ Stage 230 Application applied. Run ./stage-230-private-data-rag/validate.sh after Argo CD sync completes."
