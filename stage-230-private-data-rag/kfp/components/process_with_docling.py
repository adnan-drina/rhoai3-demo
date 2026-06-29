"""Convert downloaded PDF documents to Markdown through Docling Serve."""

from typing import NamedTuple

from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.4.0",
    packages_to_install=["requests>=2.32.0"],
    pip_index_urls=["https://pypi.org/simple"],
)
def process_with_docling_component(
    document_path: str,
    docling_service: str,
    processing_timeout: int,
) -> NamedTuple("DoclingOutput", [("processed_file", str), ("success", bool)]):
    """Convert a PDF file to Markdown and store it in the shared PVC."""
    import json
    import os
    import re
    import unicodedata
    from collections import namedtuple

    import requests

    DoclingOutput = namedtuple("DoclingOutput", ["processed_file", "success"])

    def safe_pdf_name(name: str) -> str:
        normalized = unicodedata.normalize("NFKD", name or "document.pdf")
        ascii_name = normalized.encode("ascii", "ignore").decode("ascii")
        ascii_name = re.sub(r"[^A-Za-z0-9._-]", "_", ascii_name).strip("._")
        if not ascii_name:
            ascii_name = "document.pdf"
        if not ascii_name.lower().endswith(".pdf"):
            ascii_name += ".pdf"
        return ascii_name

    if not os.path.exists(document_path):
        raise RuntimeError(f"Document not found: {document_path}")

    with open(document_path, "rb") as handle:
        files = {
            "files": (
                safe_pdf_name(os.path.basename(document_path)),
                handle.read(),
                "application/pdf",
            )
        }

    response = requests.post(
        f"{docling_service.rstrip('/')}/v1/convert/file",
        files=files,
        data={"to_formats": "md", "image_export_mode": "placeholder"},
        timeout=processing_timeout,
    )
    response.raise_for_status()

    payload = response.json()
    status = payload.get("status", "success")
    if status != "success":
        raise RuntimeError(f"Docling conversion failed: {json.dumps(payload)[:500]}")

    document = payload.get("document", {})
    markdown = document.get("md_content") or document.get("md") or document.get("text_content") or ""
    if not markdown.strip():
        raise RuntimeError(f"Docling returned no Markdown. Document keys: {list(document.keys())}")

    output_dir = "/shared-data/processed"
    os.makedirs(output_dir, exist_ok=True)
    base_name = os.path.splitext(os.path.basename(document_path))[0]
    output_path = os.path.join(output_dir, f"{base_name}.md")
    with open(output_path, "w", encoding="utf-8") as handle:
        handle.write(markdown)

    print(f"Converted {document_path} -> {output_path} ({len(markdown)} chars)")
    return DoclingOutput(processed_file=output_path, success=True)
