#!/usr/bin/env python3
"""Dutch government publication RAG smoke test for Stage 230."""

from __future__ import annotations

import argparse
import inspect
import json
import os
import re
import ssl
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from llama_stack_client import LlamaStackClient


DEFAULT_VECTOR_STORE = "stage230-dutch-woo-demo"
DEFAULT_EMBEDDING_MODEL = "sentence-transformers/nomic-ai/nomic-embed-text-v1.5"
DEFAULT_VECTOR_PROVIDER = "pgvector"
DEFAULT_GENERATION_MODEL = "nemotron-3-nano-30b-a3b"
DEFAULT_RERANKER_MODEL = "vllm-reranker/qwen3-reranker"
DEFAULT_QUERY = "Binnen welke termijn moet een bestuursorgaan beslissen op een verzoek om informatie?"
VALID_TOPICS = {
    "recht_op_toegang",
    "zorgplicht_openbaarmaking",
    "actieve_openbaarmaking",
    "openbaarmaking_op_verzoek",
    "uitzonderingen",
    "citeertitel",
}


def normalize_base_url(url: str) -> str:
    return url.rstrip("/")


def api_url(base_url: str, path: str) -> str:
    base = normalize_base_url(base_url)
    if path.startswith("/"):
        path = path[1:]
    if base.endswith("/v1") and path.startswith("v1/"):
        path = path[3:]
    return f"{base}/{path}"


def http_json(
    method: str,
    url: str,
    payload: dict[str, Any] | None = None,
    api_key: str | None = None,
) -> dict[str, Any]:
    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    context = ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(request, context=context, timeout=120) as response:
            body = response.read().decode()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise RuntimeError(f"{method} {url} failed with HTTP {exc.code}: {body[:500]}") from exc
    return json.loads(body)


def load_records(path: Path) -> list[dict[str, Any]]:
    records = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    if not records:
        raise SystemExit(f"no records found in {path}")
    return records


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
    metadata_keys = (
        "tenant_id",
        "version_no",
        "corpus",
        "language",
        "jurisdiction",
        "access_tier",
        "source_authority",
        "publication_type",
        "publication_date",
        "law_name",
        "version",
    )
    metadata = {key: first[key] for key in metadata_keys if key in first}
    metadata.update(
        {
            "environment": "demo",
            "provider_id": provider_id,
            "embedding_model": embedding_model,
        }
    )
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
    allowed_keys = {
        "id",
        "source_authority",
        "publication_type",
        "ministry",
        "topic_domain",
        "topic",
        "publication_date",
        "document_date",
        "language",
        "jurisdiction",
        "access_tier",
        "source_url",
        "source_file",
        "version",
        "law_name",
        "tenant_id",
        "version_no",
        "source",
        "document_type",
        "article_number",
        "article_title",
        "chunk_index",
        "corpus",
    }
    attrs = {key: record[key] for key in sorted(allowed_keys) if key in record and record[key] is not None}
    attrs["record_id"] = record["id"]
    return attrs


def upload_records(client: LlamaStackClient, vector_store_id: str, records: list[dict[str, Any]]) -> int:
    uploaded_count = 0
    with tempfile.TemporaryDirectory(prefix="stage230-dutch-publication-") as tmpdir:
        tmp_path = Path(tmpdir)
        for record in records:
            article_path = tmp_path / f"{record['id']}.txt"
            article_path.write_text(f"{record['title']}\n\n{record['text']}\n", encoding="utf-8")
            with article_path.open("rb") as handle:
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


def extract_json(text: str) -> dict[str, Any]:
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        raise RuntimeError(f"metadata extraction returned no JSON object: {text!r}")
    return json.loads(match.group(0))


