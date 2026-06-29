"""Insert converted Markdown into a Llama Stack vector store."""

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

    import time

    from llama_stack_client import LlamaStackClient

    InsertOutput = namedtuple("InsertOutput", ["status", "documents_inserted"])

    if not processed_file or not os.path.exists(processed_file):
        raise RuntimeError(f"Processed file is missing: {processed_file}")

    with open(processed_file, encoding="utf-8") as handle:
        content = handle.read()
    if not content.strip():
        raise RuntimeError(f"Processed file is empty: {processed_file}")

    client = LlamaStackClient(base_url=llamastack_url, timeout=300.0)
    doc_id = os.path.splitext(os.path.basename(processed_file))[0]
    source_name = os.path.basename(processed_file)
    uploaded_file = client.files.create(
        file=(source_name, content.encode("utf-8"), "text/plain"),
        purpose="assistants",
    )
    file_id = getattr(uploaded_file, "id", None)
    if not file_id:
        raise RuntimeError(f"Llama Stack file upload did not return an id for {source_name}")

    inserted = 0
    for store_id in vector_db_ids:
        store_file = client.vector_stores.files.create(
            vector_store_id=store_id,
            file_id=file_id,
            attributes={
                "source": source_name,
                "stage": "230",
                "scenario": "whoami",
                "chunk_size_tokens": str(chunk_size_tokens),
            },
        )
        status = getattr(store_file, "status", "")
        for _ in range(60):
            if status in ("completed", "failed", "cancelled"):
                break
            time.sleep(2)
            store_file = client.vector_stores.files.retrieve(
                vector_store_id=store_id,
                file_id=file_id,
            )
            status = getattr(store_file, "status", "")
        if status and status != "completed":
            raise RuntimeError(f"Vector store file {file_id} ended with status {status}")
        inserted += 1
        print(f"Inserted {doc_id} file {file_id} into vector store {store_id}")

    log_path = os.path.join(workspace_path, "ingestion-log.jsonl")
    with open(log_path, "a", encoding="utf-8") as handle:
        handle.write(
            json.dumps(
                {
                    "document": doc_id,
                    "file_id": file_id,
                    "status": "success",
                    "vector_db": vector_db_id,
                    "vector_store_ids": vector_db_ids,
                    "stores": inserted,
                }
            )
            + "\n"
        )

    return InsertOutput(status="success", documents_inserted=inserted)
