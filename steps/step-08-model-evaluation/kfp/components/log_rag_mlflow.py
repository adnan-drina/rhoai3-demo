"""Log RAG evaluation evidence to the RHOAI 3.4 MLflow tracking server."""

from typing import Any, Dict, List
from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.4.0",
    packages_to_install=[
        "boto3>=1.34.0",
        "mlflow[kubernetes]>=3.1.0,<4",
    ],
    pip_index_urls=["https://pypi.org/simple"],
)
def log_rag_mlflow_component(
    summary: List[Dict[str, Any]],
    run_id: str,
    llamastack_url: str,
    minio_console_url: str,
    mlflow_tracking_uri: str = "https://mlflow.redhat-ods-applications.svc:8443",
    enable_mlflow_tracking: bool = True,
) -> str:
    """Create an enterprise-rag MLflow run for RAG quality evidence.

    The component uses RHOAI MLflow's kubernetes-namespaced authentication
    plugin. If the cluster-scoped MLflow server is not deployed yet, logging is
    skipped so Step 08 remains runnable before the MLOps foundation step.
    """
    import json
    import os
    import re
    import time
    from pathlib import Path

    from mlflow.entities import Metric, Param, RunTag
    from mlflow.tracking import MlflowClient

    if not enable_mlflow_tracking:
        print("MLflow tracking disabled by pipeline parameter")
        return "disabled"

    if not summary:
        print("No RAG evaluation summary received; skipping MLflow logging")
        return "skipped-empty-summary"

    def safe_key(value: str) -> str:
        return re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_")[:180] or "unknown"

    def quality_counts(mode: str) -> tuple[int, int]:
        good = 0
        total = 0
        for item in summary:
            if item.get("mode") != mode:
                continue
            scores = item.get("scores", {})
            good += int(scores.get("A", 0)) + int(scores.get("B", 0))
            total += int(item.get("tests", 0))
        return good, total

    pre_good, pre_total = quality_counts("pre-rag")
    post_good, post_total = quality_counts("post-rag")

    metrics_data: dict[str, float] = {
        "scenarios": float(len(summary)),
        "total_tests": float(sum(int(item.get("tests", 0)) for item in summary)),
        "pre_rag_good_answers": float(pre_good),
        "pre_rag_total_answers": float(pre_total),
        "post_rag_good_answers": float(post_good),
        "post_rag_total_answers": float(post_total),
    }
    if pre_total:
        metrics_data["pre_rag_quality_pct"] = round(100.0 * pre_good / pre_total, 4)
    if post_total:
        metrics_data["post_rag_quality_pct"] = round(100.0 * post_good / post_total, 4)
    if pre_total and post_total:
        metrics_data["rag_improvement_pp"] = round(
            metrics_data["post_rag_quality_pct"] - metrics_data["pre_rag_quality_pct"],
            4,
        )

    for item in summary:
        tests = int(item.get("tests", 0))
        scores = item.get("scores", {})
        good = int(scores.get("A", 0)) + int(scores.get("B", 0))
        if tests:
            metric_name = f"scenario_{safe_key(item.get('scenario', 'unknown'))}_{safe_key(item.get('mode', 'unknown'))}_quality_pct"
            metrics_data[metric_name] = round(100.0 * good / tests, 4)

    os.environ.setdefault("MLFLOW_TRACKING_URI", mlflow_tracking_uri)
    os.environ.setdefault("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    os.environ.setdefault("MLFLOW_TRACKING_INSECURE_TLS", "true")
    os.environ.pop("MLFLOW_WORKSPACE", None)

    s3_endpoint = os.environ.get("AWS_S3_ENDPOINT", "")
    if s3_endpoint:
        os.environ.setdefault(
            "MLFLOW_S3_ENDPOINT_URL",
            s3_endpoint if s3_endpoint.startswith("http") else f"http://{s3_endpoint}",
        )
    os.environ.setdefault("AWS_DEFAULT_REGION", os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))

    experiment_name = "enterprise-rag"
    run_name = f"rag-eval-{run_id}"
    tags = {
        "rhoai.demo.step": "08",
        "rhoai.demo.pipeline": "rag-eval",
        "rhoai.demo.capability": "enterprise-rag-evaluation",
        "rhoai.demo.candidate_model": "granite-8b-agent",
        "rhoai.demo.judge_model": "mistral-3-bf16",
        "rhoai.demo.evidence": "pre-post-rag-quality",
        "rhoai.docs.rhoai34": "evaluating-rag-systems-with-ragas,working-with-mlflow",
        "rh-brain.pattern": "rag-evaluation-plus-mlflow-tracking",
    }
    params = {
        "run_id": run_id,
        "llamastack_url": llamastack_url,
        "candidate_model": "granite-8b-agent",
        "judge_model": "mistral-3-bf16",
        "evaluation_mode": "pre-rag-vs-post-rag",
        "score_good_letters": "A,B",
        "report_prefix": f"s3://rhoai-storage/eval-results/{run_id}/",
        "minio_console_url": minio_console_url,
    }

    artifact_dir = Path("/tmp/rag-mlflow-artifacts")
    artifact_dir.mkdir(parents=True, exist_ok=True)
    summary_file = artifact_dir / "rag-eval-summary.json"
    context_file = artifact_dir / "rag-eval-context.json"
    references_file = artifact_dir / "rag-eval-references.json"

    summary_file.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")
    context_file.write_text(json.dumps({
        "run_id": run_id,
        "experiment_name": experiment_name,
        "run_name": run_name,
        "metrics": metrics_data,
        "params": params,
        "tags": tags,
    }, indent=2, sort_keys=True), encoding="utf-8")
    references_file.write_text(json.dumps({
        "official_docs": [
            "https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate",
            "https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow/index",
        ],
        "rh_brain_sources": [
            "raw/Synthetic data for RAG evaluation Why your RAG system needs better testing.md",
            "raw/Evaluation Quickstart  MLflow AI Platform.md",
            "raw/Evaluating (Production) Traces  MLflow AI Platform 1.md",
            "raw/Build resilient guardrails for OpenClaw AI agents on Kubernetes 1.md",
        ],
    }, indent=2, sort_keys=True), encoding="utf-8")

    client = MlflowClient(tracking_uri=mlflow_tracking_uri)
    run_id_mlflow = ""
    try:
        experiments = client.search_experiments(filter_string=f'name = "{experiment_name}"')
        if experiments:
            experiment_id = experiments[0].experiment_id
        else:
            experiment_id = client.create_experiment(experiment_name)

        run = client.create_run(
            experiment_id=experiment_id,
            tags=tags,
            run_name=run_name,
        )
        run_id_mlflow = run.info.run_id
        now_ms = int(time.time() * 1000)

        client.log_batch(
            run_id=run_id_mlflow,
            metrics=[
                Metric(key=key, value=float(value), timestamp=now_ms, step=0)
                for key, value in metrics_data.items()
            ],
            params=[
                Param(key=key, value=str(value)[:500])
                for key, value in params.items()
            ],
            tags=[
                RunTag(key=key, value=value)
                for key, value in tags.items()
            ],
        )
        client.log_artifact(run_id_mlflow, str(summary_file), artifact_path="evidence")
        client.log_artifact(run_id_mlflow, str(context_file), artifact_path="evidence")
        client.log_artifact(run_id_mlflow, str(references_file), artifact_path="evidence")
        client.set_terminated(run_id_mlflow, status="FINISHED")
    except Exception as exc:
        if run_id_mlflow:
            try:
                client.set_terminated(run_id_mlflow, status="FAILED")
            except Exception:
                pass
        print(f"MLflow logging skipped or failed non-blocking: {exc}")
        return f"skipped: {exc}"

    print(f"RAG MLflow run logged: experiment={experiment_name} run={run_id_mlflow}")
    return run_id_mlflow