def chat_message_content(response: dict[str, Any], purpose: str) -> str:
    choice = (response.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    content = message.get("content")
    if isinstance(content, list):
        parts = []
        for part in content:
            if isinstance(part, dict):
                parts.append(str(part.get("text") or part.get("content") or ""))
            else:
                parts.append(str(part))
        content = "\n".join(part for part in parts if part)
    content = content or ""
    if choice.get("finish_reason") == "length" and not content.strip():
        reasoning_preview = str(message.get("reasoning") or "")[:240]
        raise RuntimeError(
            f"{purpose} stopped before assistant content was emitted; "
            f"increase max_tokens or tighten the prompt. reasoning_preview={reasoning_preview!r}"
        )
    return str(content)


def extract_metadata_filter(
    base_url: str,
    model: str,
    query: str,
    api_key: str | None,
) -> tuple[dict[str, Any], str]:
    topics = ", ".join(sorted(VALID_TOPICS))
    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are a metadata classifier for Dutch government publication RAG. "
                    "Return exactly one compact JSON object in the assistant content and no prose. "
                    "Do not wrap the JSON in markdown. Do not explain your reasoning. "
                    f"Valid topic values are: {topics}. Use null if the question is out of scope "
                    "or if no listed topic is implied.\n"
                    "Examples:\n"
                    "Question: Binnen welke termijn moet een bestuursorgaan beslissen op een verzoek om informatie?\n"
                    "Answer: {\"topic\":\"openbaarmaking_op_verzoek\"}\n"
                    "Question: Welke soorten informatie moet een bestuursorgaan uit eigen beweging openbaar maken?\n"
                    "Answer: {\"topic\":\"actieve_openbaarmaking\"}\n"
                    "Question: Wanneer blijft openbaarmaking van informatie achterwege volgens artikel 5.1?\n"
                    "Answer: {\"topic\":\"uitzonderingen\"}\n"
                    "Question: Who has the right to access public information under the Wet open overheid?\n"
                    "Answer: {\"topic\":\"recht_op_toegang\"}"
                ),
            },
            {"role": "user", "content": query},
        ],
        "temperature": 0,
        "max_tokens": 192,
    }
    response = http_json("POST", api_url(base_url, "/v1/chat/completions"), payload, api_key=api_key)
    content = chat_message_content(response, "metadata extraction")
    parsed = extract_json(content)
    topic = parsed.get("topic")
    if topic is not None:
        topic = str(topic).lower()
        if topic not in VALID_TOPICS:
            raise RuntimeError(f"metadata extraction returned unsupported topic: {topic}")
        return {"type": "eq", "key": "topic", "value": topic}, "llm-json"
    return {}, "llm-json"


def search(
    client: LlamaStackClient,
    vector_store_id: str,
    query: str,
    filters: dict[str, Any],
    search_mode: str,
    max_results: int,
) -> list[Any]:
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
    expected_topic = filters.get("value") if filters.get("key") == "topic" else None
    if expected_topic:
        mismatches = [
            item
            for item in items
            if (get_value(item, "attributes") or {}).get("topic") != expected_topic
        ]
        if mismatches:
            raise RuntimeError(
                f"{search_mode} metadata filter mismatch: expected topic={expected_topic}, "
                f"got {[get_value(item, 'attributes') for item in mismatches]}"
            )
    if not items:
        raise RuntimeError(f"{search_mode} search returned no candidates")
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
    title = attrs.get("article_title") or attrs.get("record_id") or "retrieved document"
    return f"{title}: {json.dumps(attrs, sort_keys=True)}"


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
                "max_num_results": min(3, len(documents)),
            },
        ),
        (
            "/v1/rerank",
            {
                "model": model,
                "query": query,
                "documents": documents,
                "top_n": min(3, len(documents)),
            },
        ),
    ]
    errors = []
    for path, payload in payloads:
        try:
            response = http_json("POST", api_url(base_url, path), payload)
        except Exception as exc:  # noqa: BLE001 - collect endpoint variants for diagnosis.
            errors.append(str(exc))
            continue
        results = response.get("results") or response.get("data") or response.get("rankings")
        if not results:
            errors.append(f"{path} returned no ranked results: {response}")
            continue
        normalized = []
        for result in results:
            index = result.get("index", result.get("document_index", 0))
            score = result.get("relevance_score", result.get("score", result.get("logit")))
            normalized.append(
                {
                    "index": int(index),
                    "score": score,
                    "text": documents[int(index)] if int(index) < len(documents) else str(result),
                }
            )
        return normalized, path
    raise RuntimeError("reranker endpoint failed: " + " | ".join(errors[:4]))


