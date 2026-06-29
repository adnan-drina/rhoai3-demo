"""Register the whoami vector store in Llama Stack."""

from typing import List, NamedTuple

from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.4.0",
    packages_to_install=["llama-stack-client>=0.7,<0.8"],
    pip_index_urls=["https://pypi.org/simple"],
)
def register_vector_db_component(
    llamastack_url: str,
    vector_db_id: str,
    embedding_model: str,
    embedding_dimension: int,
    vector_provider: str,
    reset_vector_db: bool,
) -> NamedTuple("VectorDbOutput", [("vector_db_ids", List[str]), ("provider_id", str)]):
    """Create a fresh vector store for this ingestion run."""
    from collections import namedtuple

    from llama_stack_client import LlamaStackClient

    VectorDbOutput = namedtuple("VectorDbOutput", ["vector_db_ids", "provider_id"])

    client = LlamaStackClient(base_url=llamastack_url, timeout=300.0)

    provider_id = None
    for provider in client.providers.list():
        if getattr(provider, "api", None) != "vector_io":
            continue
        candidate = getattr(provider, "provider_id", "") or ""
        if vector_provider.lower() in candidate.lower():
            provider_id = candidate
            break
        provider_id = provider_id or candidate

    if not provider_id:
        raise RuntimeError("No vector_io provider is available in Llama Stack")

    existing = []
    for store in client.vector_stores.list():
        store_id = getattr(store, "id", None)
        store_name = getattr(store, "name", None)
        if store_id == vector_db_id or store_name == vector_db_id:
            existing.append(store)

    if reset_vector_db:
        for store in existing:
            store_id = getattr(store, "id", None)
            if store_id:
                print(f"Deleting existing vector store {vector_db_id}: {store_id}")
                client.vector_stores.delete(vector_store_id=store_id)
        existing = []

    if existing:
        vector_store = existing[0]
        vector_store_id = getattr(vector_store, "id", None)
        print(f"Reusing vector store {vector_db_id}: {vector_store_id}")
    else:
        vector_store = client.vector_stores.create(
            name=vector_db_id,
            metadata={
                "stage": "230",
                "scenario": "whoami",
                "embedding_model": embedding_model,
                "embedding_dimension": str(embedding_dimension),
                "vector_provider": provider_id,
            },
        )
        vector_store_id = getattr(vector_store, "id", None)
        print(f"Created vector store {vector_db_id}: {vector_store_id}")

    if not vector_store_id:
        raise RuntimeError(f"Vector store {vector_db_id} did not return an id")

    return VectorDbOutput(vector_db_ids=[vector_store_id], provider_id=provider_id)
