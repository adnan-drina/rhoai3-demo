"""Train YOLO11n on the prepared dataset and export to ONNX."""

from kfp.dsl import component, Output, Metrics


@component(
    base_image="python:3.11",
    packages_to_install=[
        "ultralytics>=8.3.0",
        "opencv-python-headless>=4.10.0",
        "onnx>=1.12.0",
        "onnxslim>=0.1.71",
        "onnxruntime>=1.17.0",
    ],
)
def train_model(
    epochs: int,
    metrics: Output[Metrics],
) -> str:
    import subprocess
    from pathlib import Path

    subprocess.run(["pip", "install", "--force-reinstall", "--no-deps", "opencv-python-headless>=4.10.0"], check=True, capture_output=True)

    from ultralytics import YOLO

    SHARED = Path("/shared-data")
    DATASET_DIR = SHARED / "dataset"
    MODEL_DIR = SHARED / "model"
    MODEL_DIR.mkdir(parents=True, exist_ok=True)

    data_yaml = str(DATASET_DIR / "data.yaml")
    print(f"Training YOLO11n for {epochs} epochs on CPU...")
    print(f"Dataset: {data_yaml}")

    # Use pre-downloaded base model from shared PVC (downloaded by prepare_dataset)
    base_model = str(SHARED / "yolo11n.pt") if (SHARED / "yolo11n.pt").exists() else "yolo11n.pt"
    print(f"Base model: {base_model}")
    model = YOLO(base_model)
    results = model.train(
        data=data_yaml,
        epochs=epochs,
        imgsz=640,
        batch=4,
        device="cpu",
        mosaic=1.0,
        mixup=0.3,
        fliplr=0.5,
        degrees=15.0,
        patience=5,
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

    return onnx_path
