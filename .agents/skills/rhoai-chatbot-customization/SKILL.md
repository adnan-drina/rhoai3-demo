---
name: rhoai-chatbot-customization
metadata:
  author: rhoai3-demo
  version: 1.1.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "RHOAI Platform"
description: >
  Guide changes to the Stage 230 private RAG Streamlit chatbot. Use when the
  user asks to customize the chatbot, update direct-RAG prompts, change
  suggested questions, switch between RAG and model-only answer behavior, fix
  Llama Stack client compatibility, inspect RAG retrieval behavior, or prepare
  the app for later MCP and guardrails stages.
  The active app is a repo-owned implementation under
  stage-230-private-data-rag/chatbot/rhoai_rag_chatbot, not a copied
  quickstart UI. Do NOT use for Llama Stack server/provider/vector-store
  configuration (use rhoai-llama-stack), product NeMo/FMS guardrails resources
  (use rhoai-guardrails-safety), product Gen AI studio workflows (use
  rhoai-gen-ai-playground), or live troubleshooting without env-troubleshoot.
---

# Chatbot Customization

Structured workflow for modifying the active Stage 230 private RAG chatbot. The
chatbot is a small Streamlit app backed by the Stage 230
`LlamaStackDistribution`. It implements direct RAG over the RHOAI
product-document vector store, model-only comparison against the same governed
model, and explicit,
disabled-by-default integration boundaries for future MCP tool calling and
product guardrails.

Use `rhoai-llama-stack` for the Llama Stack platform beneath this chatbot:
`LlamaStackDistribution`, providers, vector stores, OpenAI-compatible APIs,
OAuth, ABAC, CA trust, and HA/autoscaling.

Use `rhoai-guardrails-safety` for official NeMo Guardrails, FMS Guardrails,
TrustyAI guardrails CRs, detector services, guardrails endpoints, and API
payload validation. This skill only covers how the chatbot calls or presents
those controls after the product resources exist.

## Active Implementation Status

- source: `stage-230-private-data-rag/chatbot/rhoai_rag_chatbot/`
- build resources: `gitops/stage-230-private-data-rag/app/base/build.yaml`
  in `enterprise-rag-build`
- deployment resources: `gitops/stage-230-private-data-rag/app/base/`
- validation: `stage-230-private-data-rag/validate.sh`

Legacy Step 07 chatbot paths under
`backup/legacy-implementation-2026-06-09/steps/step-07-rag/chatbot/` and the
main-branch Step 07 app are reference material only. Do not copy them blindly or
run backup scripts unless the user explicitly asks for legacy restoration.

## Architecture At A Glance

```text
private-rag-chatbot (Streamlit)
  app.py                  UI: Chat and Inspect tabs
  config.py               environment-backed app contract
  llama_stack_gateway.py  models, vector stores, search, rerank, chat completions
  prompts.py              RAG and model-only prompt and context formatting
  mcp.py                  future MCP connector discovery/tool contract
  guardrails.py           future guardrails decision boundary

Llama Stack service: lsd-enterprise-rag-service.enterprise-rag.svc:8321
Default vector store: stage230-rhoai-34-product-docs-kfp, backed by PostgreSQL + pgvector
Generation model: nemotron-3-nano-30b-a3b through Stage 220 MaaS and Stage 230 Llama Stack
Reranker: vllm-reranker/qwen3-reranker via /v1alpha/inference/rerank (enabled by default)
```

The chatbot uses a simplified RAG path compared to the AG News acceptance
scripts: it searches the vector store and optionally reranks, but does not
perform query-time LLM metadata extraction or category-based filtering. The
full metadata-aware pipeline is exercised by
`scripts/agnews_rag_acceptance.py` and validated by `validate.sh`.

## When To Use

- Changing the direct-RAG system prompt, model-only prompt, or context formatting
- Adding, removing, or editing suggested questions
- Fixing model or vector-store selection behavior
- Fixing `llama-stack-client` compatibility after a RHOAI/Llama Stack update
- Exposing additional Llama Stack runtime state in the Inspect tab
- Preparing, but not yet enabling, MCP or guardrails UI/adapter changes
- Testing chatbot behavior after RAG ingestion or Llama Stack changes

## Key Files

| File | What to edit |
|------|-------------|
| `stage-230-private-data-rag/chatbot/rhoai_rag_chatbot/app.py` | Streamlit UI, chat flow, Inspect tab, state handling |
| `stage-230-private-data-rag/chatbot/rhoai_rag_chatbot/prompts.py` | RAG and model-only system prompts and context message format |
| `stage-230-private-data-rag/chatbot/rhoai_rag_chatbot/llama_stack_gateway.py` | Llama Stack client adapter, model list, vector search, completions |
| `stage-230-private-data-rag/chatbot/rhoai_rag_chatbot/config.py` | Environment variables and defaults |
| `stage-230-private-data-rag/chatbot/rhoai_rag_chatbot/mcp.py` | Future MCP connector discovery and Responses API tool contract |
| `stage-230-private-data-rag/chatbot/rhoai_rag_chatbot/guardrails.py` | Future guardrails decision boundary |
| `stage-230-private-data-rag/chatbot/pyproject.toml` | Pinned `llama-stack-client` dependency |
| `gitops/stage-230-private-data-rag/app/base/configmap-chatbot.yaml` | Chatbot feature flags and suggested questions |
| `gitops/stage-230-private-data-rag/app/base/deployment-chatbot.yaml` | Image, endpoint, probes, resources, env wiring |
| `gitops/stage-230-private-data-rag/dashboard/base/odhapplication-rag-chatbot.yaml` | OpenShift AI dashboard application tile pointing at the chatbot Route |

