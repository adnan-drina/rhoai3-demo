# Phase 2: Develop and Deploy

## Intent

This phase covers the practitioner path: organize projects, use workbenches and storage, build pipelines, use model catalog and registry, deploy RAG and Llama Stack, experiment in the Gen AI Playground, deploy models with KServe, govern LLM access through MaaS, and consider distributed inference or workloads.

## Chapter Analysis

| Chapter | Intent | Components and recommended setup | RHOAI 3.4 specifics | Demo coverage and alignment |
|---|---|---|---|---|
| Working on projects | Organize data science work, access, storage, and deployments by project. | DataScienceProject namespaces, RBAC, workbenches, data connections. | Project-scoped governance is expected. | `covered`: Step 03 creates `maas`, `enterprise-rag`, and `enterprise-mlops` with RBAC and storage connections. |
| Data science IDE images | Use Red Hat IDE images and custom environments. | Workbench images, image metadata, PVCs, hardware profiles. | Default RHOAI images and custom image governance should be clear. | `partially-covered`: Steps 06/07/11 use workbenches, but custom image governance is not a demo focus. |
| S3-compatible object storage | Connect workbenches/pipelines/model serving to S3-compatible storage. | DataConnection secrets, MinIO/S3, KFP artifacts, KServe storage. | Data connections are dashboard-visible and project-scoped. | `covered`: Step 03 provisions MinIO and connections; Steps 07/12 use S3 for artifacts and data. |
| AI pipelines | Build, schedule, run, and track KFP pipelines. | DSPA, KFP v2, object storage, pipeline runs, artifacts. | RHOAI 3.4 pipeline configuration requires working storage and project integration. | `covered`: Step 07 ingestion and Step 12 training/promotion pipelines. |
| Connected applications | Enable dashboard applications and access external/connected tools. | Dashboard connected app tiles, app config, Jupyter access. | Useful for platform UX but not central to current story. | `not-covered`: defer unless adding a dashboard-integrated connected app. |
| Model registry usage | Register, version, share, and promote models. | ModelRegistry, model versions/artifacts, RBAC groups. | Registry should support traceability and promotion. | `covered`: Step 04 seeds registry; Step 12 promotion uses registry. |
| Model catalog usage | Discover, evaluate, register, and deploy validated models. | Model catalog, OCI model artifacts, registry, serving runtime. | 3.4 catalog is central to model discovery. | `partially-covered`: Step 04/05 use catalog narrative; qwen3 manifest is deferred and should be documented or removed. |
| RAG stack | Deploy Llama Stack, vLLM, vector store, and ingestion. | LlamaStackDistribution, pgvector, vLLM, file/vector APIs, RAG pipelines. | RHOAI 3.4 Llama Stack APIs are preview and version-sensitive. | `covered`: Step 07 aligns strongly with pgvector, Llama Stack 0.7, Docling, and KFP ingestion. |
| Gen AI Playground | Experiment with models, guardrails, knowledge sources, and MCP servers. | Dashboard playground, MCP server config map, model endpoints. | Product-native UI can compare components. | `partially-covered`: Step 10 configures MCP servers for the dashboard; demo centers on custom chatbot. Add a product-native playground scene. |
| Distributed workloads | Run distributed data processing/training workloads. | Kueue, Ray, CodeFlare, Workload, cluster queues. | Supports GPU-aware scale-out workloads. | `partially-covered`: Step 01/03 install Kueue and queues, but no Ray/CodeFlare workload is demonstrated. |
| Spark Operator | Create Spark data processing apps. | Kubeflow Spark Operator, SparkApplication, storage. | Useful for large-scale data prep. | `not-covered`: future data processing enhancement. |
| AutoML | Run automated model selection/training. | AutoML components and dashboard/project integration. | Predictive AI accelerator. | `not-covered`: not part of current demo. |
| AutoRAG | Automate RAG optimization. | AutoRAG workflows, evaluation, datasets, vector stores. | Relevant to RAG quality iteration. | `not-covered`: future RAG improvement. |
| MLflow | Track experiments, models, and metrics. | MLflow tracking server, artifact store, KFP integration. | Useful for model lifecycle governance. | `covered`: Step 12 includes MLflow alongside registry and pipelines. |
| KServe RawDeployment | Deploy large models and predictive models with KServe. | ServingRuntime, InferenceService, RawDeployment/Standard mode, auth. | RawDeployment is the demo serving baseline. | `covered`: Steps 05, 11, and 13 use KServe-compatible Standard/RawDeployment patterns. |
| Models-as-a-Service | Govern LLM access and model deployment lifecycle. | MaaS, Gateway, AuthPolicy, model catalog, vLLM serving. | Technology Preview; requires gateway and DB config. | `covered`: Steps 02 and 05 implement MaaS and LLM serving with preview caveats. |
| llm-d | Distributed inference for LLM serving at scale. | llm-d, vLLM, distributed serving components. | Important scale-out inference option. | `intentionally-deferred`: no active llm-d deployment; rh-brain material supports future track. |

## Recommended Improvements

| Priority | Recommendation | Demo area |
|---|---|---|
| P1 | Decide whether `qwen3-8b-agent.yaml` is future scope or remove it from the repo. | Step 05 |
| P1 | Add a Gen AI Playground scene that uses product-native model/MCP/guardrails comparison without replacing the chatbot. | Step 10 |
| P2 | Add an explicit distributed workload deferment or a minimal Ray/CodeFlare validation workload. | Step 01/03 or new step |
| P2 | Add exact MLflow doc references and clarify MLflow tracking/artifact boundaries. | Step 12 |
| P2 | Add AutoRAG and AutoML to the backlog as named RHOAI 3.4 gaps, not silent omissions. | Docs backlog |
| P3 | Consider a future llm-d optional path for the 4-GPU Mistral/Judge node. | Step 05/06 |

## rh-brain Alignment

Relevant sources:

- `raw/Deploy an enterprise RAG chatbot with Red Hat OpenShift AI.md`
- `raw/Planning the design of your production-grade RAG system.md`
- `raw/Building effective AI agents with Model Context Protocol (MCP).md`
- `raw/Demystifying llm-d and vLLM The race to production.md`
- `raw/GuideLLM Evaluate LLM deployments for real-world inference.md`

Narrative fit: strong for RAG, MaaS, MCP, and model serving. Medium for product-native Playground and distributed workloads because the demo uses a custom app and primarily single-node model serving.
