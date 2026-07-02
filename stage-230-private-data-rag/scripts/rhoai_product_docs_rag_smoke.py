#!/usr/bin/env python3
"""RHOAI product documentation RAG smoke test for Stage 230."""

from __future__ import annotations

import argparse
import inspect
import json
import os
import re
import ssl
import sys
import tempfile
import unicodedata
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from llama_stack_client import LlamaStackClient


ROOT = Path(__file__).parents[1]
DEFAULT_MANIFEST = ROOT / "data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json"
DEFAULT_SAMPLE = ROOT / "data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl"
DEFAULT_VECTOR_STORE = "stage230-rhoai-34-product-docs"
DEFAULT_EMBEDDING_MODEL = "sentence-transformers/nomic-ai/nomic-embed-text-v1.5"
DEFAULT_VECTOR_PROVIDER = "pgvector"
DEFAULT_GENERATION_MODEL = "nemotron-3-nano-30b-a3b"
DEFAULT_RERANKER_MODEL = "vllm-reranker/qwen3-reranker"


def normalize_base_url(url: str) -> str:
    return url.rstrip("/")


def api_url(base_url: str, path: str) -> str:
    base = normalize_base_url(base_url)
    if path.startswith("/"):
        path = path[1:]
    if base.endswith("/v1") and path.startswith("v1/"):
        path = path[3:]
    return f"{base}/{path}"


def http_json(method: str, url: str, payload: dict[str, Any] | None = None, api_key: str | None = None) -> dict[str, Any]:
    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    context = ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(request, context=context, timeout=180) as response:
            body = response.read().decode()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise RuntimeError(f"{method} {url} failed with HTTP {exc.code}: {body[:500]}") from exc
    return json.loads(body)


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    records = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    if not records:
        raise SystemExit(f"no records found in {path}")
    return records


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def as_items(response: Any) -> list[Any]:
    if isinstance(response, list):
        return response
    for key in ("data", "vector_stores", "items"):
        value = getattr(response, key, None)
        if value is not None:
            return value
        if isinstance(response, dict) and key in response:
            return response[key]
    return []


def get_value(item: Any, *keys: str) -> Any:
    for key in keys:
        if isinstance(item, dict) and key in item:
            return item[key]
        value = getattr(item, key, None)
        if value is not None:
            return value
    return None


def find_vector_store(client: LlamaStackClient, name: str) -> str | None:
    for store in as_items(client.vector_stores.list()):
        if get_value(store, "name") == name:
            return get_value(store, "id", "vector_store_id")
    return None


def create_vector_store(client: LlamaStackClient, name: str, embedding_model: str, provider_id: str, records: list[dict[str, Any]]) -> str:
    first = records[0]
    metadata = {
        "tenant_id": first["tenant_id"],
        "version_no": first["version_no"],
        "corpus": first["corpus"],
        "environment": "demo",
        "language": first["language"],
        "product": first["product"],
        "product_version": first["product_version"],
        "provider_id": provider_id,
        "embedding_model": embedding_model,
    }
    create_kwargs = {
        "name": name,
        "metadata": metadata,
        "extra_body": {"provider_id": provider_id},
    }
    if "embedding_model" in inspect.signature(client.vector_stores.create).parameters:
        create_kwargs["embedding_model"] = embedding_model
    else:
        create_kwargs["extra_body"]["embedding_model"] = embedding_model
    store = client.vector_stores.create(**create_kwargs)
    return get_value(store, "id", "vector_store_id")


def record_attributes(record: dict[str, Any]) -> dict[str, Any]:
    allowed = {
        "id",
        "access_tier",
        "chunk_index",
        "corpus",
        "document_title",
        "document_type",
        "documentation_category",
        "guide_slug",
        "language",
        "matched_terms",
        "page_end",
        "page_start",
        "preparation_method",
        "product",
        "product_version",
        "retrieved_url",
        "source",
        "source_authority",
        "source_file",
        "source_format",
        "source_url",
        "tenant_id",
        "topic",
        "version",
        "version_no",
    }
    attrs = {key: record[key] for key in sorted(allowed) if key in record and record[key] is not None}
    if isinstance(attrs.get("matched_terms"), list):
        attrs["matched_terms"] = ",".join(str(term) for term in attrs["matched_terms"])
    attrs["record_id"] = record["id"]
    return attrs


