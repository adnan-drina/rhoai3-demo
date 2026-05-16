# Phase 4: Supported Configurations and Cross-Cutting Alignment

## Intent

This phase checks that the demo's claims, support posture, and Red Hat narrative alignment are consistent across all steps, not just individual components.

## Supported Configuration Assessment

| Area | Current demo state | Alignment | Improvement |
|---|---|---|---|
| OpenShift baseline | Live cluster reports OCP 4.20.22. | `covered` | Keep exact version in audit evidence. |
| RHOAI baseline | Live cluster uses `rhods-operator.3.4.0`. | `covered` | Keep CSV/version evidence in audit output. |
| GPU nodes | Demo documents g6.4xlarge and g6.12xlarge GPU roles. | `partially-covered` | Add supported accelerator reference and verification commands. |
| Managed operators | NFD, GPU Operator, Serverless, Kueue, RHCL/Authorino, RHOAI are GitOps-managed. | `covered` | Keep install-plan and operator lifecycle caveats. |
| Storage | In-cluster MinIO and demo databases are used. | `partially-covered` | Continue to label demo/evaluation storage and DBs as non-production. |
| API support tiers | Preview and Developer Preview features are mentioned in some READMEs. | `partially-covered` | Add central API/support-tier table. |
| Disconnected environments | Not implemented. | `not-covered` | Add explicit out-of-scope note or future backlog. |
| Edge | Step 13 central simulation and Step 13b MicroShift bootstrap are separate. | `covered` | Normalize Step 13b Argo app standards. |

## Cross-Cutting Claim Review

| Claim type | Status | Required posture |
|---|---|---|
| Production readiness | Mixed. Some steps use production language for demo components. | Keep production concepts, but label demo infrastructure limits and preview APIs. |
| Red Hat recommended architecture | Strong for KServe, model registry, RAG, LM-Eval, NeMo Guardrails, KFP, MCP ecosystem usage. | Avoid saying unsupported/deferred features are implemented. |
| Security | Good baseline for RBAC, project boundaries, NetworkPolicy, managed streams, and non-production secret caveats. | Add MCP least-privilege/tool governance section. |
| GitOps | Strong after recent cleanup. | Add deploy-script lint and normalize Step 13b. |
| Observability | Strong for vLLM metrics and dashboards; partial for RHOAI TrustyAI monitoring. | Add model monitoring chapter mapping. |

## rh-brain Narrative Alignment

| Theme | rh-brain sources | Demo alignment |
|---|---|---|
| Private AI platform | `Operationalize AI with Red Hat AI`, `Why customers are choosing Red Hat AI for real business outcomes` | Strong: project boundaries, model serving, governance, storage, evaluation. |
| GPU-as-a-Service | `GPU-as-a-Service for AI at scale Practical strategies with Red Hat OpenShift AI` | Strong: GPU operators, hardware profiles, Kueue, MaaS model roles. |
| RAG and agentic AI | `Deploy an enterprise RAG chatbot with Red Hat OpenShift AI`, `From RAG to agentic AI When models stop answering and start acting` | Strong: Step 07 RAG and Step 10 MCP. |
| MCP security | `MCP security Containerization and Red Hat OpenShift integration`, `MCP security Implementing robust authentication and authorization` | Medium: MCP servers are containerized and scoped, but explicit security narrative can improve. |
| Guardrails | `Build resilient guardrails for OpenClaw AI agents on Kubernetes` | Strong after NeMo migration; keep the release-note/product-book support-status nuance visible. |
| Evaluation and observability | `Eval-driven development Build and evaluate reliable AI agents`, `GuideLLM Evaluate LLM deployments for real-world inference` | Strong for LM-Eval and GuideLLM; add TrustyAI monitoring comparison. |
| Edge AI | `What is edge AI?` | Strong split between central simulation and MicroShift edge path. |

## Final Cross-Cutting Recommendations

| Priority | Recommendation |
|---|---|
| P1 | Add a central support-tier matrix for all preview, Developer Preview, and stable APIs used by the demo. |
| P1 | Normalize Step 13b Argo CD sync options and ignore differences. |
| P1 | Decide whether deferred `qwen3-8b-agent.yaml` remains future scope or is removed. |
| P2 | Add a supported-configuration evidence section for OCP, RHOAI, GPU, and core operators. |
| P2 | Add product-native Gen AI Playground path to Step 10. |
| P2 | Add explicit telemetry and disconnected-install out-of-scope notes. |
| P2 | Add MCP security/least-privilege narrative and validation checks. |
| P3 | Add optional future tracks for Feature Store, AutoML, AutoRAG, Spark, Ray/CodeFlare, model customization, and llm-d. |
