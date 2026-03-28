"""Download user photos and unknown faces from MinIO, auto-annotate with
YOLO11-face, split train/val, write data.yaml. Falls back to LFW
portraits if no unknown photos are in MinIO."""

from kfp.dsl import component, Output, Dataset, Metrics


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    packages_to_install=[
        "ultralytics>=8.3.0",
        "huggingface_hub>=0.20.0",
        "datasets>=2.14.0",
        "boto3>=1.34.0",
        "opencv-python-headless>=4.10.0",
        "lapx>=0.5.2",
    ],
    pip_index_urls=["https://pypi.org/simple"],
)
def prepare_dataset(
    photos_s3_prefix: str,
    minio_endpoint: str,
    unknown_s3_prefix: str = "s3://face-training-photos/unknown/",
    dataset: Output[Dataset] = None,
    metrics: Output[Metrics] = None,
) -> int:
    """Download user and unknown photos from MinIO, auto-annotate, split train/val.

    Args:
        photos_s3_prefix: S3 URI to the user's photo collection (class 0).
        minio_endpoint: MinIO endpoint URL (fallback if env var not set).
        unknown_s3_prefix: S3 URI to unknown face photos (class 1).
            Falls back to LFW dataset if empty.
        metrics: KFP Metrics artifact for Dashboard visibility.

    Returns:
        Total number of annotated images (train + val).
    """
    import subprocess, os, shutil, random
    from pathlib import Path

    subprocess.run(["pip", "install", "--force-reinstall", "--no-deps", "opencv-python-headless>=4.10.0"], check=True, capture_output=True)

    from ultralytics import YOLO
    from huggingface_hub import hf_hub_download
    import boto3
    from botocore.config import Config

    SHARED = Path("/shared-data")
    DATASET_DIR = SHARED / "dataset"
    PHOTOS_DIR = SHARED / "photos"
    UNKNOWN_DIR = SHARED / "unknown_faces"

    for d in [DATASET_DIR, PHOTOS_DIR, UNKNOWN_DIR]:
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True)

    for split in ["train", "val"]:
        (DATASET_DIR / "images" / split).mkdir(parents=True)
        (DATASET_DIR / "labels" / split).mkdir(parents=True)

    s3 = boto3.client("s3",
        endpoint_url=os.environ.get("AWS_S3_ENDPOINT", minio_endpoint),
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        config=Config(signature_version="s3v4"))

    def download_s3_photos(s3_prefix, dest_dir):
        parts = s3_prefix.replace("s3://", "").split("/", 1)
        bucket, prefix = parts[0], parts[1] if len(parts) > 1 else ""
        downloaded = 0
        paginator = s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                if key.lower().endswith((".jpg", ".jpeg", ".png")):
                    local = dest_dir / key.replace("/", "_")
                    s3.download_file(bucket, key, str(local))
                    downloaded += 1
        return downloaded

    # --- Download user photos from MinIO ---
    n_user = download_s3_photos(photos_s3_prefix, PHOTOS_DIR)
    user_photos = sorted(PHOTOS_DIR.glob("*"))
    print(f"Downloaded {n_user} user photos from {photos_s3_prefix}")

    # --- Download unknown photos from MinIO, fall back to LFW ---
    n_unknown = download_s3_photos(unknown_s3_prefix, UNKNOWN_DIR)
    print(f"Downloaded {n_unknown} unknown photos from {unknown_s3_prefix}")

    # Augment with HuggingFace portraits for diversity
    NUM_PORTRAITS = 200
    print(f"Downloading {NUM_PORTRAITS} realistic face portraits from HuggingFace...")
    try:
        from datasets import load_dataset
        from PIL import Image
        ds = load_dataset("prithivMLmods/Realistic-Face-Portrait-1024px", split="train", streaming=True)
        p_count = 0
        for example in ds:
            if p_count >= NUM_PORTRAITS:
                break
            try:
                img = example["image"]
                if img.width >= 256:
                    img = img.resize((512, 512))
                    img.save(UNKNOWN_DIR / f"portrait_{p_count:04d}.jpg", quality=95)
                    p_count += 1
            except:
                continue
        print(f"Added {p_count} HuggingFace portraits")
    except Exception as e:
        print(f"Portrait download failed ({e}) — continuing with MinIO photos only")

    unknown_photos = sorted(UNKNOWN_DIR.glob("*.jpg")) + sorted(UNKNOWN_DIR.glob("*.jpeg"))
    print(f"Total unknown faces: {len(unknown_photos)}")

    # --- Auto-annotate ---
    print("Auto-annotating with YOLO11-face detector...")
    det_path = hf_hub_download(repo_id="AdamCodd/YOLOv11n-face-detection", filename="model.pt")
    detector = YOLO(det_path)

    def annotate(image_path, class_id, img_dir, lbl_dir, prefix):
        results = detector.predict(str(image_path), verbose=False, conf=0.3)
        if len(results[0].boxes) == 0:
            return False
        img_name = f"{prefix}_{image_path.stem}.jpg"
        lbl_name = f"{prefix}_{image_path.stem}.txt"
        shutil.copy2(image_path, img_dir / img_name)
        img_h, img_w = results[0].orig_shape
        with open(lbl_dir / lbl_name, "w") as f:
            for box in results[0].boxes:
                x1, y1, x2, y2 = box.xyxy[0].tolist()
                cx = ((x1 + x2) / 2) / img_w
                cy = ((y1 + y2) / 2) / img_h
                w = (x2 - x1) / img_w
                h = (y2 - y1) / img_h
                f.write(f"{class_id} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}\n")
        return True

    unknown_photos = sorted(UNKNOWN_DIR.glob("*.jpg"))
    random.shuffle(list(user_photos))
    random.shuffle(unknown_photos)

    total = {"train": 0, "val": 0}
    for photos, cid, pfx in [(user_photos, 0, "adnan"), (unknown_photos, 1, "unknown")]:
        split_idx = int(len(photos) * 0.8)
        for split, photo_list in [("train", photos[:split_idx]), ("val", photos[split_idx:])]:
            for p in photo_list:
                if annotate(p, cid, DATASET_DIR / "images" / split, DATASET_DIR / "labels" / split, pfx):
                    total[split] += 1

    # --- Write data.yaml ---
    (DATASET_DIR / "data.yaml").write_text(
        f"path: {DATASET_DIR}\ntrain: images/train\nval: images/val\n\nnc: 2\nnames:\n  0: adnan\n  1: unknown_face\n"
    )

    # Download YOLO11n base model — try MinIO first, fall back to HuggingFace
    base_model_path = SHARED / "yolo11m.pt"
    if not base_model_path.exists():
        try:
            s3.download_file("models", "yolo11m.pt", str(base_model_path))
            print(f"Downloaded base model from MinIO")
        except Exception:
            print("yolo11m.pt not in MinIO — downloading from ultralytics...")
            import urllib.request
            urllib.request.urlretrieve(
                "https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo11m.pt",
                str(base_model_path))
            print(f"Downloaded base model from ultralytics")

    print(f"Dataset: {total['train']} train, {total['val']} val")
    metrics.log_metric("train_images", total["train"])
    metrics.log_metric("val_images", total["val"])
    metrics.log_metric("user_photos", len(user_photos))
    metrics.log_metric("unknown_photos", len(unknown_photos))

    # Record dataset artifact for ML lineage tracking
    dataset.uri = str(DATASET_DIR / "data.yaml")
    dataset.metadata["train_images"] = total["train"]
    dataset.metadata["val_images"] = total["val"]
    dataset.metadata["classes"] = ["adnan", "unknown_face"]

    return total["train"] + total["val"]