def upload_records(client: LlamaStackClient, vector_store_id: str, records: list[dict[str, Any]]) -> int:
    uploaded_count = 0
    with tempfile.TemporaryDirectory(prefix="stage230-rhoai-docs-") as tmpdir:
        tmp_path = Path(tmpdir)
        for record in records:
            chunk_path = tmp_path / f"{record['id']}.txt"
            chunk_path.write_text(
                f"{record['title']}\nSource: {record['source_url']}\nTopic: {record['topic']}\n\n{record['text']}\n",
                encoding="utf-8",
            )
            with chunk_path.open("rb") as handle:
                uploaded = client.files.create(file=handle, purpose="assistants")
            client.vector_stores.files.create(
                vector_store_id=vector_store_id,
                file_id=get_value(uploaded, "id", "file_id"),
                attributes=record_attributes(record),
            )
            uploaded_count += 1
    return uploaded_count


def ensure_vector_store(
    client: LlamaStackClient,
    vector_store_name: str,
    embedding_model: str,
    provider_id: str,
    records: list[dict[str, Any]],
    reset: bool,
) -> tuple[str, int]:
    vector_store_id = find_vector_store(client, vector_store_name)
    if vector_store_id and reset:
        client.vector_stores.delete(vector_store_id=vector_store_id)
        vector_store_id = None
    uploaded_count = 0
    if not vector_store_id:
        vector_store_id = create_vector_store(client, vector_store_name, embedding_model, provider_id, records)
        uploaded_count = upload_records(client, vector_store_id, records)
    return vector_store_id, uploaded_count


def vector_store_file_counts(client: LlamaStackClient, vector_store_id: str) -> dict[str, int]:
    store = client.vector_stores.retrieve(vector_store_id=vector_store_id)
    file_counts = get_value(store, "file_counts")
    counts = {
        "cancelled": int(get_value(file_counts, "cancelled") or 0),
        "completed": int(get_value(file_counts, "completed") or 0),
        "failed": int(get_value(file_counts, "failed") or 0),
        "in_progress": int(get_value(file_counts, "in_progress") or 0),
        "total": int(get_value(file_counts, "total") or 0),
    }
    if counts["failed"] or counts["cancelled"] or counts["in_progress"]:
        raise RuntimeError(f"vector store file ingestion is not clean: {counts}")
    return counts


def search(
    client: LlamaStackClient,
    vector_store_id: str,
    query: str,
    topic: str | None,
    search_mode: str,
    max_results: int,
) -> list[Any]:
    filters = {"type": "eq", "key": "topic", "value": topic} if topic else {}
    kwargs = {
        "vector_store_id": vector_store_id,
        "query": query,
        "search_mode": search_mode,
        "max_num_results": max_results,
    }
    if filters:
        kwargs["filters"] = filters
    result = client.vector_stores.search(**kwargs)
    items = as_items(result)
    if topic:
        mismatches = [item for item in items if (get_value(item, "attributes") or {}).get("topic") != topic]
        if mismatches:
            raise RuntimeError(
                f"{search_mode} metadata filter mismatch: expected topic={topic}, "
                f"got {[get_value(item, 'attributes') for item in mismatches]}"
            )
    if not items:
        raise RuntimeError(f"{search_mode} search returned no candidates for topic={topic}")
    return items


def item_text(item: Any) -> str:
    content = get_value(item, "content")
    if isinstance(content, list):
        parts = []
        for part in content:
            text = get_value(part, "text")
            if text:
                parts.append(str(text))
        if parts:
            return "\n".join(parts)
    for key in ("text", "chunk_text"):
        value = get_value(item, key)
        if value:
            return str(value)
    attrs = get_value(item, "attributes") or {}
    return f"{attrs.get('document_title', 'RHOAI documentation')}: {json.dumps(attrs, sort_keys=True)}"


