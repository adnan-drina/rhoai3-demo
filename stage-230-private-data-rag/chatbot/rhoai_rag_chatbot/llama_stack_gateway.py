"""Small Llama Stack adapter used by the Stage 230 chatbot."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

import requests
from llama_stack_client import LlamaStackClient

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ModelRef:
    id: str
    provider_id: str = ""
    model_type: str = ""


@dataclass(frozen=True)
class VectorStoreRef:
    id: str
    name: str
    provider_id: str = ""


@dataclass(frozen=True)
class SearchHit:
    text: str
    source: str
    score: float | None = None
    metadata: dict[str, Any] | None = None


def _get(obj: Any, key: str, default: Any = None) -> Any:
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)


def _identifier(obj: Any) -> str:
    for key in ("id", "identifier", "provider_resource_id", "model_id", "name"):
        value = _get(obj, key)
        if value:
            return str(value)
    return ""


def _metadata(obj: Any) -> dict[str, Any]:
    for key in ("metadata", "attributes", "custom_metadata"):
        value = _get(obj, key)
        if isinstance(value, dict):
            return value
    return {}


def _text_from_content(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            text = _get(item, "text")
            if text:
                parts.append(str(text))
            elif isinstance(item, str):
                parts.append(item)
        return "\n".join(parts)
    text = _get(content, "text")
    return str(text) if text else ""


def _search_results(response: Any) -> list[Any]:
    for key in ("data", "chunks", "results"):
        value = _get(response, key)
        if isinstance(value, list):
            return value
    content = _get(response, "content")
    if isinstance(content, list):
        return content
    return []


class LlamaStackGateway:
    """Typed wrapper around the subset of Llama Stack APIs used by the demo UI."""

    def __init__(self, base_url: str, timeout: float = 600.0):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.client = LlamaStackClient(base_url=self.base_url, timeout=timeout)

    def list_models(self) -> list[ModelRef]:
        models: list[ModelRef] = []
        for model in self.client.models.list() or []:
            model_id = _identifier(model)
            if not model_id:
                continue
            metadata = _metadata(model)
            model_type = str(metadata.get("model_type") or _get(model, "model_type") or "")
            provider_id = str(_get(model, "provider_id", "") or "")
            if model_type and model_type != "llm":
                continue
            models.append(ModelRef(id=model_id, provider_id=provider_id, model_type=model_type))
        return models

    def list_vector_stores(self) -> list[VectorStoreRef]:
        stores: list[VectorStoreRef] = []
        for store in self.client.vector_stores.list() or []:
            store_id = _identifier(store)
            if not store_id:
                continue
            name = str(_get(store, "name", "") or _get(store, "vector_store_name", "") or store_id)
            provider_id = str(_get(store, "provider_id", "") or "")
            stores.append(VectorStoreRef(id=store_id, name=name, provider_id=provider_id))
        return stores

    def search(self, vector_store_id: str, query: str, top_k: int) -> list[SearchHit]:
        response = self.client.vector_stores.search(
            vector_store_id=vector_store_id,
            query=query,
            max_num_results=top_k,
        )

        hits: list[SearchHit] = []
        for item in _search_results(response)[:top_k]:
            metadata = _metadata(item)
            text = _text_from_content(_get(item, "content"))
            if not text:
                text = _text_from_content(_get(item, "text"))
            if not text:
                continue
            source = (
                str(metadata.get("source") or metadata.get("filename") or "")
                or str(_get(item, "filename", "") or "")
                or str(metadata.get("document_id") or "unknown")
            )
            score = _get(item, "score")
            try:
                score = float(score) if score is not None else None
            except (TypeError, ValueError):
                score = None
            hits.append(SearchHit(text=" ".join(text.split()), source=source, score=score, metadata=metadata))
        return hits

    def complete(self, model: str, messages: list[dict[str, str]], temperature: float, max_tokens: int) -> str:
        response = self.client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
            stream=False,
        )
        choices = _get(response, "choices", [])
        if not choices:
            return ""
        message = _get(choices[0], "message")
        content = _get(message, "content", "") if message is not None else ""
        return str(content or "")

    def list_tools(self) -> list[dict[str, Any]]:
        return self._list_rest_items("/v1/tools")

    def list_connectors(self) -> list[dict[str, Any]]:
        return self._list_rest_items("/v1beta/connectors")

    def list_shields(self) -> list[str]:
        try:
            return [_identifier(shield) for shield in self.client.shields.list() or [] if _identifier(shield)]
        except Exception as exc:  # pylint: disable=broad-exception-caught
            logger.debug("Unable to list Llama Stack shields: %s", exc)
            return []

    def _list_rest_items(self, path: str) -> list[dict[str, Any]]:
        try:
            response = requests.get(f"{self.base_url}{path}", timeout=15)
            response.raise_for_status()
            payload = response.json()
        except Exception as exc:  # pylint: disable=broad-exception-caught
            logger.debug("Unable to fetch %s from Llama Stack: %s", path, exc)
            return []

        data = payload.get("data", payload) if isinstance(payload, dict) else payload
        return data if isinstance(data, list) else []
