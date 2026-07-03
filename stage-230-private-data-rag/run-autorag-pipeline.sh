#!/usr/bin/env bash
# Run the Stage 230 AutoRAG documents-rag-optimization-pipeline through RHOAI AI Pipelines.
#
# The pipeline definition is the vendored Red Hat build of
# red-hat-data-services/pipelines-components (branch rhoai-3.4)
# pipelines/training/autorag/documents_rag_optimization_pipeline/pipeline.yaml.
# Importing it with the documented pipeline name makes runs visible on the
# OpenShift AI Gen AI studio AutoRAG page.
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

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd oc
require_cmd python3

RAG_NS="${RHOAI_STAGE230_NAMESPACE:-enterprise-rag}"
DSPA_NAME="${RHOAI_STAGE230_DSPA_NAME:-dspa-enterprise-rag}"
PIPELINE_NAME="${RHOAI_STAGE230_AUTORAG_PIPELINE_NAME:-documents-rag-optimization-pipeline}"
# The Gen AI studio AutoRAG page lists runs by matching the pipeline display
# name against the documented value, so the display name must stay
# documents-rag-optimization-pipeline (verified live: a readable display name
# hides runs from the AutoRAG page). Readability lives in the description.
PIPELINE_DISPLAY_NAME="${RHOAI_STAGE230_AUTORAG_PIPELINE_DISPLAY_NAME:-documents-rag-optimization-pipeline}"
PIPELINE_PRODUCT_VERSION="${RHOAI_STAGE230_AUTORAG_PIPELINE_PRODUCT_VERSION:-3.4}"
PIPELINE_YAML="${RHOAI_STAGE230_AUTORAG_PIPELINE_YAML:-$SCRIPT_DIR/kfp/vendor/documents-rag-optimization-pipeline-rhoai-3.4.yaml}"
EXPERIMENT_NAME="${RHOAI_STAGE230_AUTORAG_EXPERIMENT_NAME:-stage-230-private-data-rag}"
S3_CONNECTION_SECRET="${RHOAI_STAGE230_S3_CONNECTION_SECRET:-enterprise-rag-s3}"
AUTORAG_CONNECTION_SECRET="${RHOAI_STAGE230_AUTORAG_CONNECTION_SECRET:-autorag-llama-stack-connection}"
INPUT_DATA_KEY="${RHOAI_STAGE230_AUTORAG_INPUT_PREFIX:-autorag/rhoai-product-docs/input}"
TEST_DATA_KEY="${RHOAI_STAGE230_AUTORAG_BENCHMARK_KEY:-autorag/rhoai-product-docs/benchmark_data.json}"
VECTOR_IO_PROVIDER_ID="${RHOAI_STAGE230_AUTORAG_VECTOR_IO_PROVIDER_ID:-milvus}"
GENERATION_MODELS_JSON="${RHOAI_STAGE230_AUTORAG_GENERATION_MODELS_JSON:-[\"vllm-inference/${RHOAI_MAAS_NEMOTRON_MODEL_NAME:-nemotron-3-nano-30b-a3b}\"]}"
EMBEDDINGS_MODELS_JSON="${RHOAI_STAGE230_AUTORAG_EMBEDDINGS_MODELS_JSON:-[\"sentence-transformers/ibm-granite/granite-embedding-30m-english\",\"sentence-transformers/all-MiniLM-L6-v2\"]}"
OPTIMIZATION_METRIC="${RHOAI_STAGE230_AUTORAG_OPTIMIZATION_METRIC:-faithfulness}"
MAX_RAG_PATTERNS="${RHOAI_STAGE230_AUTORAG_MAX_RAG_PATTERNS:-4}"
TIMEOUT_SECONDS="${RHOAI_STAGE230_AUTORAG_TIMEOUT_SECONDS:-7200}"
EVIDENCE_CM="${RHOAI_STAGE230_AUTORAG_EVIDENCE_CM:-stage230-autorag-pipeline-evidence}"
WAIT_FOR_RUN=true

