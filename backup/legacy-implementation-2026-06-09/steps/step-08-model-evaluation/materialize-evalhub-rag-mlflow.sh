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


def short_text(value: Any, limit: int = 480) -> str:
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    if len(text) <= limit:
        return text
    return f"{text[: limit - 3]}..."


def as_metric_dict(raw_metrics: Any) -> dict[str, Any]:
    if isinstance(raw_metrics, dict):
        return dict(raw_metrics)
    if not isinstance(raw_metrics, list):
        return {}

    metrics: dict[str, Any] = {}
    for item in raw_metrics:
        if not isinstance(item, dict):
            continue
        name = (
            item.get("metric_name")
            or item.get("name")
            or item.get("key")
            or item.get("metric")
        )
        if not name:
            continue
        if "metric_value" in item:
            value = item.get("metric_value")
        elif "value" in item:
            value = item.get("value")
        else:
            value = item.get("score")
        metrics[str(name)] = value
    return metrics


def ensure_experiment_id(experiment_name: str, candidate_id: str = "") -> str:
    if candidate_id:
        return candidate_id

    experiments = mlflow_post(
        "/api/2.0/mlflow/experiments/search",
        {"filter": f"name = '{experiment_name}'", "max_results": 1},
    ).get("experiments", [])
    if experiments:
        return str(experiments[0]["experiment_id"])

    created = mlflow_post(
        "/api/2.0/mlflow/experiments/create",
        {"name": experiment_name},
    )
    experiment_id = created.get("experiment_id")
    if not experiment_id:
        raise RuntimeError(f"MLflow did not create experiment {experiment_name}: {created}")
    return str(experiment_id)


def benchmark_artifacts(benchmark: dict[str, Any]) -> dict[str, Any]:
    artifacts = benchmark.get("artifacts")
    if isinstance(artifacts, dict):
        return artifacts

    metadata = benchmark.get("metadata")
    if isinstance(metadata, dict):
        nested = metadata.get("artifacts")
        if isinstance(nested, dict):
            return nested

    evaluation_metadata = benchmark.get("evaluation_metadata")
    if isinstance(evaluation_metadata, dict):
        nested = evaluation_metadata.get("artifacts")
        if isinstance(nested, dict):
            return nested

    return {}


def benchmark_metrics(benchmark: dict[str, Any]) -> dict[str, Any]:
    metrics = as_metric_dict(benchmark.get("metrics") or benchmark.get("results"))
    test = benchmark.get("test") or {}
    summary = benchmark_artifacts(benchmark).get("rag_scenario_summary") or {}
    scenario_results = benchmark_artifacts(benchmark).get("rag_scenario_results") or []

    for key, value in summary.items():
        if key in {"letter_counts", "grade_counts", "pass_letters", "completed_at", "scenario", "mode"}:
            continue
        if numeric(value) is not None:
            metrics.setdefault(key, value)

    letter_counts = summary.get("letter_counts") or {}
    if isinstance(letter_counts, dict):
        for letter, count in letter_counts.items():
            suffix = "unknown" if letter == "?" else str(letter).lower()
            metrics.setdefault(f"grade_{suffix}_count", count)

    pass_rate = numeric(metrics.get("pass_rate"))
    if pass_rate is not None:
        metrics.setdefault("pass_rate_percent", pass_rate * 100.0)
    mean_judge_score = numeric(metrics.get("mean_judge_score"))
    if mean_judge_score is not None:
        metrics.setdefault("mean_judge_score_percent", mean_judge_score * 100.0)

    questions_total = numeric(metrics.get("questions_total") or metrics.get("tests_total"))
    questions_passed = numeric(metrics.get("questions_passed") or metrics.get("tests_passed"))
    if questions_total is not None and questions_passed is not None:
        metrics.setdefault("questions_failed", max(questions_total - questions_passed, 0.0))

    metrics["threshold"] = test.get("threshold")
    metrics["benchmark_pass"] = test.get("pass")

    if isinstance(scenario_results, list):
        for fallback_index, result in enumerate(scenario_results, 1):
            if not isinstance(result, dict):
                continue
            index = int(result.get("index") or fallback_index)
            prefix = f"q{index:02d}"
            metrics[f"{prefix}_judge_score"] = result.get("judge_score")
            metrics[f"{prefix}_passed"] = result.get("passed")
            tool_score = result.get("tool_score") or {}
            if isinstance(tool_score, dict):
                metrics[f"{prefix}_tool_score"] = tool_score.get("score")
    return metrics


