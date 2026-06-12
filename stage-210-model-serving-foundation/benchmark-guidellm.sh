#!/usr/bin/env bash
# benchmark-guidellm.sh - Stage 210 vLLM serving baseline
# Runs GuideLLM in-cluster against the Nemotron endpoint using the llm-d
# showroom-style prompt PVC and copies results to gitignored runs/ for review.
# This is intentionally not part of every deploy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MODEL_NS="${RHOAI_MODEL_NAMESPACE:-demo-sandbox}"
MODEL_DEPLOYMENT_NAME="${RHOAI_NEMOTRON_DEPLOYMENT_NAME:-nvidia-nemotron-3-nano-30b-a3b}"
MODEL_ID="${RHOAI_NEMOTRON_GUIDELLM_MODEL_ID:-$MODEL_DEPLOYMENT_NAME}"
GUIDELLM_PROCESSOR="${RHOAI_NEMOTRON_GUIDELLM_PROCESSOR:-nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8}"
GUIDELLM_IMAGE="${RHOAI_GUIDELLM_IMAGE:-ghcr.io/vllm-project/guidellm:v0.5.0}"
GUIDELLM_RATE_TYPE="${RHOAI_GUIDELLM_RATE_TYPE:-concurrent}"
GUIDELLM_RATE="${RHOAI_GUIDELLM_RATE:-32,64}"
GUIDELLM_MAX_SECONDS="${RHOAI_GUIDELLM_MAX_SECONDS:-30}"
GUIDELLM_DATA="${RHOAI_GUIDELLM_DATA:-/data/prompts.csv}"
GUIDELLM_OUTPUTS="${RHOAI_GUIDELLM_OUTPUTS:-benchmark-results.json,benchmark-results.csv}"
GUIDELLM_DATA_PVC="${RHOAI_GUIDELLM_DATA_PVC:-benchmark-data}"
GUIDELLM_TARGET_SUFFIX="${RHOAI_GUIDELLM_TARGET_SUFFIX:-/v1}"
GUIDELLM_TIMEOUT="${RHOAI_GUIDELLM_TIMEOUT:-20m}"
KEEP_RESOURCES="${RHOAI_GUIDELLM_KEEP_RESOURCES:-false}"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

MODEL_NS="${RHOAI_MODEL_NAMESPACE:-$MODEL_NS}"
MODEL_DEPLOYMENT_NAME="${RHOAI_NEMOTRON_DEPLOYMENT_NAME:-$MODEL_DEPLOYMENT_NAME}"
MODEL_ID="${RHOAI_NEMOTRON_GUIDELLM_MODEL_ID:-$MODEL_ID}"
GUIDELLM_PROCESSOR="${RHOAI_NEMOTRON_GUIDELLM_PROCESSOR:-$GUIDELLM_PROCESSOR}"
GUIDELLM_IMAGE="${RHOAI_GUIDELLM_IMAGE:-$GUIDELLM_IMAGE}"
GUIDELLM_RATE_TYPE="${RHOAI_GUIDELLM_RATE_TYPE:-$GUIDELLM_RATE_TYPE}"
GUIDELLM_RATE="${RHOAI_GUIDELLM_RATE:-$GUIDELLM_RATE}"
GUIDELLM_MAX_SECONDS="${RHOAI_GUIDELLM_MAX_SECONDS:-$GUIDELLM_MAX_SECONDS}"
GUIDELLM_DATA="${RHOAI_GUIDELLM_DATA:-$GUIDELLM_DATA}"
GUIDELLM_OUTPUTS="${RHOAI_GUIDELLM_OUTPUTS:-$GUIDELLM_OUTPUTS}"
GUIDELLM_DATA_PVC="${RHOAI_GUIDELLM_DATA_PVC:-$GUIDELLM_DATA_PVC}"
GUIDELLM_TARGET_SUFFIX="${RHOAI_GUIDELLM_TARGET_SUFFIX:-$GUIDELLM_TARGET_SUFFIX}"
GUIDELLM_TIMEOUT="${RHOAI_GUIDELLM_TIMEOUT:-$GUIDELLM_TIMEOUT}"
KEEP_RESOURCES="${RHOAI_GUIDELLM_KEEP_RESOURCES:-$KEEP_RESOURCES}"

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

