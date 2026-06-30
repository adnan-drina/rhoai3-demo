# Gen AI Playground Patterns

These examples are review patterns. Verify active CRDs, dashboard schema,
model-serving endpoints, AI asset endpoints, Secrets, and project access before
copying anything into GitOps.

## Enable Gen AI Studio

```yaml
spec:
  dashboardConfig:
    genAiStudio: true
```

Review points:

- Confirm the active `OdhDashboardConfig` schema before authoring.
- Label Gen AI studio playground workflows as Technology Preview.
- Verify the Llama Stack Operator is enabled before demonstrating playground
  RAG or MCP workflows.

## Enable Custom Endpoints

```yaml
spec:
  dashboardConfig:
    aiAssetCustomEndpoints: true
  genAiStudioConfig:
    aiAssetCustomEndpoints:
      externalProviders: true
      clusterDomains: []
```

Review points:

- Keep `externalProviders: false` unless the demo explicitly needs external
  providers and data egress has been approved.
- `clusterDomains` adds internal domains beyond `.svc.cluster.local`.
- Preserve unrelated `OdhDashboardConfig` fields.

## MCP Server ConfigMap Shape

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gen-ai-aa-mcp-servers
  namespace: redhat-ods-applications
data:
  Example-MCP-Server: |
    {
      "url": "https://example.internal/mcp",
      "description": "Example MCP server for reviewed demo workflows."
    }
```

Review points:

- Data keys are case-sensitive and must be unique.
- Data values must be valid JSON.
- Do not include credentials in this ConfigMap.

## Model Runtime Tool-Calling Review

```text
--enable-auto-tool-choice
--tool-call-parser=<parser>
--chat-template=/opt/app-root/template/<template_file>.jinja
```

Review points:

- Confirm the selected model supports tool calling.
- Match parser and chat template to the model family.
- Use absolute template paths from `/opt/app-root/template/`.
- Keep model-serving details in `rhoai-model-serving-platform`.

## Playground RAG Review

```text
Supported upload types: PDF, DOC, CSV
Maximum files: 10
Maximum size per file: 10 MB
Vector database: inline playground vector database
```

Review points:

- Do not claim external vector database support for the playground upload path.
- Record chunk length, overlap, and delimiter values when comparing results.
- If the model ignores uploaded files, adjust system instructions to require
  knowledge search for questions about those files.

## Custom Endpoint Review

```text
Model type: Inference or Embedding
Model ID: provider-exact model id
Display name: project-facing name
Embedding dimension: required for embedding models
URL: internal service URL or external provider URL
Token: stored as a Kubernetes Secret
Use case: optional project context
```

Review points:

- Use internal cluster URLs for models in another namespace.
- External provider endpoints can send user input, RAG context, and MCP tool
  results outside the cluster.
- Use Verify model before relying on the endpoint in a demo.

## MaaS-Backed Playground Provider Pattern

Use this as a review pattern for a dashboard-created project playground that
must consume MaaS-published models through Llama Stack. Verify the active
`LlamaStackDistribution` schema and generated config before applying changes.
The `maas-vllm-inference-*` provider numbers are dashboard-generated examples;
preserve the provider ids assigned by the active playground.

```yaml
providers:
  inference:
    - provider_id: maas-vllm-inference-1
      provider_type: remote::openai
      config:
        api_key: ${env.VLLM_API_TOKEN_1:=fake}
        base_url: https://maas.<apps-domain>/models-as-a-service/gpt-5-4-mini/v1
        network:
          tls:
            verify: ${env.VLLM_TLS_VERIFY:=true}
    - provider_id: maas-vllm-inference-2
      provider_type: remote::vllm
      config:
        api_token: ${env.VLLM_API_TOKEN_2:=fake}
        base_url: https://maas.<apps-domain>/models-as-a-service/nemotron-3-nano-30b-a3b/v1
        max_tokens: ${env.VLLM_MAX_TOKENS:=4096}
        tls_verify: ${env.VLLM_TLS_VERIFY:=true}
models:
  - provider_id: maas-vllm-inference-1
    model_id: gpt-5-4-mini
    provider_model_id: gpt-5.4-mini
    model_type: llm
  - provider_id: maas-vllm-inference-2
    model_id: nemotron-3-nano-30b-a3b
    provider_model_id: nemotron-3-nano-30b-a3b
    model_type: llm
```

Review points:

- Replace placeholder app domain values with the live MaaS Gateway host.
- The token environment variables must be Secret-backed in the
  `LlamaStackDistribution` and generated deployment.
- Keep the external GPT model on `remote::openai` even though the base URL is a
  MaaS URL. This avoids the vLLM provider's `max_tokens` payload shape.
- Use Llama Stack `/v1/models` to discover the model IDs used by
  `/v1/responses`; they can include the provider ID prefix.

## Troubleshooting Pointers

```bash
oc logs <playground-pod> -n <namespace>
oc logs <model-name>-predictor-<id> -n <namespace>
```

Review points:

- Thinking indefinitely often points to context length or OOM constraints.
- `401 Unauthorized` from a MaaS route usually means the Playground Llama
  Stack deployment still has a placeholder token or stale API key.
- `Unsupported parameter: max_tokens` on external GPT models indicates the
  wrong Llama Stack provider type for an OpenAI-compatible model route.
- Missing MCP tab content points to missing platform-level MCP configuration.
- Failed MCP tool calls usually require model card and vLLM runtime argument
  review.
