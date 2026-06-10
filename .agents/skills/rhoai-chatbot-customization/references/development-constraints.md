# Chatbot Development Constraints

Use these constraints when changing `steps/step-07-rag/chatbot/**`.

## Architecture Constraints

The chatbot is a Streamlit app (`rag-chatbot`) that talks to LlamaStack
(`lsd-rag`). It has Direct and Agent modes with different APIs and prompt
patterns. Changes to one mode must not break the other.

## Agent Mode Defaults

- `agent.py` sets `tool_choice="required"` when tools are present. Do not
  change this without testing all agentic demo scenarios against
  `nemotron-3-nano-30b-a3b`.
- `max_output_tokens=512` protects the 16K context window from overflow when
  MCP and `file_search` results consume 12-16K tokens. Increase only with a
  matching model `max-model-len` change.
- Keep the agent system prompt action-oriented and short. Prefer positive
  framing such as "You MUST use tools".

## Build And Restart

Code changes require a chatbot BuildConfig rebuild, deployment restart, and
rollout status check in `private-ai`. Env-only changes, such as
`RAG_QUESTION_SUGGESTIONS`, require only a deployment restart. Before suggesting
or running live cluster commands, follow the OpenShift safety guard in
`AGENTS.md`.

Always test both Direct and Agent modes after changes.

## Container Image Standards

The chatbot `Containerfile` should stay aligned with OpenShift image guidance:

- Use a Red Hat base image such as `registry.access.redhat.com/ubi9/python-312:latest`.
- Run as `USER 1001` for OpenShift random UID compatibility.
- Keep a single foreground process: `streamlit run`.
- Do not use `hostPath`, privileged capabilities, or Docker Hub base images.
- Group `RUN` commands to reduce layers.
- Pin package versions in install commands when practical.

## Do Not Change Without Full Testing

- `tool_choice` in `agent.py`
- Guardrails orchestrator endpoint or API shape in `guardrails.py`
- `RAG_QUESTION_SUGGESTIONS` JSON keys; they must match vector store names
- The `LlamaStackApi` singleton pattern in `api.py`

## References

- Llama Stack platform skill: `.agents/skills/rhoai-llama-stack/SKILL.md`
- Current baseline Llama Stack docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_llama_stack/index
- Current baseline Guardrails docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/ai_safety_with_guardrails/
- Current OCP image guidance: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/images/creating-images
