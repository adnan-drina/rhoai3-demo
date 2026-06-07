#!/usr/bin/env bash
# Materialize an EvalHub RAG scenario job into MLflow runs visible in the RHOAI dashboard.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/scripts/lib.sh"

NAMESPACE="${NAMESPACE:-enterprise-rag}"
EVALHUB_NAMESPACE="${EVALHUB_NAMESPACE:-redhat-ods-applications}"
JOB_ID="${1:-}"

if [[ -z "$JOB_ID" ]]; then
    log_error "Usage: $0 <evalhub-job-id>"
    exit 1
fi

check_oc_logged_in

ROUTE_HOST="$(oc get route evalhub -n "$EVALHUB_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
if [[ -n "$ROUTE_HOST" ]]; then
    EVALHUB_URL="${EVALHUB_URL:-https://${ROUTE_HOST}}"
else
    EVALHUB_URL="$(oc get evalhub evalhub -n "$EVALHUB_NAMESPACE" -o jsonpath='{.status.url}' 2>/dev/null || true)"
fi

if [[ -z "$EVALHUB_URL" ]]; then
    log_error "EvalHub URL could not be resolved"
    exit 1
fi

MLFLOW_URL="$(oc get mlflow mlflow -o jsonpath='{.status.url}' 2>/dev/null || true)"
if [[ -z "$MLFLOW_URL" ]]; then
    log_error "MLflow URL could not be resolved"
    exit 1
fi

TOKEN="$(oc whoami -t)"

log_step "Materializing EvalHub RAG job $JOB_ID into MLflow"
EVALHUB_URL="$EVALHUB_URL" \
MLFLOW_URL="$MLFLOW_URL" \
OPENSHIFT_TOKEN="$TOKEN" \
NAMESPACE="$NAMESPACE" \
JOB_ID="$JOB_ID" \
python3 <<'PY'
from __future__ import annotations

import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from typing import Any


evalhub_url = os.environ["EVALHUB_URL"].rstrip("/")
mlflow_url = os.environ["MLFLOW_URL"].rstrip("/")
token = os.environ["OPENSHIFT_TOKEN"]
namespace = os.environ["NAMESPACE"]
job_id = os.environ["JOB_ID"]
job_short = job_id.split("-")[0]
context = ssl._create_unverified_context()


def request_json(method: str, url: str, payload: dict[str, Any] | None = None, *, mlflow: bool = False) -> dict[str, Any]:
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    if mlflow:
        headers["x-mlflow-workspace"] = namespace
    else:
        headers["X-Tenant"] = namespace

    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, context=context, timeout=60) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {url} failed: HTTP {exc.code}: {body}") from exc
    return json.loads(raw) if raw else {}


def mlflow_post(path: str, payload: dict[str, Any]) -> dict[str, Any]:
    return request_json("POST", f"{mlflow_url}{path}", payload, mlflow=True)


