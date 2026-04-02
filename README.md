# Red Hat OpenShift AI 3.3 Demo

**One governed, open, hybrid-cloud AI platform for private, generative, predictive, and edge AI.**

This demo shows how Red Hat OpenShift AI helps organizations build a trusted, open, and consistent AI platform across hybrid cloud. We start with **Private AI** to establish governance, sovereign-ready operations, and open-source control. We then add **Generative AI** to serve models efficiently, ground them in enterprise data, and expose them through agentic patterns. Next, we show **Predictive AI** to prove the same platform supports model development, training, and repeatable MLOps workflows. Finally, we extend that governed lifecycle to **Edge AI**, using the same operating model from core to edge.

### Why it matters

AI in the enterprise is not just about models. It is about building a governed AI platform that gives teams:

- **Trust** — control over data, privacy, security, and where AI runs
- **Choice** — flexibility in models, tools, accelerators, and environments
- **Consistency** — one operating model across private, hybrid, and edge environments

**Target audience:** Solution Architects, Platform Engineers, AI/ML Engineers evaluating Red Hat's AI platform.

## Architecture

*One platform to build, serve, and govern AI across hybrid cloud*

```text
┌───────────────────────────────────────────────────────────────────────┐
│                 GitOps-Driven AI Lifecycle                            │
│                                                                       │
│ Ingest ──→ Train ──→ Evaluate ──→ Register ──→ Deploy ──→ Monitor     │
│   ↑                                                         │         │
│   └──────────────────── Retrain ────────────────────────────┘         │
├───────────────────────────────────────────────────────────────────────┤
│                  RHOAI 3.3 — AI/ML Platform                           │
│                                                                       │
│ Model Dev &       Model Training   Intelligent GPU   AI Pipelines     │
│ Customization     & Experimentation & Hardware Speed                  │
│                                                                       │
│ Optimized Model   Agentic AI &     Model Observability  Catalog &     │
│ Serving           Gen AI UIs       & Governance         Registry      │
│                                                                       │
│ Feature Store*    Models-as-a-Service*                                │
├───────────────────────────────────────────────────────────────────────┤
│              Compute Accelerators — NVIDIA L4 GPU                     │
├───────────────────────────────────────────────────────────────────────┤
│               OpenShift Container Platform 4.20                       │
│                                                                       │
│ NFD        NVIDIA GPU  Serverless   Service Mesh     Monitoring       │
│ Operator   Operator    (Knative)    (Istio)          (Prometheus)     │
│                                                                       │
│ Auth       GitOps    Pipelines    Data Foundation*   Streams*         │
│ Operator   (ArgoCD)  (Tekton)     (Ceph)             (Kafka)          │
├───────────────────────────────────────────────────────────────────────┤
│                        Infrastructure                                 │
│                                                                       │
│    Cloud (AWS)        Edge Simulated (OCP)      Edge (MicroShift)     │
│    OCP 4.20           namespace on OCP          RHEL 9.5 + L4 GPU     │
└───────────────────────────────────────────────────────────────────────┘
  * Planned — see BACKLOG.md
```

## RHOAI 3.3 Features and Benefits Coverage

This demo covers 9 of 11 features from the [Red Hat OpenShift AI datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet):