def benchmark_params(
    benchmark: dict[str, Any],
    summary: dict[str, Any],
    scenario_results: list[dict[str, Any]],
) -> dict[str, Any]:
    params = {
        "evalhub_job_id": job_id,
        "benchmark_id": benchmark.get("id", "unknown"),
        "provider_id": benchmark.get("provider_id", ""),
        "scenario": summary.get("scenario", benchmark.get("id", "unknown")),
        "mode": summary.get("mode", ""),
        "model_name": (job.get("model") or {}).get("name", ""),
        "questions_total": summary.get("questions_total", summary.get("tests_total", "")),
        "questions_passed": summary.get("questions_passed", summary.get("tests_passed", "")),
        "questions_failed": summary.get("questions_failed", summary.get("tests_failed", "")),
        "pass_letters": ",".join(str(item) for item in summary.get("pass_letters", [])),
    }

    for result in scenario_results:
        if not isinstance(result, dict):
            continue
        index = int(result.get("index") or 0)
        if index <= 0:
            continue
        prefix = f"q{index:02d}"
        params[f"{prefix}_prompt"] = short_text(result.get("prompt"), 260)
        params[f"{prefix}_grade"] = result.get("judge_letter", "")
        params[f"{prefix}_passed"] = result.get("passed", "")
        params[f"{prefix}_answer"] = short_text(result.get("answer"), 360)
        params[f"{prefix}_expected"] = short_text(result.get("expected"), 360)
        params[f"{prefix}_judge_feedback"] = short_text(result.get("judge_feedback"), 420)
        params[f"{prefix}_tools_called"] = ",".join(str(item) for item in result.get("tool_calls", []))
        params[f"{prefix}_tools_expected"] = ",".join(str(item) for item in result.get("expected_tools", []))

    return params


def default_experiment_name_for(benchmarks: list[dict[str, Any]]) -> str:
    if len(benchmarks) != 1:
        return "evalhub-rag-pre-post"

    benchmark_id = benchmarks[0].get("id", "")
    scenario_experiments = {
        "acme_corporate_pre_rag": "evalhub-acme-corporate-pre-rag",
        "acme_corporate_post_rag": "evalhub-acme-corporate-post-rag",
        "whoami_pre_rag": "evalhub-whoami-pre-rag",
        "whoami_post_rag": "evalhub-whoami-post-rag",
    }
    return scenario_experiments.get(str(benchmark_id), "evalhub-rag-pre-post")


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
benchmarks = results.get("benchmarks") or []
if not benchmarks:
    raise RuntimeError(f"EvalHub job {job_id} has no benchmark results")

experiment_id = str(resource.get("mlflow_experiment_id") or "").strip()
experiment_name = experiment.get("name") or default_experiment_name_for(benchmarks)
experiment_id = ensure_experiment_id(experiment_name, experiment_id)

seen = existing_run_keys(experiment_id)
created: list[tuple[str, str]] = []
start_ms = iso_to_ms(resource.get("created_at"))
end_ms = int(time.time() * 1000)
single_benchmark_job = len(benchmarks) == 1

base_tags = {
    "rhoai.demo.step": "08",
    "rhoai.demo.capability": "evalhub-rag-scenario-evaluation",
    "context": "eval-hub",
    "evalhub.job_id": job_id,
    "evalhub.job_name": job.get("name", ""),
    "evalhub.experiment_name": experiment_name,
    "evalhub.evaluation_style": "independent" if single_benchmark_job else "grouped",
}

summary_key = ("summary", "")
if not single_benchmark_job and summary_key not in seen:
    summary_metrics: dict[str, Any] = {
        "collection_score": (results.get("test") or {}).get("score"),
        "collection_pass": (results.get("test") or {}).get("pass"),
        "benchmarks_total": len(benchmarks),
    }
    for benchmark in benchmarks:
        benchmark_id = benchmark.get("id", "unknown")
        for key, value in benchmark_metrics(benchmark).items():
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
    run_kind = "evaluation" if single_benchmark_job else "benchmark"
    key = (run_kind, benchmark_id)
    if key in seen:
        continue

    artifacts = benchmark_artifacts(benchmark)
    summary = artifacts.get("rag_scenario_summary") or {}
    scenario_results = artifacts.get("rag_scenario_results") or []
    if not isinstance(scenario_results, list):
        scenario_results = []

    metrics = benchmark_metrics(benchmark)
    test = benchmark.get("test") or {}
    params = benchmark_params(benchmark, summary, scenario_results)
    params["threshold"] = test.get("threshold", "")
    run_id = create_run(
        experiment_id,
        f"evalhub-{benchmark_id}-{job_short}",
        {
            **base_tags,
            "evalhub.run_kind": run_kind,
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
