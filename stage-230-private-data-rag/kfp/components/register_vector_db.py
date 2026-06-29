"""Register the whoami vector database in Llama Stack."""

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
    """Create a fresh vector DB registration for this ingestion run."""
    from collections import namedtuple

    from llama_stack_client import LlamaStackClient

    VectorDbOutput = namedtuple("VectorDbOutput", ["vector_db_ids", "provider_id"])

    client = LlamaStackClient(base_url=llamastack_url, timeout=300.0)

    def ident(obj):
        return (
            getattr(obj, "identifier", None)
            or getattr(obj, "id", None)
            or getattr(obj, "provider_id", None)
        )

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

    existing = [ident(db) for db in client.vector_dbs.list()]
    if vector_db_id in existing and reset_vector_db:
        print(f"Unregistering existing vector DB: {vector_db_id}")
        client.vector_dbs.unregister(vector_db_id=vector_db_id)
        existing = [db for db in existing if db != vector_db_id]

    if vector_db_id not in existing:
        client.vector_dbs.register(
            vector_db_id=vector_db_id,
            embedding_model=embedding_model,
            embedding_dimension=embedding_dimension,
            provider_id=provider_id,
        )
        print(f"Registered vector DB {vector_db_id} with provider {provider_id}")
    else:
        print(f"Reusing vector DB {vector_db_id} with provider {provider_id}")

    return VectorDbOutput(vector_db_ids=[vector_db_id], provider_id=provider_id)
