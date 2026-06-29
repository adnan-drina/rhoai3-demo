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
    ├── prompts.py              # Direct-RAG prompt and context format
    ├── mcp.py                  # Future MCP connector/tool boundary
    └── guardrails.py           # Future guardrails decision boundary
```

The active chatbot is intentionally smaller than the legacy Step 07 UI. It is
not a full copy of the Red Hat quickstart frontend. The quickstart and legacy
app remain references for useful behavior, especially direct RAG, agent tool
calling, Inspect pages, and prompt tuning.

## Active Mode

| Aspect | Stage 230 Direct RAG |
|--------|----------------------|
| API | `client.chat.completions.create()` |
| Retrieval | `client.vector_stores.search()` against selected vector store |
| Context | retrieved chunks are injected into the user message |
| Default model | `vllm-inference/nemotron-3-nano-30b-a3b` |
| Default vector store | `whoami` |
| Guardrails | disabled-by-default adapter in `guardrails.py` |
| MCP | connector discovery/tool contract in `mcp.py`, disabled by default |

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
Image: image-registry.openshift-image-registry.svc:5000/enterprise-rag/private-rag-chatbot:latest
BuildConfig: private-rag-chatbot
Route: private-rag-chatbot

Dependencies:
- lsd-private-rag LlamaStackDistribution
- private-rag-postgres pgvector database
- whoami vector store populated by the Stage 230 KFP ingestion pipeline
- Stage 220 MaaS-backed Nemotron model
```