for arg in "$@"; do
  case "$arg" in
    --no-wait)
      WAIT_FOR_RUN=false
      ;;
    --wait)
      WAIT_FOR_RUN=true
      ;;
    --timeout-seconds=*)
      TIMEOUT_SECONDS="${arg#*=}"
      ;;
    --optimization-metric=*)
      OPTIMIZATION_METRIC="${arg#*=}"
      ;;
    --max-rag-patterns=*)
      MAX_RAG_PATTERNS="${arg#*=}"
      ;;
    --vector-io-provider-id=*)
      VECTOR_IO_PROVIDER_ID="${arg#*=}"
      ;;
    --test-data-key=*)
      TEST_DATA_KEY="${arg#*=}"
      ;;
    --input-data-key=*)
      INPUT_DATA_KEY="${arg#*=}"
      ;;
    --generation-models-json=*)
      GENERATION_MODELS_JSON="${arg#*=}"
      ;;
    --embeddings-models-json=*)
      EMBEDDINGS_MODELS_JSON="${arg#*=}"
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

echo "✓ Cluster guard passed: ${ACTUAL_SERVER}"

if [[ ! -s "$PIPELINE_YAML" ]]; then
  echo "ERROR: vendored AutoRAG pipeline definition is missing: ${PIPELINE_YAML}" >&2
  exit 1
fi

case "$OPTIMIZATION_METRIC" in
  faithfulness|answer_correctness|context_correctness) ;;
  *)
    echo "ERROR: unsupported optimization metric: ${OPTIMIZATION_METRIC}" >&2
    exit 1
    ;;
esac

BUCKET_NAME=$(oc get configmap "${RHOAI_STAGE230_BUCKET_OBC:-enterprise-rag-bucket}" -n "$RAG_NS" \
  -o jsonpath='{.data.BUCKET_NAME}' --insecure-skip-tls-verify=true 2>/dev/null || true)
BUCKET_NAME="${BUCKET_NAME:-enterprise-rag}"

# The vendored pipeline pins the odh-autorag image digest from the
# pipelines-components rhoai-3.4 branch, which can lag or lead what the
# installed operator actually ships. Align the image to the installed RHOAI
# CSV relatedImages entry so the run uses the supported product build.
AUTORAG_PRODUCT_IMAGE="${RHOAI_STAGE230_AUTORAG_IMAGE:-$(oc get csv -n redhat-ods-operator -o json --insecure-skip-tls-verify=true 2>/dev/null \
  | jq -r '[.items[].spec.relatedImages[]? | select(.name=="odh_autorag_image")][0].image // empty')}"
if [[ -z "$AUTORAG_PRODUCT_IMAGE" ]]; then
  echo "WARNING: could not resolve odh_autorag_image from the installed RHOAI CSV; using the vendored image digest as-is." >&2
fi

for secret in "$S3_CONNECTION_SECRET" "$AUTORAG_CONNECTION_SECRET"; do
  if ! oc get secret "$secret" -n "$RAG_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
    echo "ERROR: required Secret ${RAG_NS}/${secret} is missing. Run deploy.sh first." >&2
    exit 1
  fi
done

ensure_kfp_venv() {
  local venv_path="$ROOT_DIR/.venv-kfp"
  if [[ ! -d "$venv_path" ]]; then
    python3 -m venv "$venv_path"
  fi
  "$venv_path/bin/pip" install -q --upgrade pip
  "$venv_path/bin/pip" install -q kfp==2.14.6 kfp-kubernetes==2.14.6
}

wait_for_dspa_route() {
  local route
  for _ in $(seq 1 120); do
    route=$(oc get route "ds-pipeline-${DSPA_NAME}" -n "$RAG_NS" \
      -o jsonpath='{.spec.host}' --insecure-skip-tls-verify=true 2>/dev/null || true)
    if [[ -n "$route" ]]; then
      printf '%s' "$route"
      return 0
    fi
    sleep 5
  done
  echo "ERROR: DSPA route ds-pipeline-${DSPA_NAME} was not created in ${RAG_NS}." >&2
  exit 1
}

