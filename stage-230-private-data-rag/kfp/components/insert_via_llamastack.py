"""Insert converted Markdown into the Llama Stack RAG tool runtime."""

from typing import List, NamedTuple

from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.4.0",
    packages_to_install=["llama-stack-client>=0.7,<0.8"],
    pip_index_urls=["https://pypi.org/simple"],
)
def insert_via_llamastack_component(
    llamastack_url: str,
    processed_file: str,
    vector_db_ids: List[str],
    vector_db_id: str,
    chunk_size_tokens: int,
    workspace_path: str,
) -> NamedTuple("InsertOutput", [("status", str), ("documents_inserted", int)]):
    """Insert one processed Markdown document through Llama Stack."""
    import json
    import os
    from collections import namedtuple

    from llama_stack_client import LlamaStackClient
    from llama_stack_client.types import Document as RAGDocument

    InsertOutput = namedtuple("InsertOutput", ["status", "documents_inserted"])

    if not processed_file or not os.path.exists(processed_file):
        raise RuntimeError(f"Processed file is missing: {processed_file}")

    with open(processed_file, encoding="utf-8") as handle:
        content = handle.read()
    if not content.strip():
        raise RuntimeError(f"Processed file is empty: {processed_file}")

    client = LlamaStackClient(base_url=llamastack_url, timeout=300.0)
    doc_id = os.path.splitext(os.path.basename(processed_file))[0]
    document = RAGDocument(
        document_id=doc_id,
        content=content,
        mime_type="text/plain",
        metadata={
            "source": os.path.basename(processed_file),
            "stage": "230",
            "scenario": "whoami",
        },
    )

    inserted = 0
    for db_id in vector_db_ids:
        client.tool_runtime.rag_tool.insert(
            documents=[document],
            vector_db_id=db_id,
            chunk_size_in_tokens=chunk_size_tokens,
        )
        inserted += 1
        print(f"Inserted {doc_id} into vector DB {db_id}")

    log_path = os.path.join(workspace_path, "ingestion-log.jsonl")
    with open(log_path, "a", encoding="utf-8") as handle:
        handle.write(
            json.dumps(
                {
                    "document": doc_id,
                    "status": "success",
                    "vector_db": vector_db_id,
                    "stores": inserted,
                }
            )
            + "\n"
        )

    return InsertOutput(status="success", documents_inserted=inserted)
