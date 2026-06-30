"""Prompt and message builders for private RAG."""

from __future__ import annotations

from .llama_stack_gateway import SearchHit


RAG_SYSTEM_PROMPT = (
    "You are a helpful enterprise AI assistant. Answer questions using the "
    "provided private context. If the context does not contain enough "
    "information, say so clearly. Keep the answer concise and include source "
    "names when context is available."
)

MODEL_ONLY_SYSTEM_PROMPT = (
    "You are a helpful enterprise AI assistant. Answer questions directly from "
    "the model's general capabilities. Do not claim to have used private "
    "documents, retrieved context, or source citations."
)


def build_context(hits: list[SearchHit], max_chars: int) -> str:
    remaining = max_chars
    parts: list[str] = []

    for hit in hits:
        if remaining <= 0:
            break
        source = hit.source or "unknown"
        text = hit.text[:remaining]
        if not text:
            continue
        part = f"[Source: {source}]\n{text}"
        parts.append(part)
        remaining -= len(part)

    return "\n\n".join(parts)


def build_rag_messages(question: str, hits: list[SearchHit], max_context_chars: int) -> list[dict[str, str]]:
    context = build_context(hits, max_context_chars)
    if not context:
        user_content = (
            "No private RAG context was retrieved.\n\n"
            f"Question: {question}"
        )
    else:
        user_content = (
            "Use this private RAG context to answer the question.\n\n"
            f"CONTEXT:\n{context}\n\n"
            f"QUESTION:\n{question}"
        )

    return [
        {"role": "system", "content": RAG_SYSTEM_PROMPT},
        {"role": "user", "content": user_content},
    ]


def build_model_only_messages(question: str) -> list[dict[str, str]]:
    return [
        {"role": "system", "content": MODEL_ONLY_SYSTEM_PROMPT},
        {"role": "user", "content": question},
    ]
