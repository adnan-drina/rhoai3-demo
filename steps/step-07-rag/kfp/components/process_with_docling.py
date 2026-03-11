"""
Process with Docling Component — converts a downloaded PDF to Markdown
using the Docling REST API.

Includes two-format fallback logic (flat fields vs options JSON) and
multi-shape response extraction adopted from rhoai-genaiops.
Writes results to /shared-data/processed/.
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

    print(f"Processing: {original_key}")
    print(f"  Docling: {api_address}/v1alpha/convert/file")

    DoclingOutput = namedtuple("DoclingOutput", ["processed_file", "success"])

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

    attempts = [
        {"desc": "flat fields", "data": {"to_formats": "md", "image_export_mode": "placeholder"}},
        {"desc": "options JSON", "data": {"options": json.dumps({"to_formats": ["md"], "image_export_mode": "placeholder"})}},
    ]

    last_err = None
    response = None
    for attempt in attempts:
        print(f"  -> Trying {attempt['desc']}...")
        try:
            response = requests.post(
                f"{api_address}/v1alpha/convert/file",
                files=files,
                data=attempt["data"],
                timeout=timeout,
            )
            if response.status_code == 422:
                last_err = f"422 {response.text[:400]}"
                continue
            response.raise_for_status()
            break
        except requests.exceptions.RequestException as e:
            last_err = str(e)
            continue
    else:
        print(f"  [FAIL] Docling failed after retries: {last_err}")
        return DoclingOutput(processed_file="", success=False)

    def _extract_md(payload: dict) -> str:
        if isinstance(payload, dict):
            doc = payload.get("document")
            if isinstance(doc, dict):
                for k in ("md_content", "md"):
                    if isinstance(doc.get(k), str):
                        return doc[k]
                content = doc.get("content")
                if isinstance(content, dict) and isinstance(content.get("md"), str):
                    return content["md"]
            docs = payload.get("documents")
            if isinstance(docs, list) and docs:
                first = docs[0]
                if isinstance(first, dict):
                    for k in ("md_content", "md"):
                        if isinstance(first.get(k), str):
                            return first[k]
            res = payload.get("result")
            if isinstance(res, dict) and isinstance(res.get("md"), str):
                return res["md"]
        raise KeyError(f"No markdown found. Keys: {list(payload) if isinstance(payload, dict) else type(payload).__name__}")

    try:
        md_content = _extract_md(response.json())
    except (KeyError, json.JSONDecodeError) as e:
        print(f"  [FAIL] Response parse error: {e}")
        return DoclingOutput(processed_file="", success=False)

    os.makedirs("/shared-data/processed", exist_ok=True)
    out_path = f"/shared-data/processed/{uuid.uuid4().hex}.md"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(md_content)

    print(f"  [OK] {len(md_content)} chars -> {out_path}")
    return DoclingOutput(processed_file=out_path, success=True)
