"""
Setup Config Component — builds a runtime configuration dict
consumed by all downstream pipeline components.

Adopted from rhoai-genaiops with greedy/top_p sampling strategy.
"""

from typing import NamedTuple, Optional, Dict, Any
from kfp.dsl import component


@component(
    base_image="python:3.12",
    packages_to_install=["llama_stack_client>=0.4,<0.5", "requests"],
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
