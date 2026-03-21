"""
Setup Config Component — builds a runtime configuration dict
consumed by all downstream pipeline components.

Adopted from rhoai-genaiops with greedy/top_p sampling strategy.
"""

from typing import NamedTuple, Dict, Any
from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    pip_index_urls=["https://pypi.org/simple"],
)
def setup_config_component(
    llamastack_url: str,
    model_id: str,
    temperature: float,
    max_tokens: int,
    embedding_model: str,
    embedding_dimension: int,
    chunk_size_tokens: int,
    vector_provider: str,
    docling_service: str,
    processing_timeout: int,
    vector_db_id: str,
) -> NamedTuple("SetupOutput", [("setup_config", Dict[str, Any])]):
    """Build a runtime configuration dict consumed by all downstream components.

    Args:
        llamastack_url: LlamaStack service endpoint URL.
        model_id: LLM model identifier for inference.
        temperature: Sampling temperature (0.0 for greedy).
        max_tokens: Maximum tokens for model responses.
        embedding_model: Embedding model identifier for vector search.
        embedding_dimension: Dimensionality of the embedding vectors.
        chunk_size_tokens: Token count per chunk for document splitting.
        vector_provider: Vector DB provider (e.g. pgvector).
        docling_service: Docling REST API endpoint URL.
        processing_timeout: Timeout in seconds for document processing.
        vector_db_id: Identifier for the vector store collection.

    Returns:
        setup_config: Dict containing all pipeline configuration.
    """
    from collections import namedtuple

    print("Initializing RAG Pipeline Configuration")
    print("=" * 60)

    if temperature > 0.0:
        sampling_strategy = {
            "type": "top_p",
            "temperature": temperature,
            "top_p": 0.95,
        }
    else:
        sampling_strategy = {"type": "greedy"}

    sampling_params = {
        "strategy": sampling_strategy,
        "max_tokens": max_tokens,
    }

    setup_config = {
        "base_url": llamastack_url,
        "model_config": {
            "model_id": model_id,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": True,
        },
        "sampling_params": sampling_params,
        "document_intelligence": {
            "embedding_model": embedding_model,
            "embedding_dimension": embedding_dimension,
            "chunk_size_tokens": chunk_size_tokens,
            "vector_provider": vector_provider,
            "docling_service": docling_service,
            "processing_timeout": processing_timeout,
        },
        "vector_db_id": vector_db_id,
    }

    print(f"  LlamaStack URL: {llamastack_url}")
    print(f"  Model: {model_id}")
    print(f"  Sampling: {sampling_strategy['type']}")
    print(f"  Embedding: {embedding_model} ({embedding_dimension}d)")
    print(f"  Vector DB: {vector_db_id}")
    print(f"  Docling: {docling_service}")
    print("=" * 60)

    SetupOutput = namedtuple("SetupOutput", ["setup_config"])
    return SetupOutput(setup_config=setup_config)
