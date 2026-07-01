#!/usr/bin/env python3
"""Small AG News RAG smoke test for Stage 230.

This script is intentionally client-side. It should be run only after the
Stage 230 Llama Stack route is ready and the required Python dependencies are
available in the execution environment.
"""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path

from llama_stack_client import LlamaStackClient


DEFAULT_VECTOR_STORE = "stage230-agnews-smoke"
DEFAULT_EMBEDDING_MODEL = "all-MiniLM-L6-v2"


def load_records(path: Path) -> list[dict]:
    records = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    if not records:
        raise SystemExit(f"no records found in {path}")
    return records


def as_items(response):
    if isinstance(response, list):
        return response
    for key in ("data", "vector_stores", "items"):
        value = getattr(response, key, None)
        if value is not None:
            return value
        if isinstance(response, dict) and key in response:
            return response[key]
    return []


def get_value(item, *keys):
    for key in keys:
        if isinstance(item, dict) and key in item:
            return item[key]
        value = getattr(item, key, None)
        if value is not None:
            return value
    return None


def find_or_create_vector_store(client, name: str, embedding_model: str):
    for store in as_items(client.vector_stores.list()):
        if get_value(store, "name") == name:
            return get_value(store, "id", "vector_store_id")

    store = client.vector_stores.create(
        name=name,
        embedding_model=embedding_model,
        metadata={
            "tenant_id": "rhoai-demo",
            "version_no": "v1",
            "corpus": "agnews-sample",
            "environment": "demo",
            "language": "en",
        },
    )
    return get_value(store, "id", "vector_store_id")


def upload_records(client, vector_store_id: str, records: list[dict]) -> None:
    with tempfile.TemporaryDirectory(prefix="stage230-agnews-") as tmpdir:
        tmp_path = Path(tmpdir)
        for record in records:
            article_path = tmp_path / f"{record['id']}.txt"
            article_path.write_text(
                f"{record['title']}\n\n{record['text']}\n",
                encoding="utf-8",
            )
            with article_path.open("rb") as handle:
                uploaded = client.files.create(file=handle, purpose="assistants")
            client.vector_stores.files.create(
                vector_store_id=vector_store_id,
                file_id=get_value(uploaded, "id", "file_id"),
                attributes={
                    "category": record["category"],
                    "doc_type": record["doc_type"],
                    "tenant_id": record["tenant_id"],
                    "version_no": record["version_no"],
                    "source": record["source"],
                    "record_id": record["id"],
                },
            )


def search(client, vector_store_id: str, query: str, category: str | None):
    filters = None
    if category:
        filters = {
            "type": "eq",
            "key": "category",
            "value": category,
        }
    kwargs = {
        "vector_store_id": vector_store_id,
        "query": query,
        "search_mode": "hybrid",
        "max_num_results": 3,
    }
    if filters:
        kwargs["filters"] = filters
    return client.vector_stores.search(**kwargs)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=os.environ.get("LLAMA_STACK_BASE_URL"))
    parser.add_argument("--sample", type=Path, default=Path(__file__).parents[1] / "data/agnews-sample/agnews-sample.jsonl")
    parser.add_argument("--vector-store", default=os.environ.get("RHOAI_STAGE230_VECTOR_STORE", DEFAULT_VECTOR_STORE))
    parser.add_argument("--embedding-model", default=os.environ.get("RHOAI_STAGE230_EMBEDDING_MODEL", DEFAULT_EMBEDDING_MODEL))
    parser.add_argument("--query", default="Find business news about oil prices.")
    parser.add_argument("--category", default="business")
    args = parser.parse_args()

    if not args.base_url:
        raise SystemExit("LLAMA_STACK_BASE_URL or --base-url is required")

    client = LlamaStackClient(base_url=args.base_url)
    records = load_records(args.sample)
    vector_store_id = find_or_create_vector_store(client, args.vector_store, args.embedding_model)
    upload_records(client, vector_store_id, records)
    result = search(client, vector_store_id, args.query, args.category)
    print(json.dumps({
        "vector_store_id": vector_store_id,
        "query": args.query,
        "category": args.category,
        "result": result.model_dump() if hasattr(result, "model_dump") else result,
    }, indent=2, default=str))


if __name__ == "__main__":
    main()
