# Backlog

Active backlog for the reimplementation.

## Stage 110: Status — COMPLETE

Deployed and validated 2026-06-11 on cluster-klvxt (OCP 4.20.24); `validate.sh` 17/17. User-validated end to end: login as both personas, workbench with RWO PVC, model registry instance with a registered model, S3 from the workbench.

Completed: GitOps bootstrap, ODF MCG (S3 verified), RHOAI 3.4 (dashboard, workbenches, model registry), htpasswd IdP + `ai-admin`/`ai-developer` + groups, `demo-sandbox` project + first OBC + S3 connection, model registry instance (day-2 dashboard).

### Open / deferred from Stage 110

| Item | Priority | Notes |
|------|----------|-------|
| Capture model registry instance in GitOps | low | `default-modelregistry` + registered models are day-2 dashboard-created (runtime, with DB secrets); optional to capture for from-scratch reproducibility |
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
| Fresh-environment MachineSet regeneration | high | Current MachineSet is specific to `cluster-klvxt`; each new AWS demo environment must regenerate the providerSpec from a live worker MachineSet |
| GPU cost control | high | Use the documented manual scale-to-zero path when the demo is idle |
| Kueue preemption demo | low | Stage 120 is non-preemptive because workbenches are not suspendable; test preemption later with suspendable jobs if needed |
| MIG partitioning | low | Time-slicing is sufficient for this demo stage |

## Stage 210: Status — PLATFORM ENABLEMENT COMPLETE

Stage 210 enables the RHOAI KServe model serving platform through the shared
Stage 110 `DataScienceCluster` owner. It creates the user-facing stage README,
PLAN, deploy wrapper, validation wrapper, and the focused KServe DSC patch.
Deployed and validated 2026-06-12 on cluster-klvxt; `validate.sh` 9/9.

### Open / deferred from Stage 210

| Item | Priority | Notes |
|------|----------|-------|
| Temporary Nemotron smoke test | high | Implement after the active vLLM runtime template, `InferenceService` or `LLMInferenceService` path, registry pull behavior, endpoint auth, and cleanup flow are verified |
| Durable curated Nemotron deployment | high | Deferred to Stage 230 after Stage 220 establishes performance limits and operating envelope |
| vLLM runtime template name | medium | Validation discovers the runtime instead of hard-coding a name until the live platform state is confirmed |
| Model-serving metrics baseline | medium | Stage 220 owns GuideLLM-style baseline evidence and metrics correlation |

## Candidate Future Stages

These map to the taxonomy ranges defined in `.agents/skills/project-demo-stage-authoring/references/stage-taxonomy.md`.

| Candidate | Theme | Concept |
|-----------|-------|---------|
| `stage-220-model-performance-baseline` | Production GenAI | GuideLLM-style model performance baseline and breakpoint evidence |
| `stage-230-models-as-a-service` | Production GenAI | MaaS governed access to Nemotron and external OpenAI `gpt-5.4-nano` |
| `stage-240-private-data-rag` | Production GenAI | Private data ingestion, RAG application |
| `stage-250-guardrails-and-safety` | Production GenAI | AI safety, guardrails, and policy controls around GenAI workloads |
| `stage-320-llama-stack-runtime` | Agentic AI | Llama Stack runtime and API integration |
| `stage-410-ai-pipelines` | AI Operations/MLOps | AI Pipelines and KFP workflows |
| `stage-420-model-evaluation` | AI Operations/MLOps | LMEval / EvalHub evaluation and evidence capture |
| `stage-440-observability-and-governance` | AI Operations/MLOps | TrustyAI, Grafana, monitoring |

Legacy backlog content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/BACKLOG.md`
