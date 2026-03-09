"""
Download from S3 Component — lists and downloads all PDFs from an S3 prefix.

Uses boto3 with credentials injected from a Kubernetes secret via
kubernetes.use_secret_as_env(). Files are written to a shared PVC
at /shared-data/documents/.

Original MinIO keys are preserved separately for metadata tracing.
"""

from typing import NamedTuple, List
from kfp.dsl import component


@component(
    base_image="python:3.11",
    packages_to_install=["boto3==1.34.103"],
)
def download_from_s3_component(
    s3_prefix: str,
    minio_endpoint: str,
) -> NamedTuple(
    "DownloadOutput",
    [("downloaded_files", List[str]), ("original_keys", List[str]), ("file_count", int)],
):
    import boto3
    import os
    from collections import namedtuple
    from urllib.parse import urlparse

    print("Downloading Documents from MinIO")
    print("=" * 60)

    endpoint = os.environ.get("AWS_S3_ENDPOINT", minio_endpoint)
    access_key = os.environ.get("AWS_ACCESS_KEY_ID")
    secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY")

    if not all([endpoint, access_key, secret_key]):
        raise RuntimeError(
            "Missing MinIO credentials. Expected env vars: "
            "AWS_S3_ENDPOINT, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
        )

    parsed = urlparse(s3_prefix)
    bucket = parsed.netloc or s3_prefix.split("//")[1].split("/")[0]
    prefix = "/".join(parsed.path.strip("/").split("/")) if parsed.path.strip("/") else ""

    print(f"  Endpoint: {endpoint}")
    print(f"  Bucket:   {bucket}")
    print(f"  Prefix:   {prefix}")

    shared_dir = "/shared-data/documents"
    os.makedirs(shared_dir, exist_ok=True)

    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint if endpoint.startswith("http") else f"http://{endpoint}",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        verify=False,
    )

    response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
    objects = response.get("Contents", [])
    print(f"  Found {len(objects)} objects")

    downloaded_files: list[str] = []
    original_keys: list[str] = []

    for obj in objects:
        key = obj["Key"]
        if key.endswith("/"):
            continue
        if not key.lower().endswith(".pdf"):
            print(f"  Skipping non-PDF: {key}")
            continue

        safe_name = key.replace("/", "_")
        local_path = f"{shared_dir}/{safe_name}"

        try:
            s3.download_file(bucket, key, local_path)
            size = os.path.getsize(local_path)
            print(f"  [OK] {key} ({size} bytes)")
            downloaded_files.append(local_path)
            original_keys.append(key)
        except Exception as e:
            print(f"  [FAIL] {key}: {e}")
            continue

    print(f"\nDownloaded {len(downloaded_files)} / {len(objects)} objects")

    DownloadOutput = namedtuple("DownloadOutput", ["downloaded_files", "original_keys", "file_count"])
    return DownloadOutput(
        downloaded_files=downloaded_files,
        original_keys=original_keys,
        file_count=len(downloaded_files),
    )
