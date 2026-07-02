"""Enrich Docling chunk artifacts with RHOAI product-document metadata and
publish the final RAG JSONL handoff to S3.

Reads per-split converted Markdown/JSON and chunk JSONL artifacts from S3,
applies metadata enrichment (topic rules, focus terms, corpus fields), and
writes a single combined JSONL file to S3 for downstream RAG ingestion.
"""

from kfp import dsl
from kfp.dsl import Dataset, Metrics, Output

from .constants import PYTHON_BASE_IMAGE


@dsl.component(
    base_image=PYTHON_BASE_IMAGE,
    packages_to_install=["boto3==1.42.54"],
)
def enrich_and_publish_rhoai_chunks(
    output_chunks: Output[Dataset],
    output_metrics: Output[Metrics],
    manifest_json: str,
    output_s3_key: str,
    focus_only: bool = True,
    s3_secret_mount_path: str = "/mnt/secrets",
):
    """Create metadata-rich JSONL chunks from Docling HybridChunker output."""

    import json  # pylint: disable=import-outside-toplevel
    import re  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    import boto3  # pylint: disable=import-outside-toplevel
    from botocore.exceptions import ClientError  # pylint: disable=import-outside-toplevel
    from botocore.config import Config  # pylint: disable=import-outside-toplevel
    from urllib3 import disable_warnings  # pylint: disable=import-outside-toplevel
    from urllib3.exceptions import InsecureRequestWarning  # pylint: disable=import-outside-toplevel

    def secret_value(name: str) -> str:
        value_path = Path(s3_secret_mount_path) / name
        if not value_path.is_file():
            raise RuntimeError(f"missing S3 Secret key {name} in {s3_secret_mount_path}")
        return value_path.read_text(encoding="utf-8").strip()

    def normalize_text(value: str) -> str:
        value = value.replace("\u00a0", " ")
        value = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", " ", value)
        value = re.sub(r"(?<=\w)-\s*\n\s*(?=\w)", "", value)
        value = re.sub(r"[ \t]+", " ", value)
        value = re.sub(r"\n[ \t]+", "\n", value)
        value = re.sub(r"\n{3,}", "\n\n", value)
        return value.strip()

    def slugify(value: str) -> str:
        value = value.lower()
        value = re.sub(r"[^a-z0-9]+", "-", value)
        return value.strip("-")

    def matched_terms(text: str, terms: list[str]) -> list[str]:
        lowered = text.casefold()
        return [term for term in terms if term.casefold() in lowered]

    def choose_topic(document: dict, text: str) -> tuple[str, list[str]]:
        for rule in document.get("topic_rules", []):
            matches = matched_terms(text, rule.get("terms", []))
            if matches:
                return rule["topic"], matches
        return document["default_topic"], []

    def require_s3_object(key: str) -> int:
        try:
            response = s3_client.head_object(Bucket=bucket, Key=key)
        except ClientError as exc:
            raise RuntimeError(f"required S3 artifact is missing: s3://{bucket}/{key}") from exc
        return int(response.get("ContentLength", 0))

    def read_s3_text(key: str) -> str:
        try:
            response = s3_client.get_object(Bucket=bucket, Key=key)
        except ClientError as exc:
            raise RuntimeError(f"required S3 artifact is missing: s3://{bucket}/{key}") from exc
        return response["Body"].read().decode("utf-8")

    manifest = json.loads(manifest_json)
    corpus = manifest["corpus"]
    documents = manifest.get("documents", [])
    if not documents:
        raise RuntimeError("manifest does not contain selected documents")

    document_by_stem = {Path(document["source_file"]).stem: document for document in documents}
    output_key = output_s3_key.strip("/")
    if not output_key:
        raise RuntimeError("output_s3_key must not be empty")

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

    output_prefix = output_key.rsplit("/", 1)[0]
    artifact_prefix = f"{output_prefix}/docling-artifacts"
    chunk_prefix = f"{output_prefix}/docling-chunks"
    verified_artifacts = 0
    markdown_bytes = 0
    for document in documents:
        json_key = f"{artifact_prefix}/{document['guide_slug']}.json"
        md_key = f"{artifact_prefix}/{document['guide_slug']}.md"
        verified_artifacts += 1
        require_s3_object(json_key)
        verified_artifacts += 1
        markdown_bytes += require_s3_object(md_key)

    records: list[dict] = []
    document_counts: dict[str, int] = {}
    source_prefix = secret_value("S3_PREFIX").strip("/")
    for document in documents:
        chunk_key = f"{chunk_prefix}/{document['guide_slug']}_chunks.jsonl"
        chunk_payload = read_s3_text(chunk_key)
        doc_records: list[dict] = []
        for line in chunk_payload.splitlines():
            if not line.strip():
                continue
            chunk_record = json.loads(line)
            text = normalize_text(chunk_record.get("text", ""))
            if not text:
                continue
            topic, topic_matches = choose_topic(document, text)
            focus_matches = matched_terms(text, document.get("focus_terms", []))
            if focus_only and not (topic_matches or focus_matches):
                continue
            chunk_index = int(chunk_record.get("chunk_index", len(doc_records) + 1))
            record_id = (
                f"{corpus['version']}-{document['guide_slug']}-"
                f"docling-hybrid-c{chunk_index:03d}-{slugify(topic)}"
            )
            doc_records.append(
                {
                    **corpus,
                    "id": record_id,
                    "title": f"{document['title']} - Docling HybridChunker chunk {chunk_index}",
                    "text": text,
                    "topic": topic,
                    "matched_terms": sorted(set(topic_matches + focus_matches)),
                    "guide_slug": document["guide_slug"],
                    "document_title": document["title"],
                    "documentation_category": document["documentation_category"],
                    "source_url": document["source_url"],
                    "retrieved_url": f"s3://{bucket}/{source_prefix}/{document['source_file']}",
                    "source_file": document["source_file"],
                    "source_format": "pdf",
                    "page_start": None,
                    "page_end": None,
                    "chunk_index": len(records) + len(doc_records) + 1,
                    "docling_chunk_index": chunk_index,
                    "chunking_config": chunk_record.get("chunking_config", {}),
                    "preparation_method": "docling-standard-hybridchunker-kfp",
                    "source_artifact": "docling-hybridchunker-jsonl",
                    "docling_artifact_prefix": f"s3://{bucket}/{artifact_prefix}",
                    "chunk_artifact": f"s3://{bucket}/{chunk_key}",
                }
            )
        if not doc_records:
            raise RuntimeError(f"Docling produced no focused chunks for {document['guide_slug']}")
        document_counts[document["guide_slug"]] = len(doc_records)
        records.extend(doc_records)

    if not records:
        raise RuntimeError("Docling HybridChunker output produced no RAG records")
    if verified_artifacts == 0:
        raise RuntimeError("no converted Markdown or Docling JSON artifacts were verified")

    payload = "".join(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n" for record in records)
    output_path = Path(output_chunks.path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(payload, encoding="utf-8")
    s3_client.put_object(
        Bucket=bucket,
        Key=output_key,
        Body=payload.encode("utf-8"),
        ContentType="application/jsonl",
    )
    s3_client.head_object(Bucket=bucket, Key=output_key)

    topics = sorted({record["topic"] for record in records})
    output_metrics.log_metric("record_count", len(records))
    output_metrics.log_metric("document_count", len(documents))
    output_metrics.log_metric("payload_bytes", len(payload.encode("utf-8")))
    output_metrics.log_metric("markdown_bytes", markdown_bytes)
    output_metrics.log_metric("verified_artifact_count", verified_artifacts)
    output_metrics.metadata["bucket"] = bucket
    output_metrics.metadata["docling_artifact_prefix"] = artifact_prefix
    output_metrics.metadata["docling_chunk_prefix"] = chunk_prefix
    output_metrics.metadata["output_s3_key"] = output_key
    output_metrics.metadata["preparation_method"] = "docling-standard-hybridchunker-kfp"
    output_metrics.metadata["topics"] = ",".join(topics)
    output_metrics.metadata["document_counts"] = json.dumps(document_counts, sort_keys=True)