def safe_key(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_")[:180] or "unknown"


def iso_to_ms(value: str | None) -> int:
    if not value:
        return int(time.time() * 1000)
    try:
        return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return int(time.time() * 1000)


def numeric(value: Any) -> float | None:
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    if isinstance(value, (int, float)):
        return float(value)
    return None


def existing_run_keys(experiment_id: str) -> set[tuple[str, str]]:
    runs = mlflow_post(
        "/api/2.0/mlflow/runs/search",
        {
            "experiment_ids": [experiment_id],
            "max_results": 500,
            "order_by": ["attributes.start_time DESC"],
        },
    ).get("runs", [])
    keys: set[tuple[str, str]] = set()
    for run in runs:
        tags = {
            item.get("key"): item.get("value")
            for item in run.get("data", {}).get("tags", [])
        }
        if tags.get("evalhub.job_id") == job_id:
            keys.add((tags.get("evalhub.run_kind", ""), tags.get("evalhub.benchmark_id", "")))
    return keys


def create_run(
    experiment_id: str,
    run_name: str,
    tags: dict[str, str],
    params: dict[str, Any],
    metrics: dict[str, Any],
    start_time: int,
    end_time: int,
) -> str:
    create = mlflow_post(
        "/api/2.0/mlflow/runs/create",
        {
            "experiment_id": experiment_id,
            "start_time": start_time,
            "run_name": run_name,
            "tags": [{"key": key, "value": str(value)[:5000]} for key, value in tags.items()],
        },
    )
    run_id = create.get("run", {}).get("info", {}).get("run_id")
    if not run_id:
        raise RuntimeError(f"MLflow did not return a run id for {run_name}: {create}")

    metric_rows = []
    for key, value in metrics.items():
        metric_value = numeric(value)
        if metric_value is not None:
            metric_rows.append(
                {
                    "key": safe_key(key),
                    "value": metric_value,
                    "timestamp": end_time,
                    "step": 0,
                }
            )

    mlflow_post(
        "/api/2.0/mlflow/runs/log-batch",
        {
            "run_id": run_id,
            "metrics": metric_rows,
            "params": [
                {"key": safe_key(key), "value": str(value)[:500]}
                for key, value in params.items()
            ],
            "tags": [{"key": key, "value": str(value)[:5000]} for key, value in tags.items()],
        },
    )
    mlflow_post(
        "/api/2.0/mlflow/runs/update",
        {
            "run_id": run_id,
            "status": "FINISHED",
            "end_time": end_time,
        },
    )
    return run_id


job = request_json("GET", f"{evalhub_url}/api/v1/evaluations/jobs/{job_id}")
resource = job.get("resource") or {}
results = job.get("results") or {}
experiment = job.get("experiment") or {}
experiment_id = str(resource.get("mlflow_experiment_id") or "")
experiment_name = experiment.get("name") or "evalhub-rag-pre-post"
if not experiment_id:
    experiments = mlflow_post(
        "/api/2.0/mlflow/experiments/search",
        {"filter": f"name = '{experiment_name}'", "max_results": 1},
    ).get("experiments", [])
    if not experiments:
        raise RuntimeError(f"MLflow experiment not found: {experiment_name}")
    experiment_id = str(experiments[0]["experiment_id"])

benchmarks = results.get("benchmarks") or []
if not benchmarks:
    raise RuntimeError(f"EvalHub job {job_id} has no benchmark results")

seen = existing_run_keys(experiment_id)
created: list[tuple[str, str]] = []
start_ms = iso_to_ms(resource.get("created_at"))
end_ms = int(time.time() * 1000)

base_tags = {
    "rhoai.demo.step": "08",
    "rhoai.demo.capability": "evalhub-rag-scenario-evaluation",
    "context": "eval-hub",
    "evalhub.job_id": job_id,
    "evalhub.job_name": job.get("name", ""),
    "evalhub.experiment_name": experiment_name,
}

summary_key = ("summary", "")
if summary_key not in seen:
    summary_metrics: dict[str, Any] = {
        "collection_score": (results.get("test") or {}).get("score"),
        "collection_pass": (results.get("test") or {}).get("pass"),
        "benchmarks_total": len(benchmarks),
    }
    for benchmark in benchmarks:
        benchmark_id = benchmark.get("id", "unknown")
        for key, value in (benchmark.get("metrics") or {}).items():
            metric_value = numeric(value)
            if metric_value is not None:
                summary_metrics[f"{benchmark_id}_{key}"] = metric_value
    run_id = create_run(
        experiment_id,
        f"evalhub-rag-pre-post-summary-{job_short}",
        {**base_tags, "evalhub.run_kind": "summary"},
        {
            "evalhub_job_id": job_id,
            "evalhub_job_name": job.get("name", ""),
            "model_name": (job.get("model") or {}).get("name", ""),
            "collection": "rhoai-rag-pre-post-v1",
        },
        summary_metrics,
        start_ms,
        end_ms,
    )
    created.append(("summary", run_id))

for benchmark in sorted(benchmarks, key=lambda item: item.get("benchmark_index", 0)):
    benchmark_id = benchmark.get("id", "unknown")
    key = ("benchmark", benchmark_id)
    if key in seen:
        continue

    metrics = dict(benchmark.get("metrics") or {})
    test = benchmark.get("test") or {}
    metrics["threshold"] = test.get("threshold")
    metrics["benchmark_pass"] = test.get("pass")
    summary = (benchmark.get("artifacts") or {}).get("rag_scenario_summary") or {}
    params = {
        "evalhub_job_id": job_id,
        "benchmark_id": benchmark_id,
        "provider_id": benchmark.get("provider_id", ""),
        "scenario": summary.get("scenario", benchmark_id),
        "mode": summary.get("mode", ""),
        "model_name": (job.get("model") or {}).get("name", ""),
        "threshold": test.get("threshold", ""),
        "tests_total": metrics.get("tests_total", ""),
        "tests_passed": metrics.get("tests_passed", ""),
    }
    run_id = create_run(
        experiment_id,
        f"evalhub-{benchmark_id}-{job_short}",
        {
            **base_tags,
            "evalhub.run_kind": "benchmark",
            "evalhub.benchmark_id": benchmark_id,
            "evalhub.scenario": str(summary.get("scenario", benchmark_id)),
            "evalhub.mode": str(summary.get("mode", "")),
        },
        params,
        metrics,
        start_ms,
        end_ms,
    )
    created.append((benchmark_id, run_id))

if created:
    for name, run_id in created:
        print(f"created {name}: {run_id}")
else:
    print(f"MLflow runs already exist for EvalHub job {job_id}")
PY
