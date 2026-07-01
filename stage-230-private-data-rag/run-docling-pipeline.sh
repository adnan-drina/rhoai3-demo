#!/usr/bin/env bash
# Run the Stage 230 Docling preparation pipeline through RHOAI AI Pipelines.
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
PIPELINE_NAME="${RHOAI_STAGE230_DOCLING_PIPELINE_NAME:-stage-230-dutch-publication-docling}"
EXPERIMENT_NAME="${RHOAI_STAGE230_DOCLING_EXPERIMENT_NAME:-stage-230-private-data-rag}"
PIPELINE_S3_SECRET="${RHOAI_STAGE230_PIPELINE_S3_SECRET:-data-processing-docling-pipeline}"
S3_PDF_KEY="${RHOAI_STAGE230_DOCLING_INPUT_KEY:-raw/dutch-government/stb-2022-14.pdf}"
OUTPUT_S3_KEY="${RHOAI_STAGE230_DOCLING_OUTPUT_KEY:-processed/dutch-government/stb-2022-14-docling-kfp-chunks.jsonl}"
SOURCE_FILENAME="${RHOAI_STAGE230_DOCLING_SOURCE_FILENAME:-stb-2022-14.pdf}"
CHUNK_MAX_TOKENS="${RHOAI_STAGE230_DOCLING_CHUNK_MAX_TOKENS:-512}"
TIMEOUT_SECONDS="${RHOAI_STAGE230_DOCLING_TIMEOUT_SECONDS:-1800}"
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
    --s3-pdf-key=*)
      S3_PDF_KEY="${arg#*=}"
      ;;
    --output-s3-key=*)
      OUTPUT_S3_KEY="${arg#*=}"
      ;;
    --chunk-max-tokens=*)
      CHUNK_MAX_TOKENS="${arg#*=}"
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

echo "✓ Cluster guard passed: ${ACTUAL_SERVER}"

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
  local output="$ROOT_DIR/artifacts/stage-230-dutch-publication-docling.yaml"

  if [[ ! -d "$venv_path" ]]; then
    python3 -m venv "$venv_path"
  fi
  "$venv_path/bin/pip" install -q --upgrade pip
  "$venv_path/bin/pip" install -q kfp==2.16.1 kfp-kubernetes==2.16.1

  mkdir -p "$ROOT_DIR/artifacts"
  "$venv_path/bin/python" "$SCRIPT_DIR/kfp/dutch_publication_docling_pipeline.py" --output "$output" >/dev/null
  if [[ ! -s "$output" ]]; then
    echo "ERROR: KFP compile did not produce ${output}." >&2
    exit 1
  fi
  printf '%s' "$output"
}