## Instructions

### Read Before You Write

1. Read `stage-230-private-data-rag/README.md` and
   `stage-230-private-data-rag/PLAN.md`.
2. If changing prompts or response style, read `references/prompt-engineering.md`.
3. If touching code architecture, read `references/chatbot-architecture.md`.
4. If changing `llama-stack-client`, verify the deployed Llama Stack server
   version and run the Stage 230 validator. A stale client fails with HTTP 426
   `Client version ... is not compatible with server version ...`.

### Change Answer Behavior

1. Edit `prompts.py` for RAG prompt, model-only prompt, or context formatting.
2. Edit `llama_stack_gateway.py` only when Llama Stack response shape or API use
   changes.
3. In RAG mode, keep answers grounded in retrieved context. If no context is
   retrieved, the answer should say so rather than inventing private facts.
4. In model-only mode, skip vector-store search and do not claim private
   document grounding or source citations.
5. Validate by asking the same whoami question in both `RAG` and `Model only`
   modes.

### Change Suggested Questions

The active Stage 230 app intentionally does not render large suggested-question
buttons on the main chat page. If a later stage reintroduces suggestions:

1. Edit `RAG_QUESTION_SUGGESTIONS` in
   `gitops/stage-230-private-data-rag/app/base/configmap-chatbot.yaml`.
2. Keys must match vector store names or ids, such as
   `stage230-rhoai-34-product-docs-kfp`.
3. Argo CD applies the ConfigMap. Restart the deployment if the running pod does
   not pick up the new environment:

   ```bash
   oc rollout restart deployment/private-rag-chatbot -n enterprise-rag
   ```

### Prepare MCP

Stage 230 does not enable tool-calling by default. Future MCP work should:

1. Use `rhoai-llama-stack` to register MCP connectors in Llama Stack.
2. Keep connector discovery in `mcp.py`.
3. Enable the feature with `MCP_ENABLED=true` only after the registered
   connector is visible in the Inspect tab.
4. Add an agent/Responses API path separately from direct RAG, keeping
   `tool_choice` and max-token defaults aligned with `references/prompt-engineering.md`.

### Prepare Guardrails

Stage 230 does not deploy safety resources. Future guardrails work should:

1. Use `rhoai-guardrails-safety` to choose NeMo or FMS product resources and
   validate official API payloads.
2. Keep the chatbot integration boundary in `guardrails.py`.
3. Enable the feature with `GUARDRAILS_ENABLED=true` and
   `GUARDRAILS_ENDPOINT=<reviewed endpoint>` only after the product endpoint is
   deployed and validated and `guardrails.py` implements the reviewed request
   payload. The Stage 230 adapter fails closed if the flag is enabled before
   that implementation exists.
4. Treat guardrails as policy controls with known limitations, not proof of
   compliance or risk-free behavior.

### Build And Deploy Cycle

Code changes require `stage-230-private-data-rag/deploy.sh` so OpenShift Builds
rebuilds the image from `stage-230-private-data-rag/chatbot/` using the
GitOps-managed binary `BuildConfig` in `enterprise-rag-build`. Keep build
resources out of the Kueue-managed `enterprise-rag` runtime namespace; build
pods are infrastructure, not AI workloads.
Env-only changes may need only an Argo CD sync plus a deployment restart.

Do not switch the active RHOAI 3.4 demo back to
`quay.io/rh-ai-quickstart/llamastack-dist-ui:0.2.45` without retesting client
compatibility. That image pins `llama-stack-client==0.6.0`; Stage 230 uses the
`0.7.x` client line for the observed RHOAI 3.4 Llama Stack server.

### Validation

After any code or config change:

1. Run `python3 -m compileall -q stage-230-private-data-rag/chatbot`.
2. Run `./stage-230-private-data-rag/validate.sh` against the guarded target
   cluster after deployment.
3. Test the chatbot route:

   ```bash
   oc get route private-rag-chatbot -n enterprise-rag -o jsonpath='{.spec.host}'
   ```

4. Ask a whoami suggested question and confirm retrieved context appears.
5. Check the Inspect tab for model, vector-store, MCP, and guardrails state.

For detailed architecture, container constraints, and prompt patterns, read:

- `references/chatbot-architecture.md`
- `references/development-constraints.md`
- `references/prompt-engineering.md`