def rerank(base_url: str, model: str, query: str, candidates: list[Any]) -> tuple[list[dict[str, Any]], str]:
    documents = [item_text(item)[:1200] for item in candidates[:4]]
    typed_items = [{"type": "text", "text": document} for document in documents]
    payloads = [
        (
            "/v1alpha/inference/rerank",
            {
                "model": model,
                "query": query,
                "items": typed_items,
                "max_num_results": min(4, len(documents)),
            },
        ),
        (
            "/v1/rerank",
            {
                "model": model,
                "query": query,
                "documents": documents,
                "top_n": min(4, len(documents)),
            },
        ),
    ]
    errors = []
    for path, payload in payloads:
        try:
            response = http_json("POST", api_url(base_url, path), payload)
        except Exception as exc:  # noqa: BLE001 - collect endpoint variants.
            errors.append(str(exc))
            continue
        results = response.get("results") or response.get("data") or response.get("rankings")
        if not results:
            errors.append(f"{path} returned no ranked results: {response}")
            continue
        ranked = []
        for result in results:
            index = int(result.get("index", result.get("document_index", 0)))
            ranked.append(
                {
                    "index": index,
                    "score": result.get("relevance_score", result.get("score", result.get("logit"))),
                    "text": documents[index] if index < len(documents) else str(result),
                }
            )
        return ranked, path
    raise RuntimeError("reranker endpoint failed: " + " | ".join(errors[:4]))


def chat_message_content(response: dict[str, Any], purpose: str) -> str:
    choice = (response.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    content = message.get("content")
    if isinstance(content, list):
        content = "\n".join(str(part.get("text") or part.get("content") or "") for part in content if isinstance(part, dict))
    content = content or ""
    if choice.get("finish_reason") == "length" and not content.strip():
        raise RuntimeError(f"{purpose} stopped before assistant content was emitted")
    return str(content)


def final_answer(base_url: str, model: str, query: str, ranked: list[dict[str, Any]], api_key: str | None) -> str:
    context = "\n\n".join(f"[{index + 1}] {item['text']}" for index, item in enumerate(ranked))
    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": (
                    "You explain Red Hat OpenShift AI product capabilities to a technical demo audience. "
                    "Answer using only the retrieved official Red Hat documentation context. "
                    "Mention the relevant product component names. If the context is insufficient, say so."
                ),
            },
            {"role": "user", "content": f"Question: {query}\n\nRetrieved context:\n{context}"},
        ],
        "temperature": 0,
        "max_tokens": 700,
    }
    response = http_json("POST", api_url(base_url, "/v1/chat/completions"), payload, api_key=api_key)
    answer = chat_message_content(response, "final answer").strip()
    if len(answer) < 10:
        raise RuntimeError(f"final answer was empty or too short: {answer!r}")
    return answer


def assert_expected_terms(answer: str, terms: list[str]) -> None:
    normalized_answer = normalize_assertion_text(answer)
    missing = [term for term in terms if normalize_assertion_text(term) not in normalized_answer]
    if missing:
        raise RuntimeError(f"final answer missed expected terms {missing}: {answer!r}")


def normalize_assertion_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return re.sub(r"\s+", " ", normalized)


def select_questions(manifest: dict[str, Any], args: argparse.Namespace) -> list[dict[str, Any]]:
    if args.query:
        return [
            {
                "query": args.query,
                "expected_topic": args.expected_topic,
                "expected_terms": args.expected_term or [],
            }
        ]
    questions = list(manifest.get("smoke_questions", []))
    if args.max_questions:
        questions = questions[: args.max_questions]
    return questions