| RHOAI Feature | Benefit (from datasheet) | Demo Steps |
|---------------|--------------------------|------------|
| **Intelligent GPU and hardware speed** | Self-service GPU access is available. Offers intelligent GPU use for workload scheduling, quota management, priority access and visibility of use through hardware profiles. | Steps 01, 02, 03 |
| **Catalog and registry** | Centralized management for predictive and gen AI models and MCP servers and their metadata, and artifacts. | Step 04 |
| **Optimized model serving** | Serves models from various providers and frameworks via a virtual large language model (vLLM), optimized for high throughput and low latency. The llm-d distributed inference framework supports predictable and scalable performance and efficient resource management. Includes LLM compressor and access to common, optimized and validated gen AI models. | Steps 05, 06 |
| **Model development and customization** | An interactive JupyterLab interface with AI/ML libraries and workbenches. Integrates data ingestion, synthetic data generation, InstructLab toolkit, and Retrieval Augmented Generation (RAG) for private data connection. | Steps 07, 11 |
| **AI pipelines** | Can automate model delivery and testing. Pipelines are versioned, tracked and managed to reduce user error and simplify experimentation and production workflows. | Steps 07, 08, 12 |
| **Model observability and governance** | Common open source tooling for lifecycle management, performance, and management. Tracks metrics, including performance, data drift and bias detection and AI guardrails or inference. Offers LLM evaluation (LM Eval) and LLM benchmarking (GuideLLM) to assist real world inference deployments. | Steps 06, 08, 09, 12 |
| **Agentic AI and gen AI user interfaces (UIs)** | Speeds agentic AI workflows with core platform services. A unified application programming interface (API) layer (MCP and Llama Stack API) and dedicated dashboard experience (AI hub and gen AI studio). | Steps 05, 09, 10 |
| **Model training and experimentation** | Organizes development files and artifacts. Supports distributed workloads for efficient training and tuning. Features experiment tracking and simplified hardware allocation. | Steps 11, 12 |
| **Disconnected environments and edge** | Supports disconnected and air-gapped clusters for security and regulatory compliance. | Steps 13, 13b |
| Feature store | *A UI for managing clean, well-defined data features for ML models, enhancing performance and accelerating workflows.* | *Not yet demonstrated — see [BACKLOG.md](BACKLOG.md)* |
| Models-as-a-service | *Allows AI engineers to use models via a managed, built-in API gateway for self-service access and usage tracking (developer preview feature).* | *Not yet demonstrated — see [BACKLOG.md](BACKLOG.md)* |

## OpenShift Container Platform 4.20 Features Used

The demo runs on [Red Hat OpenShift Container Platform 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/architecture/architecture) and leverages the following platform capabilities:

| OCP Feature | What It Provides | Demo Steps |
|-------------|-----------------|------------|
| **Operator Lifecycle Manager (OLM)** | Manages the lifecycle of Kubernetes native applications (Operators) — install, update, and RBAC across clusters | Steps 01, 02 |
| **Node Feature Discovery (NFD)** | Detects hardware features and configuration, labeling nodes with hardware-specific attributes for workload scheduling | Step 01 |
| **NVIDIA GPU Operator** | Automates deployment and management of GPU software components on worker nodes — drivers, monitoring, and resource optimization | Step 01 |
| **OpenShift Serverless** | Deploying and serving applications as serverless containers with dynamic scaling based on incoming traffic | Step 01 |
| **Service Mesh 3** | Service mesh based on Istio — gateway, traffic management, and zero-trust networking for RHOAI Dashboard and KServe endpoints | Step 02 |
| **Monitoring** | Preconfigured monitoring stack based on Prometheus — platform metrics, user workload metrics, alerts, and dashboards | Steps 01, 06, 12 |
| **Authentication and Authorization** | Built-in OAuth server with identity providers and Role-Based Access Control (RBAC) for multi-tenant access control | Step 03 |
| **OpenShift GitOps (ArgoCD)** | Declarative GitOps continuous delivery — Git as the single source of truth for cluster and application configuration | All steps |
| **OpenShift Pipelines (Tekton)** | Cloud-native CI/CD with Kubernetes-native pipelines that scale on demand in isolated containers | Step 12 |
| **MicroShift 4.20** | Small-form-factor container orchestration runtime designed for edge computing on managed RHEL devices | Step 13b |
| OpenShift Data Foundation | *Persistent storage, data services, and data protection for containers and virtual machines* | *Not yet demonstrated — see [BACKLOG.md](BACKLOG.md)* |
| AMQ Streams (Kafka) | *Event streaming platform for real-time data pipelines and streaming applications* | *Not yet demonstrated — see [BACKLOG.md](BACKLOG.md)* |

