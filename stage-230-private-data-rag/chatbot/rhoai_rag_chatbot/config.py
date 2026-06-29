"""Environment-backed configuration for the private RAG chatbot."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Any


def _bool_env(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _int_env(name: str, default: int) -> int:
    value = os.getenv(name)
    if not value:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def _float_env(name: str, default: float) -> float:
    value = os.getenv(name)
    if not value:
        return default
    try:
        return float(value)
    except ValueError:
        return default


def _suggestions() -> dict[str, list[str]]:
    raw = os.getenv("RAG_QUESTION_SUGGESTIONS", "{}")
    try:
        parsed: Any = json.loads(raw)
    except json.JSONDecodeError:
        return {}

    if not isinstance(parsed, dict):
        return {}

    normalized: dict[str, list[str]] = {}
    for key, value in parsed.items():
        if isinstance(value, list):
            normalized[str(key)] = [str(item) for item in value if item]
    return normalized


@dataclass(frozen=True)
class ChatbotConfig:
    title: str = field(default_factory=lambda: os.getenv("CHATBOT_TITLE", "Private RAG Chatbot"))
    namespace: str = field(default_factory=lambda: os.getenv("POD_NAMESPACE", "enterprise-rag"))
    llama_stack_endpoint: str = field(
        default_factory=lambda: os.getenv(
            "LLAMA_STACK_ENDPOINT",
            os.getenv("LLAMA_STACK_URL", "http://lsd-private-rag-service.enterprise-rag.svc.cluster.local:8321"),
        ).rstrip("/")
    )
    llama_stack_timeout: float = field(default_factory=lambda: _float_env("LLAMA_STACK_TIMEOUT", 600.0))
    default_model: str = field(
        default_factory=lambda: os.getenv("INFERENCE_MODEL", "vllm-inference/nemotron-3-nano-30b-a3b")
    )
    default_vector_store: str = field(default_factory=lambda: os.getenv("DEFAULT_VECTOR_STORE", "whoami"))
    top_k: int = field(default_factory=lambda: _int_env("RAG_TOP_K", 5))
    max_context_chars: int = field(default_factory=lambda: _int_env("RAG_MAX_CONTEXT_CHARS", 16000))
    max_tokens: int = field(default_factory=lambda: _int_env("RAG_MAX_OUTPUT_TOKENS", 512))
    temperature: float = field(default_factory=lambda: _float_env("RAG_TEMPERATURE", 0.1))
    enable_agent_mode: bool = field(default_factory=lambda: _bool_env("ENABLE_AGENT_MODE", False))
    mcp_enabled: bool = field(default_factory=lambda: _bool_env("MCP_ENABLED", False))
    guardrails_enabled: bool = field(default_factory=lambda: _bool_env("GUARDRAILS_ENABLED", False))
    guardrails_endpoint: str = field(default_factory=lambda: os.getenv("GUARDRAILS_ENDPOINT", "").rstrip("/"))
    guardrails_timeout: float = field(default_factory=lambda: _float_env("GUARDRAILS_TIMEOUT", 20.0))
    guardrails_verify_tls: bool = field(default_factory=lambda: _bool_env("GUARDRAILS_VERIFY_TLS", False))
    suggestions: dict[str, list[str]] = field(default_factory=_suggestions)


def load_config() -> ChatbotConfig:
    return ChatbotConfig()
