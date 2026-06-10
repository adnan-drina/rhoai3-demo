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

## Troubleshooting Pointers

```bash
oc logs <playground-pod> -n <namespace>
oc logs <model-name>-predictor-<id> -n <namespace>
```

Review points:

- Thinking indefinitely often points to context length or OOM constraints.
- Missing MCP tab content points to missing platform-level MCP configuration.
- Failed MCP tool calls usually require model card and vLLM runtime argument
  review.
