#!/usr/bin/env bash
# Run the Stage 230 RHOAI product-document Docling pipeline through RHOAI AI Pipelines.
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
PIPELINE_NAME="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_NAME:-stage-230-rhoai-product-docs-docling}"
PIPELINE_DISPLAY_NAME="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_DISPLAY_NAME:-RHOAI Product Docs Docling Pipeline}"
EXPERIMENT_NAME="${RHOAI_STAGE230_RHOAI_DOCS_EXPERIMENT_NAME:-stage-230-private-data-rag}"
PIPELINE_S3_SECRET="${RHOAI_STAGE230_PIPELINE_S3_SECRET:-data-processing-docling-pipeline}"
SOURCE_PREFIX="${RHOAI_STAGE230_PRODUCT_DOCS_PREFIX:-raw/rhoai-product-docs}"
OUTPUT_S3_KEY="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_OUTPUT_KEY:-processed/rhoai-product-docs/rhoai-3.4-product-docs-docling-kfp-chunks.jsonl}"
MAX_DOCUMENTS="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_MAX_DOCUMENTS:-0}"
NUM_SPLITS="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_NUM_SPLITS:-3}"
FOCUS_ONLY="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_FOCUS_ONLY:-true}"
DOCLING_PDF_BACKEND="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_PDF_BACKEND:-dlparse_v4}"
DOCLING_IMAGE_EXPORT_MODE="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_IMAGE_EXPORT_MODE:-embedded}"
DOCLING_TABLE_MODE="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_TABLE_MODE:-accurate}"
DOCLING_NUM_THREADS="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_NUM_THREADS:-4}"
DOCLING_TIMEOUT_PER_DOCUMENT="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_TIMEOUT_PER_DOCUMENT:-300}"
DOCLING_OCR="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_OCR:-false}"
DOCLING_FORCE_OCR="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_FORCE_OCR:-false}"
DOCLING_OCR_ENGINE="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_OCR_ENGINE:-tesseract_cli}"
LLAMA_STACK_BASE_URL="${RHOAI_STAGE230_LLAMA_STACK_BASE_URL:-http://lsd-enterprise-rag-service.enterprise-rag.svc.cluster.local:8321}"
VECTOR_STORE_NAME="${RHOAI_STAGE230_RHOAI_DOCS_VECTOR_STORE:-stage230-rhoai-34-product-docs}"
EMBEDDING_MODEL="${RHOAI_STAGE230_EMBEDDING_MODEL:-sentence-transformers/nomic-ai/nomic-embed-text-v1.5}"
VECTOR_PROVIDER="${RHOAI_STAGE230_VECTOR_PROVIDER:-pgvector}"
TIMEOUT_SECONDS="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_TIMEOUT_SECONDS:-3600}"
EVIDENCE_CM="${RHOAI_STAGE230_RHOAI_DOCS_PIPELINE_EVIDENCE_CM:-stage230-rhoai-docs-pipeline-evidence}"
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
    --source-prefix=*)
      SOURCE_PREFIX="${arg#*=}"
      ;;
    --output-s3-key=*)
      OUTPUT_S3_KEY="${arg#*=}"
      ;;
    --max-chars=*)
      echo "ERROR: --max-chars is no longer supported." >&2
      exit 1
      ;;
    --vector-store-name=*)
      VECTOR_STORE_NAME="${arg#*=}"
      ;;
    --llama-stack-base-url=*)
      LLAMA_STACK_BASE_URL="${arg#*=}"
      ;;
    --embedding-model=*)
      EMBEDDING_MODEL="${arg#*=}"
      ;;
    --max-documents=*)
      MAX_DOCUMENTS="${arg#*=}"
      ;;
    --num-splits=*)
      NUM_SPLITS="${arg#*=}"
      ;;
    --focus-only=*)
      FOCUS_ONLY="${arg#*=}"
      ;;
    --do-ocr=*)
      DOCLING_OCR="${arg#*=}"
      ;;
    --force-ocr=*)
      DOCLING_FORCE_OCR="${arg#*=}"
      ;;
    --table-mode=*)
      DOCLING_TABLE_MODE="${arg#*=}"
      ;;
    --pdf-backend=*)
      DOCLING_PDF_BACKEND="${arg#*=}"
      ;;
    --docling-num-threads=*)
      DOCLING_NUM_THREADS="${arg#*=}"
      ;;
    --docling-timeout-per-document=*)
      DOCLING_TIMEOUT_PER_DOCUMENT="${arg#*=}"
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

