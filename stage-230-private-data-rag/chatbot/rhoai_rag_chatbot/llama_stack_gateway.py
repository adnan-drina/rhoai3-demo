"""Small Llama Stack adapter for the Stage 230 Streamlit app."""

from __future__ import annotations

from dataclasses import dataclass
import json
import logging
import ssl
from typing import Any
import urllib.error
import urllib.request

from llama_stack_client import LlamaStackClient


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class SearchHit:
    text: str
    source: str
    score: float | None
    attributes: dict[str, Any]


def as_items(response: Any) -> list[Any]:
    if response is None:
        return []
    if isinstance(response, list):
        return response
    for key in ("data", "vector_stores", "items", "results", "chunks"):
        if isinstance(response, dict) and key in response:
            return response[key] or []
        value = getattr(response, key, None)
        if value is not None:
            return value or []
    return []


def get_value(item: Any, *keys: str) -> Any:
    for key in keys:
        if isinstance(item, dict) and key in item:
            return item[key]
        value = getattr(item, key, None)
        if value is not None:
            return value
    return None


def item_id(item: Any) -> str:
    return str(get_value(item, "identifier", "id", "vector_store_id") or "")


def item_name(item: Any) -> str:
    return str(get_value(item, "name", "identifier", "id", "vector_store_id") or "")


class LlamaStackGateway:
    def __init__(self, base_url: str, timeout: float):
        self.base_url = base_url.rstrip("/")
        self.client = LlamaStackClient(base_url=self.base_url, timeout=timeout)

    def list_models(self) -> list[str]:
        models = []
        for model in as_items(self.client.models.list()):
            model_id = item_id(model)
            if not model_id:
                continue
            model_type = get_value(model, "model_type", "api_model_type")
            if isinstance(model_type, str) and model_type.lower() not in {"llm", "chat"}:
                continue
            if "embed" in model_id or "reranker" in model_id:
                continue
            models.append(model_id)
        return sorted(dict.fromkeys(models))

    def list_vector_stores(self) -> list[dict[str, str]]:
        stores = []
        for store in as_items(self.client.vector_stores.list()):
            store_id = item_id(store)
            name = item_name(store)
            if store_id:
                stores.append({"id": store_id, "name": name or store_id})
        return stores

    def search_vector_store(
        self,
        vector_store_id: str,
        query: str,
        top_k: int,
        search_mode: str,
    ) -> list[SearchHit]:
        kwargs = {
            "vector_store_id": vector_store_id,
            "query": query,
            "max_num_results": top_k,
        }
        if search_mode:
            kwargs["search_mode"] = search_mode
        try:
            response = self.client.vector_stores.search(**kwargs)
        except TypeError:
            kwargs.pop("search_mode", None)
            response = self.client.vector_stores.search(**kwargs)

        hits = []
        for item in as_items(response):
            text = self._extract_text(item)
            if not text:
                continue
            attributes = get_value(item, "attributes") or {}
            if not isinstance(attributes, dict):
                attributes = {}
            source = (
                attributes.get("document_title")
                or attributes.get("source_file")
                or attributes.get("source")
                or attributes.get("record_id")
                or "retrieved document"
            )
            score = get_value(item, "score", "ranking_score")
            try:
                score = float(score) if score is not None else None
            except (TypeError, ValueError):
                score = None
            hits.append(SearchHit(text=text.strip(), source=str(source), score=score, attributes=attributes))
        return hits

    def rerank(self, model: str, query: str, hits: list[SearchHit], top_k: int) -> list[SearchHit]:
        if not hits:
            return []
        documents = [hit.text[:1200] for hit in hits]
        typed_items = [{"type": "text", "text": document} for document in documents]
        payloads = [
            (
                "/v1alpha/inference/rerank",
                {"model": model, "query": query, "items": typed_items, "max_num_results": min(top_k, len(hits))},
            ),
            (
                "/v1/rerank",
                {"model": model, "query": query, "documents": documents, "top_n": min(top_k, len(hits))},
            ),
        ]
        errors = []
        for path, payload in payloads:
            try:
                response = self._http_json("POST", path, payload)
            except Exception as exc:  # noqa: BLE001 - show all endpoint attempts.
                errors.append(str(exc))
                continue
            results = response.get("results") or response.get("data") or response.get("rankings")
            if not results:
                errors.append(f"{path} returned no ranked results")
                continue
            ranked = []
            for result in results:
                index = int(result.get("index", result.get("document_index", 0)))
                if 0 <= index < len(hits):
                    ranked.append(hits[index])
            return ranked or hits[:top_k]
        logger.warning("Reranker failed; using original search order: %s", " | ".join(errors[:3]))
        return hits[:top_k]

    def chat_completion(
        self,
        model: str,
        messages: list[dict[str, str]],
        temperature: float,
        max_tokens: int,
    ) -> str:
        response = self.client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
        )
        return self._chat_text(response).strip()

    def list_tools(self) -> list[str]:
        try:
            return [item_id(tool) for tool in as_items(self.client.tools.list()) if item_id(tool)]
        except Exception:
            return []

    def list_shields(self) -> list[str]:
        try:
            return [item_id(shield) for shield in as_items(self.client.shields.list()) if item_id(shield)]
        except Exception:
            return []

    def _http_json(self, method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        url = self._api_url(path)
        data = None if payload is None else json.dumps(payload).encode()
        request = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={"Content-Type": "application/json"},
        )
        context = ssl._create_unverified_context()
        try:
            with urllib.request.urlopen(request, context=context, timeout=120) as response:
                body = response.read().decode()
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")
            raise RuntimeError(f"{method} {url} failed with HTTP {exc.code}: {body[:400]}") from exc
        return json.loads(body or "{}")

    def _api_url(self, path: str) -> str:
        base = self.base_url.rstrip("/")
        path = path.lstrip("/")
        if base.endswith("/v1") and path.startswith("v1/"):
            path = path[3:]
        return f"{base}/{path}"

    @staticmethod
    def _extract_text(item: Any) -> str:
        content = get_value(item, "content")
        if isinstance(content, list):
            parts = []
            for part in content:
                text = get_value(part, "text", "content")
                if text:
                    parts.append(str(text))
            if parts:
                return "\n".join(parts)
        if isinstance(content, str):
            return content
        for key in ("text", "chunk_text"):
            value = get_value(item, key)
            if value:
                return str(value)
        return ""

    @staticmethod
    def _chat_text(response: Any) -> str:
        choices = get_value(response, "choices") or []
        if choices:
            message = get_value(choices[0], "message") or {}
            content = get_value(message, "content")
            if isinstance(content, list):
                return "\n".join(
                    str(get_value(part, "text", "content") or "")
                    for part in content
                )
            if content is not None:
                return str(content)
        content = get_value(response, "content", "text")
        if content is not None:
            return str(content)
        return ""
