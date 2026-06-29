---
name: rhoai-chatbot-customization
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "RHOAI Platform"
description: >
  Guide RHOAI chatbot UI and behavior changes once the active chatbot exists;
  during the reimplementation, use this skill to rebuild chatbot requirements
  from legacy Step 07 references. Covers system prompts, guardrails toggle,
  suggested questions, tool_choice, Inspect page tabs, and prompt engineering
  for the Llama Stack RAG application.
  Use when the user asks to customize the chatbot, update the system prompt,
  change suggested questions, modify guardrails behavior, adjust tool_choice,
  tweak agent parameters (max_infer_iters, max_output_tokens), or fix chatbot
  UI issues. Also use when the user reports the chatbot is not using tools,
  giving truncated answers, or behaving unexpectedly in agent mode.
  Do NOT use for Llama Stack server, provider, vector store, RAG platform,
  OAuth, ABAC, CA, or HA configuration (use rhoai-llama-stack), live deployment
  issues (use env-troubleshoot), model serving infrastructure changes (use
  env-deploy-and-evaluate plus the relevant RHOAI Platform skill), product Gen
  AI studio playground workflows (use rhoai-gen-ai-playground), official
  NeMo/FMS Guardrails product configuration (use rhoai-guardrails-safety), or
  evaluation workflows (use rhoai-model-evaluation).
---

# Chatbot Customization

Structured workflow for modifying the active-baseline RHOAI RAG chatbot — a Streamlit app
backed by LlamaStack with agent/direct modes, guardrails integration, and MCP
tool support.

Use `rhoai-llama-stack` for the Llama Stack platform beneath this chatbot:
`LlamaStackDistribution`, providers, vector stores, OpenAI-compatible APIs,
OAuth, ABAC, CA trust, and HA/autoscaling.

Use `rhoai-guardrails-safety` for official NeMo Guardrails, FMS Guardrails,
TrustyAI guardrails CRs, detector services, and guardrails endpoints. This
skill only covers how the custom chatbot UI calls or presents those controls.

## Active Implementation Status

The active chatbot implementation lives in Stage 230:

- source: `stage-230-private-data-rag/chatbot/`
- build resources: `gitops/stage-230-private-data-rag/app/build/`
- deployment resources: `gitops/stage-230-private-data-rag/app/base/`
- validation: `stage-230-private-data-rag/validate.sh`

Legacy Step 07 chatbot paths under
`backup/legacy-implementation-2026-06-09/steps/step-07-rag/chatbot/` remain
reference material only. Do not run or modify backup scripts unless the user
explicitly asks to restore or inspect the legacy implementation.

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────┐
│ rag-chatbot (Streamlit)                                         │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────────────┐│
│  │ Direct mode │  │ Agent mode │  │ Inspect page               ││
│  │ completions │  │ Responses  │  │ Providers│Models│ToolGroups││
│  │ manual RAG  │  │ tool_choice│  │ VectorDBs│Shields│Scoring  ││
│  └──────┬─────┘  └─────┬──────┘  └────────────────────────────┘│
│         └───────┬───────┘                                       │
│           LlamaStack API (lsd-rag)                              │
│           ┌──────────┬──────────────┬────────────┐              │
│           │ pgvector │ vLLM models  │ MCP tools  │              │
│           └──────────┴──────────────┴────────────┘              │
└─────────────────────────────────────────────────────────────────┘
         │ (optional)
         ▼
  Legacy Guardrails Orchestrator (step-09 reference, port 8032)
