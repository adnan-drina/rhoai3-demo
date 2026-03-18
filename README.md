# Red Hat OpenShift AI 3.3 Demo

A production-like deployment of **Generative AI on Red Hat OpenShift AI (RHOAI) 3.3** on **Red Hat OpenShift Container Platform (RHOCP) 4.20**, demonstrating each platform component following Red Hat's best practices and official documentation. Deployed using GitOps (ArgoCD + Kustomize).

**Target audience:** Solution Architects, Platform Engineers, AI Engineers evaluating Red Hat's AI platform.

## What This Demo Proves

Each step introduces a core RHOAI capability, deployed the way Red Hat recommends for production environments. The ACME Semiconductor scenario serves as a practical example of how these components work together in an end-to-end agentic workflow.

| Step | RHOAI Capability | What You See | Ref |
|------|-----------------|--------------|-----|
| 01 | **GPU Infrastructure** | NFD, GPU Operator, Serverless, RHCL — the foundation for AI workloads | [Installing RHOAI dependencies](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-distributed-inference-dependencies) |
| 02 | **RHOAI Platform** | DataScienceCluster, GenAI Studio, Hardware Profiles — the AI platform layer | [Installing RHOAI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index) |
| 03 | **Multitenancy & GPU-as-a-Service** | Projects, users, GPU scheduling, MinIO storage, RBAC — governed resource sharing | [Managing OpenShift AI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_openshift_ai/) |
| 04 | **Model Governance** | Model Registry with seed job, RBAC, Model Catalog — the gatekeeper pattern | [Managing model registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/managing_model_registries/index) |
| 05 | **LLM Serving on vLLM** | 5 models with GPU scheduling via nodeSelector, live GPU swapping, GenAI Playground | [Deploying models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/) |
| 06 | **Performance Monitoring** | Grafana dashboards, GuideLLM benchmarks, ROI analysis (INT4 vs BF16) | [Managing and monitoring models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_and_monitoring_models/index) |
| 07 | **RAG with LlamaStack** | pgvector, Docling ingestion, KFP pipelines, LlamaStack RAG backend | [Deploying a RAG stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/deploying-a-rag-stack-in-a-project_rag) |
| 08 | **Model Evaluation** | Pre/post RAG scoring (LLM-as-Judge), LM-Eval standard benchmarks, HTML reports in MinIO | [Evaluating AI systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/) |
| 09 | **AI Safety & Guardrails** | TrustyAI: HAP detection, prompt injection, PII filtering — CPU-only | [Enabling AI safety with guardrails](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/enabling_ai_safety_with_guardrails/) |
| 10 | **Agentic AI & MCP** | Database, OpenShift, Slack MCP servers — autonomous tool orchestration | [Configuring MCP servers](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user) |
| 11 | **Predictive AI / Computer Vision** | YOLO11 face recognition, KServe + OpenVINO Model Server — traditional ML workloads | [Deploying models (KServe RawDeployment)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/) |
| 12 | **MLOps Training Pipeline** | KFP v2 pipeline: train, evaluate, register in Model Registry, deploy — automated ML lifecycle | [Working with AI Pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_ai_pipelines/) |

## The E2E Scenario: ACME Semiconductor

Steps 07-10 come together in a practical example where `granite-8b-agent` autonomously:
1. **Inspects the cluster** — finds a failing equipment pod via OpenShift MCP
2. **Queries a database** — identifies the equipment (L-900-08 EUV Scanner) via Database MCP
3. **Searches internal docs** — finds the DFO calibration procedure via RAG
4. **Sends an alert** — notifies the platform team via Slack MCP

## What You Need

- OpenShift 4.20+ cluster on AWS
- 1x g6.4xlarge (1 GPU) + 1x g6.12xlarge (4 GPU) — 5 GPUs total
- Cluster admin access
- `oc` CLI installed

## Quick Start

```bash
git clone https://github.com/adnan-drina/rhoai3-demo.git && cd rhoai3-demo
cp env.example .env              # Edit with your config
oc login --token=<token> --server=<api>
./scripts/bootstrap.sh           # Install ArgoCD
```

Deploy each step in order:
```bash
./steps/step-01-gpu-and-prereq/deploy.sh
./steps/step-02-rhoai/deploy.sh
# ... through step-10
```

Validate the full demo:
```bash
./scripts/validate-demo-flow.sh   # 4-question E2E test
```

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
