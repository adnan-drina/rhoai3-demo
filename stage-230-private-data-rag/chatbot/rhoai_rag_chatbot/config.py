"""Environment-backed configuration for the Stage 230 chatbot."""

from __future__ import annotations

from dataclasses import dataclass, field
import json
import os


def _bool(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if not value:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def _float(name: str, default: float) -> float:
    value = os.environ.get(name)
    if not value:
        return default
    try:
        return float(value)
    except ValueError:
        return default


def _json_dict(name: str) -> dict:
    value = os.environ.get(name, "").strip()
    if not value:
        return {}
    try:
        parsed = json.loads(value)
        return parsed if isinstance(parsed, dict) else {}
    except (json.JSONDecodeError, TypeError):
        return {}


@dataclass(frozen=True)
class AppConfig:
    llama_stack_endpoint: str
    timeout: float
    default_model: str
    default_vector_store: str
    default_search_mode: str
    default_top_k: int
    rerank_enabled: bool
    reranker_model: str
    max_context_chars: int
    max_output_tokens: int
    temperature: float
    history_turns: int
    mcp_enabled: bool
    guardrails_enabled: bool
    guardrails_endpoint: str
    question_suggestions: dict = field(default_factory=dict)


def load_config() -> AppConfig:
    endpoint = (
        os.environ.get("LLAMA_STACK_ENDPOINT")
        or os.environ.get("LLAMA_STACK_BASE_URL")
        or "http://lsd-enterprise-rag-service.enterprise-rag.svc.cluster.local:8321"
    )
    return AppConfig(
        llama_stack_endpoint=endpoint.rstrip("/"),
        timeout=_float("LLAMA_STACK_TIMEOUT", 120.0),
        default_model=os.environ.get("INFERENCE_MODEL", "nemotron-3-nano-30b-a3b"),
        default_vector_store=os.environ.get(
            "DEFAULT_VECTOR_STORE",
            "stage230-rhoai-34-product-docs-kfp",
        ),
        default_search_mode=os.environ.get("RAG_SEARCH_MODE", "hybrid"),
        default_top_k=_int("RAG_TOP_K", 6),
        rerank_enabled=_bool("RAG_RERANK_ENABLED", True),
        reranker_model=os.environ.get("RAG_RERANKER_MODEL", "vllm-reranker/qwen3-reranker"),
        max_context_chars=_int("RAG_MAX_CONTEXT_CHARS", 8000),
        max_output_tokens=_int("RAG_MAX_OUTPUT_TOKENS", 512),
        temperature=_float("RAG_TEMPERATURE", 0.1),
        history_turns=_int("RAG_HISTORY_TURNS", 3),
        mcp_enabled=_bool("MCP_ENABLED", False),
        guardrails_enabled=_bool("GUARDRAILS_ENABLED", False),
        guardrails_endpoint=os.environ.get("GUARDRAILS_ENDPOINT", ""),
        question_suggestions=_json_dict("RAG_QUESTION_SUGGESTIONS"),
    )
