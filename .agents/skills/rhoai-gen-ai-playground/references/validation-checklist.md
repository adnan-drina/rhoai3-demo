# Validation Checklist

Use this checklist before accepting Gen AI studio playground documentation,
runbooks, GitOps changes, or demo scripts.

## Source Alignment

- Product links use the active baseline in `docs/PLATFORM_BASELINE.md`.
- The official gen AI playground source is recorded when the workflow is
  introduced.
- Playground, AI asset endpoints, custom endpoints, multi-model comparison, and
  prompt management are labeled Technology Preview in user-facing material.
- Llama Stack server and provider details are checked with
  `rhoai-llama-stack`.
- Model-serving runtime details are checked with
  `rhoai-model-serving-platform`.
- Dashboard-wide feature flag behavior is checked with
  `rhoai-dashboard-customization`.

## Prerequisite Review

- OpenShift AI is installed on an OpenShift cluster that meets the documented
  version prerequisite.
- Dashboard configuration includes `spec.dashboardConfig.genAiStudio: true`.
- OpenShift AI user and administrator group prerequisites are satisfied when
  groups are used.
- The Llama Stack Operator is enabled through `DataScienceCluster`.
- Required MCP servers are configured before MCP workflows are demonstrated.
- The project exists and the user has access.
- Required project connections exist.
- At least one model is deployed and added as an AI asset endpoint.

## Model And Runtime Review

- The selected model supports tool calling before using RAG or MCP.
- The selected model has enough context length for the intended RAG documents
  and conversation history.
- vLLM runtime arguments are reviewed for tool calling:
  `--enable-auto-tool-choice`, `--tool-call-parser`, and any required
  `--chat-template`.
- Chat template paths use `/opt/app-root/template/` and are not relative.
- Demo model choices are not copied from official examples unless the project
  intentionally chooses them.

## AI Asset Endpoint Review

- AI asset endpoints are scoped to the selected project.
- Project-local model deployments are marked as AI asset endpoints before
  playground testing.
- Custom endpoints are enabled only when required.
- External provider endpoints are enabled only after data egress and security
  posture are documented.
- Endpoint tokens and provider API keys are stored in Secrets and are not
  committed.
- Verify model is used when creating custom endpoints.

## Playground Workflow Review

- Dashboard path is Gen AI studio -> Playground or Gen AI studio -> AI asset
  endpoints.
- Playground creation selects the project containing the model deployment.
- Each selected model is classified as inference or embedding.
- The loaded playground shows the selected model in the Model tab and header.
- Temperature, streaming, and system instructions are recorded when they matter
  to results.
- Multi-model comparison is labeled Technology Preview and requires at least
  two available models.

## RAG Review

- Playground RAG upload is documented as using an inline vector database.
- External or remote vector database support is not claimed for the playground
  upload path.
- Uploaded files match supported types: PDF, DOC, or CSV.
- Upload limits are respected: up to 10 files and 10 MB per file.
- Chunk length, chunk overlap, and delimiter settings are recorded when they
  affect results.
- System instructions explicitly direct use of knowledge search when the model
  otherwise ignores uploaded documents.

## Prompt Management Review

- Prompt management is labeled Technology Preview.
- MLflow availability in the project is confirmed before promising persistent
  prompts.
- Saved prompts are described as project-scoped and versioned.
- Prompt names, versions, and commit messages are captured when used for demo
  evidence.

## MCP Review

- MCP server entries come from the platform-level `gen-ai-aa-mcp-servers`
  `ConfigMap` in `redhat-ods-applications`.
- MCP server data keys are unique and case-sensitive.
- MCP server values are valid JSON.
- The selected model supports tool calling.
- Token authorization behavior is documented as browser-session scoped.
- The demo verifies that the model uses the selected MCP tool.

## Export, Update, And Delete Review

- Exported Python is described as a template, not a runnable script.
- Exported code is checked for the expected model, parameters, RAG files, and
  MCP tools.
- Updating a playground is documented as permanently deleting the inline vector
  database for all project users.
- Deleting a playground is documented as removing the playground for all users
  in the project.

## Optional Read-Only Checks

Run only after following the OpenShift safety guard in `AGENTS.md`:

```bash
oc get odhdashboardconfig -A -o yaml
oc get datasciencecluster -A -o yaml
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o yaml
oc get pods -A | rg 'lsd-genai-playground|predictor'
```

Schema checks:

```bash
oc explain odhdashboardconfig.spec.dashboardConfig
oc explain odhdashboardconfig.spec.genAiStudioConfig
oc explain datasciencecluster.spec.components.llamastackoperator
```

## Fail Conditions

Stop and correct the work if any of these are true:

- The playground is presented as production-supported without Technology
  Preview context.
- External provider endpoints are enabled without documenting that user input,
  RAG context, and MCP tool results can leave the cluster.
- Provider tokens or API keys are committed.
- The playground RAG upload path is described as using an external or remote
  vector database.
- RAG or MCP behavior is promised without checking model tool-calling support
  and runtime arguments.
- Updating a playground omits the inline vector database deletion warning.
- Exported Python is presented as a complete runnable application.