## Four Demo Themes

### Theme 1: Private AI (Steps 01-04)
**Run AI with control over data, operations, and deployment choices.**

OpenShift AI adds GPU enablement, governance, multitenancy, and consistent operations to OpenShift. Built on open source and designed for hybrid cloud, it helps organizations establish a sovereign-ready foundation for predictive and generative AI without creating a separate stack.

| Step | Capability | RHOAI Features Introduced | OCP Features Introduced |
|------|-----------|--------------------------|------------------------|
| 01 | GPU Infrastructure | Intelligent GPU and hardware speed | OLM, NFD, NVIDIA GPU Operator, Serverless, Monitoring |
| 02 | RHOAI Platform | Agentic AI and gen AI UIs (GenAI Studio) | Service Mesh 3 |
| 03 | Multitenancy | — (uses GPU features from 01) | Authentication and Authorization |
| 04 | Model Governance | Catalog and registry | — |

### Theme 2: Generative AI — ACME Semiconductor (Steps 05-10)
**Turn LLMs into useful applications grounded in business context.**

Building on the private AI base, this theme adds scalable serving, data grounding, and agentic patterns. It helps teams deliver more relevant outcomes on the same governed platform — reusing governance, observability, and access controls already in place.

| Step | Capability | RHOAI Features Introduced | Reuses From |
|------|-----------|--------------------------|-------------|
| 05 | LLM Serving | Optimized model serving | GPU (01), Registry (04) |
| 06 | Performance Monitoring | Model observability and governance | Monitoring (01), Serving (05) |
| 07 | RAG Pipeline | Model development and customization, AI pipelines | Serving (05) |
| 08 | Model Evaluation | — (uses observability from 06, pipelines from 07) | Pipelines (07), Observability (06) |
| 09 | AI Safety | — (uses observability: guardrails) | Serving (05), Observability (06) |
| 10 | Agentic AI & MCP | Agentic AI and gen AI UIs (MCP, Llama Stack) | RAG (07), Guardrails (09) |

### Theme 3: Predictive AI — WhoAmI Face Recognition (Steps 11-12)
**Build, train, and operationalize predictive AI on the same platform as generative AI.**

Building on the serving, pipelines, and observability established earlier, this theme adds model development, training, and repeatable MLOps workflows. It proves that OpenShift AI supports predictive and generative AI together — not as separate toolchains.

| Step | Capability | RHOAI Features Introduced | Reuses From |
|------|-----------|--------------------------|-------------|
| 11 | Computer Vision | Model training and experimentation | Serving (05), GPU (01) |
| 12 | MLOps Pipeline | — (uses pipelines, observability, registry) | Pipelines (07), Registry (04), Observability (06) |

### Theme 4: Edge AI (Steps 13-13b)
**Run AI closer to where decisions happen without losing central control.**

Building on the models, pipelines, and governance established centrally, this theme extends the same operating model from core to edge. Teams keep one governed lifecycle across datacenter, cloud, and distributed environments.

| Step | Capability | RHOAI Features Introduced | OCP Features Introduced |
|------|-----------|--------------------------|------------------------|
| 13 | Edge AI | Disconnected environments and edge | — |
| 13b | Edge AI on MicroShift *(optional)* | — (same feature, real hardware) | MicroShift 4.20, Pipelines (Tekton) |

## E2E Scenarios

### ACME Semiconductor (GenAI — Steps 07-10)

The agentic model autonomously resolves an equipment alert using four integrated tools. *"Agentic architectures orchestrate multiple AI agents that can query databases, call APIs, search internal knowledge bases, and take actions based on results. This moves AI from answering questions to completing tasks."*