```

## When to Use

- Changing the system prompt for direct or agent mode
- Adding, removing, or editing suggested questions
- Toggling or configuring guardrails (HAP, PII, prompt injection)
- Adjusting `tool_choice`, `max_infer_iters`, or `max_output_tokens`
- Fixing chatbot behavior (not using tools, truncated output, wrong mode)
- Adding new Inspect page tabs or modifying existing ones
- Prompt engineering iterations

## Key Files

| File | What to edit |
|------|-------------|
| `stage-230-private-data-rag/chatbot/llama_stack_ui/distribution/ui/page/playground/chat.py` | System prompts, sidebar config, suggested questions display, mode switching |
| `stage-230-private-data-rag/chatbot/llama_stack_ui/distribution/ui/page/playground/agent.py` | tool_choice, guardrails integration, Responses API streaming |
| `stage-230-private-data-rag/chatbot/llama_stack_ui/distribution/ui/page/playground/direct.py` | Direct mode RAG, completions API |
| `stage-230-private-data-rag/chatbot/llama_stack_ui/distribution/ui/modules/guardrails.py` | Input/output safety checks |
| `stage-230-private-data-rag/chatbot/llama_stack_ui/distribution/ui/modules/utils.py` | Question suggestions parsing, vector DB helpers |
| `stage-230-private-data-rag/chatbot/pyproject.toml` | Llama Stack client dependency pin; must stay compatible with the deployed RHOAI Llama Stack server |
| `gitops/stage-230-private-data-rag/app/base/configmap-chatbot.yaml` | Env vars such as `RAG_QUESTION_SUGGESTIONS` |
| `gitops/stage-230-private-data-rag/app/base/deployment-chatbot.yaml` | Env vars such as `LLAMA_STACK_ENDPOINT`, image reference, probes, resources |
| `stage-230-private-data-rag/README.md` | Design decisions (must update with code changes) |

## Instructions

### Read Before You Write

1. Read `stage-230-private-data-rag/README.md` and
   `stage-230-private-data-rag/PLAN.md`.
2. If doing prompt engineering, also read `references/prompt-engineering.md`
3. If touching the architecture, also read `references/chatbot-architecture.md`
4. If changing `llama-stack-client`, verify the deployed Llama Stack server
   version and run the Stage 230 validator. A stale client fails with HTTP 426
   `Client version ... is not compatible with server version ...`.

### Common Workflows

#### Change the System Prompt

1. Edit `chat.py` around line 288-308 (the `default_system_prompt` logic)
2. Direct mode prompt: ~line 292-295
3. Agent mode prompt: ~line 298-307
4. Test the change via the chatbot UI (sidebar shows the editable prompt)
5. Update `backup/legacy-implementation-2026-06-09/steps/step-07-rag/README.md` design decisions

**Prompt engineering constraints for the current private model path:**
- Verbose prompts cause narration instead of action
- Prefer positive framing over long lists of negative instructions
- Include explicit tool hints ("use execute_sql on the acme_pod_equipment_map table")
- Keep retry instructions short ("If a tool call fails, retry with corrected parameters")

#### Change Suggested Questions

1. Edit `RAG_QUESTION_SUGGESTIONS` in
   `gitops/stage-230-private-data-rag/app/base/configmap-chatbot.yaml`
2. Format: JSON object keyed by vector store name (`whoami`, `acme_corporate`)
3. ArgoCD sync applies the change
4. Restart deployment: `oc rollout restart deployment/private-rag-chatbot -n enterprise-rag`
5. No rebuild needed — env-var-only change

#### Adjust Agent Parameters

| Parameter | Location | Default | Impact |
|-----------|----------|---------|--------|
| `tool_choice` | `agent.py` ~line 391 | `"required"` | Forces tool use every inference step |
| `max_infer_iters` | `chat.py` sidebar | `20` | Max tool-call rounds per turn |
| `max_output_tokens` | `chat.py` sidebar | `512` | Prevents context overflow with large tool results |

- `max_output_tokens=512` exists because MCP/file_search can consume 12-16K of the 16K context window; larger values cause vLLM to error
- `max_infer_iters=20` exists because MCP chains need 4-5 iterations; the original default of 10 caused mid-chain stops

#### Toggle Guardrails

Guardrails are only available in Agent mode (not Direct mode).
- Toggle is in `chat.py` sidebar (~line 243-259)
- Legacy references require the step-09 Guardrails Orchestrator; new product
  guardrails work should be checked with `rhoai-guardrails-safety`
- Input checks: HAP + Prompt Injection
- Output checks: HAP + PII regex (email, phone, credit card, LinkedIn, GitHub)
- Implementation: `guardrails.py` → called from `agent.py`

### Build & Deploy Cycle

For rebuild/restart guidance, container image standards, and "do not change
without full testing" constraints, read
`references/development-constraints.md`. Key distinction: code changes require
`stage-230-private-data-rag/deploy.sh` to run the OpenShift binary build from
`stage-230-private-data-rag/chatbot/` and roll the deployment; env-only changes
need only `oc rollout restart`.

Do not switch the active RHOAI 3.4 demo back to
`quay.io/rh-ai-quickstart/llamastack-dist-ui:0.2.45` without retesting client
compatibility. That image pins `llama-stack-client==0.6.0`; the Stage 230
server has been observed at `llama-stack=0.7.1+rhaiv.1` and rejects the 0.6
client with HTTP 426.

### Validation

After any change:
1. Open the chatbot route: `oc get route private-rag-chatbot -n enterprise-rag -o jsonpath='{.spec.host}'`
2. Test in both Direct and Agent modes
3. Verify suggested questions appear for each vector store
4. If guardrails changed, test with PII content
5. Run `./stage-230-private-data-rag/validate.sh` and confirm the chatbot
   Llama Stack client compatibility check passes.

For detailed architecture, component map, and prompt engineering patterns, read the references:
- `references/chatbot-architecture.md`
- `references/development-constraints.md`
- `references/prompt-engineering.md`
