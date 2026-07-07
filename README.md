# Building a Private AI Platform on Red Hat OpenShift AI

A GitOps-managed, GPU-accelerated enterprise AI infrastructure on
**Red Hat OpenShift AI 3.4** and **OpenShift Container Platform 4.20** —
assembled stage by stage from governed GPU compute through model serving,
retrieval-augmented generation, safety guardrails, and standardized evaluation.

**Target audience:** Platform Architects, AI/ML Engineers, and Solution
Architects evaluating Red Hat's AI platform for enterprise generative AI.

## Platform Stack

| Component | Version |
|-----------|---------|
| Red Hat OpenShift AI Self-Managed | 3.4 |
| OpenShift Container Platform | 4.20 |
| OpenShift Data Foundation | 4.20 |
| Red Hat Connectivity Link (Kuadrant) | 1.3.4 |

## Demo Stages

The platform is assembled incrementally. Each stage is a self-contained
Argo CD Application — auditable, repeatable, and rollback-ready from a single
Git commit.

### Foundation (1xx)

| Stage | Capability | Highlights |
|-------|-----------|------------|
| [110](stage-110-rhoai-base-platform/) | Base Platform | RHOAI operator, ODF Multicloud Object Gateway, Argo CD GitOps, RBAC, Model Registry |
| [120](stage-120-gpu-as-a-service/) | GPU-as-a-Service | NFD, NVIDIA GPU Operator, Kueue quota management, Hardware Profiles |

### Generative AI (2xx)

| Stage | Capability | Highlights |
|-------|-----------|------------|
| [210](stage-210-model-serving-foundation/) | Model Serving | KServe + vLLM, Nemotron 3 Nano 30B on L4 GPU, Grafana LLM dashboards, GuideLLM benchmarks |
| [220](stage-220-models-as-a-service/) | Models-as-a-Service | MaaS Gateway API, Kuadrant AuthPolicy, API key governance, GPT-4o-mini proxy, GenAI Playground |
| [230](stage-230-private-data-rag/) | Private Data RAG | Llama Stack / OGX, Milvus vector DB, Docling pipelines, AutoRAG optimization, RHOAI product docs corpus |
| [240](stage-240-guardrails-and-safety/) | Guardrails & Safety | TrustyAI NeMo Guardrails, prompt injection detection, PII filtering, topic control |
| [250](stage-250-model-evaluation/) | Model Evaluation | Garak vulnerability scans, OWASP LLM Top 10, guard-vs-prove delta analysis |

## What You Need

- OpenShift 4.20+ cluster (AWS recommended)
- 1x GPU worker node (NVIDIA L4, 24 GB VRAM)
- Cluster admin access
- `oc` CLI installed

## Quick Start

```bash
git clone https://github.com/adnan-drina/rhoai3-demo.git && cd rhoai3-demo
cp env.example .env              # Set RHOAI_EXPECTED_API_SERVER
oc login --token=<token> --server=<api>

# Deploy stage by stage
./stage-110-rhoai-base-platform/deploy.sh
./stage-120-gpu-as-a-service/deploy.sh
./stage-210-model-serving-foundation/deploy.sh
./stage-220-models-as-a-service/deploy.sh
./stage-230-private-data-rag/deploy.sh
./stage-240-guardrails-and-safety/deploy.sh
./stage-250-model-evaluation/deploy.sh
```

Validate any stage:

```bash
./stage-110-rhoai-base-platform/validate.sh
```

## GitOps Architecture

- **Stage-based deployment** — each `deploy.sh` applies its Argo CD Application,
  giving control over ordering and runtime setup between syncs.
- **`targetRevision: main`** — single trunk is the GitOps source of truth.
- **Annotation-based tracking** — Argo CD uses `resourceTrackingMethod: annotation`
  to avoid label conflicts with operator-managed resources.
- **Fork-friendly** — update `repoURL` in `gitops/argocd/app-of-apps/` for your fork.

## Presentation

An interactive HTML deck covering all stages is available at
[`docs/assets/rhoai-platform-overview.html`](docs/assets/rhoai-platform-overview.html) —
open in any browser, navigate with arrow keys.

## References

- [RHOAI 3.4 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/)
- [OpenShift 4.20 Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/)
- [OpenShift Data Foundation 4.20](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.20/)
- [Platform Baseline](docs/PLATFORM_BASELINE.md) — version-pinned doc links
