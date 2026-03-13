# Red Hat OpenShift AI 3.3 Demo

Adopting open-source LLMs on private infrastructure — from GPU provisioning through RAG, evaluation, guardrails, and enterprise tool orchestration. All managed by ArgoCD and Kustomize on **OpenShift 4.20**.

## The Demo Story

This demo walks through the **four pillars of enterprise AI** in 10 progressive steps:

| Pillar | Steps | What You Show |
|--------|-------|---------------|
| **Flexible Foundation** | 01-05 | GPU infrastructure, RHOAI platform, GPU-as-a-Service queuing, model registry, model serving with live swapping |
| **Data & AI Integration** | 06-08 | Performance benchmarks with ROI analysis, RAG pipeline with pgvector, pre/post RAG evaluation |
| **Trust & Governance** | 09 | Guardrails: hate speech, prompt injection, PII detection |
| **Integration & Automation** | 10 | MCP servers: database queries, cluster inspection, Slack notifications — the 4-question E2E flow |

### The Climax: 4-Question E2E Demo (Step 10)

The demo builds to a single agentic conversation where the AI:
1. Inspects an OpenShift cluster and finds a failing pod
2. Queries a database to identify the equipment
3. Searches RAG documents for known issues
4. Sends a Slack notification to the platform team

## Quick Start

```bash
git clone https://github.com/adnan-drina/rhoai3-demo.git && cd rhoai3-demo
cp env.example .env              # Edit with your config
oc login --token=<token> --server=<api>
./scripts/bootstrap.sh           # Install ArgoCD
```

Then deploy each step in order:

```bash
./steps/step-01-gpu-and-prereq/deploy.sh
./steps/step-02-rhoai/deploy.sh
# ... through step-10
```

## Demo Steps

| Step | Name | Demo Highlight |
|------|------|----------------|
| 01 | [GPU Infrastructure](steps/step-01-gpu-and-prereq/README.md) | GPU nodes online, DCGM monitoring |
| 02 | [RHOAI 3.3 Platform](steps/step-02-rhoai/README.md) | Dashboard, GenAI Studio, Hardware Profiles |
| 03 | [Private AI](steps/step-03-private-ai/README.md) | **GPU queuing demo** — workloads queue when capacity is full |
| 04 | [Model Registry](steps/step-04-model-registry/README.md) | **Gatekeeper pattern** — 48+ models, RBAC access control |
| 05 | [LLM on vLLM](steps/step-05-llm-on-vllm/README.md) | **Model swapping** — live GPU reallocation + GenAI Playground |
| 06 | [Model Metrics](steps/step-06-model-metrics/README.md) | **ROI of Quantization** — Grafana dashboards, INT4 vs BF16 |
| 07 | [RAG Pipeline](steps/step-07-rag/README.md) | **RAG Chatbot** — pgvector, Docling ingestion, agent mode |
| 08 | [Model Evaluation](steps/step-08-model-evaluation/README.md) | **Pre/Post RAG** — hallucination vs grounded answers |
| 09 | [Guardrails](steps/step-09-guardrails/README.md) | **Safety shields** — HAP, injection, PII detection live |
| 10 | [MCP Integration](steps/step-10-mcp-integration/README.md) | **4-question E2E** — database + k8s + RAG + Slack in one flow |

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
