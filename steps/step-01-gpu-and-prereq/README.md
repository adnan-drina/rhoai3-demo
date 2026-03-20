# Step 01: GPU Infrastructure & Prerequisites

**Transform a vanilla OpenShift 4.20 cluster into an AI-ready platform with GPU compute, hardware discovery, and the operator stack that RHOAI 3.3 depends on.**

## The Business Story

Your organization is adopting AI on private infrastructure — both generative AI (LLMs, RAG, agentic workflows) and predictive AI (computer vision, MLOps pipelines). Before any model can be served, the cluster needs GPU-accelerated compute, hardware discovery, and the networking primitives that power inference. This step provisions NVIDIA L4 GPU nodes on AWS and installs every operator prerequisite defined in the RHOAI 3.3 installation guide — turning a vanilla OpenShift cluster into an AI platform foundation.

## What It Does

```text
OpenShift 4.20 Cluster
├── NFD Operator          → Hardware labels for GPU discovery
├── NVIDIA GPU Operator   → Driver lifecycle (DTK, DCGM exporter)
├── GPU MachineSets       → g6.4xlarge (1×L4) + g6.12xlarge (4×L4) = 5 GPUs
├── OpenShift Serverless  → KnativeServing for KServe networking
├── LeaderWorkerSet       → Multi-node GPU orchestration for llm-d
├── RHCL Stack            → Authorino, Limitador, DNS, RHCL (Inference Gateway)
└── User Workload Mon.    → Prometheus scraping for GPU telemetry
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| Node Feature Discovery | Hardware labels (PCI, kernel) for GPU Operator | `openshift-nfd` |
| NVIDIA GPU Operator v25.10 | Driver lifecycle via Driver Toolkit (DTK) | `nvidia-gpu-operator` |
| GPU MachineSets (AWS G6) | 1×g6.4xl + 1×g6.12xl = 5 NVIDIA L4 GPUs | `openshift-machine-api` |
| OpenShift Serverless | Knative infrastructure for KServe | `openshift-serverless` |
| LeaderWorkerSet (LWS) | Multi-node GPU orchestration for llm-d | `openshift-lws-operator` |
| Authorino + Limitador | AuthZ and rate limiting for Inference Gateway | `openshift-authorino` / `openshift-limitador-operator` |
| DNS Operator + RHCL | Endpoint DNS and AuthPolicy CRD for llm-d | `openshift-dns-operator` / `rhcl-operator` |
| User Workload Monitoring | Prometheus scraping for DCGM metrics | `openshift-monitoring` |

> **AWS Quota:** Requires "Running On-Demand G and VT instances" >= 64 vCPU (16 + 48). Sandbox accounts default to 64.

Manifests: [`gitops/step-01-gpu-and-prereq/base/`](../../gitops/step-01-gpu-and-prereq/base/)

## What to Verify After Deployment

- **GPU nodes online** — two nodes with `nvidia.com/gpu` allocatable (1 GPU + 4 GPUs)
- **DCGM dashboard** — GPU utilization, temperature, and memory visible in OpenShift Monitoring
- **All operators Succeeded** — 8 CSVs across their respective namespaces
- **KnativeServing Ready** — control plane healthy in `knative-serving`

## Demo Walkthrough

### Scene 1: GPU Nodes Online

**Do:** Open the OpenShift Console → **Compute** → **Nodes**. Filter by label `nvidia.com/gpu.present=true`.

**Expect:** Two GPU nodes — `g6.4xlarge` (1 GPU) and `g6.12xlarge` (4 GPUs). Both showing `Ready`.

*"The cluster now has 5 NVIDIA L4 GPUs across two node types. The taints ensure only AI workloads that explicitly request GPUs get scheduled here — no accidental consumption."*

### Scene 2: Operator Stack

**Do:** Navigate to **Operators** → **Installed Operators**. Filter by the GPU and AI-related namespaces.

**Expect:** All operators showing `Succeeded` — NFD, GPU Operator, Serverless, LeaderWorkerSet, Authorino, Limitador, DNS Operator, RHCL.

*"Every operator prerequisite from the RHOAI 3.3 installation guide is deployed and healthy. This is the foundation — GPU drivers, KServe networking, and the RHCL stack for distributed inference."*

## Design Decisions

> **Default GPU driver (no pin):** RHOAI 3.3 AI Inference Server uses CUDA 13.0 (vLLM v0.13.0), which is compatible with GPU Operator 25.10's default driver 580.x. The CUDA 12.8 vs 13.0 conflict documented in [KB 7134740](https://access.redhat.com/solutions/7134740) no longer applies. Subscription uses `installPlanApproval: Automatic`.

> **Driver Toolkit over RHEL entitlements:** OCP 4.20 uses DTK for pre-compiled driver images, eliminating RHEL entitlement secrets on GPU nodes.

> **GPU node taints (`nvidia.com/gpu=true:NoSchedule`):** Reserves expensive GPU instances exclusively for workloads that explicitly request GPU resources.

> **RHCL stack for Inference Gateway:** Authorino, Limitador, DNS Operator, and RHCL provide the AuthPolicy CRD and networking primitives required by the llm-d Inference Gateway in step-05.

> **GPU MachineSet AZ auto-detection:** `deploy.sh` detects the availability zone from existing worker machinesets (`items[0].spec.template.spec.providerSpec.value.placement.availabilityZone`) rather than hardcoding `${REGION}b`. AWS sandbox clusters may only have subnets in a single AZ (e.g. `us-east-2a`), causing MachineSet creation to fail silently if the hardcoded AZ has no subnet.

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

## Operations

Deploy: `./steps/step-01-gpu-and-prereq/deploy.sh` · Validate: `./steps/step-01-gpu-and-prereq/validate.sh`

## Next Steps

Proceed to [Step 02: Red Hat OpenShift AI 3.3 Platform](../step-02-rhoai/README.md) to deploy the RHOAI operator and configure the DataScienceCluster.
