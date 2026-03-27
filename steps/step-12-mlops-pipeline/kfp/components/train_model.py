"""Train YOLO11n on the prepared dataset and export to ONNX."""

from kfp.dsl import component, Output, Metrics, Model


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    packages_to_install=[
        "ultralytics>=8.3.0",
        "opencv-python-headless>=4.10.0",
        "onnx>=1.12.0",
        "onnxslim>=0.1.71",
        "onnxruntime>=1.17.0",
    ],
    pip_index_urls=["https://pypi.org/simple"],
)
def train_model(
    epochs: int,
    metrics: Output[Metrics],
    trained_model: Output[Model],
) -> str:
    """Train YOLO11n on the prepared dataset and export to ONNX.

    Args:
        epochs: Number of training epochs.
        metrics: KFP Metrics artifact for Dashboard visibility.
        trained_model: KFP Model artifact for Dashboard lineage tracking.

    Returns:
        Path to the exported ONNX model file on the shared PVC.
    """
    import subprocess
    from pathlib import Path

    subprocess.run(["pip", "install", "--force-reinstall", "--no-deps", "opencv-python-headless>=4.10.0"], check=True, capture_output=True)

    from ultralytics import YOLO

    SHARED = Path("/shared-data")
    DATASET_DIR = SHARED / "dataset"
    MODEL_DIR = SHARED / "model"
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    data_yaml = str(DATASET_DIR / "data.yaml")
    # Auto-detect GPU; fall back to CPU
    import torch
    device = 0 if torch.cuda.is_available() else "cpu"
    print(f"Training YOLO26m for {epochs} epochs on {device}...")
    print(f"Dataset: {data_yaml}")

    base_model = str(SHARED / "yolo26m.pt") if (SHARED / "yolo26m.pt").exists() else "yolo26m.pt"
    print(f"Base model: {base_model}")
    model = YOLO(base_model)
    results = model.train(
        data=data_yaml,
        epochs=epochs,
        imgsz=640,
        batch=32 if device == 0 else 4,
        device=device,
        workers=0,
        cos_lr=True,
        mosaic=1.0,
        mixup=0.3,
        fliplr=0.5,
        degrees=15.0,
        patience=10,
        project=str(MODEL_DIR / "runs"),
        name="train",
        exist_ok=True,
    )

    best_pt = list(MODEL_DIR.rglob("train/weights/best.pt"))
    if not best_pt:
        raise RuntimeError("Training failed -- no best.pt found")

    best = best_pt[0]
    print(f"Best model: {best}")

    # Export to ONNX
    trained = YOLO(str(best))
    onnx_path = trained.export(format="onnx")
    print(f"ONNX exported: {onnx_path}")

    # Log final metrics from training
    metrics.log_metric("epochs_completed", epochs)
    metrics.log_metric("onnx_path", onnx_path)

    # Write ONNX to KFP Model artifact for Dashboard lineage tracking
    import shutil
    shutil.copy2(onnx_path, trained_model.path)
    trained_model.metadata["framework"] = "ultralytics-yolo26m"
    trained_model.metadata["format"] = "onnx"
    trained_model.metadata["epochs"] = epochs

    return onnx_path
