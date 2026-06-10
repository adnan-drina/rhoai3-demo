# Prompt Engineering Reference

## Table of Contents

- [Private Model Behavioral Traits](#private-model-behavioral-traits)
- [Current System Prompts](#current-system-prompts)
- [Tested Patterns](#tested-patterns)
- [Anti-Patterns](#anti-patterns)
- [Parameter Tuning](#parameter-tuning)

## Private Model Behavioral Traits

These traits came from earlier private-model testing and must be revalidated
against `nemotron-3-nano-30b-a3b` during the reimplementation. They affect
prompt design choices:

| Trait | Impact | Mitigation |
|-------|--------|------------|
| Ignores negative instructions | "Do NOT narrate" → still narrates | Use positive framing: "Answer concisely using tool results" |
| Verbose prompts cause narration | Long system prompt → model explains actions instead of doing them | Keep prompts short and action-oriented |
| Single-tool preference | When 31 tools available, picks wrong one | Scope tools per task; use `tool_choice="required"` |
| Needs explicit tool hints | Won't discover `execute_sql` on its own | Add "use execute_sql on the acme_pod_equipment_map table" |
| Retry on failure works | "If a tool call fails, retry" → actually retries | Include retry instruction (but keep it short) |
| Citation format works | Model follows citation template | Include "Sources:\n- filename.md" format |

## Current System Prompts

### Direct Mode (completions)

```
You are a helpful AI assistant. Answer questions using the provided context.
If the context doesn't contain enough information, say so clearly.
```

Context is injected as a user message:
```
CONTEXT:
{retrieved_chunks}

QUERY:
{user_question}
```

### Agent Mode (Responses API)

```
You are a helpful assistant. You MUST use your tools to answer questions.
Base your answer on the tool results, not prior knowledge.
If a tool call fails, retry with corrected parameters.
For equipment database lookups, use execute_sql on the acme_pod_equipment_map table
(columns: pod_name, equipment_id, product_name).
For pod and cluster queries, use the OpenShift tools.
Answer directly and concisely.
Your response format: provide only the answer. Do not add a Sources section.
```

## Tested Patterns

### What works

| Pattern | Example | Why it works |
|---------|---------|--------------|
| Positive action commands | "You MUST use your tools" | Keeps tool-use intent explicit |
| Explicit tool hints | "use execute_sql on acme_pod_equipment_map" | Removes ambiguity about which tool to call |
| Short retry instruction | "If a tool call fails, retry with corrected parameters" | Model actually retries; long explanation makes it narrate |
| Citation template | "Sources:\n- filename.md" | Model follows formatting templates |
| Grounding instruction | "Base your answer on the tool results, not prior knowledge" | Reduces hallucination from pre-training data |

### What doesn't work

| Pattern | Example | What happens instead |
|---------|---------|---------------------|
| Negative instructions | "Do NOT explain your reasoning" | Model explains its reasoning |
| Long conditional logic | "If tool A fails, try tool B, unless..." | Model narrates the conditional instead of executing |
| Multi-paragraph prompts | 200+ word system prompts | Model starts explaining the prompt instead of following it |
| Implicit tool discovery | Omitting tool hints | Model calls wrong tools or hallucinates parameters |

## Anti-Patterns

1. **Over-scoping tools**: Making all MCP tools available in a single session
   can cause the model to pick wrong tools. Scope tools per use case.

2. **Temperature too high**: For tool-calling tasks, keep temperature low (0.1-0.3). Higher values cause the model to vary tool parameters randomly.

3. **max_output_tokens too large**: With MCP/file_search consuming 12-16K of the 16K context window, setting max_output_tokens > 512 causes vLLM to reject the request.

4. **Changing tool_choice to "auto"**: The model frequently skips tools when set to "auto". Keep it "required" for agent mode.

## Parameter Tuning

| Parameter | Location | Default | Safe Range | Notes |
|-----------|----------|---------|------------|-------|
| temperature | chat.py sidebar | 0.1 | 0.0-0.3 | Low for tool-calling reliability |
| top_p | chat.py sidebar | 0.9 | 0.8-1.0 | Standard nucleus sampling |
| max_output_tokens | chat.py sidebar | 512 | 256-1024 | Constrained by 16K context window |
| max_infer_iters | chat.py sidebar | 20 | 10-30 | MCP chains need 4-5 iterations minimum |
| tool_choice | agent.py | "required" | "required" | Don't change to "auto" without testing |

### Context Window Budget

```
System prompt:         ~200 tokens
Conversation history:  ~2000 tokens (varies)
file_search results:   ~4000-8000 tokens
MCP tool results:      ~2000-6000 tokens
─────────────────────────────────────
Available for output:  ~500-2000 tokens
```

This is why `max_output_tokens=512` is the safe default.
