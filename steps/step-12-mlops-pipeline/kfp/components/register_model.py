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
    import os, json
    from pathlib import Path
    import boto3
    from botocore.config import Config
    from model_registry import ModelRegistry, utils

    SHARED = Path("/shared-data")
    METRICS_DIR = SHARED / "metrics"

    # Load metrics
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

    # Register in Model Registry
    s3_endpoint = os.environ.get("AWS_S3_ENDPOINT", minio_endpoint)
    s3_uri = f"s3://{BUCKET}/{KEY}?endpoint={s3_endpoint}"

    metadata = {k: str(v) for k, v in metrics_data.items()}

    try:
        # Read ServiceAccount token for authentication
        token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        sa_token = Path(token_path).read_text() if Path(token_path).exists() else None

        registry = ModelRegistry(
            server_address=registry_url, port=443,
            author="face-recognition-pipeline", is_secure=False,
            custom_headers={"Authorization": f"Bearer {sa_token}"} if sa_token else None,
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
