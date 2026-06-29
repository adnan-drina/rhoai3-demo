"""Streamlit app for Stage 230 private RAG."""

from __future__ import annotations

import importlib.metadata as md
import logging
from typing import Iterable

import streamlit as st

from rhoai_rag_chatbot.config import ChatbotConfig, load_config
from rhoai_rag_chatbot.guardrails import GuardrailsGateway
from rhoai_rag_chatbot.llama_stack_gateway import LlamaStackGateway, SearchHit, VectorStoreRef
from rhoai_rag_chatbot.mcp import McpRegistry
from rhoai_rag_chatbot.prompts import build_rag_messages

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger(__name__)


@st.cache_resource(show_spinner=False)
def gateway_for(endpoint: str, timeout: float) -> LlamaStackGateway:
    return LlamaStackGateway(endpoint, timeout=timeout)


def _pick_default(options: list[str], preferred: str) -> int:
    if preferred in options:
        return options.index(preferred)
    return 0


def _store_label(store: VectorStoreRef) -> str:
    return store.name if store.name == store.id else f"{store.name} ({store.id})"


def _render_hits(hits: Iterable[SearchHit]) -> None:
    for index, hit in enumerate(hits, start=1):
        label = f"{index}. {hit.source}"
        if hit.score is not None:
            label = f"{label} - score {hit.score:.3f}"
        with st.expander(label, expanded=index == 1):
            st.write(hit.text)


def _init_messages() -> None:
    if "messages" not in st.session_state:
        st.session_state.messages = [
            {
                "role": "assistant",
                "content": "Ask a question about the private whoami knowledge base.",
                "hits": [],
            }
        ]


def _render_history() -> None:
    _init_messages()
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])
            hits = message.get("hits") or []
            if hits:
                _render_hits(hits)


def _suggestion_buttons(config: ChatbotConfig, store: VectorStoreRef | None) -> str | None:
    if store is None:
        return None
    suggestions = config.suggestions.get(store.name) or config.suggestions.get(store.id) or []
    if not suggestions:
        return None

    selected: str | None = None
    cols = st.columns(min(len(suggestions), 3))
    for idx, question in enumerate(suggestions):
        with cols[idx % len(cols)]:
            if st.button(question, use_container_width=True, key=f"suggestion-{idx}"):
                selected = question
    return selected


def _inspect(
    config: ChatbotConfig,
    gateway: LlamaStackGateway,
    models: list[str],
    stores: list[VectorStoreRef],
    mcp: McpRegistry,
    guardrails: GuardrailsGateway,
) -> None:
    st.subheader("Runtime")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Models", len(models))
    c2.metric("Vector stores", len(stores))
    c3.metric("MCP", "enabled" if mcp.enabled else "deferred")
    c4.metric("Guardrails", guardrails.status().status)

    st.code(f"Llama Stack: {config.llama_stack_endpoint}")
    st.caption(f"llama-stack-client {md.version('llama-stack-client')}")

    st.subheader("Models")
    st.table([{"id": model} for model in models])

    st.subheader("Vector Stores")
    st.table([{"name": store.name, "id": store.id, "provider": store.provider_id} for store in stores])

    st.subheader("MCP Connectors")
    connectors = mcp.connectors()
    if connectors:
        st.table([{"id": item.id, "server_label": item.server_label, "url": item.url} for item in connectors])
    else:
        st.info("No MCP connectors are registered in the current Llama Stack distribution.")

    st.subheader("Llama Stack Tools")
    tools = gateway.list_tools()
    if tools:
        st.json(tools)
    else:
        st.info("No tools are reported by the current Llama Stack distribution.")

    st.subheader("Shields")
    shields = gateway.list_shields()
    if shields:
        st.table([{"id": shield} for shield in shields])
    else:
        st.info("No shields are registered. Guardrails are intentionally deferred for this stage.")


def _chat(config: ChatbotConfig, gateway: LlamaStackGateway, models: list[str], stores: list[VectorStoreRef]) -> None:
    guardrails = GuardrailsGateway(config)
    mcp = McpRegistry(config, gateway)

    with st.sidebar:
        st.header("Settings")
        model = st.selectbox(
            "Model",
            models,
            index=_pick_default(models, config.default_model),
        )
        store_options = stores
        selected_store = st.selectbox(
            "Knowledge base",
            store_options,
            index=_pick_default([store.name for store in store_options], config.default_vector_store),
            format_func=_store_label,
        ) if store_options else None
        top_k = st.slider("Retrieved chunks", 1, 10, min(max(config.top_k, 1), 10))
        temperature = st.slider("Temperature", 0.0, 1.0, config.temperature, 0.05)
        max_tokens = st.slider("Max output tokens", 128, 2048, min(max(config.max_tokens, 128), 2048), 64)

        st.divider()
        st.caption(f"MCP: {'enabled' if mcp.enabled else 'deferred'}")
        st.caption(f"Guardrails: {guardrails.status().status}")

    st.title(config.title)
    selected_question = _suggestion_buttons(config, selected_store)
    _render_history()

    prompt = selected_question or st.chat_input("Ask about the private knowledge base")
    if not prompt:
        return

    st.session_state.messages.append({"role": "user", "content": prompt, "hits": []})
    with st.chat_message("user"):
        st.markdown(prompt)

    decision = guardrails.check_input(prompt)
    if not decision.allowed:
        content = f"Input blocked by guardrails: {decision.reason or decision.status}"
        st.session_state.messages.append({"role": "assistant", "content": content, "hits": []})
        with st.chat_message("assistant"):
            st.warning(content)
        return

    with st.chat_message("assistant"):
        hits: list[SearchHit] = []
        if selected_store is not None:
            with st.spinner("Retrieving private context"):
                hits = gateway.search(selected_store.id, prompt, top_k)
            if hits:
                _render_hits(hits)
            else:
                st.info("No private context was retrieved.")

        with st.spinner("Generating answer"):
            messages = build_rag_messages(prompt, hits, config.max_context_chars)
            try:
                answer = gateway.complete(model, messages, temperature=temperature, max_tokens=max_tokens)
            except Exception as exc:  # pylint: disable=broad-exception-caught
                logger.exception("Llama Stack completion failed")
                answer = f"Model request failed: {exc}"

        output_decision = guardrails.check_output(answer)
        if not output_decision.allowed:
            answer = f"Output blocked by guardrails: {output_decision.reason or output_decision.status}"
            st.warning(answer)
        else:
            st.markdown(answer or "The model returned an empty response.")

    st.session_state.messages.append({"role": "assistant", "content": answer, "hits": hits})


def main() -> None:
    config = load_config()
    st.set_page_config(page_title=config.title, page_icon="RAG", layout="wide")
    gateway = gateway_for(config.llama_stack_endpoint, config.llama_stack_timeout)

    try:
        models = [model.id for model in gateway.list_models()]
        stores = gateway.list_vector_stores()
    except Exception as exc:  # pylint: disable=broad-exception-caught
        st.error(f"Llama Stack is not reachable: {exc}")
        st.stop()

    if not models:
        st.error("No LLM models are available from Llama Stack.")
        st.stop()

    tab_chat, tab_inspect = st.tabs(["Chat", "Inspect"])
    with tab_chat:
        _chat(config, gateway, models, stores)
    with tab_inspect:
        _inspect(config, gateway, models, stores, McpRegistry(config, gateway), GuardrailsGateway(config))


if __name__ == "__main__":
    main()
