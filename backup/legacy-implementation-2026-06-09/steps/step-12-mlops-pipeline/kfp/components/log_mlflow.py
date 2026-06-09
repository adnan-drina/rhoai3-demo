"""Log the training run to the RHOAI 3.4 MLflow tracking server."""

from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.4.0",
    packages_to_install=[
        "boto3>=1.34.0",
        "mlflow[kubernetes]>=3.1.0,<4",
    ],
    pip_index_urls=["https://pypi.org/simple"],
)
def log_mlflow_run(
    onnx_path: str,
    mAP50: float,
    model_name: str,
    version: str,
    minio_endpoint: str,
    epochs: int,
    mAP_threshold: float,
    max_user_photos: int,
    max_unknown_photos: int,
    num_hf_portraits: int,
    mlflow_tracking_uri: str = "https://mlflow.redhat-ods-applications.svc:8443",
    mlflow_workspace: str = "enterprise-mlops",
) -> str:
    """Create an MLflow run and log metrics, params, tags, and compact artifacts.

    RHOAI 3.4 documents the MLflow SDK's kubernetes-namespaced auth plugin for
    pod-to-MLflow access. The pipeline pod runs in enterprise-mlops, where the
    MLflowConfig sets the S3 artifact root for new runs.
    """
    import hashlib
    import json
    import os
    import time
    from pathlib import Path

    from mlflow.entities import Metric, Param, RunTag
    from mlflow.tracking import MlflowClient

    shared = Path("/shared-data")
    metrics_file = shared / "metrics" / "results.json"
    model_path = Path(onnx_path)
    experiment_name = model_name
    run_name = f"{model_name}-{version}"

    if not metrics_file.exists():
        raise RuntimeError(f"metrics file not found: {metrics_file}")

    metrics_data = json.loads(metrics_file.read_text())
    metrics_data.setdefault("mAP50", float(mAP50))

    model_sha256 = ""
    model_size_bytes = 0
    if model_path.exists():
        model_size_bytes = model_path.stat().st_size
        hasher = hashlib.sha256()
        with model_path.open("rb") as model_file:
            for chunk in iter(lambda: model_file.read(1024 * 1024), b""):
                hasher.update(chunk)
        model_sha256 = hasher.hexdigest()

    threshold = float(metrics_data.get("mAP_threshold", mAP_threshold))
    profile = "smoke" if epochs <= 5 or threshold <= 0.0 else "quality-gated"
    metrics_data.update({
        "mAP50_pct": round(100.0 * float(metrics_data.get("mAP50", mAP50)), 4),
        "mAP50_95_pct": round(100.0 * float(metrics_data.get("mAP50_95", 0.0)), 4),
        "adnan_mAP50_pct": round(100.0 * float(metrics_data.get("adnan_mAP50", 0.0)), 4),
        "mAP_threshold_pct": round(100.0 * threshold, 4),
        "quality_gate_margin_pct": round(
            100.0 * float(metrics_data.get("quality_gate_margin", float(mAP50) - threshold)),
            4,
        ),
    })

    numeric_metrics = {}
    for key, value in metrics_data.items():
        try:
            numeric_metrics[str(key)] = float(value)
        except (TypeError, ValueError):
            pass

    params = {
        "model_name": model_name,
        "version": version,
        "onnx_path": onnx_path,
        "model_size_bytes": str(model_size_bytes),
        "training_profile": profile,
        "epochs": str(epochs),
        "mAP_threshold": str(threshold),
        "max_user_photos": str(max_user_photos),
        "max_unknown_photos": str(max_unknown_photos),
        "num_hf_portraits": str(num_hf_portraits),
    }
    if model_sha256:
        params["model_sha256"] = model_sha256

    os.environ.setdefault("MLFLOW_TRACKING_URI", mlflow_tracking_uri)
    os.environ.setdefault("MLFLOW_TRACKING_AUTH", "kubernetes-namespaced")
    os.environ.setdefault("MLFLOW_TRACKING_INSECURE_TLS", "true")
    # The kubernetes-namespaced auth plugin derives the workspace from the pod
    # namespace. Do not set MLFLOW_WORKSPACE; the RHOAI server does not expose
    # MLflow OSS workspace mode.
    os.environ.pop("MLFLOW_WORKSPACE", None)
    os.environ.setdefault("MLFLOW_S3_ENDPOINT_URL", minio_endpoint)
    os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")

    artifact_dir = shared / "mlflow-artifacts"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    context_file = artifact_dir / "run-context.json"

    tags = {
        "rhoai.demo.step": "12",
        "rhoai.demo.pipeline": "face-recognition-training",
        "rhoai.demo.model_name": model_name,
        "rhoai.demo.version": version,
        "rhoai.demo.quality_gate": "passed",
        "rhoai.demo.training_profile": profile,
    }

    client = MlflowClient(tracking_uri=mlflow_tracking_uri)
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
    run_id = run.info.run_id

    try:
        context_file.write_text(json.dumps({
            "run_id": run_id,
            "experiment_id": experiment_id,
            "artifact_uri": run.info.artifact_uri,
            "model_name": model_name,
            "version": version,
            "onnx_path": onnx_path,
            "model_size_bytes": model_size_bytes,
            "model_sha256": model_sha256,
            "metrics": metrics_data,
        }, indent=2))

        now_ms = int(time.time() * 1000)
        metric_entities = [
            Metric(key=key, value=value, timestamp=now_ms, step=0)
            for key, value in numeric_metrics.items()
        ]
        param_entities = [
            Param(key=key, value=value)
            for key, value in params.items()
        ]
        tag_entities = [
            RunTag(key=key, value=value)
            for key, value in tags.items()
        ]
        client.log_batch(
            run_id=run_id,
            metrics=metric_entities,
            params=param_entities,
            tags=tag_entities,
        )
        client.log_artifact(run_id, str(metrics_file), artifact_path="evidence")
        client.log_artifact(run_id, str(context_file), artifact_path="evidence")
        client.set_terminated(run_id, status="FINISHED")
    except Exception:
        client.set_terminated(run_id, status="FAILED")
        raise

    print(f"MLflow run logged: experiment={experiment_id} run={run_id}")
    return run_id
