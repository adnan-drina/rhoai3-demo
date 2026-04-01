# Red Hat OpenShift AI 3.3 Demo

A production-like deployment of **Red Hat OpenShift AI (RHOAI) 3.3** on **Red Hat OpenShift Container Platform (RHOCP) 4.20** — covering Generative AI (LLMs, RAG, agentic workflows) and Predictive AI (computer vision, MLOps pipelines) on the same platform. Deployed using GitOps (ArgoCD + Kustomize), following Red Hat's official documentation and best practices.

Red Hat OpenShift AI is an MLOps platform that allows you to develop, train, and deploy AI models and applications at scale across private and hybrid cloud environments. This demo brings that value proposition to life across 14 deployment steps organized into three themes, each mapping to Red Hat's core AI pillars.

**Target audience:** Solution Architects, Platform Engineers, AI/ML Engineers evaluating Red Hat's AI platform.

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
| **MachineSets** | Declarative GPU node provisioning on AWS (g6.4xlarge, g6.12xlarge) | Step 01 |
| **Node Feature Discovery (NFD)** | Hardware labels for automatic GPU discovery and scheduling | Step 01 |
| **Operator Lifecycle Manager (OLM)** | Installation and upgrade of GPU Operator, Serverless, RHOAI, and all dependencies | Steps 01, 02 |
| **OpenShift Serverless** | KnativeServing infrastructure for KServe model serving networking | Step 01 |
| **Service Mesh 3** | Gateway and traffic management for the RHOAI Dashboard and KServe endpoints | Step 02 |
| **User Workload Monitoring** | Prometheus scraping for vLLM metrics, DCGM GPU telemetry, and TrustyAI metrics | Steps 01, 06, 12 |
| **OAuth / HTPasswd Identity Provider** | Demo user authentication (`ai-admin`, `ai-developer`) and RBAC | Step 03 |
| **Routes** | HTTPS endpoints for MinIO console, RAG chatbot, edge camera, Grafana, MCP servers | Steps 03, 06, 07, 10, 13, 13b |
| **BuildConfig / ImageStream** | On-cluster container builds for the RAG chatbot application | Step 07 |
| **OpenShift GitOps (ArgoCD)** | Declarative deployment of all 14 steps via GitOps — the deployment backbone | All steps |
| **OpenShift Pipelines (Tekton)** | ModelCar OCI image build and Git-driven edge model promotion | Step 12 |
| **MicroShift 4.20** | Edge-optimized Kubernetes distribution for real edge hardware deployment | Step 13b |

## Three Demo Themes

### Theme 1: Private AI Platform (Steps 01-04)

Transform a vanilla OpenShift cluster into a governed AI platform — GPU compute, hardware discovery, model governance, and multitenancy. As Red Hat's AI adoption guide notes: *"Can your current environment support AI workloads? This includes computing resources, storage, network capabilities, and the flexibility to scale as requirements grow."*

| Step | Capability | Highlights |
|------|-----------|------------|
| 01 | GPU Infrastructure | NFD, GPU Operator, Serverless, RHCL stack — the foundation |
| 02 | RHOAI Platform | DataScienceCluster, GenAI Studio, Hardware Profiles |
| 03 | Multitenancy | GPU-as-a-Service, MinIO storage, RBAC, demo personas |
| 04 | Model Governance | Model Registry + Model Catalog — discover, register, deploy |

### Theme 2: Generative AI — ACME Semiconductor (Steps 05-10)

Serve LLMs, build a RAG pipeline, add guardrails, connect MCP tools — an end-to-end agentic AI workflow grounded in enterprise documents. *"Much enterprise knowledge lives in documents scattered across the organization: PDFs, wikis, support tickets, and internal documentation. Connecting models to this knowledge is often a more efficient path to value."*

| Step | Capability | Highlights |
|------|-----------|------------|
| 05 | LLM Serving | Multiple models on vLLM, OCI ModelCar, Model Registry integration, GenAI Playground |
| 06 | Performance Monitoring | Grafana dashboards, GuideLLM benchmarks — operational SLO tracking for LLM inference |
| 07 | RAG Pipeline | pgvector, Docling ingestion, KFP pipelines, LlamaStack RAG chatbot |
| 08 | Model Evaluation | Pre/post RAG scoring (LLM-as-Judge), LM-Eval standard benchmarks |
| 09 | AI Safety | TrustyAI Guardrails: HAP detection, prompt injection, PII filtering |
| 10 | Agentic AI & MCP | Database, OpenShift, Slack MCP servers — autonomous tool orchestration |

### Theme 3: Predictive AI — WhoAmI Face Recognition (Steps 11-13)

Train a YOLO11 face recognition model, deploy on OpenVINO, automate the full MLOps lifecycle, and bring inference to the edge. *"Red Hat OpenShift AI allows training, deployment, and monitoring AI/ML workloads across various environments—cloud, on-premise datacenters, or at the edge."* This theme proves RHOAI handles both GenAI and traditional ML across datacenter and edge.

| Step | Capability | Highlights |
|------|-----------|------------|
| 11 | Computer Vision | YOLO11 ONNX on KServe + OpenVINO Model Server — CPU-only, no GPU needed |
| 12 | MLOps Pipeline | KFP v2: train → evaluate → register → deploy → monitor with TrustyAI drift detection |
| 13 | Edge AI | Phone camera app + edge inference — Red Hat Edge + On-Premise AI/ML pattern |
| 13b | Edge AI on MicroShift *(optional)* | Same model on real edge hardware — MicroShift 4.20, ModelCar OCI, NVIDIA L4 GPU |

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
