# Backlog

Active backlog for the reimplementation.

## Stage 110: Status — COMPLETE

Deployed and validated 2026-06-11 on cluster-klvxt (OCP 4.20.24); `validate.sh` 17/17. User-validated end to end: login as both personas, workbench with RWO PVC, model registry instance with a registered model, S3 from the workbench.

Completed: GitOps bootstrap, ODF MCG (S3 verified), RHOAI 3.4 (dashboard,
workbenches, model registry), htpasswd IdP + `ai-admin`/`ai-developer` +
groups, `demo-sandbox` project + first OBC + S3 connection, and the
GitOps-managed `demo-registry` instance.

### Open / deferred from Stage 110

| Item | Priority | Notes |
|------|----------|-------|
| Repo URL / branch injection in ArgoCD Application | low | `deploy.sh` uses `sed` to inject `GIT_REPO_URL`/`GIT_REPO_BRANCH` from `.env`; consider a Kustomize `configMapGenerator` + `replacements` approach (AI Accelerator pattern) |
| Dedicated `rhoai-demo-admins` group | low | RHOAI admin uses `rhods-admins`; a separate demo-admin group is optional |
| Least-privilege role for Argo CD application-controller | low | Bootstrap grants `cluster-admin` to `openshift-gitops-argocd-application-controller` (`gitops/bootstrap/overlays/demo/argocd-cluster-admin.yaml`); replace with a scoped role |
| Per-project admin RBAC for future projects | low | `rhods-admins` is bound `admin` per project (currently `demo-sandbox` only); each new project needs its own binding, by design |

## Stage 120: Status — COMPLETE

Deployed and validated 2026-06-12 on cluster-klvxt; `validate.sh` 23/23.
Stage 120 owns the GPU MachineSet, NFD, NVIDIA GPU Operator, Kueue operator and
quota resources, and RHOAI hardware profiles. It does not enable model serving;
Stage 210 owns that transition.

### Open / deferred from Stage 120

| Item | Priority | Notes |
|------|----------|-------|
| Fresh-environment MachineSet regeneration | high | Current MachineSet is specific to `cluster-klvxt`; each new AWS demo environment must regenerate the providerSpec from a live worker MachineSet. `stage-120-gpu-as-a-service/generate-gpu-machineset.sh` now previews or writes the replacement from a guarded live worker MachineSet; test it during the next fresh AWS environment redeploy before considering this closed |
| GPU cost control | high | Use the documented manual scale-to-zero path when the demo is idle |
| Kueue preemption demo | low | Stage 120 is non-preemptive because workbenches are not suspendable; test preemption later with suspendable jobs if needed |
| MIG partitioning | low | Time-slicing is sufficient for this demo stage |

## Stage 210: Status — COMPLETE

Stage 210 enables the RHOAI KServe model serving platform through the shared
Stage 110 `DataScienceCluster` owner and handles fresh-environment convergence
for `demo-registry`, Nemotron registry metadata, and the Nemotron vLLM
`InferenceService` using the curated Nemotron vLLM configuration adapted from
the Red Hat AI MaaS code assistant quickstart. It also adds user workload
monitoring, a GitOps-managed Grafana model-serving dashboard, and an on-demand
GuideLLM benchmark runner. The benchmark layer now also includes the
llm-d-showroom-style `benchmark-data` PVC, shared-prefix `prompts.csv`,
`llm-performance` Grafana dashboard, and OpenShift Console application-menu
link to the Grafana dashboard.

Deployed and validated 2026-06-12 on cluster-klvxt; current `validate.sh`
passes 49/49 after the showroom-style benchmark/dashboard enhancement and
dashboard metric alignment. A short
GuideLLM smoke run completed successfully against `/data/prompts.csv` and
wrote JSON results under gitignored `runs/stage-210-guidellm/`.

### Open / deferred from Stage 210

| Item | Priority | Notes |
|------|----------|-------|
| Endpoint auth posture | medium | Stage 210 uses a controlled direct endpoint for baseline work; Stage 230 MaaS owns governed shared API access |
| Stage 230 model publication and policy | high | MaaS prerequisites, local Nemotron `LLMInferenceService`/`MaaSModelRef`, external OpenAI `gpt-5.4-nano` resources, and combined subscription/auth policy are authored against live schemas. RHCL is now pinned to `rhcl-operator.v1.3.3`; rerun live rollout/validation to confirm the dashboard/API path. |
| Extended operating envelope | medium | Initial chat/RAG GuideLLM policy profiles now exist for one `g6e.2xlarge` GPU worker and `--max-model-len=8192`; rerun before changing MaaS quotas, GPU shape, model config, prompt sizes, or output-token defaults |

## Stage 230: Status — PENDING RHCL PIN VALIDATION

Stage 230 GitOps creates the MaaS prerequisite stack, local Nemotron
`LLMInferenceService`/`MaaSModelRef`, external OpenAI `gpt-5.4-nano`
resources, combined subscription/auth policy, and `rhods-admins` namespace
administration.

Deployed 2026-06-12 on cluster-klvxt after migrating the direct
`demo-sandbox` Nemotron deployment into `models-as-a-service`. Previous
validation reached 47/51 with all prerequisites, CRDs, local Nemotron
readiness, external OpenAI registration, subscription, and auth policy checks
passing, but user-facing dashboard/API discovery was blocked by an RHCL 1.4.0
Gateway header-injection compatibility issue. GitOps now pins RHCL to
`rhcl-operator.v1.3.3`; rerun live remediation, deploy, and validation before
marking Stage 230 complete.

### Open / deferred from Stage 230

| Item | Priority | Notes |
|------|----------|-------|
| RHCL pin rollout and validation | high | Confirm the cluster runs `rhcl-operator.v1.3.3`, not RHCL 1.4.x. Then rerun Stage 230 deploy/validate and confirm Gateway header injection, AI asset endpoints, and MaaS API discovery. Resolve through supported operator lifecycle alignment, not GitOps patches to generated AuthPolicy or EnvoyFilter resources. |
| API key and Gen AI Playground validation | high | Must validate through the dashboard and MaaS API, not only through CR readiness. |
| MaaS observability | medium | Keep Technology Preview/showback language; validate metrics only after request flow works end to end. |

## Candidate Future Stages

These map to the taxonomy ranges defined in `.agents/skills/project-demo-stage-authoring/references/stage-taxonomy.md`.

| Candidate | Theme | Concept |
|-----------|-------|---------|
| `stage-220-model-performance-baseline` | Production GenAI | Expanded performance baseline and operating-envelope evidence if the Stage 210 lightweight GuideLLM/Grafana baseline needs a dedicated follow-up |
| `stage-240-private-data-rag` | Production GenAI | Private data ingestion, RAG application |
| `stage-250-guardrails-and-safety` | Production GenAI | AI safety, guardrails, and policy controls around GenAI workloads |
| `stage-320-llama-stack-runtime` | Agentic AI | Llama Stack runtime and API integration |
| `stage-410-ai-pipelines` | AI Operations/MLOps | AI Pipelines and KFP workflows |
| `stage-420-model-evaluation` | AI Operations/MLOps | LMEval / EvalHub evaluation and evidence capture |
| `stage-440-observability-and-governance` | AI Operations/MLOps | TrustyAI, Grafana, monitoring |

Legacy backlog content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/BACKLOG.md`
