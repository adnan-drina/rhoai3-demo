"""Publish one split's Docling converted and chunked artifacts to deterministic S3 keys."""

from kfp import dsl

from .constants import PYTHON_BASE_IMAGE


@dsl.component(
    base_image=PYTHON_BASE_IMAGE,
    packages_to_install=["boto3==1.42.54"],
)
def publish_docling_split_outputs(
    converted_path: dsl.Input[dsl.Artifact],
    chunked_path: dsl.Input[dsl.Artifact],
    manifest_json: str,
    output_s3_key: str,
    s3_secret_mount_path: str = "/mnt/secrets",
):
    """Upload split-local Docling artifacts to the project S3 bucket."""

    import json  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    import boto3  # pylint: disable=import-outside-toplevel
    from botocore.config import Config  # pylint: disable=import-outside-toplevel
    from urllib3 import disable_warnings  # pylint: disable=import-outside-toplevel
    from urllib3.exceptions import InsecureRequestWarning  # pylint: disable=import-outside-toplevel

    def secret_value(name: str) -> str:
        value_path = Path(s3_secret_mount_path) / name
        if not value_path.is_file():
            raise RuntimeError(f"missing S3 Secret key {name} in {s3_secret_mount_path}")
        return value_path.read_text(encoding="utf-8").strip()

    manifest = json.loads(manifest_json)
    document_by_stem = {Path(document["source_file"]).stem: document for document in manifest.get("documents", [])}
    if not document_by_stem:
        raise RuntimeError("manifest does not contain selected documents")

    output_key = output_s3_key.strip("/")
    output_prefix = output_key.rsplit("/", 1)[0]
    artifact_prefix = f"{output_prefix}/docling-artifacts"
    chunk_prefix = f"{output_prefix}/docling-chunks"

    disable_warnings(InsecureRequestWarning)
    bucket = secret_value("S3_BUCKET")
    s3_client = boto3.client(
        "s3",
        endpoint_url=secret_value("S3_ENDPOINT_URL"),
        aws_access_key_id=secret_value("S3_ACCESS_KEY"),
        aws_secret_access_key=secret_value("S3_SECRET_KEY"),
        region_name="us-east-1",
        verify=False,
        config=Config(signature_version="s3v4"),
    )

    uploaded = 0
    converted_dir = Path(converted_path.path)
    for artifact in sorted(converted_dir.glob("*")):
        if artifact.suffix not in {".md", ".json"}:
            continue
        document = document_by_stem.get(artifact.stem)
        if not document:
            raise RuntimeError(f"converted artifact {artifact.name} is not present in the selected manifest")
        suffix = artifact.suffix.lstrip(".")
        content_type = "text/markdown" if suffix == "md" else "application/json"
        s3_client.put_object(
            Bucket=bucket,
            Key=f"{artifact_prefix}/{document['guide_slug']}.{suffix}",
            Body=artifact.read_bytes(),
            ContentType=content_type,
        )
        uploaded += 1

    chunked_dir = Path(chunked_path.path)
    for chunk_file in sorted(chunked_dir.glob("*_chunks.jsonl")):
        source_stem = chunk_file.name.removesuffix("_chunks.jsonl")
        document = document_by_stem.get(source_stem)
        if not document:
            raise RuntimeError(f"chunk artifact {chunk_file.name} is not present in the selected manifest")
        s3_client.put_object(
            Bucket=bucket,
            Key=f"{chunk_prefix}/{document['guide_slug']}_chunks.jsonl",
            Body=chunk_file.read_bytes(),
            ContentType="application/jsonl",
        )
        uploaded += 1

    if uploaded == 0:
        raise RuntimeError("no Docling split artifacts were uploaded")
    print(f"publish-docling-split-outputs: uploaded {uploaded} artifact(s)", flush=True)
