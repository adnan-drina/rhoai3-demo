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
| Stage 220 model publication and policy | done | MaaS prerequisites, local Nemotron `LLMInferenceService`/`MaaSModelRef`, external OpenAI `gpt-4o-mini` provider routing through matching MaaS resources, combined subscription/auth policy, API-key-backed inference, and Gen AI Playground MaaS consumption are authored against live schemas. Revalidate after the current `gpt-4o-mini` alignment is deployed. |
| Extended operating envelope | medium | Initial chat/RAG GuideLLM policy profiles exist for one `g6e.2xlarge` GPU worker and the Stage 210 `--max-model-len=8192` baseline; Stage 220 serves MaaS Nemotron with `--max-model-len=131072` for Playground MCP headroom. Rerun benchmarks before changing MaaS quotas, GPU shape, prompt sizes, or output-token defaults. |

## Stage 220: Status — VALIDATED

Stage 220 GitOps creates the MaaS prerequisite stack, local Nemotron
`LLMInferenceService`/`MaaSModelRef`, external OpenAI `gpt-4o-mini`
resources, combined subscription/auth policy, and `rhods-admins` namespace
administration.

Deployed and validated 2026-06-13 on cluster-klvxt after migrating the direct
`demo-sandbox` Nemotron deployment into `models-as-a-service`. Validation
confirmed `rhcl-operator.v1.3.4`, MaaS CRDs, local Nemotron readiness,
external OpenAI registration, subscription/auth policy, generated Kuadrant
policy filters, dashboard AI asset endpoint discovery, Gateway subscription
discovery for real demo users, MaaS API key lifecycle, Nemotron and external
OpenAI inference, and Gen AI Playground responses for both models.

### Open / deferred from Stage 220

| Item | Priority | Notes |
|------|----------|-------|
| API key and MaaS inference validation | done | Stage 220 validation creates and revokes a temporary MaaS API key, calls Nemotron and external OpenAI through the MaaS Gateway, verifies structured tool-call output for both models, checks token usage, and validates Gen AI Playground responses. |
| MaaS observability | medium | Keep Technology Preview/showback language; validate metrics only after request flow works end to end. |

## Stage 230: Status — REPLANNING

Stage 230 is being reset from the earlier whoami/Docling/DSPA/chatbot design
to a metadata-aware enterprise RAG implementation based on the Red Hat
Developer OGX/Llama Stack article and its linked `agnews-rag-demo` repository.
The first rebuilt version reproduces the AG News pattern with Nemotron through
Stage 220 MaaS, PostgreSQL with pgvector for Llama Stack metadata and vector
retrieval, metadata filtering, hybrid search, CPU-hosted Qwen3 reranking, and
an Enterprise RAG Workbench. The first Dutch development corpus is a single
public Staatsblad PDF (`stb-2022-14.pdf`) for smoke tests. A metadata contract,
preparation helper, and compile-ready Docling-standard KFP source now exist for
that single-document path. A larger Dutch government publication corpus still
requires DSPA/S3-backed Docling execution before it is indexed. A focused
official RHOAI 3.4 product-document explainer corpus is also available for
demo-audience Q&A about the product docs behind the stage design. The selected
official RHOAI PDFs and deterministic prepared chunks are stored under the
stage data folder and mirrored to the project S3 bucket during deployment.

### Open / deferred from Stage 230

| Item | Priority | Notes |
|------|----------|-------|
| Remove stale active implementation | high | Remove or replace old whoami, Docling, DSPA/KFP, and previous Streamlit chatbot artifacts during the Stage 230 rebuild so the stage has one coherent architecture. |
| AG News compatibility implementation | high | Re-author the Red Hat article-linked Helm/notebook pattern into local GitOps, notebooks/jobs, and validation scripts; do not apply the reference Helm chart directly. Current GitOps includes runtime foundation, Qwen3 reranker, workbench, and acceptance helper. |
| Nemotron through MaaS | high | Replace the reference Llama generation model with the governed Stage 220 Nemotron MaaS endpoint. |
| pgvector provider posture | high | Use the RHOAI 3.4 Llama Stack `remote::pgvector` provider pattern and validate the PostgreSQL `vector` extension during deploy. |
| Embedding provider and dimension | high | Select the embedding provider from installed Llama Stack capabilities, capture the model ID and vector dimension, and validate before indexing. |
| Qwen3 reranker demo exception | medium | Qwen3 reranker is in scope and deployed on CPU. Keep the modelcar and demo-local serving translation recorded as a demo exception, not a Red Hat-supported artifact claim. |
| Hybrid metadata filtering | high | Resolved by selecting the active pgvector provider path. Keep this as a validation gate: filtered `hybrid` search must return only the expected metadata category before Stage 230 is accepted. |
| Dutch government publication corpus | high | Single-document smoke path added with `stb-2022-14.pdf`, recommended metadata, default questions, and a preparation contract. Next: run Docling through DSPA/S3 and review artifacts before indexing a larger Dutch government publication corpus. |
| RHOAI product-document explainer corpus | medium | Source manifest, repo-stored official RHOAI 3.4 PDFs, deterministic prepared chunks, preparation helper, smoke helper, and workbench notebook added for Llama Stack RAG, AutoRAG, RAGAS, EvalHub, guardrails, AI Pipelines, and Docling audience Q&A. Deployment mirrors the source PDFs to the Stage 230 project bucket. This is documentation grounding, not implementation scope for those adjacent capabilities. |
| Docling/KFP data preparation | high | Compile-ready `docling-standard` KFP source and workbench/local validation are added for the single PDF. Next: add DSPA, S3 Secret generation from project object-storage data, imported pipeline/version handling, run automation, task-log checks, metrics, and artifact review. Use `docling-vlm` only for scanned, image-heavy, or complex-layout documents. |
| RAG evaluation | medium | Keep RAGAS or other quality evaluation for a later evaluation-focused stage. |
| Guardrails and MCP | medium | Add product-backed guardrails and MCP after base RAG works. |

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