echo "✓ Cluster guard passed: ${ACTUAL_SERVER}"

expected_guides_json() {
  SCRIPT_DIR="$SCRIPT_DIR" MAX_DOCUMENTS="$MAX_DOCUMENTS" python3 - <<'PY'
import json
import os
from pathlib import Path

manifest = json.loads(
    (Path(os.environ["SCRIPT_DIR"]) / "data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json")
    .read_text(encoding="utf-8")
)
documents = list(manifest["documents"])
max_documents = int(os.environ.get("MAX_DOCUMENTS", "0"))
if max_documents > 0:
    documents = documents[:max_documents]
print(json.dumps([document["guide_slug"] for document in documents]))
PY
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

compile_pipeline() {
  local venv_path="$ROOT_DIR/.venv-kfp"
  local output="$ROOT_DIR/artifacts/stage-230-rhoai-product-docs-docling.yaml"

  if [[ ! -d "$venv_path" ]]; then
    python3 -m venv "$venv_path"
  fi
  "$venv_path/bin/pip" install -q --upgrade pip
  "$venv_path/bin/pip" install -q kfp==2.14.6 kfp-kubernetes==2.14.6

  mkdir -p "$ROOT_DIR/artifacts"
  local max_doc_flag=""
  if [[ "${MAX_DOCUMENTS:-0}" -gt 0 ]]; then
    max_doc_flag="--max-documents=${MAX_DOCUMENTS}"
  fi
  "$venv_path/bin/python" "$SCRIPT_DIR/kfp/rhoai_product_docs_docling_pipeline.py" --output "$output" $max_doc_flag >/dev/null
  if [[ ! -s "$output" ]]; then
    echo "ERROR: KFP compile did not produce ${output}." >&2
    exit 1
  fi
  printf '%s' "$output"
}

review_s3_artifact() {
  local run_id="$1"
  local review_job="stage230-rhoai-docs-artifact-review"
  local logs_file="$2"

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
              key = os.environ["OUTPUT_S3_KEY"].strip("/")
              client = boto3.client(
                  "s3",
                  endpoint_url=os.environ["S3_ENDPOINT_URL"],
                  aws_access_key_id=os.environ["S3_ACCESS_KEY"],
                  aws_secret_access_key=os.environ["S3_SECRET_KEY"],
                  region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
                  verify=False,
                  config=Config(signature_version="s3v4"),
              )
              body = client.get_object(Bucket=os.environ["S3_BUCKET"], Key=key)["Body"].read().decode("utf-8")
              records = [json.loads(line) for line in body.splitlines() if line.strip()]
              if not records:
                  raise SystemExit("no JSONL records found in processed output")
              guide_slugs = sorted({record.get("guide_slug", "") for record in records})
              topics = sorted({record.get("topic", "") for record in records})
              methods = sorted({record.get("preparation_method", "") for record in records})
              required_guides = set(json.loads(os.environ["EXPECTED_GUIDES_JSON"]))
              missing_guides = sorted(required_guides - set(guide_slugs))
              if missing_guides:
                  raise SystemExit(f"processed output missing guides: {missing_guides}")
              if methods != ["docling-standard-hybridchunker-kfp"]:
                  raise SystemExit(f"unexpected preparation methods: {methods}")
              text = "\\n".join(record.get("text", "") for record in records)
              term_rules = {
                  "working-with-llama-stack": ["Llama Stack", "vector"],
                  "working-with-autorag": ["AutoRAG"],
                  "evaluating-ai-systems": ["EvalHub"],
                  "guardrails": ["guardrail"],
                  "working-with-ai-pipelines": ["pipeline"],
                  "customize-models-genai": ["Docling"],
              }
              required_terms = sorted({term for guide in required_guides for term in term_rules.get(guide, [])})
              missing_terms = [term for term in required_terms if term.casefold() not in text.casefold()]
              if missing_terms:
                  raise SystemExit(f"processed output missing expected terms: {missing_terms}")
              artifact_prefix = f"{key.rsplit('/', 1)[0]}/docling-artifacts"
              missing_artifacts = []
              for guide_slug in guide_slugs:
                  for suffix in ("md", "json"):
                      artifact_key = f"{artifact_prefix}/{guide_slug}.{suffix}"
                      try:
                          client.head_object(Bucket=os.environ["S3_BUCKET"], Key=artifact_key)
                      except Exception:
                          missing_artifacts.append(artifact_key)
              if missing_artifacts:
                  raise SystemExit(f"missing converted Docling artifacts: {missing_artifacts}")
              print(json.dumps({
                  "status": "pass",
                  "run_id": os.environ["RUN_ID"],
                  "bucket": os.environ["S3_BUCKET"],
                  "docling_artifact_prefix": artifact_prefix,
                  "output_s3_key": key,
                  "record_count": len(records),
                  "guide_slugs": guide_slugs,
                  "topics": topics,
                  "preparation_methods": methods,
              }, ensure_ascii=False, sort_keys=True))
              PY
          env:
            - name: RUN_ID
              value: "${run_id}"
            - name: OUTPUT_S3_KEY
              value: "${OUTPUT_S3_KEY}"
            - name: EXPECTED_GUIDES_JSON
              value: '${EXPECTED_GUIDES_JSON}'
            - name: S3_ENDPOINT_URL
              valueFrom:
                secretKeyRef:
                  name: ${PIPELINE_S3_SECRET}
                  key: S3_ENDPOINT_URL
            - name: S3_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: ${PIPELINE_S3_SECRET}
                  key: S3_ACCESS_KEY
            - name: S3_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: ${PIPELINE_S3_SECRET}
                  key: S3_SECRET_KEY
            - name: S3_BUCKET
              valueFrom:
                secretKeyRef:
                  name: ${PIPELINE_S3_SECRET}
                  key: S3_BUCKET
            - name: AWS_DEFAULT_REGION
              valueFrom:
                secretKeyRef:
                  name: ${PIPELINE_S3_SECRET}
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
    echo "ERROR: RHOAI product-doc pipeline output artifact review failed." >&2
    exit 1
  fi
  oc logs -n "$RAG_NS" "job/${review_job}" --insecure-skip-tls-verify=true | tee "$logs_file"
}

PIPELINE_YAML="$(compile_pipeline)"
KFP_PYTHON="$ROOT_DIR/.venv-kfp/bin/python"
DSPA_ROUTE="$(wait_for_dspa_route)"
DSPA_URL="https://${DSPA_ROUTE}"
OC_TOKEN="$(oc whoami -t --insecure-skip-tls-verify=true)"
RUN_EVIDENCE_JSON="$(mktemp)"
REVIEW_LOGS="$(mktemp)"
PIPELINE_CR_YAML="$(mktemp)"
PIPELINE_VERSION_NAME="v-$(date +%s)"
export DSPA_URL RAG_NS PIPELINE_YAML PIPELINE_NAME PIPELINE_DISPLAY_NAME PIPELINE_CR_YAML PIPELINE_VERSION_NAME
export EXPERIMENT_NAME OC_TOKEN WAIT_FOR_RUN TIMEOUT_SECONDS
export SOURCE_PREFIX OUTPUT_S3_KEY PIPELINE_S3_SECRET MAX_DOCUMENTS NUM_SPLITS FOCUS_ONLY
export DOCLING_PDF_BACKEND DOCLING_IMAGE_EXPORT_MODE DOCLING_TABLE_MODE DOCLING_NUM_THREADS
export DOCLING_TIMEOUT_PER_DOCUMENT DOCLING_OCR DOCLING_FORCE_OCR DOCLING_OCR_ENGINE
export LLAMA_STACK_BASE_URL VECTOR_STORE_NAME EMBEDDING_MODEL VECTOR_PROVIDER RUN_EVIDENCE_JSON
EXPECTED_GUIDES_JSON="$(expected_guides_json)"
export EXPECTED_GUIDES_JSON

"$KFP_PYTHON" - <<'PY'
import json
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

labels = {
    "app.kubernetes.io/part-of": "rag",
    "app.kubernetes.io/component": "docling-pipeline",
    "demo.rhoai.io/stage": "230",
}
tags = {"stage": "230", "corpus": "rhoai-product-docs"}
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
        "description": "Stage 230 RHOAI product-document Docling preparation pipeline.",
        "tags": tags,
    },
}
pipeline_version_resource = {
    "apiVersion": "pipelines.kubeflow.org/v2beta1",
    "kind": "PipelineVersion",
    "metadata": {
        "name": f"{pipeline_name}-{pipeline_version_name}",
        "namespace": os.environ["RAG_NS"],
        "labels": labels,
    },
    "spec": {
        "pipelineName": pipeline_name,
        "displayName": f"{pipeline_display_name} {pipeline_version_name}",
        "description": "Compiled Stage 230 RHOAI product-document Docling KFP IR for the current run.",
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
    expected_version_names = {
        pipeline_version_name,
        f"{pipeline_display_name} {pipeline_version_name}",
    }
    return next((candidate for candidate in pipeline_versions if item_name(candidate) in expected_version_names), None)


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
    raise RuntimeError(f"DSPA did not list PipelineVersion CR {pipeline_name}-{pipeline_version_name}")

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
    "output_s3_key": os.environ["OUTPUT_S3_KEY"],
    "pipeline_s3_secret_name": os.environ["PIPELINE_S3_SECRET"],
    "num_splits": int(os.environ["NUM_SPLITS"]),
    "pdf_from_s3": True,
    "pdf_base_url": "",
    "focus_only": os.environ["FOCUS_ONLY"].lower() == "true",
    "docling_pdf_backend": os.environ["DOCLING_PDF_BACKEND"],
    "docling_image_export_mode": os.environ["DOCLING_IMAGE_EXPORT_MODE"],
    "docling_table_mode": os.environ["DOCLING_TABLE_MODE"],
    "docling_num_threads": int(os.environ["DOCLING_NUM_THREADS"]),
    "docling_timeout_per_document": int(os.environ["DOCLING_TIMEOUT_PER_DOCUMENT"]),
    "docling_ocr": os.environ["DOCLING_OCR"].lower() == "true",
    "docling_force_ocr": os.environ["DOCLING_FORCE_OCR"].lower() == "true",
    "docling_ocr_engine": os.environ["DOCLING_OCR_ENGINE"],
    "llama_stack_base_url": os.environ["LLAMA_STACK_BASE_URL"],
    "vector_store_name": os.environ["VECTOR_STORE_NAME"],
    "embedding_model": os.environ["EMBEDDING_MODEL"],
    "vector_provider": os.environ["VECTOR_PROVIDER"],
}
run_name = f"rhoai-product-docs-docling-{int(time.time())}"
run = kfp_client.run_pipeline(
    experiment_id=experiment_id,
    job_name=run_name,
    pipeline_id=pipeline_id,
    version_id=version_id,
    params=params,
    enable_caching=False,
)
run_id = item_id(run, "run_id", "id")
state = getattr(run, "state", "")

if os.environ["WAIT_FOR_RUN"].lower() == "true":
    run = kfp_client.wait_for_run_completion(
        run_id=run_id,
        timeout=int(os.environ["TIMEOUT_SECONDS"]),
        sleep_duration=10,
    )
    state = getattr(run, "state", "")
    if str(state).upper() not in {"SUCCEEDED", "V2BETA1RUNTIMESTATE_SUCCEEDED"}:
        raise RuntimeError(f"pipeline run did not succeed: run_id={run_id}, state={state}")

evidence = {
    "dspa_url": os.environ["DSPA_URL"],
    "experiment_id": experiment_id,
    "experiment_name": experiment_name,
    "output_s3_key": os.environ["OUTPUT_S3_KEY"],
    "pipeline_id": pipeline_id,
    "pipeline_name": pipeline_name,
    "pipeline_version_id": version_id,
    "pipeline_version_name": pipeline_version_name,
    "run_id": run_id,
    "run_name": run_name,
    "run_state": str(state),
    "s3_source_prefix": os.environ["SOURCE_PREFIX"],
}
Path(os.environ["RUN_EVIDENCE_JSON"]).write_text(json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8")
print(json.dumps(evidence, indent=2, sort_keys=True))
PY

RUN_ID="$(jq -r '.run_id' "$RUN_EVIDENCE_JSON")"
if [[ "$WAIT_FOR_RUN" == "true" ]]; then
  review_s3_artifact "$RUN_ID" "$REVIEW_LOGS"
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

echo "✓ RHOAI product-document Docling KFP run evidence stored in ConfigMap ${RAG_NS}/${EVIDENCE_CM}"
