# Stage 120: GPU-as-a-Service — Plan

## Intent

- Stage identifier: `120`
- Stage family: `1xx AI Platform Foundation`
- Stage slug: `stage-120-gpu-as-a-service`
- Concept introduced: GPU capacity, presented to data scientists as governed, self-service hardware profiles backed by Kueue admission/quota/priority, plus the model-serving platform so a registry model can be deployed on GPU.
- Target audience: Platform engineer, MLOps engineer, data scientist
- Enterprise value: GPUs are scarce and expensive; Kueue turns raw GPU capacity into fair-share, prioritized, quota-governed self-service — no manual booking, no idle reservations.
- Depends on: stage-110 (GitOps bootstrap, RHOAI, ODF, demo-sandbox, model registry)
- New components: cert-manager, Red Hat build of Kueue operator, NFD operator, NVIDIA GPU operator, GPU MachineSet, Kueue quota objects, RHOAI hardware profiles, KServe model serving
- Existing components patched: the stage-110-owned `DataScienceCluster` (`kueue: Unmanaged`, `kserve: Managed`)
- Non-goals:
  - llm-d / `LLMInferenceService` and the MaaS governance layer (deferred to the MaaS stage)
  - MIG GPU partitioning (time-slicing only for this stage)
  - Multi-GPU / multi-node serving
  - AMD/Intel/IBM accelerators (NVIDIA-only demo policy)

## Hardware Decision (confirmed)

- AWS GPU instance type: `g6e.2xlarge` (parameterized via `.env` `GPU_INSTANCE_TYPE`)
- Physical GPU: **1× NVIDIA L40S (48 GB)** per node (g6e family; the "L4" in early notes was a misread — L4 is the `g6` family)
- GPU MachineSet replicas: `1` (one GPU node)
- Time-slicing: **1 physical GPU advertised as 4** `nvidia.com/gpu` units, to back the four queue experiences

## Queue / Quota / Profile Design

One CPU `ResourceFlavor` (default) and one GPU `ResourceFlavor` (`gpu-l40s`, carrying GPU node placement: nodeLabel `cluster-api/accelerator=nvidia-gpu`, toleration for `nvidia-gpu-only:NoSchedule`). Kueue-enabled hardware profiles carry **no** node selectors/tolerations — placement is the ResourceFlavor's job.

| Hardware profile | LocalQueue → ClusterQueue | `nvidia.com/gpu` nominal | Priority | Lending | Purpose |
|---|---|---|---|---|---|
| `default` | `lq-cpu-default` → `cq-cpu-default` | 0 (CPU/mem only) | normal | n/a | Everyone can start CPU-only workbenches |
| `gpu-shared` | `lq-gpu-shared` → `cq-gpu-shared` | 2 | low | borrow within cohort | Request a GPU when shared capacity is free |
| `gpu-priority` | `lq-gpu-priority` → `cq-gpu-priority` | 1 | high (preempts) | borrow within cohort | Higher-priority path for critical jobs |
| `gpu-reserved-demo` | `lq-gpu-reserved-demo` → `cq-gpu-reserved-demo` | 1 | normal | no lending | Reserved/team-owned quota, no booking app |

- GPU nominal quotas sum to 4 = the time-sliced capacity.
- `cq-gpu-shared` + `cq-gpu-priority` share a **cohort** (borrowing + priority preemption demonstrated); `cq-gpu-reserved-demo` is isolated (true reservation).
- A Kueue `WorkloadPriorityClass` gives `gpu-priority` higher admission priority.

## Acceptance Criteria

- [ ] README explains Why/What incl. a plain-language time-slicing explanation with official-doc references.
- [ ] GPU node provisioned and reports `nvidia.com/gpu` allocatable = 4 (time-sliced).
- [ ] cert-manager, Kueue, NFD, GPU operators all `Succeeded`; NVIDIA `ClusterPolicy` Ready.
- [ ] DSC patched: `kueue: Unmanaged`, `kserve: Managed`; no second DSC created.
- [ ] 1 GPU ResourceFlavor + 4 ClusterQueues + 4 LocalQueues `Active`.
- [ ] 4 hardware profiles visible in the dashboard with correct LocalQueue binding.
- [ ] KServe (RawDeployment) ready; vLLM ServingRuntime available.
- [ ] A user can select the nemotron model from the registry/catalog and deploy it on a GPU profile (validation flow).
- [ ] Manifest review and Red Hat source-alignment review pass.

## Source Capture