for cmd in oc jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  fi
done

ISVC_READY=$(oc get inferenceservice "$MODEL_DEPLOYMENT_NAME" -n "$MODEL_NS" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
  --insecure-skip-tls-verify=true 2>/dev/null || true)
if [[ "$ISVC_READY" != "True" ]]; then
  echo "ERROR: ${MODEL_NS}/${MODEL_DEPLOYMENT_NAME} is not Ready." >&2
  exit 1
fi

TARGET_URL=$(oc get inferenceservice "$MODEL_DEPLOYMENT_NAME" -n "$MODEL_NS" \
  -o jsonpath='{.status.address.url}' --insecure-skip-tls-verify=true)
if [[ -z "$TARGET_URL" ]]; then
  echo "ERROR: ${MODEL_DEPLOYMENT_NAME} has no internal status.address.url." >&2
  exit 1
fi

if [[ "$GUIDELLM_TARGET_SUFFIX" == "none" ]]; then
  BENCHMARK_TARGET="$TARGET_URL"
else
  BENCHMARK_TARGET="${TARGET_URL%/}${GUIDELLM_TARGET_SUFFIX}"
fi

if [[ "$GUIDELLM_DATA" == /data/* ]]; then
  if ! oc get pvc "$GUIDELLM_DATA_PVC" -n "$MODEL_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "ERROR: expected benchmark data PVC ${MODEL_NS}/${GUIDELLM_DATA_PVC} is missing." >&2
    echo "       Reconcile stage-210-model-serving-foundation before running the workshop benchmark." >&2
    exit 1
  fi
fi

RUN_ID="$(date -u +%Y%m%d%H%M%S)"
JOB_NAME="guidellm-stage210-${RUN_ID}"
PVC_NAME="guidellm-results-${RUN_ID}"
COPY_JOB="guidellm-copy-${RUN_ID}"
RESULTS_DIR="${ROOT_DIR}/runs/stage-210-guidellm/${RUN_ID}"

mkdir -p "$RESULTS_DIR"

echo "── Creating GuideLLM results PVC ──"
oc apply -f - --insecure-skip-tls-verify=true <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${MODEL_NS}
  labels:
    app.kubernetes.io/part-of: rhoai3-demo
    app.kubernetes.io/name: guidellm
    demo.rhoai.io/stage: "210"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

echo "── Running GuideLLM benchmark job ──"
echo "  Target: ${BENCHMARK_TARGET}"
echo "  Data: ${GUIDELLM_DATA}"
echo "  Profile: ${GUIDELLM_RATE_TYPE} ${GUIDELLM_RATE} for ${GUIDELLM_MAX_SECONDS}s per level"
oc apply -f - --insecure-skip-tls-verify=true <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${MODEL_NS}
  labels:
    app.kubernetes.io/part-of: rhoai3-demo
    app.kubernetes.io/name: guidellm
    demo.rhoai.io/stage: "210"
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app.kubernetes.io/name: guidellm
        demo.rhoai.io/stage: "210"
    spec:
      restartPolicy: Never
      containers:
        - name: guidellm
          image: ${GUIDELLM_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: HOME
              value: /results
            - name: HF_HOME
              value: /tmp/hf-cache
            - name: TRANSFORMERS_CACHE
              value: /tmp/hf-cache
            - name: XDG_CACHE_HOME
              value: /tmp
          args:
            - benchmark
            - run
            - --target
            - "${BENCHMARK_TARGET}"
            - --model
            - "${MODEL_ID}"
            - --processor
            - "${GUIDELLM_PROCESSOR}"
            - --data
            - '${GUIDELLM_DATA}'
            - --rate-type
            - "${GUIDELLM_RATE_TYPE}"
            - --rate
            - "${GUIDELLM_RATE}"
            - --max-seconds
            - "${GUIDELLM_MAX_SECONDS}"
            - --output-dir
            - /results
            - --outputs
            - "${GUIDELLM_OUTPUTS}"
          volumeMounts:
            - name: cache
              mountPath: /tmp/hf-cache
            - name: results
              mountPath: /results
            - name: data
              mountPath: /data
              readOnly: true
      volumes:
        - name: cache
          emptyDir: {}
        - name: results
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
        - name: data
          persistentVolumeClaim:
            claimName: ${GUIDELLM_DATA_PVC}
EOF

if ! oc wait -n "$MODEL_NS" --for=condition=complete "job/${JOB_NAME}" \
  "--timeout=${GUIDELLM_TIMEOUT}" --insecure-skip-tls-verify=true; then
  echo "ERROR: GuideLLM job did not complete successfully." >&2
  oc logs -n "$MODEL_NS" "job/${JOB_NAME}" --insecure-skip-tls-verify=true || true
  echo "Temporary resources retained for inspection: job/${JOB_NAME}, pvc/${PVC_NAME}" >&2
  exit 1
fi

oc logs -n "$MODEL_NS" "job/${JOB_NAME}" --insecure-skip-tls-verify=true || true

echo "── Copying GuideLLM results to ${RESULTS_DIR} ──"
oc apply -f - --insecure-skip-tls-verify=true <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${COPY_JOB}
  namespace: ${MODEL_NS}
  labels:
    app.kubernetes.io/part-of: rhoai3-demo
    app.kubernetes.io/name: guidellm-copy
    demo.rhoai.io/stage: "210"
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app.kubernetes.io/name: guidellm-copy
        demo.rhoai.io/stage: "210"
    spec:
      restartPolicy: Never
      containers:
        - name: copy
          image: registry.access.redhat.com/ubi9/ubi-minimal:latest
          command:
            - /bin/sh
            - -c
            - sleep 3600
          volumeMounts:
            - name: results
              mountPath: /results
      volumes:
        - name: results
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
EOF

COPY_POD=""
for _ in $(seq 1 60); do
  COPY_POD=$(oc get pod -n "$MODEL_NS" -l "batch.kubernetes.io/job-name=${COPY_JOB}" \
    -o jsonpath='{.items[0].metadata.name}' --insecure-skip-tls-verify=true 2>/dev/null || true)
  if [[ -n "$COPY_POD" ]]; then
    COPY_READY=$(oc get pod "$COPY_POD" -n "$MODEL_NS" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
      --insecure-skip-tls-verify=true 2>/dev/null || true)
    [[ "$COPY_READY" == "True" ]] && break
  fi
  sleep 2
done
if [[ -z "$COPY_POD" || "${COPY_READY:-}" != "True" ]]; then
  echo "ERROR: copy job pod did not become Ready." >&2
  exit 1
fi

IFS=',' read -r -a OUTPUT_FILES <<<"$GUIDELLM_OUTPUTS"
for output_file in "${OUTPUT_FILES[@]}"; do
  output_file="${output_file#"${output_file%%[![:space:]]*}"}"
  output_file="${output_file%"${output_file##*[![:space:]]}"}"
  oc exec -n "$MODEL_NS" "$COPY_POD" -c copy --insecure-skip-tls-verify=true \
    -- cat "/results/${output_file}" >"${RESULTS_DIR}/${output_file}"
done

if [[ "$KEEP_RESOURCES" != "true" ]]; then
  echo "── Cleaning temporary GuideLLM resources ──"
  oc delete job "$COPY_JOB" -n "$MODEL_NS" --ignore-not-found \
    --insecure-skip-tls-verify=true >/dev/null
  oc delete job "$JOB_NAME" -n "$MODEL_NS" --ignore-not-found \
    --insecure-skip-tls-verify=true >/dev/null
  oc delete pvc "$PVC_NAME" -n "$MODEL_NS" --ignore-not-found \
    --insecure-skip-tls-verify=true >/dev/null
else
  echo "✓ Temporary resources retained: job/${JOB_NAME}, job/${COPY_JOB}, pvc/${PVC_NAME}"
fi

echo "✓ GuideLLM benchmark complete"
echo "  Results: ${RESULTS_DIR}"
