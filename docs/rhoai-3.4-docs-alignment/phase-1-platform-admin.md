# Phase 1: Platform, Planning, Install, and Administration

## Intent

This phase covers the platform owner view: understand what changed in RHOAI 3.4, prepare OpenShift and accelerator infrastructure, install OpenShift AI, configure access and platform components, select supported APIs, and govern catalogs and registries.

## Chapter Analysis

| Chapter | Intent | Components and recommended setup | RHOAI 3.4 specifics | Demo coverage and alignment |
|---|---|---|---|---|
| Release Notes | Establish the 3.4 feature baseline and changed support posture. | RHOAI operator, DSC/DSCI, Llama Stack, MaaS, model registry, TrustyAI, KServe, dashboard. | 3.4 introduces or updates Gen AI, agentic, governance, safety, and serving capabilities; preview status matters. | `partially-covered`: audit docs and READMEs mention major preview features, but there is no feature-by-feature release traceability table. |
| Lifecycle | Explain support lifecycle and upgrade expectations. | Operator channels, OLM, supported versions. | Demo should avoid claiming production support for Technology Preview or Developer Preview APIs. | `partially-covered`: Step 02/07/09 mention preview status, but support-tier language should be centralized. |
| Get started | Orient users around projects, workbenches, pipelines, and first model deployment. | DataScienceProject, Notebook, DataSciencePipelineApplication, KServe. | Getting-started flow is user-facing and dashboard-oriented. | `covered`: Steps 03, 07, 11, and 12 provide project, workbench, pipeline, and model-serving examples. |
| Platform/hardware planning | Confirm supported OpenShift, accelerators, storage, and resource strategy. | OCP 4.20, NFD, NVIDIA GPU Operator, Kueue, hardware profiles. | Hardware profiles and accelerator management are core to governed AI. | `covered`: Step 01/02 implement operators and hardware profiles. Add supported matrix evidence for GPU instance types. |
| Validated model selection | Encourage use of validated model catalog choices. | Model catalog, OCI ModelCars, vLLM runtime, model registry. | Red Hat validated models and catalog sources are part of the platform story. | `partially-covered`: Step 04/05 use catalog narrative and selected models. Document active vs deferred models, especially Qwen. |
| Connected install | Install OpenShift AI and required components. | Subscription, DSCInitialization, DataScienceCluster, OdhDashboardConfig. | 3.4 component management includes MaaS, Llama Stack, TrustyAI, pipelines, KServe, model registry. | `covered`: Step 02 is GitOps-managed and validated. |
| Disconnected install | Install in restricted networks. | Mirroring, ImageContentSourcePolicy/IDMS, catalog sources, disconnected registries. | Critical for enterprise, but not part of this live AWS demo. | `not-covered`: mark out of scope or add a short disconnected-install appendix. |
| Secure workbenches/custom images | Publish IDE images and provision secure workbenches. | Notebook CRs, workbench images, dashboard image metadata, storage, resource profiles. | Workbench image governance and custom images are administrator concerns. | `partially-covered`: workbenches exist in Steps 06/07/11. Add custom image governance caveats. |
| Platform access/apps/operations | Configure admin/user groups, dashboard apps, logs, backups, and operations. | Groups, RBAC, dashboard config, OAuth, monitoring, backups. | Governance and tenancy are core platform requirements. | `covered`: Step 03 creates groups/RBAC and storage. Backup and telemetry boundaries need clearer docs. |
| Feature Store | Define and serve reusable ML features. | FeatureStore/Feast-style feature services and project configuration. | Important for predictive AI but absent from current demo. | `not-covered`: candidate future predictive AI enhancement. |
| Telemetry | Decide what usage data is collected and how to disable/enable it. | Dashboard/telemetry configuration and admin docs. | Enterprises need explicit telemetry posture. | `partially-covered`: Step 02 platform config exists, but telemetry status is not documented. |
| Hardware configs/resources | Enable accelerators and resource controls for projects. | HardwareProfile, accelerator operators, Kueue queues. | Hardware profiles are central in 3.4 platform resource governance. | `covered`: Steps 01/02/03 use GPU operators, profiles, and queues. |
| Model-serving platform config | Configure KServe, RawDeployment, auth, runtimes, and dashboard serving options. | KServe, ServingRuntime, InferenceService, Authorino/RHCL, gateways. | RawDeployment and model endpoint auth choices are major setup points. | `covered`: Steps 02/05/11/13 implement serving config and runtimes. |
| Llama Stack administration | Enable and operate Llama Stack APIs. | LlamaStackDistribution, providers, pgvector, vLLM, RAG APIs. | RHOAI 3.4 Llama Stack uses 0.7-era APIs and preview support. | `covered`: Step 07 deploys Llama Stack; Step 10 extends with MCP connectors. |
| Model catalog source governance | Govern which catalog sources and models are available. | Model catalog sources, dashboard governance. | Relevant to enterprise model approval. | `partially-covered`: Step 04/05 use model catalog narrative but do not configure source governance. |
| Production-ready APIs | Select API surfaces by support tier and upgrade stability. | RHOAI APIs, OpenAI-compatible endpoints, preview/developer-preview APIs. | 3.4 includes several preview API surfaces. | `partially-covered`: preview notes exist; add a central API support-tier matrix. |
| Model registry administration | Create registries, configure access, and manage lifecycle. | ModelRegistry CR/service, DB, RBAC, dashboard registry. | Registry is a governance anchor. | `covered`: Step 04 deploys registry and RBAC; Step 12 integrates promotion. |

## Recommended Improvements

| Priority | Recommendation | Demo area |
|---|---|---|
| P1 | Add a central support-tier matrix for RHOAI APIs and preview features used by the demo. | Docs, Step 02, Step 07, Step 09, Step 10 |
| P1 | Normalize Step 13b Argo CD app standards to match the rest of the demo. | Step 13b |
| P2 | Add telemetry status and verification commands to Step 02 or operations docs. | Step 02, docs/OPERATIONS.md |
| P2 | Add a supported configuration evidence table for OCP 4.20, GPU instance families, and RHOAI component versions. | Step 01, Step 02 |
| P2 | Document model catalog source governance as deferred or implement a minimal catalog-source control example. | Step 04/05 |
| P3 | Add a disconnected-install appendix that states the live demo is connected-only and lists what would change. | Step 02 |

## rh-brain Alignment

Relevant sources:

- `raw/GPU-as-a-Service for AI at scale Practical strategies with Red Hat OpenShift AI.md`
- `raw/From inference to agents Scaling AI in the enterprise with Red Hat AI 3.4.md`
- `raw/How Red Hat OpenShift AI simplifies trust and compliance.md`
- `raw/Operationalize AI with Red Hat AI.md`

Narrative fit: strong. The demo already tells a governed Private AI platform story with project tenancy, GPU-as-a-Service, model registry, MaaS, RAG, guardrails, MCP, and MLOps. The main improvement is to make support status and production caveats as explicit as the technical implementation.
