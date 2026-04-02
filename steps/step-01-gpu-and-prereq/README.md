# Step 01: GPU Infrastructure & Prerequisites
**"AI-Ready Infrastructure"** — Transform a vanilla OpenShift 4.20 cluster into an AI-ready platform with GPU compute, hardware discovery, and the operator stack that RHOAI 3.3 depends on.

## Overview

Your organization is adopting AI on private infrastructure — both generative AI (LLMs, RAG, agentic workflows) and predictive AI (computer vision, MLOps pipelines). As Red Hat's AI adoption guide asks: *"Can your current environment support AI workloads? This includes computing resources, storage, network capabilities, and the flexibility to scale as requirements grow."* Before any model can be served, the cluster needs GPU-accelerated compute, hardware discovery, and the networking primitives that power inference.

**Red Hat OpenShift AI 3.3** provides intelligent GPU and hardware acceleration — self-service GPU access, intelligent GPU use for workload scheduling, and hardware discovery that automatically labels and provisions GPU resources. GPUs are *"specialized processors for handling parallel processing tasks, making them ideal for training deep learning models that require processing large amounts of data simultaneously"* — and this step ensures they are properly discovered, provisioned, and managed. The platform handles the full stack: driver lifecycle, GPU node management, and inference networking — all deployed via GitOps and managed as first-class OpenShift resources.

This step demonstrates RHOAI's **Intelligent GPU and hardware speed** capability: self-service GPU access, intelligent workload scheduling, and hardware discovery — the foundation that every AI workload above depends on.

### What Gets Deployed

