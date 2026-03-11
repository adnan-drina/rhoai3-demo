"""
Insert via LlamaStack Component — reads processed markdown from the shared PVC
and ingests it into Milvus through Llama Stack's vector_stores.files.create() API.

Server-side chunking and embedding: LlamaStack handles both using the
granite-embedding-125m model registered in the LSD configuration.

Uses 0.4.x API: files.create() for upload, then vector_stores.files.create()
for indexing. The deprecated rag_tool.insert() / RAGDocument API is not used.
"""

from pathlib import Path
from typing import NamedTuple, Dict, Any, List
from kfp.dsl import component


@component(
    base_image="python:3.12",
    packages_to_install=["llama_stack_client>=0.4,<0.5", "requests"],
)
def insert_via_llamastack_component(
    setup_config: Dict[str, Any],
    processed_file: str,
    original_key: str,
    bucket_name: str,
    vector_db_ids: List[str],
) -> NamedTuple("InsertOutput", [("status", str), ("chunks_inserted", int)]):
    from llama_stack_client import LlamaStackClient
    from collections import namedtuple
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
    content_len = file_path.stat().st_size
    print(f"Inserting: {original_key} ({content_len} bytes)")

    client = LlamaStackClient(base_url=base_url)

    try:
        uploaded = client.files.create(file=file_path, purpose="assistants")
    except Exception as e:
        print(f"  [FAIL] File upload: {e}")
        return InsertOutput(status="error", chunks_inserted=0)

    chunk_overlap = max(1, chunk_size // 4)
    chunking_strategy = {
        "type": "static",
        "static": {
            "max_chunk_size_tokens": chunk_size,
            "chunk_overlap_tokens": chunk_overlap,
        },
    }

    for db_id in vector_db_ids:
        try:
            client.vector_stores.files.create(
                vector_store_id=db_id,
                file_id=uploaded.id,
                chunking_strategy=chunking_strategy,
            )
            print(f"  [OK] Inserted into '{db_id}'")
        except Exception as e:
            print(f"  [FAIL] Insert into '{db_id}': {e}")
            return InsertOutput(status="error", chunks_inserted=0)

    return InsertOutput(status="success", chunks_inserted=1)
