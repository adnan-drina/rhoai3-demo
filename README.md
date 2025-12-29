# Red Hat OpenShift AI 3.0 Demo

GitOps-driven demo for deploying **Red Hat OpenShift AI (RHOAI) 3.0** on OpenShift 4.20 using OpenShift GitOps (Argo CD) and Kustomize.

## Prerequisites

- OpenShift 4.20+ cluster (AWS)
- Cluster admin access
- `oc` CLI installed
- Git repository access (for GitOps)

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/adnan-drina/rhoai3-demo.git
cd rhoai3-demo

# 2. Configure environment
cp env.example .env
# Edit .env with your Git repository URL if forked

# 3. Login to OpenShift
oc login --token=<your-token> --server=<api-server>

# 4. Bootstrap GitOps (installs Argo CD)
./scripts/bootstrap.sh

# 5. Deploy Step 1: GPU Infrastructure & Prerequisites
./steps/step-01-gpu-and-prereq/deploy.sh

# 6. Deploy Step 2: RHOAI 3.0
./steps/step-02-rhoai/deploy.sh
```

## Demo Steps

| Step | Name | Description |
|------|------|-------------|
| 01 | [GPU Infrastructure](steps/step-01-gpu-and-prereq/README.md) | NFD, GPU Operator, Serverless, LWS, RHCL stack |
| 02 | [RHOAI 3.0](steps/step-02-rhoai/README.md) | RHOAI Operator, DataScienceCluster, GenAI Studio |
| 03 | [Private AI](steps/step-03-private-ai/README.md) | GPU-as-a-Service, Kueue, MinIO, User Auth |
| 04 | [Model Registry](steps/step-04-model-registry/README.md) | Enterprise model governance (registry + seed) |
| 05 | [LLM on vLLM](steps/step-05-llm-on-vllm/README.md) | GPU-as-a-Service model portfolio (KServe + vLLM) |
| 06 | [GenAI Playground](steps/step-06-private-ai-playground-maas/README.md) | GenAI Studio Playground via LlamaStackDistribution |
| 06B | [LiteMaaS (Experimental)](steps/step-06b-private-ai-litemaas/README.md) | LiteLLM + subscription UX (experimental) |
| 07 | [Model Performance Metrics](steps/step-07-model-performance-metrics/README.md) | Grafana + GuideLLM + benchmarking/pipelines |
| 07B | [GuideLLM vLLM Playground](steps/step-07b-guidellm-vllm-playground/README.md) | vLLM playground (future enhancement) |
| 08 | [Distributed Inference (llm-d)](steps/step-08-llm-d/README.md) | Distributed inference with llm-d — intelligent routing (2 replicas) |

## What Gets Deployed

### Step 1: GPU Infrastructure & RHOAI Prerequisites

- **User Workload Monitoring** - Metrics scraping for user projects
- **Node Feature Discovery (NFD)** - Hardware feature detection
- **NVIDIA GPU Operator** - GPU drivers, device plugin, DCGM metrics
- **OpenShift Serverless** - KnativeServing for KServe autoscaling
- **LeaderWorkerSet (LWS)** - Multi-node GPU orchestration for llm-d
- **Red Hat Connectivity Link (RHCL)** - AuthPolicy, rate limiting, DNS for inference gateway
- **Authorino/Limitador/DNS Operators** - RHCL component operators
- **GPU MachineSets** - AWS g6.4xlarge, g6.12xlarge instances

### Step 2: RHOAI 3.0 Platform

- **RHOAI Operator** (fast-3.x channel)
- **DSCInitialization** - Global operator configuration
- **DataScienceCluster** with components:
  - Dashboard, Workbenches
  - KServe, LlamaStackOperator
  - ModelRegistry, TrainingOperator
- **GenAI Studio** - Playground and Model Catalog UI
- **Auto-installed**: Service Mesh 3, Kueue

## Repository Structure

```
rhoai3-demo/
├── README.md                    # This file
├── env.example                  # Environment template
├── .env                         # Your config (gitignored)
│
├── scripts/
│   ├── bootstrap.sh             # Install OpenShift GitOps
│   └── lib.sh                   # Shared shell functions
│
├── gitops/
│   ├── argocd/
│   │   └── app-of-apps/         # Argo CD Application definitions
│   │       ├── step-01-gpu-and-prereq.yaml
│   │       ├── step-02-rhoai.yaml
│   │       ├── step-03-private-ai.yaml
│   │       ├── step-04-model-registry.yaml
│   │       ├── step-05-llm-on-vllm.yaml
│   │       ├── step-06-private-ai-playground-maas.yaml
│   │       ├── step-06b-private-ai-litemaas.yaml
│   │       ├── step-07-model-performance-metrics.yaml
│   │       ├── step-07b-guidellm-vllm-playground.yaml
│   │       └── step-08-llm-d.yaml
│   │
│   ├── step-01-gpu-and-prereq/  # GPU + prerequisites
│   │   └── base/
│   │
│   ├── step-02-rhoai/           # RHOAI 3.0 platform
│   │   └── base/
│   │
│   ├── step-03-private-ai/      # GPU-as-a-Service
│   │   ├── base/
│   │   └── gpu-as-a-service-demo/
│   │
│   └── step-04-model-registry/  # Model Registry (placeholder)
│       └── base/
│
└── steps/
    ├── step-01-gpu-and-prereq/
    │   ├── deploy.sh
    │   └── README.md
    │
    ├── step-02-rhoai/
    │   ├── deploy.sh
    │   └── README.md
    │
    ├── step-03-private-ai/
    │   ├── deploy.sh
    │   └── README.md
    │
    ├── step-04-model-registry/
    │   ├── deploy.sh
    │   └── README.md
    ├── step-05-llm-on-vllm/
    │   ├── deploy.sh
    │   └── README.md
    ├── step-06-private-ai-playground-maas/
    │   ├── deploy.sh
    │   └── README.md
    ├── step-06b-private-ai-litemaas/
    │   ├── deploy.sh
    │   └── README.md
    ├── step-07-model-performance-metrics/
    │   ├── deploy.sh
    │   └── README.md
    ├── step-07b-guidellm-vllm-playground/
    │   ├── deploy.sh
    │   └── README.md
    └── step-08-llm-d/
        ├── deploy.sh
        └── README.md
```

## Validation Commands

```bash
# Check Argo CD Applications
oc get applications -n openshift-gitops

# Check GPU nodes
oc get nodes -l node-role.kubernetes.io/gpu

# Check RHOAI status
oc get datasciencecluster default-dsc
oc get pods -n redhat-ods-applications

# Access RHOAI Dashboard
oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}'
```

## Documentation References

- [RHOAI 3.0 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [OpenShift 4.20 GPU Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)
- [NVIDIA GPU Operator on OpenShift](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.1/install-gpu-ocp.html)

## Adding a New Step

1. Create `gitops/step-XX-name/base/` with Kustomize manifests
2. Create `gitops/argocd/app-of-apps/step-XX-name.yaml`
3. Create `steps/step-XX-name/deploy.sh` and `README.md`
4. Validate: `kustomize build gitops/step-XX-name/base`
