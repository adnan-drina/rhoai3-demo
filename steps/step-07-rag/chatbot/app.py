"""
RAG Chatbot — Streamlit frontend for LlamaStack RAG queries.

Uses direct vector search + context injection pattern:
  1. Search vector store for relevant chunks
  2. Inject chunks as context into the prompt
  3. Model generates grounded answer

This pattern works reliably with lsd-rag's custom config (image_name: custom)
where the Responses API file_search tool doesn't have proper vector_io wiring.

Inspired by: https://github.com/rh-ai-quickstart/RAG
"""

import os
import streamlit as st
from llama_stack_client import LlamaStackClient

LLAMA_STACK_URL = os.getenv("LLAMA_STACK_URL", "http://lsd-rag-service.private-ai.svc.cluster.local:8321")
DEFAULT_MODEL = os.getenv("INFERENCE_MODEL", "vllm-granite-agent/granite-8b-agent")
MAX_CONTEXT_CHARS = 4000

SYSTEM_PROMPT_RAG = (
    "You are a knowledgeable AI assistant. Answer based strictly on the "
    "provided document context. If the context doesn't contain relevant "
    "information, say so clearly and offer what you know from general knowledge, "
    "distinguishing between document-based and general knowledge."
)
SYSTEM_PROMPT_DIRECT = (
    "You are a helpful AI assistant. Answer questions concisely and accurately."
)


@st.cache_resource
def get_client():
    return LlamaStackClient(base_url=LLAMA_STACK_URL, timeout=120.0)


@st.cache_data(ttl=60)
def get_vector_stores():
    client = get_client()
    stores = {}
    try:
        for vs in client.vector_stores.list():
            fc = vs.file_counts
            done = fc.completed if hasattr(fc, "completed") else 0
            if done > 0:
                if vs.name not in stores or done > stores[vs.name]["files"]:
                    stores[vs.name] = {"id": vs.id, "files": done}
    except Exception as e:
        st.error(f"Failed to list vector stores: {e}")
    return stores


@st.cache_data(ttl=60)
def get_models():
    client = get_client()
    models = []
    try:
        for m in client.models.list():
            if hasattr(m, "model_type") and str(m.model_type) != "embedding":
                models.append(m.identifier)
    except Exception:
        models = [DEFAULT_MODEL]
    return models


def search_vector_store(query: str, vector_store_id: str, max_results: int = 5):
    """Search vector store and return context string + chunk details."""
    client = get_client()
    try:
        results = client.vector_stores.search(
            vector_store_id=vector_store_id,
            query=query,
            max_num_results=max_results,
        )
        chunks = results.data if hasattr(results, "data") else []
        context_parts = []
        details = []
        for r in chunks:
            text = r.content[0].text if hasattr(r, "content") and r.content else ""
            score = r.score if hasattr(r, "score") else 0
            if text:
                context_parts.append(text)
                details.append({"score": round(score, 3), "preview": text[:100]})
        context = "\n\n---\n\n".join(context_parts)
        return context[:MAX_CONTEXT_CHARS], details
    except Exception as e:
        return "", [{"score": 0, "preview": f"Search error: {e}"}]


def query_rag(question: str, model: str, vector_store_id: str, system_prompt: str):
    """RAG query: search → inject context → generate."""
    context, details = search_vector_store(question, vector_store_id)

    if not context:
        return "No relevant documents found in the knowledge base.", details

    augmented_input = (
        f"QUESTION: {question}\n\n"
        f"DOCUMENT CONTEXT:\n{context}\n\n"
        f"Answer the question based on the document context above."
    )

    client = get_client()
    response = client.responses.create(
        model=model,
        input=augmented_input,
        instructions=system_prompt,
    )
    return response.output_text, details


def query_direct(question: str, model: str, system_prompt: str):
    """Direct query without RAG."""
    client = get_client()
    response = client.responses.create(
        model=model,
        input=question,
        instructions=system_prompt,
    )
    return response.output_text