1. **Inspects the cluster** — finds a failing equipment pod via OpenShift MCP
2. **Queries a database** — identifies the equipment (L-900-08 EUV Scanner) via Database MCP
3. **Searches internal docs** — finds the DFO calibration procedure via RAG
4. **Sends an alert** — notifies the platform team via Slack MCP

### WhoAmI Face Recognition (Predictive AI — Steps 11-12)

A complete MLOps lifecycle from notebook to production:

1. **Explore** — detect faces with pre-trained YOLO11 (notebook 01)
2. **Retrain** — auto-annotate your photos, train a personalized model on CPU (notebook 02)
3. **Test locally** — annotated video with green/red bounding boxes (notebook 03)
4. **Deploy** — KFP pipeline registers in Model Registry and deploys on OpenVINO (step 12)
5. **Monitor** — TrustyAI tracks confidence drift in production (step 12)
6. **Query via API** — KServe v2 REST endpoint for application integration (notebook 04)
7. **Edge inference** — phone camera app with live face recognition at the edge (step 13)

## What You Need

- OpenShift 4.20+ cluster on AWS
- 1x g6.4xlarge (1 GPU) + 1x g6.12xlarge (4 GPU) — 5 NVIDIA L4 GPUs total
- Cluster admin access
- `oc` CLI installed

## Quick Start

```bash
git clone https://github.com/adnan-drina/rhoai3-demo.git && cd rhoai3-demo
cp env.example .env              # Edit with your config
oc login --token=<token> --server=<api>
./scripts/bootstrap.sh           # Install ArgoCD + auto-detects fork URL
```

> **Using a fork?** `bootstrap.sh` auto-detects your git remote and updates all ArgoCD Applications. No manual `sed` needed.

Deploy by theme or all steps in order:

```bash
# Theme 1: Platform (required for all other themes)
./steps/step-01-gpu-and-prereq/deploy.sh
./steps/step-02-rhoai/deploy.sh
./steps/step-03-private-ai/deploy.sh
./steps/step-04-model-registry/deploy.sh

# Theme 2: Generative AI
./steps/step-05-llm-on-vllm/deploy.sh
./steps/step-06-model-metrics/deploy.sh
./steps/step-07-rag/deploy.sh
./steps/step-08-model-evaluation/deploy.sh
./steps/step-09-guardrails/deploy.sh
./steps/step-10-mcp-integration/deploy.sh

# Theme 3: Predictive AI
./steps/step-11-face-recognition/deploy.sh
./steps/step-12-mlops-pipeline/deploy.sh
./steps/step-13-edge-ai/deploy.sh

# Optional: Real edge on MicroShift (requires RHEL host with MicroShift repos)
# EDGE_HOST=<host> EDGE_USER=dev EDGE_PASS=<pass> ./steps/step-13b-edge-ai-microshift/deploy.sh
```

Validate the ACME demo flow:

```bash
./scripts/validate-demo-flow.sh   # 3-layer E2E test (Tool Runtime + Agentic + Guardrails)
```

## Step Details

