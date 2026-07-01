#!/usr/bin/env python3
"""Prepare official RHOAI 3.4 product PDF chunks for Stage 230 RAG.

The supported product-document path is the same Stage 230 RAG ingestion path:
official source capture, PDF conversion, metadata-rich chunks, Files API upload,
Vector Stores API attachment, hybrid retrieval, reranking, and MaaS-backed
Nemotron answers. This helper prepares chunks from the repo-stored product
PDFs. Use --force-download only when intentionally refreshing the active
baseline from docs.redhat.com.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import ssl
import sys
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).parents[1]
DEFAULT_MANIFEST = ROOT / "data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json"
DEFAULT_SOURCE_DIR = ROOT / "data/rhoai-product-docs/source"
DEFAULT_OUTPUT = ROOT / "data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl"


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if not manifest.get("corpus") or not manifest.get("documents"):
        raise ValueError(f"{path} must contain corpus and documents")
    return manifest


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


def is_pdf(path: Path) -> bool:
    return path.exists() and path.read_bytes()[:4] == b"%PDF"


def request_url(url: str, accept: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 rhoai3-demo-stage230/1.0",
            "Accept": accept,
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    context = ssl._create_unverified_context()
    with urllib.request.urlopen(request, context=context, timeout=120) as response:
        return response.read()


def download_pdf(url: str, destination: Path, force: bool) -> None:
    if is_pdf(destination) and not force:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    payload = request_url(url, "application/pdf,*/*")
    if not payload.startswith(b"%PDF"):
        raise RuntimeError(f"download did not return a PDF for {url}")
    destination.write_bytes(payload)


def download_html(url: str, destination: Path, force: bool) -> None:
    if destination.exists() and destination.stat().st_size > 0 and not force:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    payload = request_url(url, "text/html,*/*")
    text = payload.decode("utf-8", errors="replace")
    if "<html" not in text.lower():
        raise RuntimeError(f"download did not return HTML for {url}")
    destination.write_text(text, encoding="utf-8")


def download_source(document: dict[str, Any], source_dir: Path, force: bool) -> tuple[Path, str, str]:
    pdf_path = source_dir / document["source_file"]
    if is_pdf(pdf_path) and not force:
        return pdf_path, "pdf", document["source_url"]
    if not force:
        raise FileNotFoundError(
            f"missing staged product PDF: {pdf_path}. "
            "Restore the repo-stored source file or run with --force-download "
            "when intentionally refreshing the corpus."
        )
    try:
        download_pdf(document["source_url"], pdf_path, force=True)
        return pdf_path, "pdf", document["source_url"]
    except Exception as exc:  # noqa: BLE001 - fallback keeps official Red Hat content usable.
        html_url = document.get("html_single_url")
        if not html_url:
            raise
        html_path = source_dir / f"{Path(document['source_file']).stem}.html"
        print(f"WARN: PDF download failed for {document['guide_slug']}: {exc}; using html-single source", file=sys.stderr)
        download_html(html_url, html_path, force)
        return html_path, "html-single", html_url


def extract_pdf_pages(path: Path) -> list[tuple[int, str]]:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError("pypdf is required for product-document preparation") from exc

    reader = PdfReader(str(path))
    pages: list[tuple[int, str]] = []
    for page_index, page in enumerate(reader.pages, start=1):
        text = normalize_text(page.extract_text() or "")
        if text:
            pages.append((page_index, text))
    if not pages:
        raise RuntimeError(f"no extractable text found in {path}")
    return pages


def strip_html_to_text(path: Path) -> str:
    text = path.read_text(encoding="utf-8", errors="replace")
    article_match = re.search(r"<article\b.*?</article>", text, flags=re.IGNORECASE | re.DOTALL)
    if article_match:
        text = article_match.group(0)
    text = re.sub(r"<script\b.*?</script>", " ", text, flags=re.IGNORECASE | re.DOTALL)
    text = re.sub(r"<style\b.*?</style>", " ", text, flags=re.IGNORECASE | re.DOTALL)
    text = re.sub(r"</(h[1-6]|p|li|tr|div|section|table)>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    return normalize_text(text)


def extract_source_pages(path: Path, source_format: str) -> list[tuple[int, str]]:
    if source_format == "pdf":
        return extract_pdf_pages(path)
    if source_format == "html-single":
        text = strip_html_to_text(path)
        chunks = split_text(text, 12000)
        return [(index, chunk) for index, chunk in enumerate(chunks, start=1) if chunk]
    raise ValueError(f"unsupported source format: {source_format}")


def split_text(text: str, max_chars: int) -> list[str]:
    paragraphs = [paragraph.strip() for paragraph in re.split(r"\n{2,}", text) if paragraph.strip()]
    chunks: list[str] = []
    current: list[str] = []
    current_len = 0
    for paragraph in paragraphs:
        paragraph_len = len(paragraph)
        if current and current_len + paragraph_len + 2 > max_chars:
            chunks.append("\n\n".join(current))
            current = []
            current_len = 0
        if paragraph_len > max_chars:
            for start in range(0, paragraph_len, max_chars):
                piece = paragraph[start : start + max_chars].strip()
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


def choose_topic(document: dict[str, Any], text: str) -> tuple[str, list[str]]:
    for rule in document.get("topic_rules", []):
        matches = matched_terms(text, rule.get("terms", []))
        if matches:
            return rule["topic"], matches
    return document["default_topic"], []


def prepare_document(
    corpus: dict[str, Any],
    document: dict[str, Any],
    source_dir: Path,
    max_chars: int,
    focus_only: bool,
    force_download: bool,
) -> list[dict[str, Any]]:
    source_path, source_format, retrieved_url = download_source(document, source_dir, force_download)
    pages = extract_source_pages(source_path, source_format)

    records: list[dict[str, Any]] = []
    for page_number, page_text in pages:
        for page_chunk_index, chunk in enumerate(split_text(page_text, max_chars), start=1):
            topic, matches = choose_topic(document, chunk)
            focus_matches = matched_terms(chunk, document.get("focus_terms", []))
            if focus_only and not (matches or focus_matches):
                continue
            record_id = (
                f"{corpus['version']}-{document['guide_slug']}-"
                f"p{page_number:03d}-c{page_chunk_index:02d}-{slugify(topic)}"
            )
            records.append(
                {
                    **corpus,
                    "id": record_id,
                    "title": f"{document['title']} - page {page_number}",
                    "text": chunk,
                    "topic": topic,
                    "matched_terms": sorted(set(matches + focus_matches)),
                    "guide_slug": document["guide_slug"],
                    "document_title": document["title"],
                    "documentation_category": document["documentation_category"],
                    "source_url": document["source_url"],
                    "retrieved_url": retrieved_url,
                    "source_file": document["source_file"],
                    "source_format": source_format,
                    "page_start": page_number,
                    "page_end": page_number,
                    "chunk_index": len(records) + 1,
                    "preparation_method": "pypdf-product-docs",
                }
            )
    if not records:
        raise RuntimeError(f"no focused records generated for {document['guide_slug']}")
    return records


def write_jsonl(records: list[dict[str, Any]], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE_DIR)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--max-chars", type=int, default=4500)
    parser.add_argument("--include-all", action="store_true", help="Keep non-focused chunks too.")
    parser.add_argument(
        "--force-download",
        action="store_true",
        help="Refresh staged source PDFs from docs.redhat.com before preparing chunks.",
    )
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    records: list[dict[str, Any]] = []
    doc_counts: dict[str, int] = {}
    for document in manifest["documents"]:
        document_records = prepare_document(
            manifest["corpus"],
            document,
            args.source_dir,
            args.max_chars,
            focus_only=not args.include_all,
            force_download=args.force_download,
        )
        records.extend(document_records)
        doc_counts[document["guide_slug"]] = len(document_records)

    write_jsonl(records, args.output)
    topics = sorted({record["topic"] for record in records})
    print(
        json.dumps(
            {
                "status": "pass",
                "manifest": str(args.manifest),
                "source_dir": str(args.source_dir),
                "output": str(args.output),
                "record_count": len(records),
                "document_counts": doc_counts,
                "topics": topics,
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
