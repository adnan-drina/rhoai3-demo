"""
Insert via LlamaStack Component — reads processed markdown from the shared PVC
and ingests it into pgvector through LlamaStack's vector_stores.files.create() API.

Server-side chunking and embedding: LlamaStack handles both using the
granite-embedding-125m model registered in the LSD configuration.

Uses 0.4.x API: files.create() for upload, then vector_stores.files.create()
for indexing with static chunking strategy.
"""

from typing import NamedTuple, Dict, Any, List
from kfp.dsl import component


@component(
    base_image="registry.redhat.io/ubi9/python-312:latest",
    packages_to_install=["llama_stack_client>=0.4,<0.5"],
)
def insert_via_llamastack_component(
    setup_config: Dict[str, Any],
    processed_file: str,
    original_key: str,
    bucket_name: str,
    vector_db_ids: List[str],
) -> NamedTuple("InsertOutput", [("status", str), ("chunks_inserted", int)]):
    """Ingest processed Markdown into pgvector via LlamaStack vector_stores API.

    Args:
        setup_config: Runtime configuration dict from setup_config_component.
        processed_file: Path to the Markdown file on the shared PVC.
        original_key: Original S3 key for metadata attributes.
        bucket_name: S3 bucket name for source attribution.
        vector_db_ids: List of vector store IDs to index into.

    Returns:
        status: Insertion status (success, skipped, or error).
        chunks_inserted: Number of vector stores successfully indexed.
    """
    from llama_stack_client import LlamaStackClient
    from collections import namedtuple
    from pathlib import Path
    import os

    InsertOutput = namedtuple("InsertOutput", ["status", "chunks_inserted"])

    base_url = setup_config["base_url"]
    chunk_size = setup_config["document_intelligence"]["chunk_size_tokens"]
    vector_db_id = setup_config["vector_db_id"]

    if not vector_db_ids:
        vector_db_ids = [vector_db_id]

    if not processed_file or not os.path.exists(processed_file):
        print(f"  [SKIP] No processed file for {original_key}")
        return InsertOutput(status="skipped", chunks_inserted=0)

    file_path = Path(processed_file)
    content = file_path.read_text(encoding="utf-8")
    content_len = len(content)
    print(f"Inserting: {original_key} ({content_len} chars)")
    print(f"  LlamaStack: {base_url}")
    print(f"  Vector stores: {vector_db_ids}")

    client = LlamaStackClient(base_url=base_url, timeout=300.0)

    # Upload the markdown file to LlamaStack Files API
    # Use a descriptive filename based on the original PDF key
    upload_name = original_key.replace("/", "_").replace(" ", "_")
    for prefix in ("rag-documents_", "_shared-data_documents_"):
        if upload_name.startswith(prefix):
            upload_name = upload_name[len(prefix):]
    if not upload_name.endswith(".md"):
        upload_name = upload_name.rsplit(".", 1)[0] + ".md" if "." in upload_name else upload_name + ".md"

    try:
        with open(processed_file, "rb") as f:
            uploaded = client.files.create(
                file=(upload_name, f),
                purpose="assistants",
            )
        print(f"  Uploaded: {uploaded.id} ({upload_name})")
    except Exception as e:
        print(f"  [FAIL] File upload: {e}")
        return InsertOutput(status="error", chunks_inserted=0)

    # Index into each vector store
    chunk_overlap = max(1, chunk_size // 4)
    chunking_strategy = {
        "type": "static",
        "static": {
            "max_chunk_size_tokens": chunk_size,
            "chunk_overlap_tokens": chunk_overlap,
        },
    }

    inserted = 0
    for db_id in vector_db_ids:
        try:
            vs_file = client.vector_stores.files.create(
                vector_store_id=db_id,
                file_id=uploaded.id,
                chunking_strategy=chunking_strategy,
                attributes={
                    "source": upload_name,
                    "filename": upload_name,
                },
            )
            status = vs_file.status if hasattr(vs_file, "status") else "unknown"
            print(f"  [OK] Indexed into '{db_id}': status={status}")
            inserted += 1
        except Exception as e:
            print(f"  [FAIL] Index into '{db_id}': {e}")
            return InsertOutput(status="error", chunks_inserted=inserted)

    return InsertOutput(status="success", chunks_inserted=inserted)
