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

app_sync=$(jsonpath "applications.argoproj.io/stage-230-private-data-rag" "openshift-gitops" "{.status.sync.status}")
app_health=$(jsonpath "applications.argoproj.io/stage-230-private-data-rag" "openshift-gitops" "{.status.health.status}")
[[ "$app_sync" == "Synced" ]] && check "Stage 230 Argo CD Application is Synced" "pass" || check "Stage 230 Argo CD Application is Synced" "${app_sync:-missing}"
[[ "$app_health" == "Healthy" ]] && check "Stage 230 Argo CD Application is Healthy" "pass" || warn "Stage 230 Argo CD Application is Healthy" "${app_health:-missing}"

resource_exists "namespace/${RAG_NS}" "" && check "enterprise-rag namespace exists" "pass" || check "enterprise-rag namespace exists" "missing"
for secret in "$POSTGRES_SECRET" "$MILVUS_SECRET" "$LLAMA_SECRET"; do
  resource_exists "secret/${secret}" "$RAG_NS" && check "${secret} Secret exists" "pass" || check "${secret} Secret exists" "missing"
done

[[ "$(available_replicas statefulset/private-rag-postgres "$RAG_NS")" == "1" ]] \
  && check "PostgreSQL metadata store is available" "pass" \
  || check "PostgreSQL metadata store is available" "availableReplicas=$(available_replicas statefulset/private-rag-postgres "$RAG_NS")"

[[ "$(available_replicas deployment/private-rag-etcd "$RAG_NS")" == "1" ]] \
  && check "Milvus etcd dependency is available" "pass" \
  || check "Milvus etcd dependency is available" "availableReplicas=$(available_replicas deployment/private-rag-etcd "$RAG_NS")"

[[ "$(available_replicas deployment/private-rag-milvus "$RAG_NS")" == "1" ]] \
  && check "Milvus vector store service is available" "pass" \
  || check "Milvus vector store service is available" "availableReplicas=$(available_replicas deployment/private-rag-milvus "$RAG_NS")"

lls_ready=$(jsonpath "llamastackdistribution/lsd-enterprise-rag" "$RAG_NS" "{.status.conditions[?(@.type==\"Ready\")].status}")
[[ "$lls_ready" == "True" ]] && check "LlamaStackDistribution is Ready" "pass" || check "LlamaStackDistribution is Ready" "${lls_ready:-missing}"

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
  rm -f "$models_body"
else
  check "Llama Stack route exists" "missing"
fi

if python3 -m py_compile "$SCRIPT_DIR/scripts/agnews_rag_smoke.py" >/dev/null 2>&1; then
  check "AG News RAG smoke script compiles" "pass"
else
  check "AG News RAG smoke script compiles" "py_compile failed"
fi

echo
echo "Stage 230 validation summary: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
if (( FAIL > 0 )); then
  exit 1
fi
