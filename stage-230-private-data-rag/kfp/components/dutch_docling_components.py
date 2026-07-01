"""KFP components for Stage 230 Dutch publication Docling preparation."""

import os

from kfp import dsl
from kfp.dsl import Dataset, Input, Metrics, Output


DOCLING_BASE_IMAGE = os.getenv("DOCLING_BASE_IMAGE", "quay.io/fabianofranz/docling-ubi9:2.54.0")


@dsl.component(
    base_image=DOCLING_BASE_IMAGE,
    packages_to_install=["boto3==1.42.0"],
)
def download_pdf_from_s3(
    output_pdf: Output[Dataset],
    output_metrics: Output[Metrics],
    s3_pdf_key: str,
    source_filename: str,
):
    """Download the source PDF from the project S3 bucket."""

    import os  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    import boto3  # pylint: disable=import-outside-toplevel
    from botocore.config import Config  # pylint: disable=import-outside-toplevel
    from urllib3 import disable_warnings  # pylint: disable=import-outside-toplevel
    from urllib3.exceptions import InsecureRequestWarning  # pylint: disable=import-outside-toplevel

    required = ["S3_ENDPOINT_URL", "S3_ACCESS_KEY", "S3_SECRET_KEY", "S3_BUCKET"]
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError(f"missing S3 environment variables: {missing}")

    disable_warnings(InsecureRequestWarning)
    client = boto3.client(
        "s3",
        endpoint_url=os.environ["S3_ENDPOINT_URL"],
        aws_access_key_id=os.environ["S3_ACCESS_KEY"],
        aws_secret_access_key=os.environ["S3_SECRET_KEY"],
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        verify=False,
        config=Config(signature_version="s3v4"),
    )

    key = s3_pdf_key.strip("/")
    if not key:
        raise RuntimeError("s3_pdf_key must not be empty")

    response = client.get_object(Bucket=os.environ["S3_BUCKET"], Key=key)
    data = response["Body"].read()
    if not data.startswith(b"%PDF"):
        raise RuntimeError(f"s3://{os.environ['S3_BUCKET']}/{key} is not a PDF")

    output_path = Path(output_pdf.path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(data)

    output_metrics.log_metric("source_bytes", len(data))
    output_metrics.metadata["source_filename"] = source_filename
    output_metrics.metadata["source_s3_key"] = key


@dsl.component(base_image=DOCLING_BASE_IMAGE)
def convert_pdf_with_docling(
    input_pdf: Input[Dataset],
    output_markdown: Output[Dataset],
    output_docling_json: Output[Dataset],
    output_metrics: Output[Metrics],
):
    """Convert a source PDF with Docling and persist Markdown plus Docling JSON."""

    from pathlib import Path  # pylint: disable=import-outside-toplevel

    from docling.document_converter import DocumentConverter  # pylint: disable=import-outside-toplevel

    source_pdf = Path(input_pdf.path)
    if not source_pdf.exists() or source_pdf.stat().st_size == 0:
        raise RuntimeError(f"input PDF artifact is missing or empty: {source_pdf}")

    markdown_path = Path(output_markdown.path)
    docling_json_path = Path(output_docling_json.path)
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    docling_json_path.parent.mkdir(parents=True, exist_ok=True)

    conversion = DocumentConverter().convert(str(source_pdf))
    conversion.document.save_as_markdown(markdown_path)
    conversion.document.save_as_json(docling_json_path)

    markdown_text = markdown_path.read_text(encoding="utf-8")
    output_metrics.log_metric("markdown_chars", len(markdown_text))
    output_metrics.log_metric("docling_json_bytes", docling_json_path.stat().st_size)


@dsl.component(
    base_image=DOCLING_BASE_IMAGE,
    packages_to_install=["boto3==1.42.0"],
)
def build_dutch_publication_chunks(
    input_markdown: Input[Dataset],
    input_docling_json: Input[Dataset],
    output_chunks: Output[Dataset],
    output_metrics: Output[Metrics],
    metadata_json: str,
    output_s3_key: str,
    chunk_max_tokens: int = 512,
):
    """Build validated RAG chunks from Docling output and upload them to S3."""

    import json  # pylint: disable=import-outside-toplevel
    import os  # pylint: disable=import-outside-toplevel
    import re  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    import boto3  # pylint: disable=import-outside-toplevel
    from botocore.config import Config  # pylint: disable=import-outside-toplevel
    from urllib3 import disable_warnings  # pylint: disable=import-outside-toplevel
    from urllib3.exceptions import InsecureRequestWarning  # pylint: disable=import-outside-toplevel

    def normalize_text(value: str) -> str:
        value = value.replace("\u00a0", " ")
        value = re.sub(r"Staatsblad 2022 14 \d+", "", value)
        value = re.sub(r"(?<=\w)-\s*\n\s*(?=\w)", "", value)
        value = re.sub(r"[ \t]+", " ", value)
        value = re.sub(r"\n[ \t]+", "\n", value)
        value = re.sub(r"\n{3,}", "\n\n", value)
        return value.strip()

    def slug_article(article_number: str) -> str:
        return article_number.replace(".", "-")

    def find_bounds(text: str, articles: list[dict]) -> list[tuple[dict, int, int]]:
        starts = []
        for article in articles:
            number = re.escape(str(article["article_number"]))
            match = re.search(rf"\bArtikel\s+{number}\b", text)
            if not match:
                raise RuntimeError(f"could not find Artikel {article['article_number']} in Docling text")
            starts.append((article, match.start()))
        bounds = []
        for index, (article, start) in enumerate(starts):
            end = starts[index + 1][1] if index + 1 < len(starts) else len(text)
            bounds.append((article, start, end))
        return bounds

    required = ["S3_ENDPOINT_URL", "S3_ACCESS_KEY", "S3_SECRET_KEY", "S3_BUCKET"]
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError(f"missing S3 environment variables: {missing}")

    markdown_path = Path(input_markdown.path)
    docling_json_path = Path(input_docling_json.path)
    if not markdown_path.exists() or markdown_path.stat().st_size == 0:
        raise RuntimeError(f"Docling Markdown artifact is missing or empty: {markdown_path}")
    if not docling_json_path.exists() or docling_json_path.stat().st_size == 0:
        raise RuntimeError(f"Docling JSON artifact is missing or empty: {docling_json_path}")

    metadata = json.loads(metadata_json)
    document = metadata["document"]
    articles = metadata["articles"]
    converted_text = normalize_text(markdown_path.read_text(encoding="utf-8"))

    records = []
    for chunk_index, (article, start, end) in enumerate(find_bounds(converted_text, articles), start=1):
        article_text = normalize_text(converted_text[start:end])
        for expected in article.get("expected_terms", []):
            if expected.casefold() not in article_text.casefold():
                raise RuntimeError(f"Artikel {article['article_number']} is missing expected term {expected!r}")
        article_number = str(article["article_number"])
        records.append(
            {
                **document,
                "article_number": article_number,
                "article_title": article["article_title"],
                "chunk_index": chunk_index,
                "chunk_max_tokens": chunk_max_tokens,
                "id": f"{document['version']}-artikel-{slug_article(article_number)}",
                "preparation_method": "docling-standard-kfp",
                "source_artifact": "docling-markdown",
                "text": article_text,
                "title": article["article_title"],
                "topic": article["topic"],
            }
        )

    if not records:
        raise RuntimeError("Docling conversion produced no RAG records")

    output_path = Path(output_chunks.path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = "".join(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n" for record in records)
    output_path.write_text(payload, encoding="utf-8")

    disable_warnings(InsecureRequestWarning)
    client = boto3.client(
        "s3",
        endpoint_url=os.environ["S3_ENDPOINT_URL"],
        aws_access_key_id=os.environ["S3_ACCESS_KEY"],
        aws_secret_access_key=os.environ["S3_SECRET_KEY"],
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        verify=False,
        config=Config(signature_version="s3v4"),
    )
    key = output_s3_key.strip("/")
    if not key:
        raise RuntimeError("output_s3_key must not be empty")
    client.put_object(
        Bucket=os.environ["S3_BUCKET"],
        Key=key,
        Body=payload.encode("utf-8"),
        ContentType="application/jsonl",
    )
    client.head_object(Bucket=os.environ["S3_BUCKET"], Key=key)

    output_metrics.log_metric("record_count", len(records))
    output_metrics.log_metric("chunk_max_tokens", chunk_max_tokens)
    output_metrics.log_metric("payload_bytes", len(payload.encode("utf-8")))
    output_metrics.metadata["topics"] = ",".join(record["topic"] for record in records)
    output_metrics.metadata["output_s3_key"] = key
    output_metrics.metadata["source_url"] = document.get("source_url", "")
