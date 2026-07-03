"""Fetch the best AutoRAG pattern artifacts into the workbench workspace.

Runs inside the Enterprise RAG Workbench, which exposes the Stage 230 S3
connection environment (AWS_S3_ENDPOINT, AWS_ACCESS_KEY_ID,
AWS_SECRET_ACCESS_KEY, AWS_S3_BUCKET). It locates the requested (or latest)
documents-rag-optimization-pipeline run, ranks its exported patterns by the
selected metric, and downloads the winning pattern's pattern.json,
evaluation_results.json, and generated indexing/inference notebooks into the
visible workspace for the demo handoff.

Usage (from /opt/app-root/src/workspace):

    python .stage230/scripts/fetch_autorag_pattern.py
    python .stage230/scripts/fetch_autorag_pattern.py --metric answer_correctness
    python .stage230/scripts/fetch_autorag_pattern.py --run-id <uuid> --pattern Pattern8
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import boto3
from botocore.config import Config
from urllib3 import disable_warnings
from urllib3.exceptions import InsecureRequestWarning

PIPELINE_PREFIX = "documents-rag-optimization-pipeline/"
PATTERN_FILES = ("pattern.json", "evaluation_results.json", "indexing.ipynb", "inference.ipynb")


def s3_client():
    disable_warnings(InsecureRequestWarning)
    required = ["AWS_S3_ENDPOINT", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_S3_BUCKET"]
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise SystemExit(f"missing S3 environment variables: {missing}")
    return boto3.client(
        "s3",
        endpoint_url=os.environ["AWS_S3_ENDPOINT"],
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        verify=False,
        config=Config(signature_version="s3v4"),
    )


def list_keys(client, bucket: str, prefix: str) -> list[dict]:
    entries: list[dict] = []
    for page in client.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefix):
        entries.extend(page.get("Contents", []))
    return entries


def latest_run_id(client, bucket: str) -> str:
    runs: dict[str, object] = {}
    for entry in list_keys(client, bucket, PIPELINE_PREFIX):
        parts = entry["Key"].split("/")
        if len(parts) > 1 and parts[1]:
            stamp = runs.get(parts[1])
            if stamp is None or entry["LastModified"] > stamp:
                runs[parts[1]] = entry["LastModified"]
    if not runs:
        raise SystemExit(f"no runs found under s3://{bucket}/{PIPELINE_PREFIX}")
    return max(runs, key=lambda run: runs[run])


def rank_patterns(client, bucket: str, run_id: str, metric: str) -> list[tuple[str, float, dict]]:
    ranked = []
    for entry in list_keys(client, bucket, f"{PIPELINE_PREFIX}{run_id}/"):
        if not entry["Key"].endswith("/pattern.json"):
            continue
        data = json.loads(client.get_object(Bucket=bucket, Key=entry["Key"])["Body"].read())
        scores = data.get("scores") or data.get("metrics") or {}
        value = scores.get(metric)
        mean = value.get("mean") if isinstance(value, dict) else value
        if mean is None:
            continue
        ranked.append((entry["Key"].rsplit("/", 1)[0], float(mean), data))
    if not ranked:
        raise SystemExit(f"no scored patterns found for run {run_id}")
    ranked.sort(key=lambda item: item[1], reverse=True)
    return ranked


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", default="", help="Pipeline run id (default: latest run)")
    parser.add_argument("--metric", default="faithfulness",
                        choices=["faithfulness", "answer_correctness", "context_correctness"])
    parser.add_argument("--pattern", default="", help="Pattern name override (e.g. Pattern8)")
    parser.add_argument("--output", default="autorag", help="Workspace-relative output directory")
    args = parser.parse_args()

    client = s3_client()
    bucket = os.environ["AWS_S3_BUCKET"]
    run_id = args.run_id or latest_run_id(client, bucket)
    ranked = rank_patterns(client, bucket, run_id, args.metric)

    print(f"run {run_id} — patterns ranked by {args.metric}:")
    for prefix, mean, data in ranked:
        settings = data.get("settings", {})
        generation = (settings.get("generation") or {}).get("model_id", "?")
        embedding = (settings.get("embedding") or {}).get("model_id", "?")
        print(f"  {data.get('name')}: {args.metric}={mean:.3f} gen={generation} emb={embedding}")

    if args.pattern:
        selected = next((item for item in ranked if item[2].get("name") == args.pattern), None)
        if selected is None:
            raise SystemExit(f"pattern {args.pattern} not found in run {run_id}")
    else:
        selected = ranked[0]
    prefix, mean, data = selected

    out_dir = Path(args.output) / data.get("name", "pattern")
    out_dir.mkdir(parents=True, exist_ok=True)
    fetched = []
    for name in PATTERN_FILES:
        key = f"{prefix}/{name}"
        try:
            client.download_file(bucket, key, str(out_dir / name))
            fetched.append(name)
        except Exception:
            print(f"  (skipping missing artifact {name})", file=sys.stderr)
    print(f"\nfetched {data.get('name')} ({args.metric}={mean:.3f}) -> {out_dir}/ [{', '.join(fetched)}]")
    print("Open indexing.ipynb to (re)build the pattern's vector index and "
          "inference.ipynb to ask questions with the optimized configuration.")


if __name__ == "__main__":
    main()