| Purpose | Source | Skill | Notes |
|---|---|---|---|
| GPU operator + MachineSet + ClusterPolicy + time-slicing | redhat-cop/gitops-catalog `gpu-operator-certified` | `rhoai-nvidia-gpu-accelerators` (`references/gitops-catalog-gpu-pattern.md`, `examples/aws-gpu-machineset-gitops-pattern.md`) | Mirror operator/instance/component shape; derive MachineSet from live worker MS |
| NFD operator + NodeFeatureDiscovery | OCP 4.20 NFD docs | `ocp-node-feature-discovery` | channel `stable` |
| GPU MachineSet | live worker MachineSet export | `ocp-machine-management` | preserve provider fields; change only GPU intent |
| Kueue (RH build) + DSC integration | RHOAI 3.4 Kueue chapter | `rhoai-kueue-workload-management` | DSC `kueue: Unmanaged`; standalone operator `kueue-operator` `stable-v1.3`; cert-manager prereq |
| ResourceFlavor/ClusterQueue/LocalQueue/priority | RHOAI distributed-workload quota chapter | `rhoai-distributed-workload-operations` | quota object schema (verify post-enable) |
| Hardware profiles | live CRD `infrastructure.opendatahub.io/v1alpha1` | `rhoai-nvidia-gpu-accelerators` | verified: `scheduling.type: Queue` + `scheduling.kueue.localQueueName` |
| KServe model serving | RHOAI 3.4 model-serving config guide | `rhoai-model-serving-platform`, `rhoai-model-deployment` | RawDeployment only; vLLM runtime |
| Nemotron model | skill-specified | `rhoai-nvidia-gpu-accelerators` | `oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0` |

## Skill Routing

- Coordinator: `project-demo-stage-authoring`
- GitOps: `project-gitops-authoring`, `project-red-hat-operator-gitops`
- Components: `rhoai-nvidia-gpu-accelerators`, `ocp-node-feature-discovery`, `ocp-machine-management`, `rhoai-kueue-workload-management`, `rhoai-distributed-workload-operations`, `rhoai-model-serving-platform`, `rhoai-model-deployment`, `rhoai-dsci-dsc-configuration`
- Review: `project-manifest-review`, `project-red-hat-doc-alignment-review`, `rhoai-api-tiers`

## GitOps Ownership

- New owning Application: `stage-120-gpu-as-a-service` (project `rhoai-demo`).
- Shared resource patched: stage-110 `DataScienceCluster` — stage-120 owns a Kustomize patch enabling `kueue: Unmanaged` and `kserve: Managed`. The stage-110 Application keeps rendering the DSC; stage-120 contributes a component patch (shared-owner pattern from `project-red-hat-operator-gitops`).
- Sync-wave order: cert-manager + operators (wave 1) → operator CRs / NodeFeatureDiscovery / ClusterPolicy / DSC patch (wave 2) → MachineSet (wave 2) → Kueue quota + hardware profiles (wave 3, after `nvidia.com/gpu` is allocatable) → ServingRuntime (wave 3).
- Secret/credential handling: none committed. `registry.redhat.io` pull for the modelcar uses the cluster's existing pull secret.

## Manifest Inventory (planned)

| Path | Kind | Source authority |
|---|---|---|
| `gitops/stage-120-.../cert-manager/operator/**` | Subscription/OperatorGroup | OCP cert-manager docs |
| `gitops/stage-120-.../kueue-operator/operator/**` | Subscription/OperatorGroup | RH build of Kueue docs |
| `gitops/stage-120-.../nfd/operator/**` + `instance/` | Subscription + NodeFeatureDiscovery | NFD docs |
| `gitops/stage-120-.../gpu-operator/operator/**` + `instance/base/cluster-policy.yaml` + `device-plugin-config.yaml` | Subscription + ClusterPolicy + time-slicing ConfigMap | gitops-catalog pattern + live CRD |
| `gitops/stage-120-.../machineset/machineset.yaml` (+ machineautoscaler) | MachineSet | live worker MS export |
| `gitops/stage-120-.../kueue-quota/**` | ResourceFlavor, 4×ClusterQueue, 4×LocalQueue, WorkloadPriorityClass | distributed-workload-operations |
| `gitops/stage-120-.../hardware-profiles/**` | 4× HardwareProfile | verified CRD schema |
| `gitops/stage-120-.../serving/**` | DSC patch (kserve/kueue), vLLM ServingRuntime | model-serving guide |
| `gitops/argocd/app-of-apps/stage-120-gpu-as-a-service.yaml` | Application | project-gitops-authoring |

## Script Plan

- `deploy.sh`: guard → apply the stage-120 Argo CD Application. The GPU MachineSet `.env`-parameterized (`GPU_INSTANCE_TYPE`, `GPU_NODE_COUNT`); the MachineSet scale-up is the cost-incurring step and is called out explicitly.
- `validate.sh`: GPU node present + `nvidia.com/gpu` allocatable = 4; operators Succeeded; ClusterPolicy Ready; ClusterQueues Active; hardware profiles present; KServe ready; vLLM runtime present.

## Risks And Deferred Work

| Item | Type | Resolution |
|---|---|---|
| AWS GPU quota for `g6e` | risk | Provisioning fails if the sandbox lacks `g6e`/L40S quota; verify before scale-up |
| GPU cost | risk | One `g6e.2xlarge` runs continuously; document a scale-to-zero shutdown path |
| Kueue quota CR schema | verify | Confirm ResourceFlavor/ClusterQueue/LocalQueue fields post-operator-install |
| nemotron registry vs catalog availability | verify | Confirm the modelcar is reachable and registrable for the deploy flow |
| Kueue quota object naming/cohort | design | Validate borrowing/preemption behavior on the live queues |

## Review Log

- Source capture: complete (live CRDs + skills verified 2026-06-11)
- Manifest review: pending
- Red Hat source-alignment review: pending
- Live validation: pending
