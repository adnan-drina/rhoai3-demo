"""Prompt templates for direct RAG and model-only comparison."""

from __future__ import annotations

from .llama_stack_gateway import SearchHit


RAG_SYSTEM_PROMPT = (
    "You are a helpful enterprise AI assistant for a Red Hat OpenShift AI demo. "
    "Answer using only the retrieved official Red Hat documentation context. "
    "When citing information, reference the source number in square brackets "
    "(e.g., [1], [2]) so the user can trace each claim back to the retrieved document. "
    "If the context is insufficient, say that the retrieved context is insufficient. "
    "Keep the answer concise and well-structured."
)

MODEL_ONLY_SYSTEM_PROMPT = (
    "You are a helpful enterprise AI assistant. Answer from the model's general "
    "capabilities. Do not claim to have used private documents, retrieved context, "
    "or source citations."
)

TOPIC_KEYWORDS: dict[str, list[str]] = {
    "guardrails": ["guardrail", "safety", "content filter", "risk assessment", "nemo guardrails"],
    "llama_stack_rag": ["llama stack", "rag", "vector store", "retrieval", "pgvector", "hybrid search"],
    "ai_pipelines": ["pipeline", "kfp", "kubeflow", "data science pipeline", "dspa"],
    "autorag": ["autorag", "auto rag", "automatic rag"],
    "evalhub": ["evalhub", "evaluation hub", "lm eval", "trustyai"],
    "docling_data_prep": ["docling", "pdf conversion", "document converter"],
    "ragas_evaluation": ["ragas", "evaluation metric", "faithfulness", "context recall"],
    "lm_eval": ["lm eval", "lm-eval", "benchmark", "model evaluation"],
    "risk_assessment": ["risk", "assessment", "compliance"],
}


def detect_topic(query: str) -> str | None:
    """Lightweight keyword-based topic detection from the query."""
    query_lower = query.lower()
    best_topic = None
    best_count = 0
    for topic, keywords in TOPIC_KEYWORDS.items():
        count = sum(1 for kw in keywords if kw in query_lower)
        if count > best_count:
            best_count = count
            best_topic = topic
    return best_topic if best_count > 0 else None


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


def _history_messages(history: list[dict[str, str]], max_turns: int) -> list[dict[str, str]]:
    """Extract the last N user/assistant turn pairs from chat history."""
    if max_turns <= 0 or not history:
        return []
    pairs: list[dict[str, str]] = []
    for msg in history:
        if msg["role"] in ("user", "assistant"):
            pairs.append({"role": msg["role"], "content": msg["content"]})
    max_messages = max_turns * 2
    return pairs[-max_messages:]


def rag_messages(
    question: str,
    context: str,
    history: list[dict[str, str]] | None = None,
    max_turns: int = 0,
) -> list[dict[str, str]]:
    msgs: list[dict[str, str]] = [{"role": "system", "content": RAG_SYSTEM_PROMPT}]
    msgs.extend(_history_messages(history or [], max_turns))
    msgs.append({
        "role": "user",
        "content": (
            "Use this private RAG context to answer the question.\n\n"
            f"CONTEXT:\n{context}\n\n"
            f"QUESTION:\n{question}"
        ),
    })
    return msgs


def model_only_messages(
    question: str,
    history: list[dict[str, str]] | None = None,
    max_turns: int = 0,
) -> list[dict[str, str]]:
    msgs: list[dict[str, str]] = [{"role": "system", "content": MODEL_ONLY_SYSTEM_PROMPT}]
    msgs.extend(_history_messages(history or [], max_turns))
    msgs.append({"role": "user", "content": question})
    return msgs
