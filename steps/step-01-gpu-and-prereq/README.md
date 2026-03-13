# Step 01: GPU Infrastructure & Prerequisites

**Transform a vanilla OpenShift 4.20 cluster into an AI-ready platform with GPU compute, hardware discovery, and the operator stack that RHOAI 3.3 depends on.**

## The Business Story

ACME Corp is adopting open-source LLMs on private infrastructure. Before any model can be served, the cluster needs GPU-accelerated compute, hardware discovery, workload queuing, and the networking primitives that power distributed inference. This step provisions NVIDIA L4 GPU nodes on AWS and installs every operator prerequisite defined in the RHOAI 3.3 installation guide — turning bare metal into an AI platform foundation.

## What It Does

```
OpenShift 4.20 Cluster
├── NFD Operator          → Hardware labels for GPU discovery
├── NVIDIA GPU Operator   → Driver lifecycle (DTK, DCGM exporter)
├── GPU MachineSets       → g6.4xlarge (1×L4) + g6.12xlarge (4×L4) = 5 GPUs
├── OpenShift Serverless  → KnativeServing for KServe networking
├── LeaderWorkerSet       → Multi-node GPU orchestration for llm-d
├── RHCL Stack            → Authorino, Limitador, DNS, RHCL (Inference Gateway)
├── Kueue Operator        → GPU quota management and workload queuing
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
| Kueue | Workload queuing and GPU quota management | `openshift-kueue-operator` |
| User Workload Monitoring | Prometheus scraping for DCGM metrics | `openshift-monitoring` |

> **AWS Quota:** Requires "Running On-Demand G and VT instances" >= 64 vCPU (16 + 48). Sandbox accounts default to 64.

## What to Verify After Deployment

- **GPU nodes online** — two nodes with `nvidia.com/gpu` allocatable (1 GPU + 4 GPUs)
- **DCGM dashboard** — GPU utilization, temperature, and memory visible in OpenShift Monitoring
- **All operators Succeeded** — 10 CSVs across their respective namespaces
- **KnativeServing Ready** — control plane healthy in `knative-serving`
- **Kueue instance** — `oc get kueue cluster` shows the singleton

## Design Decisions

> **Driver pinned to 570.195.03 (pending re-validation):** GPU Operator 25.10 ships driver 580.105.08 with CUDA 13.0. RHOAI 3.3 AI Inference Server now also uses CUDA 13.0 (vLLM v0.13.0), so the conflict documented in [KB 7134740](https://access.redhat.com/solutions/7134740) may be resolved. We retain the pin and `installPlanApproval: Manual` until validated on a fresh cluster. Once confirmed, remove the pin and switch to `Automatic` approval.

> **Driver Toolkit over RHEL entitlements:** OCP 4.20 uses DTK for pre-compiled driver images, eliminating RHEL entitlement secrets on GPU nodes.

> **GPU node taints (`nvidia.com/gpu=true:NoSchedule`):** Reserves expensive GPU instances exclusively for workloads that explicitly request GPU resources.

> **RHCL stack for Inference Gateway:** Authorino, Limitador, DNS Operator, and RHCL provide the AuthPolicy CRD and networking primitives required by the llm-d Inference Gateway in step-05.

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
