"""Upload ONNX to MinIO and register version in Model Registry."""

from kfp.dsl import component


@component(
    base_image="python:3.11",
    packages_to_install=[
        "boto3>=1.34.0",
        "model-registry>=0.3.7",
    ],
)
def register_model(
    onnx_path: str,
    model_name: str,
    version: str,
    registry_url: str,
    minio_endpoint: str,
) -> str:
    """Upload ONNX model to MinIO and register the version in Model Registry.

    Args:
        onnx_path: Path to the ONNX model on the shared PVC.
        model_name: Name to register under in the Model Registry.
        version: Version string for this model release.
        registry_url: Model Registry REST endpoint.
        minio_endpoint: MinIO endpoint URL (fallback if env var not set).

    Returns:
        The version string that was registered.
    """
    import os, json
    from pathlib import Path
    import boto3
    from botocore.config import Config
    from model_registry import ModelRegistry, utils

    SHARED = Path("/shared-data")
    METRICS_DIR = SHARED / "metrics"

    metrics_data = json.loads((METRICS_DIR / "results.json").read_text())

    # Upload ONNX to MinIO
    BUCKET = "models"
    KEY = "face-recognition/1/model.onnx"

    s3 = boto3.client("s3",
        endpoint_url=os.environ.get("AWS_S3_ENDPOINT", minio_endpoint),
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        config=Config(signature_version="s3v4"))

    print(f"Uploading {onnx_path} -> s3://{BUCKET}/{KEY}...")
    s3.upload_file(onnx_path, BUCKET, KEY)

    obj = s3.head_object(Bucket=BUCKET, Key=KEY)
    print(f"Uploaded: {obj['ContentLength'] / (1024*1024):.1f} MB")

    # Register in Model Registry (pattern from rhoai-mlops/jukebox)
    s3_endpoint = os.environ.get("AWS_S3_ENDPOINT", minio_endpoint)
    s3_bucket = os.environ.get("AWS_S3_BUCKET", BUCKET)

    metadata = {k: str(v) for k, v in metrics_data.items()}

    try:
        # The model-registry SDK reads this env var for SA token auth
        os.environ["KF_PIPELINES_SA_TOKEN_PATH"] = "/var/run/secrets/kubernetes.io/serviceaccount/token"

        registry = ModelRegistry(
            server_address=registry_url,
            port=443,
            author="face-recognition-pipeline",
            is_secure=False,
        )

        s3_uri = utils.s3_uri_from(
            f"/models/{model_name}/1/model.onnx",
            bucket=s3_bucket,
            endpoint=s3_endpoint,
        )

        registry.register_model(
            model_name, s3_uri,
            model_format_name="onnx", model_format_version="1",
            version=version,
            version_description=f"YOLO11n face recognition. mAP50={metrics_data['mAP50']:.3f}",
            metadata=metadata,
        )
        print(f"Registered {model_name} v{version} in Model Registry")
    except Exception as e:
        print(f"WARNING: Model Registry registration failed: {e}")
        print("The model is deployed to MinIO and serving -- registration can be done manually.")

    return version