# --- UI ---

st.set_page_config(
    page_title="RAG Chatbot — Private AI",
    page_icon="🔍",
    layout="wide",
)

st.title("🔍 RAG Chatbot")
st.caption("Knowledge-grounded answers powered by LlamaStack + Milvus on Red Hat OpenShift AI")

# Sidebar
with st.sidebar:
    st.header("⚙️ Configuration")

    stores = get_vector_stores()
    models = get_models()

    selected_model = st.selectbox("Model", models, index=0)

    store_names = list(stores.keys())
    if store_names:
        selected_store = st.selectbox(
            "Knowledge Base",
            store_names,
            format_func=lambda x: f"{x} ({stores[x]['files']} files)",
        )
    else:
        selected_store = None
        st.warning("No vector stores found. Run the RAG ingestion pipeline first.")

    rag_enabled = st.toggle("RAG Enabled", value=True, disabled=not selected_store)
    compare_mode = st.toggle("Compare: RAG vs Direct", value=False)

    st.divider()
    system_prompt = st.text_area(
        "System Instructions",
        value=SYSTEM_PROMPT_RAG if rag_enabled else SYSTEM_PROMPT_DIRECT,
        height=120,
    )

    st.divider()
    st.markdown("**Infrastructure**")
    st.code(f"LlamaStack: {LLAMA_STACK_URL}", language=None)
    if selected_store and stores.get(selected_store):
        st.code(f"Store: {stores[selected_store]['id']}", language=None)

    st.divider()
    st.markdown(
        "Built with [LlamaStack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/) "
        "on [Red Hat OpenShift AI](https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai)"
    )

# Chat history
if "messages" not in st.session_state:
    st.session_state.messages = []

for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])

# Chat input
if question := st.chat_input("Ask a question about your documents..."):
    st.session_state.messages.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(question)

    if compare_mode and selected_store and stores.get(selected_store):
        col1, col2 = st.columns(2)

        with col1:
            st.markdown("**Without RAG**")
            with st.spinner("Querying model directly..."):
                try:
                    direct_answer = query_direct(question, selected_model, SYSTEM_PROMPT_DIRECT)
                    st.markdown(direct_answer)
                except Exception as e:
                    st.error(f"Direct query failed: {e}")
                    direct_answer = f"Error: {e}"

        with col2:
            st.markdown("**With RAG**")
            with st.spinner("Searching knowledge base..."):
                try:
                    rag_answer, details = query_rag(
                        question, selected_model, stores[selected_store]["id"], system_prompt
                    )
                    st.markdown(rag_answer)
                    with st.expander("📚 Retrieved chunks"):
                        for d in details:
                            st.markdown(f"- **Score {d['score']}:** {d['preview']}...")
                except Exception as e:
                    st.error(f"RAG query failed: {e}")
                    rag_answer = f"Error: {e}"

        combined = f"**Direct:** {direct_answer}\n\n**RAG ({selected_store}):** {rag_answer}"
        st.session_state.messages.append({"role": "assistant", "content": combined})

    elif rag_enabled and selected_store and stores.get(selected_store):
        with st.chat_message("assistant"):
            with st.spinner("Searching knowledge base..."):
                try:
                    answer, details = query_rag(
                        question, selected_model, stores[selected_store]["id"], system_prompt
                    )
                    st.markdown(answer)
                    with st.expander("📚 Retrieved chunks"):
                        for d in details:
                            st.markdown(f"- **Score {d['score']}:** {d['preview']}...")
                    st.session_state.messages.append({"role": "assistant", "content": answer})
                except Exception as e:
                    st.error(f"RAG query failed: {e}")
    else:
        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                try:
                    answer = query_direct(question, selected_model, system_prompt)
                    st.markdown(answer)
                    st.session_state.messages.append({"role": "assistant", "content": answer})
                except Exception as e:
                    st.error(f"Query failed: {e}")
