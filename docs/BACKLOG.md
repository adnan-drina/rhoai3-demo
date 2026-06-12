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
| Fresh-environment MachineSet regeneration | high | Current MachineSet is specific to `cluster-klvxt`; each new AWS demo environment must regenerate the providerSpec from a live worker MachineSet |
| GPU cost control | high | Use the documented manual scale-to-zero path when the demo is idle |
| Kueue preemption demo | low | Stage 120 is non-preemptive because workbenches are not suspendable; test preemption later with suspendable jobs if needed |
| MIG partitioning | low | Time-slicing is sufficient for this demo stage |

## Stage 210: Status — MODEL SERVING BASELINE IN PROGRESS

Stage 210 enables the RHOAI KServe model serving platform through the shared
Stage 110 `DataScienceCluster` owner and handles fresh-environment convergence
for `demo-registry`, Nemotron registry metadata, and the Nemotron vLLM
`InferenceService`. The stage remains open for lightweight GuideLLM benchmark
and Grafana metrics work.

### Open / deferred from Stage 210

| Item | Priority | Notes |
|------|----------|-------|
| GuideLLM benchmark script | high | Add a lightweight benchmark runner against the vLLM endpoint; no EvalHub or MLflow in this stage |
| Grafana metrics dashboard | high | Add GitOps-managed Grafana resources for vLLM, KServe, and GPU metrics |
| Endpoint auth posture | medium | Stage 210 uses a controlled direct endpoint for baseline work; Stage 220 MaaS owns governed shared API access |
| Durable curated MaaS deployment | high | Deferred to Stage 220 after Stage 210 establishes basic serving limits and operating envelope |

## Candidate Future Stages

These map to the taxonomy ranges defined in `.agents/skills/project-demo-stage-authoring/references/stage-taxonomy.md`.

| Candidate | Theme | Concept |
|-----------|-------|---------|
| `stage-220-models-as-a-service` | Production GenAI | MaaS governed access to Nemotron and external OpenAI `gpt-5.4-nano` |
| `stage-230-private-data-rag` | Production GenAI | Private data ingestion, RAG application |
| `stage-240-guardrails-and-safety` | Production GenAI | AI safety, guardrails, and policy controls around GenAI workloads |
| `stage-320-llama-stack-runtime` | Agentic AI | Llama Stack runtime and API integration |
| `stage-410-ai-pipelines` | AI Operations/MLOps | AI Pipelines and KFP workflows |
| `stage-420-model-evaluation` | AI Operations/MLOps | LMEval / EvalHub evaluation and evidence capture |
| `stage-440-observability-and-governance` | AI Operations/MLOps | TrustyAI, Grafana, monitoring |

Legacy backlog content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/BACKLOG.md`
