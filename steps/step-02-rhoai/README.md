# Step 02: Red Hat OpenShift AI 3.3 Platform

**Install the full RHOAI 3.3 AI platform — GenAI Studio, Hardware Profiles, model serving, distributed training, and governance — on a fresh OpenShift cluster.**

## The Business Story

RHOAI 3.3 is a new-installation-only release with no upgrade path from 2.x. It replaces Accelerator Profiles with Hardware Profiles, introduces GenAI Studio (Agent Playground + Model Catalog), renames `datasciencepipelines` to `aipipelines`, and moves group management from `OdhDashboardConfig` to a dedicated Auth resource. This step deploys the full platform on top of the GPU infrastructure from step-01, giving data scientists a self-service AI environment with built-in model serving, training, and governance.

## What It Does

```
RHOAI 3.3 Platform
├── RHOAI Operator         → stable-3.x channel, manages all components
├── DSCInitialization      → Service Mesh 3 auto-installed
├── DataScienceCluster     → Full component stack (see table)
├── GenAI Studio           → Agent Playground + Model Catalog UI
├── Hardware Profiles      → GPU/CPU profiles with Kueue scheduling
└── Kueue Integration      → Dashboard integration (operator from step-01)
```

| Component | State | Purpose |
|-----------|-------|---------|
| Dashboard | Managed | RHOAI web console |
| Workbenches | Managed | Jupyter notebooks, VS Code, RStudio |
| AI Pipelines | Managed | ML Pipelines (formerly `datasciencepipelines`) |
| LlamaStack Operator | Managed | GenAI Playground, agentic workflows |
| GenAI Studio | Enabled | Agent Playground + Model Catalog UI |
| KServe | Managed | Model serving (RawDeployment mode) |
| Model Registry | Managed | Model versioning and catalog |
| Training Operator | Managed | Kubernetes-native distributed training |
| Ray | Managed | Distributed computing framework |
| TrustyAI | Managed | Explainability, bias detection, drift monitoring |
| Feast Operator | Managed | Feature store for ML features |
| Kueue | **Unmanaged** | Standalone operator from step-01 |

**Hardware Profiles** (global, in `redhat-ods-applications`):

| Profile | Display Name | Scheduling |
|---------|-------------|------------|
| cpu-small | Small (CPU Only) | Node (direct) |
| default-profile | NVIDIA L4 1GPU (Default) | Queue → `default` |
| nvidia-l4-1gpu | NVIDIA L4 1GPU | Queue → `default` |
| nvidia-l4-4gpu | NVIDIA L4 4GPUs | Queue → `default` |

## What to Verify After Deployment

- **Dashboard URL** — RHOAI console accessible at `https://rhods-dashboard-redhat-ods-applications.<cluster>`
- **GenAI Studio visible** — Agent Playground and Model Catalog appear in the left nav
- **Hardware Profiles available** — four profiles (CPU Small, L4 1GPU, L4 1GPU Default, L4 4GPU) listed in Settings
- **DataScienceCluster Ready** — `default-dsc` phase is `Ready` with all components managed
- **Service Mesh 3** — auto-installed by DSCInitialization for KServe traffic management

## Design Decisions

> **Kueue as standalone operator (RHOAI 3.3 recommended):** The DSC sets `kueue.managementState: Unmanaged` because Kueue is installed as the Red Hat Build of Kueue Operator in step-01. The embedded Kueue component is deprecated since RHOAI 2.24 — the standalone operator is the official path. A `Kueue` component CR plus `disableKueue: false` in `OdhDashboardConfig` provides Dashboard integration. Ref: [Installing distributed workloads components](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-distributed-workloads-components_install).

> **GPU profiles use Queue scheduling, CPU uses Node:** GPU Hardware Profiles use `scheduling.type: Queue` so Kueue governs GPU allocation via ClusterQueue quotas. The CPU-only profile (`cpu-small`) uses direct Node scheduling — CPU workloads don't need GPU quota management and shouldn't be gated by Kueue. Each user project needs a `LocalQueue` named `default` for GPU profiles (created in step-03).

> **Two ClusterQueues for resource reservation:** `rhoai-main-queue` (5 GPUs for vLLM) and `rhoai-llmd-queue` (2 GPUs reserved for llm-d). This follows the RHOAI pattern of hardware-specific quota separation — llm-d always has guaranteed capacity even when vLLM workloads saturate the main queue.

> **GenAI Studio enabled by default:** `genAiStudio: true` in `OdhDashboardConfig` plus `llamastackoperator: Managed` in the DSC activate the Agent Playground and Model Catalog for all users.

## References

- [RHOAI 3.3 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/release_notes/index)
- [RHOAI 3.3 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [Installing Distributed Workloads Components](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-distributed-workloads-components_install)
- [Configuring Hardware Profiles](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/working_with_accelerators/index#working-with-hardware-profiles)
- [Managing Workloads with Kueue](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_openshift_ai/managing-workloads-with-kueue)

## Operations

Deploy: `./steps/step-02-rhoai/deploy.sh` · Validate: `./steps/step-02-rhoai/validate.sh`

## Next Steps

Continue to [Step 03 — Private AI Infrastructure](../step-03-private-ai/README.md) to configure Kueue queues, resource flavors, and per-project LocalQueues.
