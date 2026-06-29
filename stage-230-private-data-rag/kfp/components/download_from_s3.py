"""Download whoami source documents from the project ODF/NooBaa bucket."""

from typing import List, NamedTuple

from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.4.0",
    packages_to_install=["boto3>=1.34.0"],
    pip_index_urls=["https://pypi.org/simple"],
)
def download_from_s3_component(
    s3_uri: str,
    s3_endpoint: str,
) -> NamedTuple("DownloadOutput", [("downloaded_files", List[str]), ("file_count", int)]):
    """Download PDF documents from an S3 URI into the shared pipeline PVC."""
    import os
    from collections import namedtuple
    from urllib.parse import urlparse

    import boto3
    from botocore.client import Config

    DownloadOutput = namedtuple("DownloadOutput", ["downloaded_files", "file_count"])

    access_key = os.environ.get("AWS_ACCESS_KEY_ID")
    secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY")
    if not access_key or not secret_key:
        raise RuntimeError("Missing AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY")

    parsed = urlparse(s3_uri)
    bucket = parsed.netloc
    prefix = parsed.path.lstrip("/")
    if not bucket:
        raise RuntimeError(f"Invalid S3 URI: {s3_uri}")

    print(f"S3 endpoint: {s3_endpoint}")
    print(f"S3 bucket:   {bucket}")
    print(f"S3 prefix:   {prefix}")

    shared_dir = "/shared-data/documents"
    os.makedirs(shared_dir, exist_ok=True)

    client = boto3.client(
        "s3",
        endpoint_url=s3_endpoint,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(signature_version="s3v4"),
        verify=False,
    )

    response = client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    downloaded_files = []
    for item in response.get("Contents", []):
        key = item["Key"]
        if key.endswith("/") or not key.lower().endswith(".pdf"):
            continue

        local_name = key.replace("/", "_")
        local_path = os.path.join(shared_dir, local_name)
        client.download_file(bucket, key, local_path)
        print(f"Downloaded s3://{bucket}/{key} -> {local_path}")
        downloaded_files.append(local_path)

    if not downloaded_files:
        raise RuntimeError(f"No PDF documents found at {s3_uri}")

    return DownloadOutput(downloaded_files=downloaded_files, file_count=len(downloaded_files))
