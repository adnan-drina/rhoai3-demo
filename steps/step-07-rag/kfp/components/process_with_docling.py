"""
Process with Docling Component — converts a downloaded PDF to Markdown
using the Docling REST API (v1).

Docling v1.14.3 API: POST /v1/convert/file
Response: {"document": {"md_content": "..."}, "status": "success|failure"}
"""

from typing import NamedTuple, Dict, Any
from kfp.dsl import component


@component(
    base_image="python:3.11",
    packages_to_install=["requests"],
)
def process_with_docling_component(
    document_path: str,
    original_key: str,
    setup_config: Dict[str, Any],
) -> NamedTuple("DoclingOutput", [("processed_file", str), ("success", bool)]):
    import requests
    import json
    import os
    import re
    import unicodedata
    import uuid
    from collections import namedtuple

    doc_config = setup_config["document_intelligence"]
    api_address = doc_config["docling_service"]
    timeout = doc_config["processing_timeout"]

    DoclingOutput = namedtuple("DoclingOutput", ["processed_file", "success"])

    print(f"Processing: {original_key}")
    print(f"  Docling: {api_address}/v1/convert/file")

    if not os.path.exists(document_path):
        print(f"  [FAIL] File not found: {document_path}")
        return DoclingOutput(processed_file="", success=False)

    with open(document_path, "rb") as f:
        file_content = f.read()
    print(f"  Read {len(file_content)} bytes")

    def _safe_ascii_name(name: str, default: str = "upload.pdf") -> str:
        if not name:
            return default
        s = unicodedata.normalize("NFKD", name)
        s = s.encode("ascii", "ignore").decode("ascii")
        s = re.sub(r"[^A-Za-z0-9._-]", "_", s).strip("._")
        if not s:
            s = default
        if not s.lower().endswith(".pdf"):
            s += ".pdf"
        return s

    safe_name = _safe_ascii_name(os.path.basename(document_path))
    files = {"files": (safe_name, file_content, "application/pdf")}

    try:
        response = requests.post(
            f"{api_address}/v1/convert/file",
            files=files,
            data={"to_formats": "md", "image_export_mode": "placeholder"},
            timeout=timeout,
        )
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"  [FAIL] Docling request: {e}")
        return DoclingOutput(processed_file="", success=False)

    try:
        result = response.json()
        status = result.get("status", "unknown")
        if status != "success":
            print(f"  [FAIL] Docling status: {status}")
            errors = result.get("errors", [])
            if errors:
                print(f"  Errors: {errors}")
            return DoclingOutput(processed_file="", success=False)

        doc = result.get("document", {})
        md_content = doc.get("md_content")
        if not md_content:
            md_content = doc.get("md") or doc.get("text_content") or ""
        if not md_content:
            print(f"  [FAIL] No markdown in response. Keys: {list(doc.keys())}")
            return DoclingOutput(processed_file="", success=False)
    except (json.JSONDecodeError, KeyError) as e:
        print(f"  [FAIL] Response parse error: {e}")
        return DoclingOutput(processed_file="", success=False)

    os.makedirs("/shared-data/processed", exist_ok=True)
    out_path = f"/shared-data/processed/{uuid.uuid4().hex}.md"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(md_content)

    print(f"  [OK] {len(md_content)} chars -> {out_path}")
    return DoclingOutput(processed_file=out_path, success=True)
