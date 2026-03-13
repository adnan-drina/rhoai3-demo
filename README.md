# Red Hat OpenShift AI 3.3 Demo

A GitOps-driven demo for deploying **Red Hat OpenShift AI (RHOAI) 3.3** on OpenShift 4.20. Demonstrates adopting open-source LLMs on private infrastructure — from GPU provisioning through RAG, evaluation, guardrails, and enterprise tool orchestration via MCP — all managed by ArgoCD and Kustomize.

## Prerequisites

- OpenShift 4.20+ cluster (AWS)
- Cluster admin access
- `oc` CLI installed
- Git repository access (for GitOps)

## Quick Start

```bash
git clone https://github.com/adnan-drina/rhoai3-demo.git
cd rhoai3-demo

cp env.example .env    # Edit with your config

oc login --token=<your-token> --server=<api-server>

./scripts/bootstrap.sh                      # Install ArgoCD
./steps/step-01-gpu-and-prereq/deploy.sh    # GPU infrastructure
./steps/step-02-rhoai/deploy.sh             # RHOAI 3.3 platform
```

## Demo Steps

| Step | Name | Description |
|------|------|-------------|
| 01 | [GPU Infrastructure](steps/step-01-gpu-and-prereq/README.md) | NFD, GPU Operator, Serverless, LWS, RHCL, Kueue |
| 02 | [RHOAI 3.3](steps/step-02-rhoai/README.md) | RHOAI Operator, DataScienceCluster, GenAI Studio |
| 03 | [Private AI](steps/step-03-private-ai/README.md) | GPU-as-a-Service, Kueue quotas, MinIO, user auth |
| 04 | [Model Registry](steps/step-04-model-registry/README.md) | Enterprise model governance (registry + seed) |
| 05 | [LLM on vLLM](steps/step-05-llm-on-vllm/README.md) | Deploy 5 models, GPU swapping, GenAI Playground |
| 06 | [Model Metrics](steps/step-06-model-metrics/README.md) | Grafana dashboards, GuideLLM benchmarks, ROI analysis |
| 07 | [RAG](steps/step-07-rag/README.md) | pgvector, Docling, KFP pipelines, LlamaStack RAG |
| 08 | [Model Evaluation](steps/step-08-model-evaluation/README.md) | Pre/Post RAG evaluation with LLM-as-Judge |
| 09 | [Guardrails](steps/step-09-guardrails/README.md) | TrustyAI: HAP, prompt injection, PII detection |
| 10 | [MCP Integration](steps/step-10-mcp-integration/README.md) | Database, OpenShift, Slack MCP servers |

### Demo Narrative Arc

```
Foundation          → Data & AI         → Trust & Governance → Integration
(steps 01-05)         (steps 06-08)       (step 09)            (step 10)

GPU nodes +         Grafana metrics +   Guardrails:          MCP servers:
RHOAI platform +    RAG pipeline +      HAP, injection,      database, k8s,
model serving +     pre/post RAG        PII detection        Slack → 4-question
GPU-as-a-Service    evaluation                               E2E demo flow
```

## Repository Structure

```
rhoai3-demo/
├── scripts/
│   ├── bootstrap.sh              # Install OpenShift GitOps
│   └── lib.sh                    # Shared shell functions
├── gitops/
│   ├── argocd/app-of-apps/       # ArgoCD Application per step
│   ├── step-01-gpu-and-prereq/   # GPU + prerequisites
│   ├── step-02-rhoai/            # RHOAI 3.3 platform
│   ├── step-03-private-ai/       # GPU-as-a-Service
│   ├── step-04-model-registry/   # Model Registry
│   ├── step-05-llm-on-vllm/     # LLM serving
│   ├── step-06-model-metrics/    # Grafana + GuideLLM
│   ├── step-07-rag/              # pgvector, Docling, DSPA, LlamaStack
│   ├── step-08-model-evaluation/ # Eval configs (ConfigMaps)
│   ├── step-09-guardrails/       # TrustyAI Guardrails Orchestrator
│   └── step-10-mcp-integration/  # MCP servers
└── steps/
    └── step-XX-name/
        ├── deploy.sh             # ArgoCD deploy + validation
        ├── validate.sh           # Automated checks
        └── README.md             # Step documentation
```

## Validation

```bash
# ArgoCD applications
oc get applications -n openshift-gitops

# GPU nodes
oc get nodes -l node-role.kubernetes.io/gpu

# RHOAI status
oc get datasciencecluster default-dsc

# RHOAI Dashboard
oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='https://{.spec.host}'
```

## References

- [RHOAI 3.3 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [RHOAI 3.3 Working with Llama Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/)
- [OpenShift 4.20 GPU Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)
- [NVIDIA GPU Operator on OpenShift](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.1/install-gpu-ocp.html)

## Adding a New Step

1. Create `gitops/step-XX-name/base/` with Kustomize manifests
2. Create `gitops/argocd/app-of-apps/step-XX-name.yaml`
3. Create `steps/step-XX-name/deploy.sh` and `README.md`
4. Validate: `kustomize build gitops/step-XX-name/base`