| Step | Name | RHOAI Capability | Ref |
|------|------|-----------------|-----|
| 01 | [GPU Infrastructure](steps/step-01-gpu-and-prereq/README.md) | NFD, GPU Operator, Serverless, LeaderWorkerSet, RHCL | [Installing dependencies](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-distributed-inference-dependencies) |
| 02 | [RHOAI Platform](steps/step-02-rhoai/README.md) | DataScienceCluster, GenAI Studio, Hardware Profiles | [Installing RHOAI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index) |
| 03 | [Multitenancy & GPU-as-a-Service](steps/step-03-private-ai/README.md) | Projects, users, GPU scheduling, MinIO, RBAC | [Managing OpenShift AI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_openshift_ai/) |
| 04 | [Model Governance](steps/step-04-model-registry/README.md) | Model Registry, Model Catalog, seed job, RBAC | [Managing model registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/managing_model_registries/index) |
| 05 | [LLM Serving on vLLM](steps/step-05-llm-on-vllm/README.md) | Red Hat Validated models on GPU, Model Registry, GenAI Playground | [Deploying models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/) |
| 06 | [Performance Monitoring](steps/step-06-model-metrics/README.md) | Grafana dashboards, GuideLLM benchmarks, KFP pipelines | [Managing and monitoring models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_and_monitoring_models/index) |
| 07 | [RAG Pipeline](steps/step-07-rag/README.md) | pgvector, Docling, DSPA, LlamaStack RAG chatbot | [Deploying a RAG stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/deploying-a-rag-stack-in-a-project_rag) |
| 08 | [Model Evaluation](steps/step-08-model-evaluation/README.md) | Pre/post RAG eval (LLM-as-Judge), LM-Eval benchmarks | [Evaluating AI systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/) |
| 09 | [AI Safety & Guardrails](steps/step-09-guardrails/README.md) | TrustyAI: HAP, prompt injection, PII — CPU-only | [Enabling AI safety](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/enabling_ai_safety_with_guardrails/) |
| 10 | [Agentic AI & MCP](steps/step-10-mcp-integration/README.md) | Database, OpenShift, Slack MCP servers | [Configuring MCP servers](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user) |
| 11 | [Face Recognition](steps/step-11-face-recognition/README.md) | YOLO11 ONNX, KServe + OpenVINO, CPU-only inference | [Deploying models (KServe)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/) |
| 12 | [MLOps Pipeline](steps/step-12-mlops-pipeline/README.md) | KFP v2 training, Model Registry, TrustyAI monitoring | [Working with AI Pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_ai_pipelines/) |
| 13 | [Edge AI](steps/step-13-edge-ai/README.md) | Phone camera app, edge inference, GitOps model delivery | [Deploying models (KServe)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/) |
| 13b | [Edge AI on MicroShift](steps/step-13b-edge-ai-microshift/README.md) *(optional)* | Real edge: MicroShift 4.20 on RHEL, ModelCar OCI, NVIDIA L4 | [Using AI models on MicroShift](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/using_ai_models/) |

## GitOps Architecture

- **Per-step deployment** — each `deploy.sh` applies its own ArgoCD Application (`oc apply -f`), giving control over ordering and runtime setup (secrets, SCC grants, model uploads) between syncs.
- **`targetRevision: main`** — acceptable for a demo project where the single branch is the source of truth. For stable demo releases, tag the repo and update across all 14 Applications (steps 01-13b).
- **Two ArgoCD layers** — the central `openshift-gitops` instance manages platform (steps 01-02), application (steps 03-13), and the Tekton ModelCar pipeline (step-13b). A second **embedded ArgoCD core** on MicroShift manages edge workloads from `gitops/edge-ai-microshift/`, enabling Git-driven model updates to the edge without SSH.
- **Fork-friendly** — `bootstrap.sh` auto-detects the git remote URL and updates all ArgoCD Applications. No manual URL changes needed for forks.

## Demo Credentials

| Username | Password | Role |
|----------|----------|------|
| `ai-admin` | `redhat123` | Service Governor (RHOAI Admin) |
| `ai-developer` | `redhat123` | Service Consumer (RHOAI User) |
| MinIO Console | `minio-admin` / `minio-secret-123` | S3 storage admin |

## References

- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet)
- [An Open Platform for AI Models in the Hybrid Cloud](https://www.redhat.com/en/resources/openshift-ai-overview)
- [Get started with AI for enterprise organizations](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)
- [RHOAI 3.3 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/)
- [RHOAI 3.3 Working with Llama Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/)
- [OpenShift 4.20 GPU Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)
- [Red Hat AI Validated Models](https://docs.redhat.com/en/documentation/red_hat_ai/3/html-single/validated_models/index)
- [Red Hat Ecosystem Catalog — MCP Servers](https://catalog.redhat.com/en/categories/ai/mcpservers)
