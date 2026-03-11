"""
Insert via LlamaStack Component — reads processed markdown from the shared PVC
and ingests it into Milvus through Llama Stack's rag_tool.insert() API.

Server-side chunking and embedding: LlamaStack handles both using the
granite-embedding-125m model registered in the LSD configuration.
"""

from typing import NamedTuple, Dict, Any, List
from kfp.dsl import component


@component(
    base_image="python:3.12",
    packages_to_install=["llama_stack_client==0.3.1", "requests"],
)
def insert_via_llamastack_component(
    setup_config: Dict[str, Any],
    processed_file: str,
    original_key: str,
    bucket_name: str,
    vector_db_ids: List[str],
) -> NamedTuple("InsertOutput", [("status", str), ("chunks_inserted", int)]):
    from llama_stack_client import LlamaStackClient, RAGDocument
    from collections import namedtuple
    import os
    import time

    InsertOutput = namedtuple("InsertOutput", ["status", "chunks_inserted"])

    base_url = setup_config["base_url"]
    chunk_size = setup_config["document_intelligence"]["chunk_size_tokens"]
    vector_db_id = setup_config["vector_db_id"]

    if not vector_db_ids:
        vector_db_ids = [vector_db_id]

    if not processed_file or not os.path.exists(processed_file):
        print(f"  [SKIP] No processed file for {original_key}")
        return InsertOutput(status="skipped", chunks_inserted=0)

    with open(processed_file, "r", encoding="utf-8") as f:
        content = f.read()

    print(f"Inserting: {original_key} ({len(content)} chars)")

    doc = RAGDocument(
        document_id=f"doc_{os.path.basename(processed_file).replace('.md', '')}",
        content=content,
        metadata={
            "source": f"minio://{bucket_name}/{original_key}",
            "original_filename": original_key,
            "processing_method": "docling",
            "scenario": vector_db_id,
            "ingested_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        },
    )

    client = LlamaStackClient(base_url=base_url)

    for db_id in vector_db_ids:
        try:
            client.tool_runtime.rag_tool.insert(
                documents=[doc],
                vector_db_id=db_id,
                chunk_size_in_tokens=chunk_size,
            )
            print(f"  [OK] Inserted into '{db_id}'")
        except Exception as e:
            print(f"  [FAIL] Insert into '{db_id}': {e}")
            return InsertOutput(status="error", chunks_inserted=0)

    return InsertOutput(status="success", chunks_inserted=1)
