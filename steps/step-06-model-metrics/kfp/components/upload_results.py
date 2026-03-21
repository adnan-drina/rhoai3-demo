"""
Upload Results Component — reads GuideLLM results from the shared PVC
and uploads to S3.
"""

from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    packages_to_install=["boto3>=1.34.0"],
)
def upload_results(
    results_path: str,
    model_name: str,
    run_id: str,
) -> str:
    """Upload benchmark results from the shared PVC to S3.

    Args:
        results_path: Path to results JSON on the shared PVC.
        model_name: Model name for the S3 key path.
        run_id: Run identifier for the S3 key path.

    Returns:
        S3 URI of uploaded results.
    """
    import os

    endpoint = os.environ.get("AWS_S3_ENDPOINT", "")
    if not endpoint:
        print("No S3 credentials configured — skipping upload")
        return "skipped"

    if not os.path.exists(results_path):
        print(f"Results file not found: {results_path}")
        return "missing"

    import boto3

    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY"),
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
    )

    bucket = os.environ.get("AWS_S3_BUCKET", "rhoai-storage")
    key = f"benchmark-results/{run_id}/{model_name}-results.json"

    s3.upload_file(results_path, bucket, key, ExtraArgs={"ContentType": "application/json"})

    uri = f"s3://{bucket}/{key}"
    print(f"Results uploaded: {uri}")
    return uri
