"""Evaluate the trained ONNX model, compute mAP50, compare with previous
version from Model Registry. Raises exception if below threshold."""

from kfp.dsl import component, Output, Metrics


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    packages_to_install=[
        "ultralytics>=8.3.0",
        "opencv-python-headless>=4.10.0",
        "model-registry>=0.3.7",
    ],
)
def evaluate_model(
    onnx_path: str,
    mAP_threshold: float,
    registry_url: str,
    model_name: str,
    metrics: Output[Metrics],
) -> float:
    """Evaluate the ONNX model, compute mAP50, and enforce quality gate.

    Args:
        onnx_path: Path to the ONNX model on the shared PVC.
        mAP_threshold: Minimum mAP50 required to pass the quality gate.
        registry_url: Model Registry REST endpoint for comparing with previous version.
        model_name: Registered model name to look up prior metrics.
        metrics: KFP Metrics artifact for Dashboard visibility.

    Returns:
        The mAP50 score. Raises RuntimeError if below threshold.
    """
    import subprocess
    from pathlib import Path

    subprocess.run(["pip", "install", "--force-reinstall", "--no-deps", "opencv-python-headless>=4.10.0"], check=True, capture_output=True)

    from ultralytics import YOLO

    SHARED = Path("/shared-data")
    DATASET_DIR = SHARED / "dataset"
    METRICS_DIR = SHARED / "metrics"
    METRICS_DIR.mkdir(parents=True, exist_ok=True)

    # Validate on the val set
    print(f"Evaluating {onnx_path}...")
    model = YOLO(onnx_path, task="detect")
    results = model.val(
        data=str(DATASET_DIR / "data.yaml"), imgsz=640, batch=4,
        project=str(SHARED / "eval-runs"), name="val", exist_ok=True,
    )

    mAP50 = float(results.box.map50)
    mAP50_95 = float(results.box.map)

    per_class = results.box.maps
    class_names = model.names
    print(f"\nOverall: mAP50={mAP50:.3f}, mAP50-95={mAP50_95:.3f}")
    for i, m in enumerate(per_class):
        print(f"  {class_names[i]}: mAP50={float(m):.3f}")

    adnan_map = float(per_class[0]) if len(per_class) > 0 else 0.0

    metrics.log_metric("mAP50", mAP50)
    metrics.log_metric("mAP50_95", mAP50_95)
    metrics.log_metric("adnan_mAP50", adnan_map)

    # Save metrics for register step
    import json
    (METRICS_DIR / "results.json").write_text(json.dumps({
        "mAP50": mAP50, "mAP50_95": mAP50_95,
        "adnan_mAP50": adnan_map,
    }))

    # Query previous model from registry (pattern from rhoai-mlops/jukebox)
    prev_mAP50 = 0.0
    try:
        import os
        from model_registry import ModelRegistry
        from model_registry.exceptions import StoreError

        os.environ["KF_PIPELINES_SA_TOKEN_PATH"] = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        registry = ModelRegistry(
            server_address=registry_url, port=443,
            author="eval-pipeline", is_secure=False,
        )
        for v in registry.get_model_versions(model_name).order_by_id().descending():
            props = v.custom_properties
            if "mAP50" in props:
                prev_mAP50 = float(props["mAP50"])
                print(f"Previous model mAP50: {prev_mAP50:.3f}")
                break
    except Exception as e:
        print(f"Could not query registry (first run?): {e}")

    metrics.log_metric("prev_mAP50", prev_mAP50)

    # Quality gate
    if mAP50 < mAP_threshold:
        raise RuntimeError(
            f"Model quality below threshold: mAP50={mAP50:.3f} < {mAP_threshold}. "
            f"Pipeline stopped -- model will NOT be deployed."
        )

    print(f"Quality gate PASSED: mAP50={mAP50:.3f} >= {mAP_threshold}")
    return mAP50