def final_answer(
    base_url: str,
    model: str,
    query: str,
    ranked: list[dict[str, Any]],
    api_key: str | None,
) -> str:
    context = "\n\n".join(f"[{idx + 1}] {item['text']}" for idx, item in enumerate(ranked))
    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": (
                    "Answer using only the provided retrieved context. Follow the language "
                    "of the user's question. If the context does not contain the answer, say "
                    "that the retrieved context is insufficient. Put the final answer in the "
                    "assistant content."
                ),
            },
            {"role": "user", "content": f"Question: {query}\n\nRetrieved context:\n{context}"},
        ],
        "temperature": 0,
        "max_tokens": 512,
    }
    response = http_json("POST", api_url(base_url, "/v1/chat/completions"), payload, api_key=api_key)
    answer = chat_message_content(response, "final answer")
    if len(answer.strip()) < 10:
        raise RuntimeError(f"final answer was empty or too short: {answer!r}")
    return answer.strip()


def assert_expected_terms(answer: str, expected_terms: list[str]) -> None:
    lowered = answer.casefold()
    missing = [term for term in expected_terms if term.casefold() not in lowered]
    if missing:
        raise RuntimeError(f"final answer missed expected terms {missing}: {answer!r}")


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
    parser.add_argument(
        "--sample",
        type=Path,
        default=Path(__file__).parents[1] / "data/dutch-government/processed/stb-2022-14-chunks.jsonl",
    )
    parser.add_argument("--vector-store", default=os.environ.get("RHOAI_STAGE230_DUTCH_VECTOR_STORE", DEFAULT_VECTOR_STORE))
    parser.add_argument("--embedding-model", default=os.environ.get("RHOAI_STAGE230_EMBEDDING_MODEL", DEFAULT_EMBEDDING_MODEL))
    parser.add_argument("--vector-provider", default=os.environ.get("RHOAI_STAGE230_VECTOR_PROVIDER", DEFAULT_VECTOR_PROVIDER))
    parser.add_argument("--generation-model", default=os.environ.get("RHOAI_STAGE230_GENERATION_MODEL", DEFAULT_GENERATION_MODEL))
    parser.add_argument("--reranker-model", default=os.environ.get("RHOAI_STAGE230_RERANKER_MODEL", DEFAULT_RERANKER_MODEL))
    parser.add_argument("--query", default=DEFAULT_QUERY)
    parser.add_argument("--search-mode", default=os.environ.get("RHOAI_STAGE230_SEARCH_MODE", "hybrid"))
    parser.add_argument("--expected-topic", default="openbaarmaking_op_verzoek")
    parser.add_argument("--expected-term", action="append", default=["vier weken"])
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

    base_url = normalize_base_url(args.base_url)
    generation_base_url = normalize_base_url(args.generation_base_url)
    client = LlamaStackClient(base_url=base_url)
    records = load_records(args.sample)
    vector_store_id, uploaded_count = ensure_vector_store(
        client,
        args.vector_store,
        args.embedding_model,
        args.vector_provider,
        records,
        args.reset,
    )
    filters, extraction_method = extract_metadata_filter(
        generation_base_url,
        args.generation_model,
        args.query,
        args.generation_api_key,
    )
    if args.expected_topic and filters.get("value") != args.expected_topic:
        raise RuntimeError(f"expected extracted topic {args.expected_topic}, got {filters or None}")
    candidates = search(client, vector_store_id, args.query, filters, args.search_mode, max_results=5)
    ranked, reranker_path = rerank(args.reranker_base_url, args.reranker_model, args.query, candidates)
    answer = final_answer(generation_base_url, args.generation_model, args.query, ranked, args.generation_api_key)
    assert_expected_terms(answer, args.expected_term)
    print(
        json.dumps(
            {
                "status": "pass",
                "vector_store_id": vector_store_id,
                "uploaded_count": uploaded_count,
                "metadata_extraction_method": extraction_method,
                "filters": filters,
                "search_mode": args.search_mode,
                "candidate_count": len(candidates),
                "reranker_path": reranker_path,
                "reranked_count": len(ranked),
                "answer": answer,
            },
            indent=2,
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - produce concise CLI failure.
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
