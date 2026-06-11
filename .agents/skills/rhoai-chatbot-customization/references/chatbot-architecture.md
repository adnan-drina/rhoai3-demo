# Chatbot Architecture Reference

## Table of Contents

- [Component Map](#component-map)
- [Mode Comparison](#mode-comparison)
- [File-by-File Reference](#file-by-file-reference)
- [ConfigMap and Env Vars](#configmap-and-env-vars)
- [Inspect Page Tabs](#inspect-page-tabs)
- [Deployment Topology](#deployment-topology)

## Component Map

```
backup/legacy-implementation-2026-06-09/steps/step-07-rag/chatbot/
├── Containerfile                        # Build image
├── pyproject.toml                       # Dependencies
└── llama_stack_ui/distribution/ui/
    ├── app.py                           # Entry point, page routing
    ├── modules/
    │   ├── api.py                       # LlamaStackApi singleton
    │   ├── guardrails.py                # Step 09 guardrails safety client
    │   └── utils.py                     # Suggestions, vector DB helpers
    └── page/
        ├── playground/
        │   ├── chat.py                  # Main page: sidebar, prompts, modes
        │   ├── agent.py                 # Agent mode: Responses API, tools
        │   └── direct.py               # Direct mode: completions + manual RAG
        ├── upload/
        │   └── upload.py                # Document upload page
        └── distribution/
            ├── inspect.py               # Inspect page router (6 tabs)
            ├── toolgroups.py            # Tool Groups tab
            ├── scoring_functions.py     # Scoring tab
            ├── vector_dbs.py            # Vector DBs tab
            ├── models.py               # Models tab
            ├── shields.py              # Shields tab
            ├── providers.py            # API Providers tab
            ├── datasets.py             # Datasets tab
            └── eval_tasks.py           # Eval Tasks tab
```

## Mode Comparison

| Aspect | Direct Mode | Agent Mode |
|--------|-------------|------------|
| API | `chat.completions.create()` | `responses.create()` |
| RAG | Manual: query pgvector → inject context | Automatic: LlamaStack file_search tool |
| Tools | None | MCP tool groups + file_search |
| tool_choice | N/A | `"required"` |
| Guardrails | Not available | Toggle in sidebar |
| System prompt | Short grounding | Long: tool mandate + retry + hints + citation |
| Streaming | SSE completions | SSE response chunks with tool call events |

## File-by-File Reference

### chat.py — Main Chat Page

| Line Range | Feature |
|------------|---------|
| ~100-140 | Sidebar configuration: model selector, mode toggle |
| ~150-175 | Sampling params: temperature, top_p, max_tokens |
| ~180-210 | Vector store selector (RAG dropdown) |
| ~220-240 | Max inference iterations slider (agent mode only) |
| ~243-259 | Guardrails toggle (agent mode only) |
| ~288-308 | Default system prompts (direct vs agent) |
| ~539-548 | Suggested questions display |

### agent.py — Agent Mode

| Line Range | Feature |
|------------|---------|
| ~50-80 | build_response_tools(): constructs tool list from MCP groups |
| ~100-150 | stream_agent_response(): SSE streaming + chunk processing |
| ~354-366 | Input guardrails check (before sending to model) |
| ~391-393 | tool_choice = "required" when tools present |
| ~406-422 | Output guardrails check (after model response) |

### guardrails.py — Safety Module

| Function | Purpose |
|----------|---------|
| `is_available()` | Checks if Guardrails Orchestrator (step-09) is reachable |
| `check_input(text)` | HAP + Prompt Injection detection |
| `check_output(text)` | HAP + PII regex (email, phone, credit card, LinkedIn, GitHub) |

Guardrails Orchestrator endpoint: `https://guardrails-orchestrator.private-ai.svc.cluster.local:8032`
API: `/api/v2/text/detection/content`

## ConfigMap and Env Vars

The chatbot uses env vars on the Deployment, not a ConfigMap:

| Env Var | Source | Purpose |
|---------|--------|---------|
| `LLAMA_STACK_URL` | `backup/legacy-implementation-2026-06-09/gitops/step-07-rag/base/chatbot/chatbot.yaml` | LlamaStack API endpoint |
| `INFERENCE_MODEL` | Same file | Default model for inference |
| `RAG_QUESTION_SUGGESTIONS` | Same file | JSON: `{"whoami": ["Q1", ...], "acme_corporate": ["Q1", ...]}` |

### RAG_QUESTION_SUGGESTIONS Format

```json
{
  "whoami": [
    "What programming languages does the candidate know?",
    "Summarize the candidate's work experience"
  ],
  "acme_corporate": [
    "What products does ACME Corp manufacture?",
    "Describe the L-900 EUV scanner maintenance procedures"
  ]
}
```

Keys must match vector store names returned by `GET /v1/vector_stores`.

## Inspect Page Tabs

The Inspect page (`inspect.py`) has 6 tabs showing LlamaStack distribution state:

| Tab | API Call | Shows |
|-----|----------|-------|
| API Providers | `client.providers.list()` | Registered providers (vLLM, pgvector, etc.) |
| Models | `client.models.list()` | Available models and their providers |
| Vector DBs | `client.vector_dbs.list()` | Vector stores (acme_corporate, whoami) |
| Tool Groups | `client.toolgroups.list()` | MCP tool groups + builtin tools |
| Shields | `client.shields.list()` | Safety shields |
| Scoring | `client.scoring_functions.list()` | Scoring functions for eval |

## Deployment Topology

```yaml
Namespace: private-ai
Deployment: rag-chatbot
  Replicas: 1
  Image: image-registry.openshift-image-registry.svc:5000/private-ai/rag-chatbot:latest
  BuildConfig: rag-chatbot (source: backup/legacy-implementation-2026-06-09/steps/step-07-rag/chatbot/)
  Route: rag-chatbot (edge TLS)

Dependencies:
  - lsd-rag (LlamaStack distribution)
  - nemotron-3-nano-30b-a3b (LLMInferenceService/MaaS)
  - llamastack-postgres (pgvector)
  - guardrails-orchestrator (step-09, optional)
```
