"""Train YOLO11m on the prepared dataset and export to ONNX."""

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
    """Train YOLO11m on the prepared dataset and export to ONNX.

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
    print(f"Training YOLO11m for {epochs} epochs on {device}...")
    print(f"Dataset: {data_yaml}")

    base_model = str(SHARED / "yolo11m.pt") if (SHARED / "yolo11m.pt").exists() else "yolo11m.pt"
    print(f"Base model: {base_model}")
    model = YOLO(base_model)
    results = model.train(
        data=data_yaml,
        epochs=epochs,
        imgsz=640,
        batch=16 if device == 0 else 4,
        device=device,
        workers=0,
        mosaic=1.0,
        close_mosaic=20,
        mixup=0.0,
        fliplr=0.5,
        patience=15,
        project=str(MODEL_DIR / "runs"),
        name="train",
        exist_ok=True,
    )

    best_pt = list(MODEL_DIR.rglob("train/weights/best.pt"))
    if not best_pt:
        raise RuntimeError("Training failed -- no best.pt found")

    best = best_pt[0]
    print(f"Best model: {best}")

    # Validate best model to get final metrics
    val_model = YOLO(str(best))
    val_results = val_model.val(
        data=data_yaml, imgsz=640, batch=8, device=device,
        workers=0,
        project=str(MODEL_DIR / "runs"), name="final_val", exist_ok=True,
    )

    mAP50 = float(val_results.box.map50)
    mAP50_95 = float(val_results.box.map)
    precision = float(val_results.box.mp)
    recall = float(val_results.box.mr)
    per_class = val_results.box.maps
    class_names = val_model.names

    print(f"\nFinal validation: mAP50={mAP50:.3f}, mAP50-95={mAP50_95:.3f}")
    for i, m in enumerate(per_class):
        print(f"  {class_names[i]}: mAP50={float(m):.3f}")

    # Export to ONNX
    onnx_path = val_model.export(format="onnx")
    print(f"ONNX exported: {onnx_path}")

    import time
    training_time = time.time()

    # Log meaningful metrics to KFP Dashboard
    metrics.log_metric("epochs_completed", epochs)
    metrics.log_metric("mAP50", round(mAP50, 4))
    metrics.log_metric("mAP50_95", round(mAP50_95, 4))
    metrics.log_metric("precision", round(precision, 4))
    metrics.log_metric("recall", round(recall, 4))
    metrics.log_metric("device", str(device))
    metrics.log_metric("model_size_mb", round(Path(onnx_path).stat().st_size / 1024 / 1024, 1))

    for i, m in enumerate(per_class):
        metrics.log_metric(f"{class_names[i]}_mAP50", round(float(m), 4))

    # Write ONNX to KFP Model artifact for Dashboard lineage tracking
    import shutil
    shutil.copy2(onnx_path, trained_model.path)
    trained_model.metadata["framework"] = "ultralytics-yolo11m"
    trained_model.metadata["format"] = "onnx"
    trained_model.metadata["epochs"] = epochs
    trained_model.metadata["mAP50"] = round(mAP50, 4)
    trained_model.metadata["mAP50_95"] = round(mAP50_95, 4)
    trained_model.metadata["precision"] = round(precision, 4)
    trained_model.metadata["recall"] = round(recall, 4)

    return onnx_path