review_s3_artifacts() {
  local run_id="$1"
  local logs_file="$2"
  local review_job="stage230-autorag-artifact-review"

  oc delete job "$review_job" -n "$RAG_NS" --ignore-not-found \
    --insecure-skip-tls-verify=true >/dev/null
  for _ in $(seq 1 30); do
    if ! oc get job "$review_job" -n "$RAG_NS" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  oc apply -f - --insecure-skip-tls-verify=true <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${review_job}
  namespace: ${RAG_NS}
  labels:
    app.kubernetes.io/part-of: rag
    app.kubernetes.io/component: pipeline-validation
    demo.rhoai.io/stage: "230"
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: review
          image: image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/s2i-generic-data-science-notebook:3.4
          imagePullPolicy: Always
          command:
            - /bin/bash
            - -ec
          args:
            - |
              python - <<'PY'
              import json
              import os

              import boto3
              from botocore.config import Config
              from urllib3 import disable_warnings
              from urllib3.exceptions import InsecureRequestWarning

              disable_warnings(InsecureRequestWarning)
              run_id = os.environ["RUN_ID"]
              client = boto3.client(
                  "s3",
                  endpoint_url=os.environ["AWS_S3_ENDPOINT"],
                  aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
                  aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
                  region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
                  verify=False,
                  config=Config(signature_version="s3v4"),
              )
              bucket = os.environ["AWS_S3_BUCKET"]
              run_keys = []
              paginator = client.get_paginator("list_objects_v2")
              for page in paginator.paginate(Bucket=bucket, Prefix="documents-rag-optimization-pipeline/"):
                  for entry in page.get("Contents", []):
                      if run_id in entry["Key"]:
                          run_keys.append(entry["Key"])
              if not run_keys:
                  raise SystemExit(f"no pipeline artifacts found for run {run_id} under s3://{bucket}/documents-rag-optimization-pipeline/")
              leaderboard_keys = [key for key in run_keys if "leaderboard" in key.lower()]
              pattern_keys = [key for key in run_keys if "rag_pattern" in key.lower() or "pattern" in key.lower()]
              notebook_keys = [key for key in run_keys if key.endswith(".ipynb")]
              if not leaderboard_keys:
                  raise SystemExit(f"run {run_id} produced no leaderboard artifact; keys={run_keys[:20]}")
              if not pattern_keys:
                  raise SystemExit(f"run {run_id} produced no RAG pattern artifacts; keys={run_keys[:20]}")
              print(json.dumps({
                  "status": "pass",
                  "run_id": run_id,
                  "bucket": bucket,
                  "artifact_count": len(run_keys),
                  "leaderboard_artifacts": sorted(leaderboard_keys)[:10],
                  "pattern_artifact_count": len(pattern_keys),
                  "notebook_artifact_count": len(notebook_keys),
              }, ensure_ascii=False, sort_keys=True))
              PY
          env:
            - name: RUN_ID
              value: "${run_id}"
            - name: AWS_S3_ENDPOINT
              valueFrom:
                secretKeyRef:
                  name: ${S3_CONNECTION_SECRET}
                  key: AWS_S3_ENDPOINT
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: ${S3_CONNECTION_SECRET}
                  key: AWS_ACCESS_KEY_ID
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: ${S3_CONNECTION_SECRET}
                  key: AWS_SECRET_ACCESS_KEY
            - name: AWS_S3_BUCKET
              valueFrom:
                secretKeyRef:
                  name: ${S3_CONNECTION_SECRET}
                  key: AWS_S3_BUCKET
            - name: AWS_DEFAULT_REGION
              valueFrom:
                secretKeyRef:
                  name: ${S3_CONNECTION_SECRET}
                  key: AWS_DEFAULT_REGION
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 1Gi
EOF

  if ! oc wait -n "$RAG_NS" --for=condition=complete "job/${review_job}" \
    --timeout=5m --insecure-skip-tls-verify=true >/dev/null; then
    oc logs -n "$RAG_NS" "job/${review_job}" --insecure-skip-tls-verify=true >&2 || true
    echo "ERROR: AutoRAG pipeline artifact review failed." >&2
    exit 1
  fi
  oc logs -n "$RAG_NS" "job/${review_job}" --insecure-skip-tls-verify=true | tee "$logs_file"
}

prewarm_embedding_models() {
  # First use of a sentence-transformers model downloads it to the Llama
  # Stack PVC. Warm each AutoRAG embedding model with a single request so
  # the download does not burn the pipeline's fixed 60s embeddings timeout.
  local lsd_route model status
  lsd_route=$(oc get route lsd-enterprise-rag -n "$RAG_NS" \
    -o jsonpath='{.spec.host}' --insecure-skip-tls-verify=true 2>/dev/null || true)
  if [[ -z "$lsd_route" ]]; then
    echo "WARNING: Llama Stack route not found; skipping embedding model pre-warm." >&2
    return 0
  fi
  while IFS= read -r model; do
    [[ -n "$model" ]] || continue
    echo "   Pre-warming embedding model ${model} …"
    status=$(curl -sk --max-time 600 -o /dev/null -w '%{http_code}' \
      -H "Content-Type: application/json" \
      "https://${lsd_route}/v1/embeddings" \
      -d "{\"model\":\"${model}\",\"input\":[\"warmup\"]}" 2>/dev/null || true)
    if [[ "$status" != "200" ]]; then
      echo "ERROR: pre-warm of embedding model ${model} failed (status=${status})." >&2
      exit 1
    fi
  done < <(printf '%s' "$EMBEDDINGS_MODELS_JSON" | jq -r '.[]')
  echo "✓ AutoRAG embedding models are warm"
}

