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
  Do NOT use for live deployment issues (use env-troubleshoot), model serving
  infrastructure changes (use env-deploy-and-evaluate plus the relevant RHOAI
  Platform skill), or evaluation workflows (use rhoai-model-evaluation).
---

# Chatbot Customization

Structured workflow for modifying the active-baseline RHOAI RAG chatbot — a Streamlit app
backed by LlamaStack with agent/direct modes, guardrails integration, and MCP
tool support.

## Reimplementation Status

The active implementation is being rewritten. No active chatbot code, Step 07
GitOps content, or Step 07 README exists yet. Treat the file paths and command
examples in this skill as legacy reference material for rebuilding the chatbot,
not as active-project instructions.

Do not run or modify scripts from `backup/legacy-implementation-2026-06-09/`
unless the user explicitly asks to restore or inspect the legacy implementation.

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
  Guardrails Orchestrator (step-09, port 8032)
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
| `steps/step-07-rag/chatbot/llama_stack_ui/distribution/ui/page/playground/chat.py` | System prompts, sidebar config, suggested questions display, mode switching |
| `steps/step-07-rag/chatbot/llama_stack_ui/distribution/ui/page/playground/agent.py` | tool_choice, guardrails integration, Responses API streaming |
| `steps/step-07-rag/chatbot/llama_stack_ui/distribution/ui/page/playground/direct.py` | Direct mode RAG, completions API |
| `steps/step-07-rag/chatbot/llama_stack_ui/distribution/ui/modules/guardrails.py` | Input/output safety checks |
| `steps/step-07-rag/chatbot/llama_stack_ui/distribution/ui/modules/utils.py` | Question suggestions parsing, vector DB helpers |
| `gitops/step-07-rag/base/chatbot/chatbot.yaml` | Env vars: LLAMA_STACK_URL, INFERENCE_MODEL, RAG_QUESTION_SUGGESTIONS |
| `steps/step-07-rag/README.md` | Design decisions (must update with code changes) |

## Instructions

### Read Before You Write

1. Read `steps/step-07-rag/README.md` — design decisions section
2. If doing prompt engineering, also read `references/prompt-engineering.md`
3. If touching the architecture, also read `references/chatbot-architecture.md`

### Common Workflows

#### Change the System Prompt

1. Edit `chat.py` around line 288-308 (the `default_system_prompt` logic)
2. Direct mode prompt: ~line 292-295
3. Agent mode prompt: ~line 298-307
4. Test the change via the chatbot UI (sidebar shows the editable prompt)
5. Update `steps/step-07-rag/README.md` design decisions

**Prompt engineering constraints for Granite 8B:**
- Verbose prompts cause narration instead of action
- Negative instructions ("do NOT ...") are ignored — use positive framing
- Include explicit tool hints ("use execute_sql on the acme_pod_equipment_map table")
- Keep retry instructions short ("If a tool call fails, retry with corrected parameters")

#### Change Suggested Questions

1. Edit `RAG_QUESTION_SUGGESTIONS` in `gitops/step-07-rag/base/chatbot/chatbot.yaml`
2. Format: JSON object keyed by vector store name (`whoami`, `acme_corporate`)
3. ArgoCD sync applies the change
4. Restart deployment: `oc rollout restart deployment/rag-chatbot -n private-ai`
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
- Requires step-09 Guardrails Orchestrator deployed
- Input checks: HAP + Prompt Injection
- Output checks: HAP + PII regex (email, phone, credit card, LinkedIn, GitHub)
- Implementation: `guardrails.py` → called from `agent.py`

### Build & Deploy Cycle

For rebuild/restart guidance, container image standards, and "do not change
without full testing" constraints, read
`references/development-constraints.md`. Key distinction: code changes require
`oc start-build` + `oc rollout restart`; env-only changes need only `oc rollout restart`.

### Validation

After any change:
1. Open the chatbot route: `oc get route rag-chatbot -n private-ai -o jsonpath='{.spec.host}'`
2. Test in both Direct and Agent modes
3. Verify suggested questions appear for each vector store
4. If guardrails changed, test with PII content

For detailed architecture, component map, and prompt engineering patterns, read the references:
- `references/chatbot-architecture.md`
- `references/development-constraints.md`
- `references/prompt-engineering.md`
