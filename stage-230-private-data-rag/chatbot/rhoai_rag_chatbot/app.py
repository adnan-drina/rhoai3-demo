"""Streamlit UI for Stage 230 private data RAG."""

from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version
import logging

import streamlit as st

from rhoai_rag_chatbot.config import AppConfig, load_config
from rhoai_rag_chatbot.guardrails import check_input, check_output
from rhoai_rag_chatbot.llama_stack_gateway import LlamaStackGateway, SearchHit
from rhoai_rag_chatbot.mcp import mcp_status
from rhoai_rag_chatbot.prompts import (
    build_context,
    detect_topic,
    model_only_messages,
    rag_messages,
)


logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger(__name__)


def package_version(name: str) -> str:
    try:
        return version(name)
    except PackageNotFoundError:
        return "unknown"


@st.cache_resource(show_spinner=False)
def gateway(endpoint: str, timeout: float) -> LlamaStackGateway:
    return LlamaStackGateway(endpoint, timeout)


@st.cache_data(ttl=20, show_spinner=False)
def cached_models(endpoint: str, timeout: float) -> list[str]:
    return gateway(endpoint, timeout).list_models()


@st.cache_data(ttl=20, show_spinner=False)
def cached_vector_stores(endpoint: str, timeout: float) -> list[dict[str, str]]:
    return gateway(endpoint, timeout).list_vector_stores()


def initialize_state() -> None:
    if "messages" not in st.session_state:
        st.session_state.messages = [
            {
                "role": "assistant",
                "content": (
                    "Ask a question about the Red Hat OpenShift AI 3.4 documentation "
                    "-- RAG, AutoRAG, evaluation, guardrails, AI Pipelines, or Docling."
                ),
            }
        ]


def choose_index(options: list[str], preferred: str) -> int:
    if preferred in options:
        return options.index(preferred)
    for index, option in enumerate(options):
        if preferred and preferred in option:
            return index
    return 0


def render_sources(hits: list[SearchHit]) -> None:
    """Render source citations as a clean numbered list with links."""
    if not hits:
        return
    st.markdown("---")
    st.markdown("**Sources**")
    for index, hit in enumerate(hits, start=1):
        url = hit.attributes.get("source_url") or ""
        topic = hit.attributes.get("topic") or ""
        title = hit.source or "Retrieved document"

        label = f"**[{index}] {title}**"
        if topic:
            label += f"  \u2022  `{topic}`"
        if url:
            label += f"  \u2022  [view]({url})"

        with st.expander(label, expanded=False):
            st.caption(hit.text[:800])
            if hit.score is not None:
                st.caption(f"Score: {hit.score:.4f}")


def render_history() -> None:
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])
            render_sources(message.get("sources", []))


def build_sidebar(config: AppConfig) -> dict[str, object]:
    with st.sidebar:
        st.header("Configuration")
        gw = gateway(config.llama_stack_endpoint, config.timeout)
        models = cached_models(config.llama_stack_endpoint, config.timeout)
        if config.default_model not in models:
            models = [config.default_model] + models
        models = list(dict.fromkeys(models))
        model = st.selectbox(
            "Model",
            models,
            index=choose_index(models, config.default_model),
        )

        use_rag = st.toggle("Use RAG context", value=True)
        stores = cached_vector_stores(config.llama_stack_endpoint, config.timeout)
        store_names = [store["name"] for store in stores]
        selected_store = ""
        selected_store_id = ""
        if use_rag:
            if stores:
                selected_store = st.selectbox(
                    "Knowledge store",
                    store_names,
                    index=choose_index(store_names, config.default_vector_store),
                )
                selected_store_id = next(store["id"] for store in stores if store["name"] == selected_store)
            else:
                st.warning("No vector stores are currently available.")

        search_mode = st.selectbox(
            "Search mode",
            ["hybrid", "vector", "keyword"],
            index=choose_index(["hybrid", "vector", "keyword"], config.default_search_mode),
            disabled=not use_rag,
        )
        top_k = st.slider("Retrieved chunks", 1, 12, config.default_top_k, disabled=not use_rag)
        rerank_enabled = st.toggle("Rerank results", value=config.rerank_enabled, disabled=not use_rag)
        temperature = st.slider("Temperature", 0.0, 1.0, config.temperature, 0.05)
        max_tokens = st.slider("Max output tokens", 128, 1200, config.max_output_tokens, 64)

        if st.button("Clear chat", use_container_width=True):
            st.session_state.messages = []
            st.cache_data.clear()
            st.rerun()

        with st.expander("Runtime", expanded=False):
            st.write(f"Llama Stack: `{config.llama_stack_endpoint}`")
            st.write(f"llama-stack-client: `{package_version('llama-stack-client')}`")
            st.write(f"History turns: `{config.history_turns}`")
            st.write(f"MCP enabled: `{config.mcp_enabled}`")
            st.write(f"Guardrails enabled: `{config.guardrails_enabled}`")
            st.write(f"Discovered tools: `{len(gw.list_tools())}`")

    return {
        "model": model,
        "use_rag": use_rag,
        "vector_store_name": selected_store,
        "vector_store_id": selected_store_id,
        "search_mode": search_mode,
        "top_k": top_k,
        "rerank_enabled": rerank_enabled,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }


def answer_prompt(config: AppConfig, ui_config: dict[str, object], prompt: str) -> None:
    gw = gateway(config.llama_stack_endpoint, config.timeout)
    sources: list[SearchHit] = []
    input_decision = check_input(config.guardrails_enabled, config.guardrails_endpoint, prompt)
    if not input_decision.allowed:
        st.warning(input_decision.message)
        st.session_state.messages.append({"role": "assistant", "content": input_decision.message})
        return

    history = st.session_state.get("messages", [])
    rag_fallback = False

    if ui_config["use_rag"] and ui_config["vector_store_id"]:
        with st.status("Retrieving context", expanded=False):
            topic = detect_topic(prompt)
            if topic:
                st.write(f"Detected topic: `{topic}`")
            hits = gw.search_vector_store(
                str(ui_config["vector_store_id"]),
                prompt,
                int(ui_config["top_k"]),
                str(ui_config["search_mode"]),
                topic_filter=topic,
            )
            st.write(f"Retrieved {len(hits)} candidate chunks from {ui_config['vector_store_name']}.")
            if hits and ui_config["rerank_enabled"]:
                hits = gw.rerank(config.reranker_model, prompt, hits, int(ui_config["top_k"]))
                st.write("Reranked retrieved chunks.")
            sources = hits

        if not sources:
            st.info(
                "No relevant context found in the knowledge store. "
                "Answering from general model knowledge (not grounded in private documents)."
            )
            rag_fallback = True
            messages = model_only_messages(prompt, history, config.history_turns)
        else:
            context = build_context(sources, config.max_context_chars)
            messages = rag_messages(prompt, context, history, config.history_turns)
    else:
        messages = model_only_messages(prompt, history, config.history_turns)

    try:
        stream = gw.chat_completion_stream(
            str(ui_config["model"]),
            messages,
            float(ui_config["temperature"]),
            int(ui_config["max_tokens"]),
        )
        answer = st.write_stream(stream)
    except Exception:
        logger.warning("Streaming failed, falling back to non-streaming")
        answer = gw.chat_completion(
            str(ui_config["model"]),
            messages,
            float(ui_config["temperature"]),
            int(ui_config["max_tokens"]),
        )
        st.markdown(answer)

    if not answer:
        answer = "The model returned an empty response."
        st.markdown(answer)

    output_decision = check_output(config.guardrails_enabled, config.guardrails_endpoint, str(answer))
    if not output_decision.allowed:
        st.warning(output_decision.message)
        st.session_state.messages.append({"role": "assistant", "content": output_decision.message})
        return

    if rag_fallback:
        st.caption("*This answer is based on general model knowledge, not private documentation.*")

    render_sources(sources)
    st.session_state.messages.append({
        "role": "assistant",
        "content": str(answer),
        "sources": sources,
    })


def render_suggestions(config: AppConfig, store_name: str) -> None:
    """Render clickable suggested question chips."""
    suggestions = config.question_suggestions.get(store_name, [])
    if not suggestions:
        suggestions = config.question_suggestions.get("default", [])
    if not suggestions or not isinstance(suggestions, list):
        return

    cols = st.columns(min(len(suggestions), 3))
    for i, suggestion in enumerate(suggestions):
        if not isinstance(suggestion, str):
            continue
        col = cols[i % len(cols)]
        if col.button(suggestion, key=f"suggest_{i}", use_container_width=True):
            st.session_state["_pending_suggestion"] = suggestion
            st.rerun()


def chat_tab(config: AppConfig) -> None:
    st.title("RHOAI Product Documentation Assistant")
    st.caption("Grounded in the Stage 230 RHOAI 3.4 product-document vector store.")
    ui_config = build_sidebar(config)
    initialize_state()
    render_history()

    if len(st.session_state.messages) <= 1:
        render_suggestions(config, str(ui_config.get("vector_store_name", "")))

    pending = st.session_state.pop("_pending_suggestion", None)
    prompt = pending or st.chat_input(
        "Ask about RHOAI RAG, AutoRAG, RAGAS, EvalHub, guardrails, AI Pipelines, or Docling"
    )

    if prompt:
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)
        with st.chat_message("assistant"):
            try:
                answer_prompt(config, ui_config, prompt)
            except Exception as exc:  # noqa: BLE001 - UI should report runtime errors.
                logger.exception("Chat request failed")
                message = f"Something went wrong while processing your request. Please try again.\n\n`{exc}`"
                st.error(message)
                st.session_state.messages.append({"role": "assistant", "content": message})


def inspect_tab(config: AppConfig) -> None:
    st.title("Inspect RAG Runtime")
    gw = gateway(config.llama_stack_endpoint, config.timeout)
    col1, col2 = st.columns(2)
    with col1:
        st.subheader("Models")
        st.json(cached_models(config.llama_stack_endpoint, config.timeout))
        st.subheader("MCP")
        st.json(mcp_status(config.mcp_enabled, gw.list_tools()))
    with col2:
        st.subheader("Vector stores")
        st.json(cached_vector_stores(config.llama_stack_endpoint, config.timeout))
        st.subheader("Guardrails")
        st.json(
            {
                "enabled": config.guardrails_enabled,
                "endpoint_configured": bool(config.guardrails_endpoint),
                "shields": gw.list_shields(),
            }
        )


def main() -> None:
    st.set_page_config(page_title="RHOAI RAG Assistant", layout="wide")
    config = load_config()
    chat, inspect = st.tabs(["Chat", "Inspect"])
    with chat:
        chat_tab(config)
    with inspect:
        inspect_tab(config)


if __name__ == "__main__":
    main()