ensure_kfp_venv
KFP_PYTHON="$ROOT_DIR/.venv-kfp/bin/python"
prewarm_embedding_models
DSPA_ROUTE="$(wait_for_dspa_route)"
DSPA_URL="https://${DSPA_ROUTE}"
OC_TOKEN="$(oc whoami -t --insecure-skip-tls-verify=true)"
RUN_EVIDENCE_JSON="$(mktemp)"
REVIEW_LOGS="$(mktemp)"
PIPELINE_CR_YAML="$(mktemp)"
PIPELINE_VERSION_NAME="${PIPELINE_NAME}-${PIPELINE_PRODUCT_VERSION}-$(date +%s)"
export DSPA_URL RAG_NS PIPELINE_YAML PIPELINE_NAME PIPELINE_DISPLAY_NAME PIPELINE_CR_YAML PIPELINE_VERSION_NAME
export EXPERIMENT_NAME OC_TOKEN WAIT_FOR_RUN TIMEOUT_SECONDS
export S3_CONNECTION_SECRET AUTORAG_CONNECTION_SECRET BUCKET_NAME INPUT_DATA_KEY TEST_DATA_KEY
export VECTOR_IO_PROVIDER_ID GENERATION_MODELS_JSON EMBEDDINGS_MODELS_JSON
export OPTIMIZATION_METRIC MAX_RAG_PATTERNS RUN_EVIDENCE_JSON AUTORAG_PRODUCT_IMAGE

"$KFP_PYTHON" - <<'PY'
import os
from pathlib import Path

import yaml


pipeline_name = os.environ["PIPELINE_NAME"]
pipeline_display_name = os.environ["PIPELINE_DISPLAY_NAME"]
pipeline_version_name = os.environ["PIPELINE_VERSION_NAME"]
pipeline_yaml = Path(os.environ["PIPELINE_YAML"])
pipeline_cr_yaml = Path(os.environ["PIPELINE_CR_YAML"])

compiled_docs = [doc for doc in yaml.safe_load_all(pipeline_yaml.read_text(encoding="utf-8")) if doc]
if not compiled_docs:
    raise RuntimeError(f"{pipeline_yaml} did not contain a compiled KFP pipeline spec")
pipeline_spec = compiled_docs[0]
platform_spec = compiled_docs[1] if len(compiled_docs) > 1 else None
if not isinstance(pipeline_spec, dict) or "pipelineInfo" not in pipeline_spec:
    raise RuntimeError(f"{pipeline_yaml} is not a valid compiled KFP pipeline spec")
if pipeline_spec["pipelineInfo"].get("name") != pipeline_name:
    raise RuntimeError(
        f"vendored pipeline name {pipeline_spec['pipelineInfo'].get('name')!r} "
        f"does not match expected {pipeline_name!r}"
    )

product_image = os.environ.get("AUTORAG_PRODUCT_IMAGE", "")
if product_image:
    substituted = 0
    for executor in pipeline_spec.get("deploymentSpec", {}).get("executors", {}).values():
        container = executor.get("container")
        if not container:
            continue
        image = container.get("image", "")
        if image.startswith("registry.redhat.io/rhoai/odh-autorag-rhel9@") and image != product_image:
            container["image"] = product_image
            substituted += 1
    if substituted:
        print(f"aligned {substituted} executor image(s) to installed CSV image {product_image}")

