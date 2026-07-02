# Chatbot Architecture Reference

## Component Map

```text
stage-230-private-data-rag/chatbot/
├── Containerfile
├── pyproject.toml
└── rhoai_rag_chatbot/
    ├── app.py                  # Streamlit Chat and Inspect tabs
    ├── config.py               # Environment-backed app contract
    ├── llama_stack_gateway.py  # Llama Stack adapter
    ├── prompts.py              # RAG and model-only prompt and context format
    ├── mcp.py                  # Future MCP connector/tool boundary
    └── guardrails.py           # Future guardrails decision boundary
```

The active chatbot is intentionally smaller than the legacy Step 07 UI and the
Red Hat AI RAG quickstart frontend. The quickstart is the selected Streamlit
reference for direct chat layout, vector-store selection, suggested-question
configuration, and Inspect-style runtime visibility. Stage 230 reuses those
patterns without copying upload workflows, outdated client pins, or agent/tool
flows that belong to later stages.

## Active Modes

| Aspect | RAG mode | Model-only mode |
|--------|----------|-----------------|
| API | `client.chat.completions.create()` | `client.chat.completions.create()` |
| Retrieval | `client.vector_stores.search()` against selected vector store | skipped |
| Context | retrieved chunks are injected into the user message | none |
| Default model | `nemotron-3-nano-30b-a3b` | `nemotron-3-nano-30b-a3b` |
| Default vector store | `stage230-rhoai-34-product-docs-kfp` | not used |
| Guardrails | disabled-by-default adapter in `guardrails.py` | disabled-by-default adapter in `guardrails.py` |
| MCP | connector discovery/tool contract in `mcp.py`, disabled by default | connector discovery/tool contract in `mcp.py`, disabled by default |

## Future Extension Points

### MCP

`mcp.py` discovers RHOAI 3.4 Llama Stack MCP connectors from
`/v1beta/connectors` and can convert them to Responses API tool objects when
`MCP_ENABLED=true`. Future work must register the product-side connector in
Llama Stack first and then add an agent/Responses API execution path.

### Guardrails

`guardrails.py` exposes `check_input()` and `check_output()` decisions. Stage
230 leaves `GUARDRAILS_ENABLED=false`; a later stage should use
`rhoai-guardrails-safety` to deploy and validate NeMo or FMS guardrails before
turning this on. If the flag is enabled before a reviewed product API payload is
implemented, the adapter must fail closed rather than silently allowing traffic.

## ConfigMap And Env Vars

| Env Var | Purpose |
|---------|---------|
| `LLAMA_STACK_ENDPOINT` | Llama Stack service URL without `/v1` |
| `LLAMA_STACK_TIMEOUT` | client request timeout |
| `INFERENCE_MODEL` | default Llama Stack model id |
| `DEFAULT_VECTOR_STORE` | default vector store name/id |
| `RAG_TOP_K` | number of retrieved chunks |
| `RAG_MAX_CONTEXT_CHARS` | maximum context injected into the prompt |
| `RAG_MAX_OUTPUT_TOKENS` | maximum completion tokens |
| `RAG_TEMPERATURE` | completion temperature |
| `RAG_SEARCH_MODE` | default search mode: `hybrid`, `vector`, or `keyword` |
| `RAG_RERANK_ENABLED` | enable Qwen3 reranking of search results |
| `RAG_RERANKER_MODEL` | Llama Stack reranker model id |
| `RAG_QUESTION_SUGGESTIONS` | JSON object keyed by vector-store name/id |
| `MCP_ENABLED` | future MCP feature flag |
| `GUARDRAILS_ENABLED` | future guardrails feature flag |
| `GUARDRAILS_ENDPOINT` | future guardrails endpoint |

## Inspect Tab

The Inspect tab should remain lightweight and operational:

- Llama Stack endpoint and client version
- model count and model ids
- vector store count and vector-store ids
- MCP connector discovery state
- `/v1/tools` output when available
- Llama Stack shields when available
- guardrails status from the adapter

## Deployment Topology

```text
Namespace: enterprise-rag
Deployment: private-rag-chatbot
Image: image-registry.openshift-image-registry.svc:5000/enterprise-rag-build/private-rag-chatbot:latest
Build namespace: enterprise-rag-build
BuildConfig: private-rag-chatbot
Route: private-rag-chatbot
OpenShift AI dashboard tile: redhat-ods-applications/rhoai-demo-private-rag-chatbot

Dependencies:
- lsd-enterprise-rag LlamaStackDistribution
- private-rag-postgres pgvector database
- stage230-rhoai-34-product-docs-kfp vector store populated by the Stage 230 KFP ingestion pipeline
- Stage 220 MaaS-backed Nemotron model
```

The dashboard tile is an `OdhApplication`, not an OpenShift `ConsoleLink`. Keep
it in `redhat-ods-applications`, point `spec.route` at
`enterprise-rag/private-rag-chatbot`, and preserve the documented dashboard
labels `app: odh-dashboard` and `app.kubernetes.io/part-of: odh-dashboard`.

The OpenShift BuildConfig and ImageStream live in `enterprise-rag-build`
instead of `enterprise-rag`. The runtime service account has
`system:image-puller` on that build namespace. This prevents Kueue from
admitting OpenShift build pods as plain RAG workload pods while preserving
queue enforcement for the RAG runtime project.
