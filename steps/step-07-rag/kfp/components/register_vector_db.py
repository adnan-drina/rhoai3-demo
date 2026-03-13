"""
Register Vector DB Component — creates (or re-uses) a pgvector vector store
through the Llama Stack vector_stores API.

Idempotent: looks up existing stores by name before creating.
"""

from typing import NamedTuple, Dict, Any, List
from kfp.dsl import component


@component(
    base_image="python:3.12",
    packages_to_install=["llama_stack_client>=0.4,<0.5", "requests"],
)
def register_vector_db_component(
    setup_config: Dict[str, Any],
) -> NamedTuple("VectorDBOutput", [("vector_db_status", Dict[str, Any]), ("vector_db_ids", List[str])]):
    from llama_stack_client import LlamaStackClient
    from collections import namedtuple

    print("Registering Vector Database")
    print("=" * 60)

    base_url = setup_config["base_url"]
    vector_db_id = setup_config["vector_db_id"]
    doc_config = setup_config["document_intelligence"]

    print(f"  LlamaStack: {base_url}")
    print(f"  DB ID:      {vector_db_id}")
    print(f"  Embedding:  {doc_config['embedding_model']} ({doc_config['embedding_dimension']}d)")
    print(f"  Provider:   {doc_config['vector_provider']}")

    client = LlamaStackClient(base_url=base_url)

    # Look up existing vector store by name before attempting to create
    created_id = None
    try:
        existing = client.vector_stores.list()
        for vs in existing.data if hasattr(existing, "data") else existing:
            if getattr(vs, "name", None) == vector_db_id:
                created_id = vs.id
                print(f"  [OK] Found existing vector store: {created_id} (name={vector_db_id})")
                break
    except Exception as e:
        print(f"  [WARN] Could not list stores: {e}")

    if not created_id:
        try:
            vs = client.vector_stores.create(
                name=vector_db_id,
                extra_body={
                    "embedding_model": doc_config["embedding_model"],
                    "embedding_dimension": doc_config["embedding_dimension"],
                    "provider_id": doc_config["vector_provider"],
                    "vector_db_id": vector_db_id,
                },
            )
            created_id = vs.id
            print(f"  [OK] Vector store created: {created_id}")
        except Exception as e:
            if "already exists" in str(e).lower():
                created_id = vector_db_id
                print(f"  [OK] Already exists, using name as ID: {created_id}")
            else:
                print(f"  [FAIL] {e}")
                VectorDBOutput = namedtuple("VectorDBOutput", ["vector_db_status", "vector_db_ids"])
                return VectorDBOutput(
                    vector_db_status={"status": "error", "error": str(e), "ready": False},
                    vector_db_ids=[],
                )

    status = {
        "status": "success",
        "vector_db_id": created_id,
        "embedding_model": doc_config["embedding_model"],
        "embedding_dimension": doc_config["embedding_dimension"],
        "provider": doc_config["vector_provider"],
        "ready": True,
    }

    VectorDBOutput = namedtuple("VectorDBOutput", ["vector_db_status", "vector_db_ids"])
    return VectorDBOutput(vector_db_status=status, vector_db_ids=[created_id])
