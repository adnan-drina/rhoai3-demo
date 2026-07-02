"""Chunk Docling JSON artifacts and upload converted and chunked outputs to S3."""

from kfp import dsl

from .constants import DOCLING_BASE_IMAGE


@dsl.component(
    base_image=DOCLING_BASE_IMAGE,
    packages_to_install=["boto3==1.42.54"],
)
def docling_chunk_and_upload(
    input_path: dsl.Input[dsl.Artifact],
    output_path: dsl.Output[dsl.Artifact],
    manifest_json: str,
    output_s3_key: str,
    s3_secret_mount_path: str = "/mnt/secrets",
    max_tokens: int = 512,
    merge_peers: bool = True,
):
    """Chunk converted Docling artifacts with HybridChunker, then upload
    converted Markdown/JSON and chunk JSONL outputs to deterministic S3 keys.

    Combines the reference ``docling_chunk`` logic with per-split S3 artifact
    publishing so the ParallelFor loop contains only two nodes (convert then
    chunk-and-upload) instead of three.
    """

    import json  # pylint: disable=import-outside-toplevel
    from datetime import datetime, timezone  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    import boto3  # pylint: disable=import-outside-toplevel
    from botocore.config import Config  # pylint: disable=import-outside-toplevel
    from docling.chunking import HybridChunker  # pylint: disable=import-outside-toplevel
    from docling_core.transforms.chunker.tokenizer.huggingface import (  # pylint: disable=import-outside-toplevel
        HuggingFaceTokenizer,
    )
    from docling_core.types import DoclingDocument  # pylint: disable=import-outside-toplevel
    from transformers import AutoTokenizer  # pylint: disable=import-outside-toplevel
    from urllib3 import disable_warnings  # pylint: disable=import-outside-toplevel
    from urllib3.exceptions import InsecureRequestWarning  # pylint: disable=import-outside-toplevel

    def secret_value(name: str) -> str:
        value_path = Path(s3_secret_mount_path) / name
        if not value_path.is_file():
            raise RuntimeError(f"missing S3 Secret key {name} in {s3_secret_mount_path}")
        return value_path.read_text(encoding="utf-8").strip()

    input_dir = Path(input_path.path)
    output_dir = Path(output_path.path)
    output_dir.mkdir(parents=True, exist_ok=True)

    embed_model_id = "sentence-transformers/all-MiniLM-L6-v2"
    hf_tokenizer = AutoTokenizer.from_pretrained(
        embed_model_id,
        resume_download=True,
        timeout=60,
    )
    tokenizer = HuggingFaceTokenizer(tokenizer=hf_tokenizer, max_tokens=max_tokens)
    chunker = HybridChunker(tokenizer=tokenizer, merge_peers=merge_peers)

    json_files = sorted(input_dir.glob("*.json"))
    if not json_files:
        raise RuntimeError(f"docling-chunk-and-upload: no JSON files found in {input_dir}")

    timestamp = datetime.now(timezone.utc).isoformat()
    chunking_config = {
        "max_tokens": max_tokens,
        "merge_peers": merge_peers,
        "tokenizer_model": embed_model_id,
    }

    for json_file in json_files:
        doc_data = json.loads(json_file.read_text(encoding="utf-8"))
        document = DoclingDocument.model_validate(doc_data)
        chunks = list(chunker.chunk(dl_doc=document))
        output_file = output_dir / f"{json_file.stem}_chunks.jsonl"
        with output_file.open("w", encoding="utf-8") as output:
            for index, chunk in enumerate(chunks, start=1):
                record = {
                    "timestamp": timestamp,
                    "source_document": json_file.name,
                    "chunk_index": index,
                    "chunking_config": chunking_config,
                    "text": chunker.contextualize(chunk=chunk),
                }
                output.write(json.dumps(record, ensure_ascii=False) + "\n")
        print(f"docling-chunk-and-upload: saved {len(chunks)} chunks to {output_file.name}", flush=True)

    print(f"docling-chunk-and-upload: chunked {len(json_files)} document(s)", flush=True)

    manifest = json.loads(manifest_json)
    document_by_stem = {
        Path(doc["source_file"]).stem: doc
        for doc in manifest.get("documents", [])
    }

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
    for artifact in sorted(input_dir.glob("*")):
        if artifact.suffix not in {".md", ".json"}:
            continue
        doc = document_by_stem.get(artifact.stem)
        if not doc:
            raise RuntimeError(
                f"docling-chunk-and-upload: converted artifact {artifact.name} "
                f"is not present in the manifest"
            )
        suffix = artifact.suffix.lstrip(".")
        content_type = "text/markdown" if suffix == "md" else "application/json"
        s3_client.put_object(
            Bucket=bucket,
            Key=f"{artifact_prefix}/{doc['guide_slug']}.{suffix}",
            Body=artifact.read_bytes(),
            ContentType=content_type,
        )
        uploaded += 1

    for chunk_file in sorted(output_dir.glob("*_chunks.jsonl")):
        source_stem = chunk_file.name.removesuffix("_chunks.jsonl")
        doc = document_by_stem.get(source_stem)
        if not doc:
            raise RuntimeError(
                f"docling-chunk-and-upload: chunk artifact {chunk_file.name} "
                f"is not present in the manifest"
            )
        s3_client.put_object(
            Bucket=bucket,
            Key=f"{chunk_prefix}/{doc['guide_slug']}_chunks.jsonl",
            Body=chunk_file.read_bytes(),
            ContentType="application/jsonl",
        )
        uploaded += 1

    if uploaded == 0:
        raise RuntimeError("docling-chunk-and-upload: no artifacts were uploaded to S3")
    print(f"docling-chunk-and-upload: uploaded {uploaded} artifact(s) to S3", flush=True)
