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
| Endpoint auth posture | medium | Stage 210 uses a controlled direct endpoint for baseline work; Stage 220 MaaS owns governed shared API access |
| Stage 220 model publication and policy | done | MaaS prerequisites, local Nemotron `LLMInferenceService`/`MaaSModelRef`, external OpenAI `gpt-5.4-mini` provider routing through DNS-safe `gpt-5-4-mini` MaaS resources, combined subscription/auth policy, API-key-backed inference, and Gen AI Playground MaaS consumption are authored against live schemas. Full validation on 2026-06-13 passed 62/62 checks on cluster-klvxt. |
| Extended operating envelope | medium | Initial chat/RAG GuideLLM policy profiles now exist for one `g6e.2xlarge` GPU worker and `--max-model-len=8192`; rerun before changing MaaS quotas, GPU shape, model config, prompt sizes, or output-token defaults |

## Stage 220: Status — VALIDATED

Stage 220 GitOps creates the MaaS prerequisite stack, local Nemotron
`LLMInferenceService`/`MaaSModelRef`, external OpenAI `gpt-5.4-mini`
resources, combined subscription/auth policy, and `rhods-admins` namespace
administration.

Deployed and validated 2026-06-13 on cluster-klvxt after migrating the direct
`demo-sandbox` Nemotron deployment into `models-as-a-service`. Validation
confirmed `rhcl-operator.v1.3.3`, MaaS CRDs, local Nemotron readiness,
external OpenAI registration, subscription/auth policy, generated Kuadrant
policy filters, dashboard AI asset endpoint discovery, Gateway subscription
discovery for real demo users, MaaS API key lifecycle, Nemotron and external
OpenAI inference, and Gen AI Playground responses for both models.

### Open / deferred from Stage 220

| Item | Priority | Notes |
|------|----------|-------|
| API key and MaaS inference validation | done | Stage 220 validation creates and revokes a temporary MaaS API key, calls Nemotron and external OpenAI through the MaaS Gateway, verifies structured tool-call output where applicable, checks token usage, and validates Gen AI Playground responses. |
| MaaS observability | medium | Keep Technology Preview/showback language; validate metrics only after request flow works end to end. |

## Stage 230: Status — IMPLEMENTATION ADDED

Stage 230 implements the private enterprise RAG baseline: the whoami PDF corpus
from the previous implementation, Stage 110 object storage, Docling conversion,
a stage-owned DSPA/KFP ingestion pipeline, a stage-owned pgvector database,
RHOAI Llama Stack, and Nemotron consumed through Stage 220 MaaS. The stage is
designed for fresh-environment deployment through
`stage-230-private-data-rag/deploy.sh` and validation through
`stage-230-private-data-rag/validate.sh`.

### Open / deferred from Stage 230

| Item | Priority | Notes |
|------|----------|-------|
| Fresh-environment rollout | high | Static render and server-side dry-run passed on cluster-xgg8t; run the full Stage 230 deploy after the branch is pushed so Argo CD can fetch the new GitOps path. |
| Production embedding posture | medium | First implementation uses the quickstart `sentence-transformers/all-MiniLM-L6-v2` inline sentence-transformers provider; consider a separately served embedding model for a more production-like enterprise RAG stage. |
| Docling image posture | medium | Stage 230 uses `quay.io/docling-project/docling-serve:latest` as a demo/reference dependency inherited from the previous implementation and quickstart pattern; pin or replace before production-positioned delivery. |
| Pipeline hardening | medium | DSPA/KFP ingestion is now active; hardening work remains around pipeline image pinning, artifact retention policy, run cleanup, and richer dashboard evidence. |
| AutoRAG comparison | low | Keep AutoRAG as a later optimization path because it is Technology Preview and Milvus-oriented in the current skill baseline. |
| Guardrails | high | Safety shields and prompt-injection controls belong in the next GenAI stage after the private RAG baseline is validated. |

## Candidate Future Stages

These map to the taxonomy ranges defined in `.agents/skills/project-demo-stage-authoring/references/stage-taxonomy.md`.

| Candidate | Theme | Concept |
|-----------|-------|---------|
| `stage-240-guardrails-and-safety` | Production GenAI | AI safety, guardrails, and policy controls around GenAI workloads |
| `stage-320-llama-stack-runtime` | Agentic AI | Llama Stack runtime and API integration |
| `stage-410-ai-pipelines` | AI Operations/MLOps | AI Pipelines and KFP workflows |
| `stage-420-model-evaluation` | AI Operations/MLOps | LMEval / EvalHub evaluation and evidence capture |
| `stage-440-observability-and-governance` | AI Operations/MLOps | TrustyAI, Grafana, monitoring |

Legacy backlog content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/BACKLOG.md`
