# Labels And Annotations

Use these conventions for Kubernetes recommended labels, OpenShift Topology
metadata, Argo CD Application labels, and RHOAI Dashboard annotations.

## Required Kubernetes Labels

Most resources should include:

| Label | Purpose | Example |
|-------|---------|---------|
| `app.kubernetes.io/part-of` | Topology grouping | `llm-serving` |
| `app.kubernetes.io/name` | Component name | `mistral-3-bf16` |
| `app.kubernetes.io/component` | Component role | `inference` |
| `app.kubernetes.io/instance` | Unique instance when useful | `mistral-3-bf16-private-ai` |

Label values must be Kubernetes-label safe and under 63 characters.

## `app.kubernetes.io/part-of` Values

Use short functional group names, not step numbers.

| Value | Typical resources |
|-------|-------------------|
| `llm-serving` | InferenceService, ServingRuntime, vLLM pods |
| `rag` | LlamaStack, PostgreSQL, Docling, chatbot, ingestion |
| `guardrails` | NemoGuardrails, guardrails config, safety service account |
| `mcp-integration` | database, OpenShift, Slack, and proxy MCP servers |
| `observability` | Grafana, ServiceMonitors, dashboards |
| `benchmarking` | GuideLLM jobs and benchmark workbench |
| `model-registry` | ModelRegistry, MariaDB, seed jobs |
| `rag-evaluation` | Eval configs, EvalHub, LMEval templates |
| `face-recognition` | YOLO, OpenVINO runtime, workbench, upload jobs |
| `gpu-infra` | NFD, GPU Operator, MachineSets |
| `storage` | MinIO resources |

## `app.kubernetes.io/component` Values

Use standard values where possible:

| Value | Use for |
|-------|---------|
| `inference` | model serving endpoints |
| `backend` | API services and app logic |
| `database` | PostgreSQL, MariaDB, MinIO |
| `frontend` | user-facing UI |
| `monitoring` | observability components |
| `orchestrator` | workflow coordination |
| `safety` | guardrails services |
| `integration` | ingestion and MCP integration services |

## OpenShift Topology Labels

Visible resources should set `app.openshift.io/runtime` when an icon helps the
Topology view. Common demo values:

| Component | Runtime |
|-----------|---------|
| PostgreSQL | `postgresql` |
| MinIO | `golang` |
| Python apps and vLLM endpoints | `python` |
| Grafana | `grafana` |
| MCP servers | `golang` |

Use `app.openshift.io/connects-to` on primary resources when it improves the
demo architecture view.

## RHOAI Dashboard ServingRuntime Annotations

GitOps-managed ServingRuntimes should include Dashboard metadata that the UI
would otherwise add automatically:

| Annotation | Purpose |
|------------|---------|
| `opendatahub.io/template-name` | platform template reference |
| `opendatahub.io/template-display-name` | dashboard display name |
| `opendatahub.io/apiProtocol` | REST or gRPC protocol |
| `opendatahub.io/runtime-version` | runtime version badge |

Verify template names from platform templates in `redhat-ods-applications` when
the live cluster is available.

## Argo CD Application Labels

Argo CD Application objects use demo-level labels:

```yaml
metadata:
  labels:
    app.kubernetes.io/part-of: rhoai3-demo
    demo.rhoai.io/step: "XX"
```

Do not use workload `part-of` values such as `llm-serving` on Application
objects.

## Anti-Patterns

- step numbers in workload `part-of`
- overly long group names
- generic values such as `app` or `demo`
- ServingRuntimes without Dashboard annotations

## References

- Kubernetes recommended labels: https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/
- Red Hat app labels guide: https://github.com/redhat-developer/app-labels/blob/master/labels-annotation-for-openshift.adoc
- Current OCP Topology docs: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html-single/building_applications/index#odc-viewing-application-composition-using-topology-view
