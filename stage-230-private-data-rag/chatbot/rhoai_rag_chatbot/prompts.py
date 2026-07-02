"""Prompt templates for direct RAG and model-only comparison."""

from __future__ import annotations

from .llama_stack_gateway import SearchHit


RAG_SYSTEM_PROMPT = (
    "You are a helpful enterprise AI assistant for a Red Hat OpenShift AI demo. "
    "Answer using only the retrieved official Red Hat documentation context. "
    "If the context is insufficient, say that the retrieved context is insufficient. "
    "Keep the answer concise and mention source document names when available."
)

MODEL_ONLY_SYSTEM_PROMPT = (
    "You are a helpful enterprise AI assistant. Answer from the model's general "
    "capabilities. Do not claim to have used private documents, retrieved context, "
    "or source citations."
)


def build_context(hits: list[SearchHit], max_chars: int) -> str:
    parts: list[str] = []
    used = 0
    for index, hit in enumerate(hits, start=1):
        source = hit.source or "RHOAI product documentation"
        section = f"[{index}] Source: {source}\n{hit.text.strip()}"
        remaining = max_chars - used
        if remaining <= 0:
            break
        if len(section) > remaining:
            section = section[:remaining].rstrip()
        parts.append(section)
        used += len(section)
    return "\n\n".join(parts)


def rag_messages(question: str, context: str) -> list[dict[str, str]]:
    return [
        {"role": "system", "content": RAG_SYSTEM_PROMPT},
        {
            "role": "user",
            "content": (
                "Use this private RAG context to answer the question.\n\n"
                f"CONTEXT:\n{context}\n\n"
                f"QUESTION:\n{question}"
            ),
        },
    ]


def model_only_messages(question: str) -> list[dict[str, str]]:
    return [
        {"role": "system", "content": MODEL_ONLY_SYSTEM_PROMPT},
        {"role": "user", "content": question},
    ]
