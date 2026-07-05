# Backlog

Active backlog for the reimplementation.

## Model Monitoring — RHOAI 3.4 Doc Alignment (audited 2026-07-05)

Audited against the official guides
`managing_and_monitoring_models` and `monitoring_your_ai_systems` (backed by
`rhoai-model-management-monitoring` and `rhoai-monitoring-trustyai`).

Aligned: User Workload Monitoring with `enableUserWorkload: true` and 15d
Prometheus retention; KServe-generated ServiceMonitor scraping `vllm:*`
(KServe emits no metrics itself — the runtime does, per the guide); Grafana
dashboards keyed on NAMESPACE + MODEL_NAME covering the guide's metric
families (TTFT, ITL/TPOT, throughput, KV-cache, running/waiting requests,
prefix-cache, DCGM GPU); NVIDIA GPU metrics via the GPU operator. Added
2026-07-05: serving-health `PrometheusRule`, `monitoring-rules-view` for
demo user groups, and cost-per-1M-tokens in the capacity report (the
guide's cost metric).

Not applicable to our stack (recorded so it is not mistaken for a gap):

- **TrustyAI bias/data-drift monitoring is OVMS-only** per
  `monitoring_your_ai_systems`; our models are vLLM, so bias/SPD/DIR and
  MeanShift/KSTest drift do not apply to the LLM/RAG path. The LLM-relevant
  parts of that guide reduce to: TrustyAI component `Managed` (already done
  for guardrails), guardrails observability (Stage 240, done), and formal
  evaluation (future `stage-250`, EvalHub/LM-Eval).
- Istio `ServiceMonitor`/`PodMonitor` from the managing guide target the
  Service Mesh serving path; our KServe RawDeployment / LLMInference
  Service (llm-d) path does not use Service Mesh.

Deferred (Technology Preview or future-stage):

| Item | Priority | Notes |
|------|----------|-------|
| Metrics-based autoscaling (KEDA/CMA) | medium | TP in the guide; `serving.kserve.io/autoscalerClass: keda` + `spec.predictor.autoscaling.metrics` on `vllm:num_requests_waiting`. Natural pairing with the capacity benchmark's scale-out signal. |
| LLM evaluation (EvalHub / LM-Eval) | medium | The LLM quality/safety-measurement half of AI-systems monitoring; belongs in `stage-250-model-evaluation`. |
| TrustyAI bias/drift demo on an OVMS model | low | Only if the demo adds a predictive OVMS model; out of scope for the GenAI/RAG storyline. |

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

## Stage 230: Status - VALIDATED

Stage 230 has been reset from the earlier whoami/Docling/DSPA/chatbot design
to a metadata-aware enterprise RAG implementation based on the Red Hat
Developer OGX/Llama Stack article. The implementation uses Nemotron through
Stage 220 MaaS, PostgreSQL with pgvector for Llama Stack metadata and vector
retrieval, metadata filtering, hybrid search, CPU-hosted Qwen3 reranking, and
an Enterprise RAG Workbench. The primary corpus is the focused official
RHOAI 3.4 product-document explainer corpus, which lets the demo answer
questions about the product docs behind the stage design. The selected
official RHOAI PDFs and deterministic prepared chunks are stored under the
stage data folder and mirrored to the project S3 bucket during deployment. The
Docling KFP runner now uses a modular upstream-shaped Docling standard
pipeline through the Stage 230 DSPA server and stores reviewed pipeline output
in S3.

Validated in `cluster-qt67m` on 2026-07-02:

- Stage 230 Argo CD Application synced and healthy.
- DSPA/KFP pipeline evidence from the previous implementation passed for the
  full six-document Docling run. The modular upstream-shaped Docling pipeline
  must replace that evidence on the next Stage 230 validation run.
- RHOAI product-document RAG smoke over pipeline-generated chunks passed with
  hybrid search, reranking, and Nemotron answers.

### Validated Stage 230 Gates

| Item | Priority | Notes |
|------|----------|-------|
| Fresh-environment Stage 230 validation | active | Re-run `validate.sh` after the modular Docling KFP refactor so the evidence reflects the new dashboard-visible task graph. |
| Hybrid metadata filtering | done | Resolved by selecting the active pgvector provider path. Keep this as a recurring validation gate: filtered `hybrid` search must return only the expected metadata category before Stage 230 is accepted in each fresh environment. |
| RHOAI product-document explainer corpus | done | Source manifest, repo-stored official RHOAI 3.4 PDFs, deterministic prepared chunks, preparation helper, smoke helper, and workbench notebook added for Llama Stack RAG, AutoRAG, RAGAS, EvalHub, guardrails, AI Pipelines, and Docling audience Q&A. Deployment mirrors the source PDFs to the Stage 230 project bucket. This is documentation grounding, not implementation scope for those adjacent capabilities. |
| RHOAI product-document KFP automation | active | Docling KFP source and runner now follow the upstream modular `docling-standard` pattern. Revalidate through DSPA, review S3 artifacts, and feed the pipeline-generated JSONL into the RAG smoke helper. Use `docling-vlm` only for scanned, image-heavy, or complex-layout documents. |
| Product-document RAG chatbot | implementation ready | Streamlit app added from the Red Hat AI RAG quickstart direct-chat pattern, adapted to the Stage 230 product-doc vector store, reranker, and Nemotron through Llama Stack. Validate route health and RAG on/off behavior during the next Stage 230 deploy. |

### Open / deferred from Stage 230

| Item | Priority | Notes |
|------|----------|-------|
| Qwen3 reranker demo exception | medium | Qwen3 reranker is in scope and deployed on CPU. Keep the modelcar and demo-local serving translation recorded as a demo exception, not a Red Hat-supported artifact claim. |
| RAG evaluation | medium | Keep RAGAS or other quality evaluation for a later evaluation-focused stage. |
| Guardrails and MCP | done | MCP landed in Stage 230 (OpenShift MCP connector); product-backed guardrails are Stage 240 (active). |

## Stage 240: Guardrails and Safety (Complete)

NeMo Guardrails service with an LLM per the RHOAI 3.4 guardrails guide:
Presidio + regex detectors, custom Colang rails with Python actions, LLM
self-check input/output rails through MaaS-governed Nemotron, Llama Stack
shield wiring for the Stage 230 chatbot (guardrail selectors + demo
suggestion chips), and OpenTelemetry traces to a stage-local Tempo.
Deployed and validated on cluster-qt67m 2026-07-05: stage-240 validate.sh
30/0/0 (including live block/pass rail checks and a Tempo span query),
stage-230 validate.sh 110/1/0 after the chatbot integration. Scope,
shared-owner touches, live findings, and the retrospective are recorded in
`stage-240-guardrails-and-safety/PLAN.md`.

### Open / deferred from Stage 240

| Item | Priority | Notes |
|------|----------|-------|
| Chatbot fail-closed shield hardening | done 2026-07-05 | The vendored UI now fails closed on a shield error (blocks with a visible "guardrail unavailable" message); `RAG_SHIELD_FAIL_MODE=open` restores answer-anyway. Earlier a silent fail-open hid a broken client call for a full session. |
| Separate self-check model | declined 2026-07-05 | Nemotron self-checks itself; revisit only if latency or policy separation demands it (guide recommends Qwen3-14B as judge starting point). |
| PII masking mode, retrieval rails, library hate/profanity flows | low | Blocking-only demo scope; retrieval rails blocked by the Llama Stack shield API passing messages, not chunks. |
| Guardrails metrics + formal safety measurement | medium | Route to `rhoai-evaluation` in the future `stage-250-model-evaluation`. |
| FMS Guardrails / Llama Stack PII via FMS | not adopted | Legacy per the guardrails guide and repo Demo Policy; Stage 230 `trustyai_fms` shields stay empty. |

## Stage 250: Model Evaluation (Complete)

EvalHub evaluation control plane + dashboard LMEvalJob + product-managed
MLflow, evaluating the governed Nemotron model with the OOTB
`safety-and-fairness-v1` collection (pass threshold 0.758) and providers
`lm-evaluation-harness`, `garak`, `guidellm`. MLflow is the minimal dev
pattern (SQLite + PVC), pulled forward from stage-430; EvalHub uses
PostgreSQL. Deployed and validated on cluster-qt67m 2026-07-05:
`validate.sh` 22/0/0, with a real LMEval scorecard (arc_easy acc 0.76 /
acc_norm 0.84, truthfulqa_mc1 0.36). Scope, live findings, retrospective,
and the garak-kfp implementation assessment are in
`stage-250-model-evaluation/PLAN.md`.

### Open / deferred from Stage 250

Enhancement themes are backed by the Red Hat Developer EvalHub series
(2026-05/06): evaluation-driven development, collections, BYOF, CI/CD, OCI
immutable records, Kueue-at-scale, and protected model servers.

| Item | Priority | Notes |
|------|----------|-------|
| Automated risk assessment (garak-kfp) | medium | Adversarial red-teaming through a KFP pipeline + judge model; strongest tie-back to Stage 240 guardrails. Needs a DSPA/pipeline server. |
| Custom evaluation collection for the RAG assistant | medium | Author a `user`-scoped collection (weighted benchmarks + per-benchmark and collection pass thresholds) tuned to the demo's assistant use case, via ConfigMap/CLI — "understanding evaluation collections". |
| EvalHub OCI immutable evaluation records | medium | Export weighted results to an OCI registry with SHA256 tags, embedding the evaluation record in the ModelCar — tamper-evident governance evidence ("store immutable AI evaluation records"). Needs the S3/OCI surface deferred here. |
| EvalHub in CI/CD | medium | Gate model promotion on a collection pass in a pipeline — "add automated AI evaluations to your CI/CD pipeline". |
| Kueue-managed evaluation workloads at scale | low | Route EvalHub jobs through the Stage 120 Kueue quotas for fair scheduling — "manage LLM evaluation workloads at scale with EvalHub and Kueue". |
| Bring-your-own evaluation framework (BYOF) | low | Custom adapter via the EvalHub SDK `FrameworkAdapter` — "bring your own evaluation framework". |
| Production MLflow (PostgreSQL + S3, HA) | medium | Minimal SQLite+PVC now; production storage is future `stage-430-mlflow-experiment-tracking`, which now narrows to advanced MLflow lifecycle / model-registry integration since 250 delivers the MLflow foundation. |
| Multi-model evaluation (Nemotron vs gpt-4o-mini) | low | User chose Nemotron-only; add a model ref + second job for a head-to-head scorecard. |

Aligned with the series already: protected model servers (EvalHub reaches the
governed Nemotron through the MaaS proxy + minted key / job SA token);
evaluation-driven development (README framing); the OOTB
`safety-and-fairness-v1` collection with pass thresholds.

## Candidate Future Stages

These map to the taxonomy ranges defined in `.agents/skills/project-demo-stage-authoring/references/stage-taxonomy.md`.

| Candidate | Theme | Concept |
|-----------|-------|---------|
| `stage-250-model-evaluation` | Production GenAI | LMEval / EvalHub evaluation and evidence capture (next stage) |
| `stage-320-llama-stack-runtime` | Agentic AI | Llama Stack runtime and API integration |
| `stage-410-ai-pipelines` | AI Operations/MLOps | AI Pipelines and KFP workflows |
| `stage-440-observability-and-governance` | AI Operations/MLOps | TrustyAI, Grafana, monitoring |

Legacy backlog content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/BACKLOG.md`
