# Stage 120: GPU-as-a-Service

**Theme:** AI Platform Foundation
**Concept:** Turn scarce, expensive GPU hardware into governed, self-service capacity — data scientists request GPUs through simple hardware profiles, and Kueue handles admission, quota, fair-share, and priority underneath.

---

## Why This Matters

**GPUs are the scarcest, most expensive resource in any AI platform.** A single accelerator node costs more per hour than a rack of CPU workers, and demand always exceeds supply. The naive answers — first-come-first-served, manual booking spreadsheets, or static per-team reservations — either leave expensive silicon idle or block the work that matters most. Enterprises need GPUs to behave like a *managed shared service*: every team gets fair access, critical jobs can jump the queue, and reserved capacity is honored without a human in the loop.

**Self-service without governance is chaos; governance without self-service is a ticket queue.** The platform has to give data scientists a one-click "give me a GPU" experience while the platform team retains control over *who* gets *how much*, *when*, and *at what priority*. That is exactly the gap Kueue fills: it is a Kubernetes-native job queueing and quota system that admits workloads against declared quotas, lends idle capacity between teams, and preempts lower-priority work when a high-priority job arrives.

**Red Hat OpenShift AI makes this consumable.** Raw Kueue queues and GPU resource accounting are powerful but low-level. RHOAI **hardware profiles** wrap a queue and a resource shape into a named choice a user simply selects when creating a workbench or deploying a model — "GPU Shared," "GPU Priority," "GPU Reserved." The complexity (ResourceFlavors, ClusterQueues, cohorts, priorities, node placement, tolerations) stays with the platform team, expressed as GitOps.

---

## What Enables It

This stage builds the GPU-as-a-Service stack on top of the stage-110 base platform.

### GPU capacity (NFD + NVIDIA GPU Operator)

- **Node Feature Discovery (NFD)** labels nodes with their hardware features so the GPU operator knows where GPUs live.
- **NVIDIA GPU Operator** installs drivers, the container toolkit, and the device plugin that exposes GPUs to Kubernetes as the `nvidia.com/gpu` resource, governed by an NVIDIA `ClusterPolicy`.
- **GPU node:** an AWS `g6e.2xlarge` worker (1× NVIDIA **L40S**, 48 GB), provisioned by a Git-tracked MachineSet derived from a live worker MachineSet.

### GPU time-slicing — sharing one card across many users

A single physical GPU can only be allocated to one pod at a time by default. **Time-slicing** tells the NVIDIA device plugin to advertise each physical GPU as several *schedulable replicas* — here, **1 L40S → 4 `nvidia.com/gpu` units**. The GPU's compute is then interleaved (time-shared) across the pods that land on those replicas.

This is what makes the four-queue demo possible on one card: the four queues draw from a pool of 4 GPU units instead of fighting over 1. Time-slicing trades isolation for density — it shares compute without memory partitioning — which is ideal for demos, development, and bursty inference, and is the documented entry point before MIG-based hardware partitioning.

- NVIDIA GPU Operator — GPU sharing / time-slicing: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html
- Red Hat OpenShift AI 3.4 — working with accelerators: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_accelerators/

### Workload management (Red Hat build of Kueue)

- **Red Hat build of Kueue** (a standalone operator; cert-manager is a prerequisite) provides admission, quota, borrowing, and priority. RHOAI integrates with it by setting the `DataScienceCluster` `kueue` component to **`Unmanaged`** (the embedded `Managed` Kueue is deprecated).
- **Quota objects:** one CPU and one GPU `ResourceFlavor`, four `ClusterQueue`s, four `LocalQueue`s, and a `WorkloadPriorityClass`. The GPU node placement (node label + taint toleration) lives in the GPU ResourceFlavor — Kueue-enabled hardware profiles intentionally carry no node selectors.
- Docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_resources/

### The four queue experiences

| Hardware profile | Queue | GPU quota | Behavior |
|---|---|---|---|
| **CPU Default** | `cq-cpu-default` | none | Everyone can start CPU-only workbenches |
| **GPU Shared – 1× NVIDIA** | `cq-gpu-shared` | 2 (low priority, borrowable) | Request a GPU when shared capacity is free |
| **GPU Priority – 1× NVIDIA** | `cq-gpu-priority` | 1 (high priority, preempts) | Critical jobs jump the queue |
| **GPU Reserved – Demo Team** | `cq-gpu-reserved-demo` | 1 (no lending) | Reserved team quota, no booking app |

Shared and Priority share a cohort, so they can borrow idle capacity from each other and Priority can preempt Shared; Reserved is isolated to simulate a true reservation. Quotas sum to the 4 time-sliced units.

### Model serving (KServe)

- **KServe** is enabled on the stage-110 `DataScienceCluster` (`kserve: Managed`) in **RawDeployment** mode — the only supported mode in RHOAI 3.4, so no Service Mesh or Serverless dependency. The **vLLM NVIDIA GPU runtime** serves the model.
- **Outcome:** a user selects the NVIDIA **Nemotron** model (`nemotron-3-nano-30b-a3b`, served from `oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0`) and deploys it onto a GPU hardware profile.
- Docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/serving_models/

---

## Architecture

```
GPU Nodes (g6e.2xlarge, 1× L40S)
   │  labeled by
   ▼
NFD Operator ──▶ NVIDIA GPU Operator ──▶ ClusterPolicy + device-plugin time-slicing (1 GPU → 4×)
                                              │ exposes nvidia.com/gpu (×4)
                                              ▼
Red Hat build of Kueue (+ cert-manager) ── DSC kueue: Unmanaged
   │
   ▼
ResourceFlavor (gpu-l40s) ──▶ 4× ClusterQueue ──▶ 4× LocalQueue
                                              │  bound by scheduling.kueue.localQueueName
                                              ▼
4× RHOAI Hardware Profile (default, gpu-shared, gpu-priority, gpu-reserved-demo)
   │  selected in the dashboard
   ▼
Workbench   |   Model deployment (KServe RawDeployment + vLLM) → Nemotron from registry
```

---

## References

| Source | Role |
|---|---|
| [RHOAI 3.4 — Working with accelerators](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_accelerators/) | NFD, GPU operator, hardware profiles |
| [RHOAI 3.4 — Managing resources (Kueue)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_resources/) | Kueue integration, quota, queues |
| [RHOAI 3.4 — Serving models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/serving_models/) | KServe RawDeployment, vLLM runtime |
| [NVIDIA GPU Operator — GPU sharing / time-slicing](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html) | Time-slicing mechanism |
| [redhat-cop/gitops-catalog — gpu-operator-certified](https://github.com/redhat-cop/gitops-catalog/tree/main/gpu-operator-certified) | GitOps reference implementation |
| `docs/PLATFORM_BASELINE.md` | Active product version targets |
