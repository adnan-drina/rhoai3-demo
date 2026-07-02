# Chatbot Development Constraints

Use these constraints when changing
`stage-230-private-data-rag/chatbot/rhoai_rag_chatbot/**`.

## Architecture Constraints

The active chatbot is a Streamlit app that talks to the Stage 230
`lsd-enterprise-rag` Llama Stack service. Stage 230 implements direct RAG only:
search vector store, inject context, call chat completions. MCP and guardrails
are explicit extension points but are not active product capabilities in this
stage.

Keep these boundaries:

- `app.py` owns UI and chat orchestration.
- `llama_stack_gateway.py` owns Llama Stack API shape handling.
- `prompts.py` owns direct-RAG prompt text.
- `mcp.py` owns future MCP connector/tool conversion.
- `guardrails.py` owns future safety decisions.

## Container Image Standards

The chatbot `Containerfile` should stay aligned with OpenShift image guidance:

- Use a Red Hat base image such as `registry.access.redhat.com/ubi9/python-312:latest`.
- Run as `USER 1001` for OpenShift random UID compatibility.
- Keep a single foreground process: `streamlit run`.
- Do not use `hostPath`, privileged capabilities, or Docker Hub base images.
- Pin `llama-stack-client` to a version compatible with the deployed RHOAI
  Llama Stack server.

## Build And Restart

Code changes require the Stage 230 OpenShift binary build:

```bash
./stage-230-private-data-rag/deploy.sh
```

Env-only changes, such as `RAG_QUESTION_SUGGESTIONS`, require an Argo CD sync
and may require:

```bash
oc rollout restart deployment/private-rag-chatbot -n enterprise-rag
```

Before suggesting or running live cluster commands, follow the OpenShift safety
guard in `AGENTS.md`.

## Do Not Change Without Full Testing

- `llama-stack-client` version pin in `pyproject.toml`
- model id defaults in `INFERENCE_MODEL`
- context window controls: `RAG_MAX_CONTEXT_CHARS` and `RAG_MAX_OUTPUT_TOKENS`
- `MCP_ENABLED` or `GUARDRAILS_ENABLED`, unless the backing product resources
  have been deployed and validated
- `LLAMA_STACK_ENDPOINT` base URL shape; `LlamaStackClient` expects no `/v1`

## References

- Llama Stack platform skill: `.agents/skills/rhoai-llama-stack/SKILL.md`
- Guardrails skill: `.agents/skills/rhoai-guardrails-safety/SKILL.md`
- Current baseline Llama Stack docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_llama_stack/index
- Current baseline Guardrails docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/enabling_ai_safety_with_guardrails/index
- Current OCP image guidance: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/images/creating-images
