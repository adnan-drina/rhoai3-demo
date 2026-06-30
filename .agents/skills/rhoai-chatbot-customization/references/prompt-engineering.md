# Prompt Engineering Reference

## Active Prompts

The active Stage 230 chatbot prompt lives in
`stage-230-private-data-rag/chatbot/rhoai_rag_chatbot/prompts.py`.

RAG mode uses:

```text
You are a helpful enterprise AI assistant. Answer questions using the provided
private context. If the context does not contain enough information, say so
clearly. Keep the answer concise and include source names when context is
available.
```

Model-only mode uses:

```text
You are a helpful enterprise AI assistant. Answer questions directly from the
model's general capabilities. Do not claim to have used private documents,
retrieved context, or source citations.
```

RAG context is injected as:

```text
Use this private RAG context to answer the question.

CONTEXT:
[Source: ...]
...

QUESTION:
...
```

## Private Model Traits To Revalidate

These traits came from earlier private-model testing and should be revalidated
when changing prompts or adding agent/tool paths:

| Trait | Impact | Mitigation |
|-------|--------|------------|
| Ignores negative instructions | Negative prompts can be repeated or ignored | Prefer positive commands |
| Verbose prompts cause narration | Long prompts can make the model explain the task | Keep prompts short and direct |
| Single-tool preference | Too many tools can produce wrong calls | Scope future MCP tools per use case |
| Needs explicit tool hints | Tool names may not be discovered reliably | Add concise tool hints in future agent prompts |
| Retry on failure works | Short retry prompts can help tool flows | Use concise retry instruction only |

## RAG And Model-Only Guidelines

- Keep the system prompt short.
- Keep retrieval context bounded with `RAG_MAX_CONTEXT_CHARS`.
- Keep `RAG_MAX_OUTPUT_TOKENS=512` unless model-serving context limits are
  revalidated.
- Ask for source names when context is available, but do not claim chunk-level
  citation precision.
- If no context is retrieved, prefer a clear "not enough private context"
  answer over a general-knowledge answer.
- In model-only mode, skip vector-store search and do not claim private
  document grounding or citations.

## Future Agent/MCP Guidelines

When a later stage enables MCP or Responses API tool calling:

- Use positive action commands such as "Use the selected tools to answer."
- Scope tool lists tightly to the task.
- Keep `tool_choice="required"` for workflows where the demo promise depends on
  using tools.
- Keep temperature low, typically `0.1` to `0.3`.
- Budget context for file-search and MCP output before increasing completion
  tokens.