labels = {
    "app.kubernetes.io/part-of": "rag",
    "app.kubernetes.io/component": "autorag-pipeline",
    "demo.rhoai.io/stage": "230",
}
tags = {"stage": "230", "feature": "autorag"}
pipeline_resource = {
    "apiVersion": "pipelines.kubeflow.org/v2beta1",
    "kind": "Pipeline",
    "metadata": {
        "name": pipeline_name,
        "namespace": os.environ["RAG_NS"],
        "labels": labels,
    },
    "spec": {
        "displayName": pipeline_display_name,
        "description": "AutoRAG documents RAG optimization pipeline (Red Hat pipelines-components, rhoai-3.4).",
        "tags": tags,
    },
}
pipeline_version_resource = {
    "apiVersion": "pipelines.kubeflow.org/v2beta1",
    "kind": "PipelineVersion",
    "metadata": {
        "name": pipeline_version_name,
        "namespace": os.environ["RAG_NS"],
        "labels": labels,
    },
    "spec": {
        "pipelineName": pipeline_name,
        "displayName": pipeline_version_name,
        "description": "Vendored compiled AutoRAG pipeline IR from pipelines-components branch rhoai-3.4.",
        "pipelineSpec": pipeline_spec,
        "tags": tags,
    },
}
if platform_spec:
    pipeline_version_resource["spec"]["platformSpec"] = platform_spec
pipeline_cr_yaml.write_text(
    yaml.safe_dump_all(
        [pipeline_resource, pipeline_version_resource],
        sort_keys=False,
        allow_unicode=True,
    ),
    encoding="utf-8",
)
print(pipeline_cr_yaml)
PY

oc apply -f "$PIPELINE_CR_YAML" --insecure-skip-tls-verify=true >/dev/null

"$KFP_PYTHON" - <<'PY'
import json
import os
import time
from pathlib import Path

from urllib3 import disable_warnings
from urllib3.exceptions import InsecureRequestWarning

disable_warnings(InsecureRequestWarning)

from kfp import client


def item_name(item):
    return getattr(item, "display_name", None) or getattr(item, "name", None)


def item_id(item, *names):
    for name in names:
        value = getattr(item, name, None)
        if value:
            return value
    return None


namespace = os.environ["RAG_NS"]
pipeline_name = os.environ["PIPELINE_NAME"]
pipeline_display_name = os.environ["PIPELINE_DISPLAY_NAME"]
pipeline_version_name = os.environ["PIPELINE_VERSION_NAME"]
experiment_name = os.environ["EXPERIMENT_NAME"]

kfp_client = client.Client(
    host=os.environ["DSPA_URL"],
    namespace=namespace,
    existing_token=os.environ["OC_TOKEN"],
    verify_ssl=False,
)


def find_pipeline():
    pipelines = kfp_client.list_pipelines(page_size=100).pipelines or []
    return next(
        (
            candidate
            for candidate in pipelines
            if item_name(candidate) in {pipeline_name, pipeline_display_name}
        ),
        None,
    )


def find_pipeline_version(pipeline_id):
    versions = kfp_client.list_pipeline_versions(pipeline_id=pipeline_id, page_size=100)
    pipeline_versions = versions.pipeline_versions or []
    return next(
        (candidate for candidate in pipeline_versions if item_name(candidate) == pipeline_version_name),
        None,
    )


pipeline = None
for _ in range(60):
    pipeline = find_pipeline()
    if pipeline is not None:
        break
    time.sleep(2)
if pipeline is None:
    raise RuntimeError(f"DSPA did not list Pipeline CR {pipeline_name}")

pipeline_id = item_id(pipeline, "pipeline_id", "id")
if not pipeline_id:
    raise RuntimeError(f"could not resolve pipeline id for {pipeline_name}")

version = None
for _ in range(60):
    version = find_pipeline_version(pipeline_id)
    if version is not None:
        break
    time.sleep(2)
if version is None:
    raise RuntimeError(f"DSPA did not list PipelineVersion CR {pipeline_version_name}")

version_id = item_id(version, "pipeline_version_id", "id")
if not version_id:
    raise RuntimeError(f"could not resolve pipeline version id for {pipeline_version_name}")

try:
    experiment = kfp_client.create_experiment(name=experiment_name, namespace=namespace)
except Exception:
    experiments = kfp_client.list_experiments(namespace=namespace, page_size=100).experiments or []
    experiment = next((candidate for candidate in experiments if item_name(candidate) == experiment_name), None)
    if experiment is None:
        raise
experiment_id = item_id(experiment, "experiment_id", "id")

