"""
Insert via LlamaStack Component — reads processed markdown from the shared PVC
and ingests it into pgvector through LlamaStack's vector_stores.files.create() API.

Server-side chunking and embedding: LlamaStack handles both using the
granite-embedding-125m model registered in the LSD configuration.

Uses 0.4.x API: files.create() for upload, then vector_stores.files.create()
for indexing with static chunking strategy.
"""

from typing import NamedTuple, List
from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    packages_to_install=["llama_stack_client>=0.4,<0.5"],
    pip_index_urls=["https://pypi.org/simple"],
)
def insert_via_llamastack_component(
    llamastack_url: str,
    processed_file: str,
    vector_db_ids: List[str],
    vector_db_name: str = "",
    chunk_size_tokens: int = 512,
) -> NamedTuple("InsertOutput", [("status", str), ("chunks_inserted", int)]):
    """Ingest processed Markdown into pgvector via LlamaStack vector_stores API.

    Args:
        llamastack_url: LlamaStack service endpoint URL.
        processed_file: Path to the Markdown file on the shared PVC.
        vector_db_ids: List of vector store IDs to index into.
        chunk_size_tokens: Token count per chunk for static chunking strategy.

    Returns:
        status: Insertion status (success, skipped, or error).
        chunks_inserted: Number of vector stores successfully indexed.
    """
    from llama_stack_client import LlamaStackClient
    from collections import namedtuple
    import os

    InsertOutput = namedtuple("InsertOutput", ["status", "chunks_inserted"])

    if not processed_file or not os.path.exists(processed_file):
        print(f"  [SKIP] No processed file: {processed_file}")
        import json as _json
        with open("/shared-data/ingestion-log.jsonl", "a") as lf:
            lf.write(_json.dumps({"document": processed_file or "unknown", "status": "skipped", "stores": 0, "vector_db": vector_db_name}) + "\n")
        return InsertOutput(status="skipped", chunks_inserted=0)

    file_size = os.path.getsize(processed_file)
    upload_name = os.path.splitext(os.path.basename(processed_file))[0] + ".md"

    print(f"Inserting: {upload_name} ({file_size} bytes)")
    print(f"  LlamaStack: {llamastack_url}")
    print(f"  Vector stores: {vector_db_ids}")

    client = LlamaStackClient(base_url=llamastack_url, timeout=300.0)

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

    chunk_overlap = max(1, chunk_size_tokens // 4)
    chunking_strategy = {
        "type": "static",
        "static": {
            "max_chunk_size_tokens": chunk_size_tokens,
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

    import json as _json
    log_path = "/shared-data/ingestion-log.jsonl"
    with open(log_path, "a") as lf:
        lf.write(_json.dumps({"document": upload_name, "status": "success", "stores": inserted, "vector_db": vector_db_name}) + "\n")

    return InsertOutput(status="success", chunks_inserted=inserted)
