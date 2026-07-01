#!/usr/bin/env python3
"""Prepare Dutch government publication chunks for Stage 230 RAG ingestion.

The supported runtime path is Docling standard conversion, matching the
RHOAI data-preparation guidance and the opendatahub-io/data-processing
docling-standard pipeline shape. The pypdf converter is only for local
validation of article detection when the Docling runtime image is not present.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


DEFAULT_METADATA = Path(__file__).parents[1] / "data/dutch-government/metadata/stb-2022-14-metadata.json"
DEFAULT_SOURCE_PDF = Path(__file__).parents[1] / "data/dutch-government/source/stb-2022-14.pdf"
DEFAULT_OUTPUT = Path(__file__).parents[1] / "data/dutch-government/processed/stb-2022-14-docling-chunks.jsonl"


def load_metadata(path: Path) -> dict[str, Any]:
    metadata = json.loads(path.read_text(encoding="utf-8"))
    if not metadata.get("document") or not metadata.get("articles"):
        raise ValueError(f"{path} must contain document and articles sections")
    return metadata


def slug_article(article_number: str) -> str:
    return article_number.replace(".", "-")


def normalize_text(text: str) -> str:
    text = text.replace("\u00a0", " ")
    text = re.sub(r"Staatsblad 2022 14 \d+", "", text)
    text = re.sub(r"(?<=\w)-\s*\n\s*(?=\w)", "", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def article_bounds(text: str, articles: list[dict[str, Any]]) -> list[tuple[dict[str, Any], int, int]]:
    starts: list[tuple[dict[str, Any], int]] = []
    for article in articles:
        number = re.escape(str(article["article_number"]))
        match = re.search(rf"\bArtikel\s+{number}\b", text)
        if not match:
            raise RuntimeError(f"could not find Artikel {article['article_number']} in converted text")
        starts.append((article, match.start()))

    bounds = []
    for idx, (article, start) in enumerate(starts):
        end = starts[idx + 1][1] if idx + 1 < len(starts) else len(text)
        bounds.append((article, start, end))
    return bounds


def build_records(text: str, metadata: dict[str, Any], preparation_method: str) -> list[dict[str, Any]]:
    document = metadata["document"]
    records = []
    for chunk_index, (article, start, end) in enumerate(article_bounds(text, metadata["articles"]), start=1):
        article_text = normalize_text(text[start:end])
        for expected in article.get("expected_terms", []):
            if expected.casefold() not in article_text.casefold():
                raise RuntimeError(
                    f"Artikel {article['article_number']} is missing expected term {expected!r}"
                )
        article_number = str(article["article_number"])
        record = {
            **document,
            "article_number": article_number,
            "article_title": article["article_title"],
            "chunk_index": chunk_index,
            "id": f"{document['version']}-artikel-{slug_article(article_number)}",
            "preparation_method": preparation_method,
            "text": article_text,
            "title": article["article_title"],
            "topic": article["topic"],
        }
        records.append(record)
    return records


def write_jsonl(records: list[dict[str, Any]], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def convert_with_docling(source_pdf: Path, converted_dir: Path) -> str:
    try:
        from docling.document_converter import DocumentConverter
    except ImportError as exc:
        raise RuntimeError(
            "Docling is not installed. Run this helper in the Docling KFP image "
            "or use --converter pypdf only for local article-detection validation."
        ) from exc

    converted_dir.mkdir(parents=True, exist_ok=True)
    result = DocumentConverter().convert(str(source_pdf))
    markdown_path = converted_dir / f"{source_pdf.stem}.md"
    json_path = converted_dir / f"{source_pdf.stem}.json"
    result.document.save_as_markdown(markdown_path)
    result.document.save_as_json(json_path)
    return markdown_path.read_text(encoding="utf-8")


def convert_with_pypdf(source_pdf: Path, converted_dir: Path) -> str:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError("pypdf is not installed in this Python environment") from exc

    converted_dir.mkdir(parents=True, exist_ok=True)
    reader = PdfReader(str(source_pdf))
    text = "\n".join(page.extract_text() or "" for page in reader.pages)
    text_path = converted_dir / f"{source_pdf.stem}.pypdf.txt"
    text_path.write_text(text, encoding="utf-8")
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-pdf", type=Path, default=DEFAULT_SOURCE_PDF)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--converted-dir",
        type=Path,
        default=Path(__file__).parents[1] / "data/dutch-government/processed/docling",
    )
    parser.add_argument(
        "--converter",
        choices=("docling", "pypdf"),
        default="docling",
        help="Use docling for the supported path; pypdf is a local validation helper.",
    )
    args = parser.parse_args()

    if not args.source_pdf.exists():
        raise SystemExit(f"source PDF not found: {args.source_pdf}")

    metadata = load_metadata(args.metadata)
    if args.converter == "docling":
        text = convert_with_docling(args.source_pdf, args.converted_dir)
        preparation_method = "docling-standard"
    else:
        text = convert_with_pypdf(args.source_pdf, args.converted_dir)
        preparation_method = "pypdf-local-validation"

    records = build_records(normalize_text(text), metadata, preparation_method)
    write_jsonl(records, args.output)
    print(
        json.dumps(
            {
                "status": "pass",
                "converter": args.converter,
                "preparation_method": preparation_method,
                "source_pdf": str(args.source_pdf),
                "output": str(args.output),
                "record_count": len(records),
                "topics": [record["topic"] for record in records],
            },
            indent=2,
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - concise CLI diagnostics.
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
