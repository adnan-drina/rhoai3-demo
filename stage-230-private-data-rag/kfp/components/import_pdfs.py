"""Import PDFs from HTTP/S or S3 for the modular Docling pipeline."""

from kfp import dsl

from .constants import PYTHON_BASE_IMAGE


@dsl.component(
    base_image=PYTHON_BASE_IMAGE,
    packages_to_install=["boto3==1.42.54", "requests==2.32.5"],
)
def import_pdfs(
    output_path: dsl.Output[dsl.Artifact],
    filenames: str,
    base_url: str,
    from_s3: bool = False,
    s3_secret_mount_path: str = "/mnt/secrets",
):
    """Import comma-separated PDF filenames from HTTP/S or S3-compatible storage."""

    import os  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    import boto3  # pylint: disable=import-outside-toplevel
    import requests  # pylint: disable=import-outside-toplevel
    from botocore.config import Config  # pylint: disable=import-outside-toplevel
    from urllib3 import disable_warnings  # pylint: disable=import-outside-toplevel
    from urllib3.exceptions import InsecureRequestWarning  # pylint: disable=import-outside-toplevel

    def secret_value(name: str) -> str:
        value_path = Path(s3_secret_mount_path) / name
        if not value_path.is_file():
            raise ValueError(f"Key {name} not defined in secret mount {s3_secret_mount_path}")
        return value_path.read_text(encoding="utf-8").strip()

    filenames_list = [name.strip() for name in filenames.split(",") if name.strip()]
    if not filenames_list:
        raise ValueError("filenames must contain at least one filename")

    output_dir = Path(output_path.path)
    output_dir.mkdir(parents=True, exist_ok=True)

    if from_s3:
        if not Path(s3_secret_mount_path).exists():
            raise ValueError(f"Secret for S3 should be mounted in {s3_secret_mount_path}")

        disable_warnings(InsecureRequestWarning)
        s3_endpoint_url = secret_value("S3_ENDPOINT_URL")
        s3_bucket = secret_value("S3_BUCKET")
        s3_prefix = secret_value("S3_PREFIX")
        s3_client = boto3.client(
            "s3",
            endpoint_url=s3_endpoint_url,
            aws_access_key_id=secret_value("S3_ACCESS_KEY"),
            aws_secret_access_key=secret_value("S3_SECRET_KEY"),
            region_name="us-east-1",
            verify=False,
            config=Config(signature_version="s3v4"),
        )

        for filename in filenames_list:
            source_key = f"{s3_prefix.rstrip('/')}/{filename.lstrip('/')}"
            destination = output_dir / filename
            print(f"import-pdfs: downloading s3://{s3_bucket}/{source_key} -> {destination}", flush=True)
            s3_client.download_file(s3_bucket, source_key, str(destination))
    else:
        if not base_url:
            raise ValueError("base_url must be provided for HTTP/S import")
        for filename in filenames_list:
            source_url = f"{base_url.rstrip('/')}/{filename.lstrip('/')}"
            destination = output_dir / filename
            print(f"import-pdfs: downloading {source_url} -> {destination}", flush=True)
            with requests.get(source_url, stream=True, timeout=30) as response:
                response.raise_for_status()
                with destination.open("wb") as output_file:
                    for chunk in response.iter_content(chunk_size=8192):
                        if chunk:
                            output_file.write(chunk)

    print(f"import-pdfs: imported {len(filenames_list)} PDF file(s)", flush=True)

