"""KFP components for Dutch government publication Docling preparation."""

import os

from kfp import dsl
from kfp.dsl import Dataset, Metrics, Output


DOCLING_BASE_IMAGE = os.getenv("DOCLING_BASE_IMAGE", "quay.io/fabianofranz/docling-ubi9:2.54.0")


@dsl.component(
    base_image=DOCLING_BASE_IMAGE,
    packages_to_install=["requests==2.32.5"],
)
def prepare_dutch_publication_chunks(
    output_chunks: Output[Dataset],
    output_metrics: Output[Metrics],
    source_url: str,
    source_filename: str,
    metadata_json: str,
    chunk_max_tokens: int = 512,
):
    """Convert a Dutch publication PDF with Docling and emit RAG chunk JSONL."""

    import json  # pylint: disable=import-outside-toplevel
    import re  # pylint: disable=import-outside-toplevel
    import tempfile  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    import requests  # pylint: disable=import-outside-toplevel
    from docling.document_converter import DocumentConverter  # pylint: disable=import-outside-toplevel

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

    metadata = json.loads(metadata_json)
    document = metadata["document"]
    articles = metadata["articles"]

    with tempfile.TemporaryDirectory(prefix="stage230-docling-") as tmpdir:
        tmp = Path(tmpdir)
        source_pdf = tmp / source_filename
        response = requests.get(source_url, timeout=60)
        response.raise_for_status()
        source_pdf.write_bytes(response.content)

        conversion = DocumentConverter().convert(str(source_pdf))
        markdown_path = tmp / f"{source_pdf.stem}.md"
        json_path = tmp / f"{source_pdf.stem}.json"
        conversion.document.save_as_markdown(markdown_path)
        conversion.document.save_as_json(json_path)
        converted_text = normalize_text(markdown_path.read_text(encoding="utf-8"))

        records = []
        for chunk_index, (article, start, end) in enumerate(find_bounds(converted_text, articles), start=1):
            article_text = normalize_text(converted_text[start:end])
            for expected in article.get("expected_terms", []):
                if expected.casefold() not in article_text.casefold():
                    raise RuntimeError(
                        f"Artikel {article['article_number']} is missing expected term {expected!r}"
                    )
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
                    "text": article_text,
                    "title": article["article_title"],
                    "topic": article["topic"],
                }
            )

    output_path = Path(output_chunks.path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")

    output_metrics.log_metric("record_count", len(records))
    output_metrics.log_metric("chunk_max_tokens", chunk_max_tokens)
    output_metrics.metadata["topics"] = ",".join(record["topic"] for record in records)
    output_metrics.metadata["source_url"] = source_url