def select_smoke_records(
    records: list[dict[str, Any]],
    questions: list[dict[str, Any]],
    records_per_topic: int,
    full_corpus: bool,
) -> list[dict[str, Any]]:
    if full_corpus:
        return records

    topics = [question.get("expected_topic") for question in questions if question.get("expected_topic")]
    if not topics:
        return records[:records_per_topic]

    selected: list[dict[str, Any]] = []
    for topic in dict.fromkeys(topics):
        topic_records = [record for record in records if record.get("topic") == topic]
        if not topic_records:
            raise RuntimeError(f"no product-document chunks found for expected topic={topic}")
        selected.extend(topic_records[:records_per_topic])
    return selected


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=os.environ.get("LLAMA_STACK_BASE_URL"))
    parser.add_argument("--reranker-base-url", default=os.environ.get("RHOAI_STAGE230_RERANKER_BASE_URL"))
    parser.add_argument(
        "--generation-base-url",
        default=os.environ.get("RHOAI_STAGE230_GENERATION_BASE_URL") or os.environ.get("RHOAI_STAGE230_MAAS_BASE_URL"),
    )
    parser.add_argument(
        "--generation-api-key",
        default=os.environ.get("RHOAI_STAGE230_GENERATION_API_KEY") or os.environ.get("RHOAI_STAGE230_MAAS_API_KEY"),
    )
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--sample", type=Path, default=DEFAULT_SAMPLE)
    parser.add_argument("--vector-store", default=os.environ.get("RHOAI_STAGE230_RHOAI_DOCS_VECTOR_STORE", DEFAULT_VECTOR_STORE))
    parser.add_argument("--embedding-model", default=os.environ.get("RHOAI_STAGE230_EMBEDDING_MODEL", DEFAULT_EMBEDDING_MODEL))
    parser.add_argument("--vector-provider", default=os.environ.get("RHOAI_STAGE230_VECTOR_PROVIDER", DEFAULT_VECTOR_PROVIDER))
    parser.add_argument("--generation-model", default=os.environ.get("RHOAI_STAGE230_GENERATION_MODEL", DEFAULT_GENERATION_MODEL))
    parser.add_argument("--reranker-model", default=os.environ.get("RHOAI_STAGE230_RERANKER_MODEL", DEFAULT_RERANKER_MODEL))
    parser.add_argument("--query")
    parser.add_argument("--expected-topic")
    parser.add_argument("--expected-term", action="append")
    parser.add_argument("--max-questions", type=int, default=3)
    parser.add_argument("--records-per-topic", type=int, default=int(os.environ.get("RHOAI_STAGE230_RHOAI_DOCS_RECORDS_PER_TOPIC", "12")))
    parser.add_argument("--full-corpus", action="store_true")
    parser.add_argument("--search-mode", default=os.environ.get("RHOAI_STAGE230_SEARCH_MODE", "hybrid"))
    parser.add_argument("--reset", action="store_true")
    args = parser.parse_args()

    if not args.base_url:
        raise SystemExit("LLAMA_STACK_BASE_URL or --base-url is required")
    if not args.reranker_base_url:
        raise SystemExit("RHOAI_STAGE230_RERANKER_BASE_URL or --reranker-base-url is required")
    if not args.generation_base_url:
        raise SystemExit("RHOAI_STAGE230_GENERATION_BASE_URL or --generation-base-url is required")
    if not args.generation_api_key:
        raise SystemExit("RHOAI_STAGE230_GENERATION_API_KEY or --generation-api-key is required")

    manifest = load_manifest(args.manifest)
    records = load_jsonl(args.sample)
    questions = select_questions(manifest, args)
    smoke_records = select_smoke_records(records, questions, args.records_per_topic, args.full_corpus)
    client = LlamaStackClient(base_url=normalize_base_url(args.base_url))
    vector_store_id, uploaded_count = ensure_vector_store(
        client,
        args.vector_store,
        args.embedding_model,
        args.vector_provider,
        smoke_records,
        args.reset,
    )
    file_counts = vector_store_file_counts(client, vector_store_id)

    results = []
    for question in questions:
        query = question["query"]
        topic = question.get("expected_topic")
        candidates = search(client, vector_store_id, query, topic, args.search_mode, max_results=8)
        ranked, reranker_path = rerank(args.reranker_base_url, args.reranker_model, query, candidates)
        answer = final_answer(
            normalize_base_url(args.generation_base_url),
            args.generation_model,
            query,
            ranked,
            args.generation_api_key,
        )
        assert_expected_terms(answer, question.get("expected_terms", []))
        results.append(
            {
                "query": query,
                "expected_topic": topic,
                "candidate_count": len(candidates),
                "reranker_path": reranker_path,
                "answer": answer,
            }
        )

    print(
        json.dumps(
            {
                "status": "pass",
                "vector_store_id": vector_store_id,
                "uploaded_count": uploaded_count,
                "file_counts": file_counts,
                "input_record_count": len(records),
                "indexed_record_count": len(smoke_records),
                "full_corpus": args.full_corpus,
                "search_mode": args.search_mode,
                "question_count": len(results),
                "results": results,
            },
            indent=2,
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - concise CLI failure.
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