params = {
    "test_data_secret_name": os.environ["S3_CONNECTION_SECRET"],
    "test_data_bucket_name": os.environ["BUCKET_NAME"],
    "test_data_key": os.environ["TEST_DATA_KEY"],
    "input_data_secret_name": os.environ["S3_CONNECTION_SECRET"],
    "input_data_bucket_name": os.environ["BUCKET_NAME"],
    "input_data_key": os.environ["INPUT_DATA_KEY"],
    "llama_stack_secret_name": os.environ["AUTORAG_CONNECTION_SECRET"],
    "llama_stack_vector_io_provider_id": os.environ["VECTOR_IO_PROVIDER_ID"],
    "embeddings_models": json.loads(os.environ["EMBEDDINGS_MODELS_JSON"]),
    "generation_models": json.loads(os.environ["GENERATION_MODELS_JSON"]),
    "optimization_metric": os.environ["OPTIMIZATION_METRIC"],
    "optimization_max_rag_patterns": int(os.environ["MAX_RAG_PATTERNS"]),
}
run_name = f"autorag-optimization-run-{int(time.time())}"
# The AutoRAG results page expects artifacts at the KFP default layout from
# the bucket root: <bucket>/documents-rag-optimization-pipeline/<run-id>/...
# The DSP API server otherwise stamps its built-in "<bucket>/pipelines" root
# into the run, so pass the bucket-root pipeline_root explicitly.
run = kfp_client.run_pipeline(
    experiment_id=experiment_id,
    job_name=run_name,
    pipeline_id=pipeline_id,
    version_id=version_id,
    params=params,
    enable_caching=False,
    pipeline_root=f"s3://{os.environ['BUCKET_NAME']}",
)
run_id = item_id(run, "run_id", "id")
state = getattr(run, "state", "")

if os.environ["WAIT_FOR_RUN"].lower() == "true":
    run = kfp_client.wait_for_run_completion(
        run_id=run_id,
        timeout=int(os.environ["TIMEOUT_SECONDS"]),
        sleep_duration=20,
    )
    state = getattr(run, "state", "")
    if str(state).upper() not in {"SUCCEEDED", "V2BETA1RUNTIMESTATE_SUCCEEDED"}:
        raise RuntimeError(f"pipeline run did not succeed: run_id={run_id}, state={state}")

evidence = {
    "autorag_image": os.environ.get("AUTORAG_PRODUCT_IMAGE", "vendored default"),
    "dspa_url": os.environ["DSPA_URL"],
    "experiment_id": experiment_id,
    "pipeline_root": f"s3://{os.environ['BUCKET_NAME']}",
    "experiment_name": experiment_name,
    "embeddings_models": json.loads(os.environ["EMBEDDINGS_MODELS_JSON"]),
    "generation_models": json.loads(os.environ["GENERATION_MODELS_JSON"]),
    "input_data_key": os.environ["INPUT_DATA_KEY"],
    "optimization_metric": os.environ["OPTIMIZATION_METRIC"],
    "optimization_max_rag_patterns": int(os.environ["MAX_RAG_PATTERNS"]),
    "pipeline_id": pipeline_id,
    "pipeline_name": pipeline_name,
    "pipeline_version_id": version_id,
    "pipeline_version_name": pipeline_version_name,
    "run_id": run_id,
    "run_name": run_name,
    "run_state": str(state),
    "test_data_key": os.environ["TEST_DATA_KEY"],
    "vector_io_provider_id": os.environ["VECTOR_IO_PROVIDER_ID"],
}
Path(os.environ["RUN_EVIDENCE_JSON"]).write_text(json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8")
print(json.dumps(evidence, indent=2, sort_keys=True))
PY

RUN_ID="$(jq -r '.run_id' "$RUN_EVIDENCE_JSON")"
if [[ "$WAIT_FOR_RUN" == "true" ]]; then
  review_s3_artifacts "$RUN_ID" "$REVIEW_LOGS"
else
  printf '{"status": "pending", "run_id": "%s", "note": "run submitted with --no-wait; rerun without --no-wait or review artifacts manually"}\n' \
    "$RUN_ID" > "$REVIEW_LOGS"
fi

oc create configmap "$EVIDENCE_CM" \
  -n "$RAG_NS" \
  --from-file=run-evidence.json="$RUN_EVIDENCE_JSON" \
  --from-file=artifact-review.json="$REVIEW_LOGS" \
  --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null
oc label configmap "$EVIDENCE_CM" -n "$RAG_NS" --overwrite \
  app.kubernetes.io/part-of=rag \
  app.kubernetes.io/component=pipeline-validation \
  demo.rhoai.io/stage=230 \
  --insecure-skip-tls-verify=true >/dev/null

echo "✓ AutoRAG optimization run evidence stored in ConfigMap ${RAG_NS}/${EVIDENCE_CM}"
echo "  Review the leaderboard on the OpenShift AI AutoRAG page or in the run artifacts."