```text
OpenShift 4.20 Cluster
├── NFD Operator          → Hardware labels for GPU discovery
├── NVIDIA GPU Operator   → Driver lifecycle (DTK, DCGM exporter)
├── GPU MachineSets       → g6.4xlarge (1×L4) + g6.12xlarge (4×L4) = 5 GPUs
├── OpenShift Serverless  → KnativeServing for KServe networking
└── User Workload Mon.    → Prometheus scraping for GPU telemetry
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| Node Feature Discovery | Hardware labels (PCI, kernel) for GPU Operator | `openshift-nfd` |
| NVIDIA GPU Operator v25.10 | Driver lifecycle via Driver Toolkit (DTK) | `nvidia-gpu-operator` |
| GPU MachineSets (AWS G6) | 1×g6.4xl + 1×g6.12xl = 5 NVIDIA L4 GPUs | `openshift-machine-api` |
| OpenShift Serverless | Knative infrastructure for KServe | `openshift-serverless` |
| User Workload Monitoring | Prometheus scraping for DCGM metrics | `openshift-monitoring` |

> **llm-d prerequisites (commented out):** LeaderWorkerSet, Authorino, Limitador, DNS Operator, and RHCL are defined in the kustomization file but commented out. They are prerequisites for the llm-d Inference Gateway, which is planned but not yet demonstrated. See [BACKLOG.md](../../BACKLOG.md).

> **AWS Quota:** Requires "Running On-Demand G and VT instances" >= 64 vCPU (16 + 48). Sandbox accounts default to 64.

Manifests: [`gitops/step-01-gpu-and-prereq/base/`](../../gitops/step-01-gpu-and-prereq/base/)

### Design Decisions

> **Default GPU driver (no pin):** RHOAI 3.3 AI Inference Server uses CUDA 13.0 (vLLM v0.13.0), which is compatible with GPU Operator 25.10's default driver 580.x. The CUDA 12.8 vs 13.0 conflict documented in [KB 7134740](https://access.redhat.com/solutions/7134740) no longer applies. Subscription uses `installPlanApproval: Automatic`.

> **Driver Toolkit over RHEL entitlements:** OCP 4.20 uses DTK for pre-compiled driver images, eliminating RHEL entitlement secrets on GPU nodes.

> **GPU node taints (`nvidia.com/gpu=true:NoSchedule`):** Reserves expensive GPU instances exclusively for workloads that explicitly request GPU resources.

> **RHCL stack for Inference Gateway (commented out):** Authorino, Limitador, DNS Operator, and RHCL provide the AuthPolicy CRD and networking primitives required by the llm-d Inference Gateway. These are defined in the kustomization file but commented out until llm-d distributed inference is added to the demo.

> **GPU MachineSet AZ auto-detection:** `deploy.sh` detects the availability zone from existing worker machinesets (`items[0].spec.template.spec.providerSpec.value.placement.availabilityZone`) rather than hardcoding `${REGION}b`. AWS sandbox clusters may only have subnets in a single AZ (e.g. `us-east-2a`), causing MachineSet creation to fail silently if the hardcoded AZ has no subnet.

> **ArgoCD `selfHeal: false`:** This step's ArgoCD Application uses `selfHeal: false` (unlike other steps) to allow operators to manually scale GPU MachineSets without ArgoCD reverting the change. ArgoCD shows OutOfSync for visibility but does not auto-heal. Git-triggered syncs still work. See the `manage-resources` skill for scaling workflows.

> **Custom ArgoCD health checks** (`bootstrap.sh`): Three custom Lua health checks are configured during bootstrap to fix ArgoCD misreporting:
> - **PersistentVolumeClaim** — Treats `Pending` PVCs as Healthy (for `WaitForFirstConsumer` storage classes that stay Pending until a pod mounts them)
> - **InferenceService** — Reads the KServe `Ready` condition correctly (ArgoCD's built-in check misinterprets the condition format)
> - **TrustyAIService** — Reads the `Available` condition (ArgoCD has no built-in health check for this CRD)

### Deploy

```bash
./steps/step-01-gpu-and-prereq/deploy.sh     # ArgoCD app: operators + GPU MachineSets
./steps/step-01-gpu-and-prereq/validate.sh   # Verify GPUs, operators, KnativeServing
```

### What to Verify After Deployment

| Check | What It Tests | Pass Criteria |
|-------|--------------|---------------|
| GPU nodes online | Two nodes with `nvidia.com/gpu` allocatable | 1 GPU + 4 GPUs |
| DCGM dashboard | GPU utilization, temperature, and memory | Visible in OpenShift Monitoring |
| All operators Succeeded | 8 CSVs across their respective namespaces | All Succeeded |
| KnativeServing Ready | Control plane healthy | Ready in `knative-serving` |

## The Demo

> In this demo, we verify that the OpenShift cluster has been transformed into an AI-ready platform — GPU nodes are online, drivers are active, and every operator prerequisite for RHOAI 3.3 is in place.

### GPU Nodes Online

> Before any model can be served, the cluster needs GPU compute. We start by confirming that the GPU nodes provisioned by the MachineSets are online and reporting their accelerator capacity to the scheduler.

1. Open the OpenShift Console → **Compute** → **Nodes**
2. Filter by label `nvidia.com/gpu.present=true`

**Expect:** Two GPU nodes — `g6.4xlarge` (1 GPU) and `g6.12xlarge` (4 GPUs). Both showing `Ready`.

> Five NVIDIA L4 GPUs across two node types, provisioned and tainted for AI workloads only. The taints ensure no accidental consumption — only workloads that explicitly request GPUs get scheduled here. This is Red Hat OpenShift AI's intelligent GPU management in action.

### Operator Stack

> GPU nodes are ready, but inference networking, distributed training, and model serving require additional platform capabilities. The RHOAI 3.3 installation guide defines eight operator prerequisites — we verify they are all deployed and healthy.

1. Navigate to **Operators** → **Installed Operators**
2. Filter by the GPU and AI-related namespaces

**Expect:** All operators showing `Succeeded` — NFD, GPU Operator, Serverless.

> Every operator prerequisite for RHOAI 3.3 model serving is deployed and healthy. This is the AI-ready foundation — GPU drivers and KServe networking — all managed via GitOps on Red Hat OpenShift Container Platform.

## Key Takeaways

**For business stakeholders:**

- GPU infrastructure is provisioned as code — no manual hardware requests, no ticket queues
- GPU nodes are tainted and isolated for AI workloads, preventing accidental consumption by non-AI applications
- The entire operator stack deploys via GitOps, making the AI platform reproducible across any OpenShift cluster

**For technical teams:**

- NVIDIA L4 GPUs run on AWS G6 instances with Driver Toolkit — no RHEL entitlement secrets required
- Three operator prerequisites are managed declaratively: NFD, GPU Operator, Serverless (llm-d stack available in kustomization when needed)
- Custom ArgoCD health checks ensure accurate sync status for PVCs, InferenceServices, and TrustyAI CRDs

## Troubleshooting

### GPU MachineSet stuck in Provisioning

**Symptom:** MachineSet shows desired replicas but machines remain in `Provisioning` state.

**Root Cause:** The hardcoded availability zone has no subnet in the sandbox cluster. AWS sandbox accounts may only have one AZ available.

**Solution:** `deploy.sh` auto-detects the AZ from existing worker MachineSets. If deploying manually, check available AZs:
```bash
oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.placement.availabilityZone}'
```

### GPU Operator InstallPlan stuck on Manual approval

**Symptom:** GPU Operator CSV not progressing, `oc get installplan` shows `RequiresApproval`.

**Solution:**
```bash
oc get installplan -n nvidia-gpu-operator -o name | xargs -I {} oc patch {} -n nvidia-gpu-operator --type merge -p '{"spec":{"approved":true}}'
```

### NVIDIA driver pods CrashLoopBackOff after cluster restart

**Symptom:** `nvidia-driver-daemonset` pods crash after a cluster stop/start cycle.

**Root Cause:** Driver container image cache may be stale after node reprovisioning.

**Solution:** Delete the driver pods to force re-pull:
```bash
oc delete pods -n nvidia-gpu-operator -l app=nvidia-driver-daemonset
```

## References

- [RHOAI 3.3 — Installing and Uninstalling](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [RHOAI 3.3 — Distributed Inference Dependencies](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-distributed-inference-dependencies)
- [OCP 4.20 — Understanding the Driver Toolkit](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/using-the-driver-toolkit)
- [OCP 4.20 — NVIDIA GPU Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)
- [NVIDIA GPU driver 580.105.08 compatibility (KB 7134740)](https://access.redhat.com/solutions/7134740)
- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet)
- [Get started with AI for enterprise organizations — Red Hat](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)

## Next Steps

- **Step 02**: [Red Hat OpenShift AI 3.3 Platform](../step-02-rhoai/README.md) — Install the full RHOAI platform with GenAI Studio, Hardware Profiles, and model serving
