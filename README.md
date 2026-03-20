# Red Hat OpenShift AI 3.3 Demo

A production-like deployment of **AI on Red Hat OpenShift AI (RHOAI) 3.3** on **Red Hat OpenShift Container Platform (RHOCP) 4.20** — covering Generative AI (LLMs, RAG, agentic workflows) and Predictive AI (computer vision, MLOps pipelines) on the same platform. Deployed using GitOps (ArgoCD + Kustomize), following Red Hat's official documentation and best practices.

**Target audience:** Solution Architects, Platform Engineers, AI/ML Engineers evaluating Red Hat's AI platform.

## Three Demo Themes

### Theme 1: Private AI Platform (Steps 01-04)

Transform a vanilla OpenShift cluster into a governed AI platform — GPU compute, hardware discovery, model governance, and multitenancy.

| Step | Capability | Highlights |
|------|-----------|------------|
| 01 | GPU Infrastructure | NFD, GPU Operator, Serverless, RHCL stack — the foundation |
| 02 | RHOAI Platform | DataScienceCluster, GenAI Studio, Hardware Profiles |
| 03 | Multitenancy | GPU-as-a-Service, MinIO storage, RBAC, demo personas |
| 04 | Model Governance | Model Registry + Model Catalog — discover, register, deploy |

### Theme 2: Generative AI — ACME Semiconductor (Steps 05-10)

Serve LLMs, build a RAG pipeline, add guardrails, connect MCP tools — an end-to-end agentic AI workflow grounded in enterprise documents.

| Step | Capability | Highlights |
|------|-----------|------------|
| 05 | LLM Serving | Multiple models on vLLM, OCI ModelCar, Model Registry integration, GenAI Playground |
| 06 | Performance Monitoring | Grafana dashboards, GuideLLM benchmarks — operational SLO tracking for LLM inference |
| 07 | RAG Pipeline | pgvector, Docling ingestion, KFP pipelines, LlamaStack RAG chatbot |
| 08 | Model Evaluation | Pre/post RAG scoring (LLM-as-Judge), LM-Eval standard benchmarks |
| 09 | AI Safety | TrustyAI Guardrails: HAP detection, prompt injection, PII filtering |
| 10 | Agentic AI & MCP | Database, OpenShift, Slack MCP servers — autonomous tool orchestration |

### Theme 3: Predictive AI — WhoAmI Face Recognition (Steps 11-12)

Train a YOLO11 face recognition model, deploy on OpenVINO, and automate the full MLOps lifecycle — proving RHOAI handles both GenAI and traditional ML.

| Step | Capability | Highlights |
|------|-----------|------------|
| 11 | Computer Vision | YOLO11 ONNX on KServe + OpenVINO Model Server — CPU-only, no GPU needed |
| 12 | MLOps Pipeline | KFP v2: train → evaluate → register → deploy → monitor with TrustyAI drift detection |

## E2E Scenarios

### ACME Semiconductor (GenAI — Steps 07-10)

The agentic model autonomously resolves an equipment alert using four integrated tools:

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
./scripts/bootstrap.sh           # Install ArgoCD + AppProject
```

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

## Demo Credentials

| Username | Password | Role |
|----------|----------|------|
| `ai-admin` | `redhat123` | Service Governor (RHOAI Admin) |
| `ai-developer` | `redhat123` | Service Consumer (RHOAI User) |
| MinIO Console | `minio-admin` / `minio-secret-123` | S3 storage admin |

## References

- [RHOAI 3.3 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/)
- [RHOAI 3.3 Working with Llama Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/)
- [OpenShift 4.20 GPU Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)
- [Red Hat AI Validated Models](https://docs.redhat.com/en/documentation/red_hat_ai/3/html-single/validated_models/index)
