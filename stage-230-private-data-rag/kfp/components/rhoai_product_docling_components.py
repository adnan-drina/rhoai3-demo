"""KFP components for Stage 230 RHOAI product-document Docling preparation."""

import os

from kfp import dsl
from kfp.dsl import Dataset, Metrics, Output


DOCLING_BASE_IMAGE = os.getenv("DOCLING_BASE_IMAGE", "quay.io/fabianofranz/docling-ubi9:2.54.0")


@dsl.component(
    base_image=DOCLING_BASE_IMAGE,
    packages_to_install=["boto3==1.42.54"],
)
def prepare_rhoai_product_doc_chunks(
    output_chunks: Output[Dataset],
    output_metrics: Output[Metrics],
    manifest_json: str,
    s3_source_prefix: str,
    output_s3_key: str,
    max_chars: int = 1800,
    focus_only: bool = True,
    max_documents: int = 0,
    do_ocr: bool = False,
    do_table_structure: bool = True,
):
    """Convert RHOAI product PDFs with Docling and upload RAG chunks to S3."""

    import json  # pylint: disable=import-outside-toplevel
    import os  # pylint: disable=import-outside-toplevel
    import re  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    import boto3  # pylint: disable=import-outside-toplevel
    from botocore.config import Config  # pylint: disable=import-outside-toplevel
    from docling.datamodel.base_models import InputFormat  # pylint: disable=import-outside-toplevel
    from docling.datamodel.pipeline_options import PdfPipelineOptions  # pylint: disable=import-outside-toplevel
    from docling.document_converter import DocumentConverter, PdfFormatOption  # pylint: disable=import-outside-toplevel
    from urllib3 import disable_warnings  # pylint: disable=import-outside-toplevel
    from urllib3.exceptions import InsecureRequestWarning  # pylint: disable=import-outside-toplevel

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

    def split_text(text: str, limit: int) -> list[str]:
        paragraphs = [part.strip() for part in re.split(r"\n{2,}", text) if part.strip()]
        chunks: list[str] = []
        current: list[str] = []
        current_len = 0
        for paragraph in paragraphs:
            paragraph_len = len(paragraph)
            if current and current_len + paragraph_len + 2 > limit:
                chunks.append("\n\n".join(current))
                current = []
                current_len = 0
            if paragraph_len > limit:
                for start in range(0, paragraph_len, limit):
                    piece = paragraph[start : start + limit].strip()
                    if piece:
                        chunks.append(piece)
                continue
            current.append(paragraph)
            current_len += paragraph_len + 2
        if current:
            chunks.append("\n\n".join(current))
        return chunks

    def matched_terms(text: str, terms: list[str]) -> list[str]:
        lowered = text.casefold()
        return [term for term in terms if term.casefold() in lowered]

    def choose_topic(document: dict, text: str) -> tuple[str, list[str]]:
        for rule in document.get("topic_rules", []):
            matches = matched_terms(text, rule.get("terms", []))
            if matches:
                return rule["topic"], matches
        return document["default_topic"], []

    def s3_client():
        required = ["S3_ENDPOINT_URL", "S3_ACCESS_KEY", "S3_SECRET_KEY", "S3_BUCKET"]
        missing = [name for name in required if not os.environ.get(name)]
        if missing:
            raise RuntimeError(f"missing S3 environment variables: {missing}")
        disable_warnings(InsecureRequestWarning)
        return boto3.client(
            "s3",
            endpoint_url=os.environ["S3_ENDPOINT_URL"],
            aws_access_key_id=os.environ["S3_ACCESS_KEY"],
            aws_secret_access_key=os.environ["S3_SECRET_KEY"],
            region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
            verify=False,
            config=Config(signature_version="s3v4"),
        )

    manifest = json.loads(manifest_json)
    corpus = manifest["corpus"]
    documents = list(manifest["documents"])
    if max_documents and max_documents > 0:
        documents = documents[:max_documents]
    if not documents:
        raise RuntimeError("manifest does not contain any documents to process")

    source_prefix = s3_source_prefix.strip("/")
    output_key = output_s3_key.strip("/")
    if not source_prefix:
        raise RuntimeError("s3_source_prefix must not be empty")
    if not output_key:
        raise RuntimeError("output_s3_key must not be empty")

    client = s3_client()
    bucket = os.environ["S3_BUCKET"]
    work_dir = Path("/tmp/stage230-rhoai-product-docs")
    source_dir = work_dir / "source"
    converted_dir = work_dir / "converted"
    source_dir.mkdir(parents=True, exist_ok=True)
    converted_dir.mkdir(parents=True, exist_ok=True)

    pipeline_options = PdfPipelineOptions()
    pipeline_options.do_ocr = do_ocr
    pipeline_options.do_table_structure = do_table_structure
    converter = DocumentConverter(
        format_options={
            InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options),
        }
    )
    records: list[dict] = []
    document_counts: dict[str, int] = {}
    markdown_bytes = 0
    artifact_prefix = f"{output_key.rsplit('/', 1)[0]}/docling-artifacts"

    for document in documents:
        source_file = document["source_file"]
        source_key = f"{source_prefix}/{source_file}"
        local_pdf = source_dir / source_file
        response = client.get_object(Bucket=bucket, Key=source_key)
        payload = response["Body"].read()
        if not payload.startswith(b"%PDF"):
            raise RuntimeError(f"s3://{bucket}/{source_key} is not a PDF")
        local_pdf.write_bytes(payload)

        conversion = converter.convert(str(local_pdf))
        markdown_path = converted_dir / f"{document['guide_slug']}.md"
        docling_json_path = converted_dir / f"{document['guide_slug']}.json"
        conversion.document.save_as_markdown(markdown_path)
        conversion.document.save_as_json(docling_json_path)
        client.put_object(
            Bucket=bucket,
            Key=f"{artifact_prefix}/{document['guide_slug']}.md",
            Body=markdown_path.read_bytes(),
            ContentType="text/markdown",
        )
        client.put_object(
            Bucket=bucket,
            Key=f"{artifact_prefix}/{document['guide_slug']}.json",
            Body=docling_json_path.read_bytes(),
            ContentType="application/json",
        )
        markdown = normalize_text(markdown_path.read_text(encoding="utf-8"))
        markdown_bytes += len(markdown.encode("utf-8"))

        doc_records: list[dict] = []
        for chunk_index, chunk in enumerate(split_text(markdown, max_chars), start=1):
            topic, matches = choose_topic(document, chunk)
            focus_matches = matched_terms(chunk, document.get("focus_terms", []))
            if focus_only and not (matches or focus_matches):
                continue
            record_id = (
                f"{corpus['version']}-{document['guide_slug']}-"
                f"docling-c{chunk_index:03d}-{slugify(topic)}"
            )
            doc_records.append(
                {
                    **corpus,
                    "id": record_id,
                    "title": f"{document['title']} - Docling chunk {chunk_index}",
                    "text": chunk,
                    "topic": topic,
                    "matched_terms": sorted(set(matches + focus_matches)),
                    "guide_slug": document["guide_slug"],
                    "document_title": document["title"],
                    "documentation_category": document["documentation_category"],
                    "source_url": document["source_url"],
                    "retrieved_url": f"s3://{bucket}/{source_key}",
                    "source_file": source_file,
                    "source_format": "pdf",
                    "page_start": None,
                    "page_end": None,
                    "chunk_index": len(records) + len(doc_records) + 1,
                    "preparation_method": "docling-standard-kfp",
                    "source_artifact": "docling-markdown",
                }
            )
        if not doc_records:
            raise RuntimeError(f"Docling produced no focused chunks for {document['guide_slug']}")
        document_counts[document["guide_slug"]] = len(doc_records)
        records.extend(doc_records)

    if not records:
        raise RuntimeError("Docling conversion produced no RAG records")

    payload = "".join(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n" for record in records)
    output_path = Path(output_chunks.path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(payload, encoding="utf-8")
    client.put_object(
        Bucket=bucket,
        Key=output_key,
        Body=payload.encode("utf-8"),
        ContentType="application/jsonl",
    )
    client.head_object(Bucket=bucket, Key=output_key)

    topics = sorted({record["topic"] for record in records})
    output_metrics.log_metric("record_count", len(records))
    output_metrics.log_metric("document_count", len(documents))
    output_metrics.log_metric("payload_bytes", len(payload.encode("utf-8")))
    output_metrics.log_metric("markdown_bytes", markdown_bytes)
    output_metrics.metadata["bucket"] = bucket
    output_metrics.metadata["docling_artifact_prefix"] = artifact_prefix
    output_metrics.metadata["output_s3_key"] = output_key
    output_metrics.metadata["preparation_method"] = "docling-standard-kfp"
    output_metrics.metadata["topics"] = ",".join(topics)
    output_metrics.metadata["document_counts"] = json.dumps(document_counts, sort_keys=True)