review_s3_artifact() {
  local run_id="$1"
  local review_job="stage230-docling-artifact-review"
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
              topics = sorted({record.get("topic", "") for record in records})
              required_terms = ["vier weken", "openbaarmaking", "Woo"]
              text = "\\n".join(record.get("text", "") for record in records)
              missing = [term for term in required_terms if term.casefold() not in text.casefold()]
              if missing:
                  raise SystemExit(f"processed output missing expected terms: {missing}")
              print(json.dumps({
                  "status": "pass",
                  "run_id": os.environ["RUN_ID"],
                  "bucket": os.environ["S3_BUCKET"],
                  "output_s3_key": key,
                  "record_count": len(records),
                  "topics": topics,
                  "preparation_methods": sorted({record.get("preparation_method", "") for record in records}),
              }, ensure_ascii=False, sort_keys=True))
              PY
          env:
            - name: RUN_ID
              value: "${run_id}"
            - name: OUTPUT_S3_KEY
              value: "${OUTPUT_S3_KEY}"
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
    echo "ERROR: Docling pipeline output artifact review failed." >&2
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
export DSPA_URL RAG_NS PIPELINE_YAML PIPELINE_NAME EXPERIMENT_NAME OC_TOKEN WAIT_FOR_RUN TIMEOUT_SECONDS
export S3_PDF_KEY OUTPUT_S3_KEY SOURCE_FILENAME PIPELINE_S3_SECRET CHUNK_MAX_TOKENS RUN_EVIDENCE_JSON

"$KFP_PYTHON" - <<'PY'
import json
import os
import time
from pathlib import Path

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
experiment_name = os.environ["EXPERIMENT_NAME"]
pipeline_yaml = os.environ["PIPELINE_YAML"]
run_suffix = int(time.time())

kfp_client = client.Client(
    host=os.environ["DSPA_URL"],
    namespace=namespace,
    existing_token=os.environ["OC_TOKEN"],
    verify_ssl=False,
)
kfp_client.list_pipelines(page_size=1)

pipeline_id = None
try:
    pipeline = kfp_client.upload_pipeline(
        pipeline_package_path=pipeline_yaml,
        pipeline_name=pipeline_name,
    )
    pipeline_id = item_id(pipeline, "pipeline_id", "pipeline_id")
except Exception:
    pipelines = kfp_client.list_pipelines(page_size=100).pipelines or []
    pipeline = next((candidate for candidate in pipelines if item_name(candidate) == pipeline_name), None)
    if pipeline is None:
        raise
    pipeline_id = item_id(pipeline, "pipeline_id", "id")

if not pipeline_id:
    raise RuntimeError(f"could not resolve pipeline id for {pipeline_name}")

version_name = f"v-{run_suffix}"
version = kfp_client.upload_pipeline_version(
    pipeline_package_path=pipeline_yaml,
    pipeline_version_name=version_name,
    pipeline_id=pipeline_id,
)
version_id = item_id(version, "pipeline_version_id", "id")
if not version_id:
    versions = kfp_client.list_pipeline_versions(pipeline_id=pipeline_id, sort_by="created_at desc")
    version_id = item_id(versions.pipeline_versions[0], "pipeline_version_id", "id")

try:
    experiment = kfp_client.create_experiment(name=experiment_name, namespace=namespace)
except Exception:
    experiments = kfp_client.list_experiments(namespace=namespace, page_size=100).experiments or []
    experiment = next((candidate for candidate in experiments if item_name(candidate) == experiment_name), None)
    if experiment is None:
        raise
experiment_id = item_id(experiment, "experiment_id", "id")

params = {
    "s3_pdf_key": os.environ["S3_PDF_KEY"],
    "output_s3_key": os.environ["OUTPUT_S3_KEY"],
    "source_filename": os.environ["SOURCE_FILENAME"],
    "pipeline_s3_secret_name": os.environ["PIPELINE_S3_SECRET"],
    "chunk_max_tokens": int(os.environ["CHUNK_MAX_TOKENS"]),
}
run_name = f"docling-stb-2022-14-{run_suffix}"
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
    "pipeline_version_name": version_name,
    "run_id": run_id,
    "run_name": run_name,
    "run_state": str(state),
    "s3_pdf_key": os.environ["S3_PDF_KEY"],
}
Path(os.environ["RUN_EVIDENCE_JSON"]).write_text(json.dumps(evidence, indent=2, sort_keys=True), encoding="utf-8")
print(json.dumps(evidence, indent=2, sort_keys=True))
PY

RUN_ID="$(jq -r '.run_id' "$RUN_EVIDENCE_JSON")"
if [[ "$WAIT_FOR_RUN" == "true" ]]; then
  review_s3_artifact "$RUN_ID" "$REVIEW_LOGS"
fi

oc create configmap stage230-docling-pipeline-evidence \
  -n "$RAG_NS" \
  --from-file=run-evidence.json="$RUN_EVIDENCE_JSON" \
  --from-file=artifact-review.json="$REVIEW_LOGS" \
  --dry-run=client -o yaml | oc apply -f - --insecure-skip-tls-verify=true >/dev/null
oc label configmap stage230-docling-pipeline-evidence -n "$RAG_NS" --overwrite \
  app.kubernetes.io/part-of=rag \
  app.kubernetes.io/component=pipeline-validation \
  demo.rhoai.io/stage=230 \
  --insecure-skip-tls-verify=true >/dev/null

echo "✓ Docling KFP run evidence stored in ConfigMap ${RAG_NS}/stage230-docling-pipeline-evidence"
