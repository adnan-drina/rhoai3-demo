# Backlog

Active backlog for the reimplementation. Refined 2026-07-09: all seven
stages (110–250) are complete and wrapped; the current focus is the
medium-item burn-down below. Fresh-environment recurring gates are
consolidated into their own checklist so they are not scattered across
stage sections.

## Now: Medium-Item Burn-Down (focus chosen 2026-07-09)

Standalone enhancements to completed stages, in suggested order. Each is
small enough to plan and deliver without opening a new stage.

| # | Item | Stage | Notes |
|---|------|-------|-------|
| 1 | File EvalHub `attack_success_rate` aggregate bug upstream | 250 | The EvalHub job result reported `attack_success_rate: 0.0` where its own garak scan showed ~0.24 (426/1,750 hits). Reproduce, capture the garak-kfp adapter aggregation path, and file with Red Hat / the TrustyAI EvalHub project. Workaround documented in TROUBLESHOOTING (read the garak report, not the aggregate). |
| 2 | Custom evaluation collection for the RAG assistant | 250 | Author a `user`-scoped collection (weighted benchmarks + per-benchmark and collection pass thresholds) tuned to the demo's assistant use case, via ConfigMap/CLI — "understanding evaluation collections". |
| 3 | MaaS observability | 220 | Keep Technology Preview/showback language; validate metrics now that the request flow works end to end. |
| 4 | EvalHub in CI/CD | 250 | Gate model promotion on a collection pass in a pipeline — "add automated AI evaluations to your CI/CD pipeline". Also covers the pipeline-centric remainder of the retired `stage-410` candidate. |
| 5 | EvalHub OCI immutable evaluation records | 250 | Export weighted results to an OCI registry with SHA256 tags, embedding the evaluation record in the ModelCar — tamper-evident governance evidence ("store immutable AI evaluation records"). |
| 6 | Metrics-based autoscaling (KEDA/CMA) | 210/240 | TP in the managing guide; `serving.kserve.io/autoscalerClass: keda` + `spec.predictor.autoscaling.metrics` on `vllm:num_requests_waiting`. Natural pairing with the capacity benchmark's scale-out signal. |

Production MLflow (PostgreSQL + S3, HA) stays out of the burn-down: it is
the core of the `stage-430` candidate below.

## Next Fresh Environment — Recurring Gates

Run these together on the next fresh AWS demo environment; several stage
sections used to carry them individually.

- **Stage 120 — MachineSet regeneration (high).** The committed MachineSet
  is specific to the last cluster; regenerate the providerSpec from a live
  worker MachineSet with `stage-120-gpu-as-a-service/generate-gpu-machineset.sh`
  (preview or write mode). Test it during the redeploy before considering
  it closed.
- **Stage 220 — full revalidation.** Revalidate MaaS end to end (Nemotron +
  external `gpt-4o-mini`, key lifecycle, Playground) after redeploy.
- **Stage 230 — hybrid metadata filtering gate.** Filtered `hybrid` search
  must return only the expected metadata category before Stage 230 is
  accepted in each fresh environment.
- **Stage 230 — modular Docling pipeline evidence.** The recorded DSPA/KFP
  evidence still predates the upstream-shaped modular `docling-standard`
  refactor (post-refactor runs exercised AutoRAG, not Docling). Re-run the
  Docling pipeline through DSPA, review S3 artifacts, and feed the
  pipeline-generated JSONL into the RAG smoke helper. Use `docling-vlm`
  only for scanned, image-heavy, or complex-layout documents.
- **All stages — `validate.sh` re-runs** (110/120/210/220/230/240/250) as
  the acceptance bar.

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
guide's cost metric). LLM evaluation (EvalHub / LM-Eval), previously
deferred here, shipped in Stage 250.

Not applicable to our stack (recorded so it is not mistaken for a gap):

- **TrustyAI bias/data-drift monitoring is OVMS-only** per
  `monitoring_your_ai_systems`; our models are vLLM, so bias/SPD/DIR and
  MeanShift/KSTest drift do not apply to the LLM/RAG path. The LLM-relevant
  parts of that guide reduce to: TrustyAI component `Managed` (done for
  guardrails), guardrails observability (Stage 240, done), and formal
  evaluation (Stage 250, done).
- Istio `ServiceMonitor`/`PodMonitor` from the managing guide target the
  Service Mesh serving path; our KServe RawDeployment / LLMInference
  Service (llm-d) path does not use Service Mesh.

Still deferred: metrics-based autoscaling (burn-down item 6) and a TrustyAI
bias/drift demo on an OVMS model (low; only if the demo ever adds a
predictive OVMS model — out of scope for the GenAI/RAG storyline).

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
| Fresh-environment MachineSet regeneration | high | Tracked in the fresh-environment checklist above. |
| GPU cost control | done 2026-07-09 | Closed as operational practice: park with Nemotron `LLMInferenceService` replicas 0 + GPU MachineSet scaled to 0 (`env-manage-resources`); exercised at the Stage 230 and 250 wraps. |
| Kueue preemption demo | low | Stage 120 is non-preemptive because workbenches are not suspendable; test preemption later with suspendable jobs if needed. A candidate scope element for `stage-450-gpu-self-service` — the [gpu-booking-app-plugin](https://github.com/rhai-code/gpu-booking-app-plugin) implements exactly this (reserved workloads protected from preemption via per-user ClusterQueue `nominalQuota`). |
| MIG partitioning | low | Time-slicing is sufficient for this demo stage |

## Stage 210: Status — COMPLETE

Stage 210 enables the RHOAI KServe model serving platform through the shared
Stage 110 `DataScienceCluster` owner and handles fresh-environment convergence
for `demo-registry`, Nemotron registry metadata, and the Nemotron vLLM
`InferenceService` using the curated Nemotron vLLM configuration adapted from
the Red Hat AI MaaS code assistant quickstart. It also adds user workload
monitoring, a GitOps-managed Grafana model-serving dashboard, and an on-demand
GuideLLM benchmark runner with the llm-d-showroom-style `benchmark-data` PVC,
shared-prefix `prompts.csv`, `llm-performance` Grafana dashboard, and console
application-menu link.

Deployed and validated 2026-06-12 on cluster-klvxt; `validate.sh` 49/49 after
the showroom-style benchmark/dashboard enhancement and dashboard metric
alignment, with a successful GuideLLM smoke run.

### Open / deferred from Stage 210

| Item | Priority | Notes |
|------|----------|-------|
| Endpoint auth posture | done | Stage 210 used a controlled direct endpoint for baseline work; the Nemotron deployment migrated into `models-as-a-service` under Stage 220 governance. |
| Extended operating envelope | medium | Initial chat/RAG GuideLLM policy profiles exist for one `g6e.2xlarge` GPU worker and the Stage 210 `--max-model-len=8192` baseline; Stage 220 serves MaaS Nemotron with `--max-model-len=131072` for Playground MCP headroom. Rerun benchmarks before changing MaaS quotas, GPU shape, prompt sizes, or output-token defaults. |

## Stage 220: Status — COMPLETE

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
OpenAI inference (including structured tool calls and token usage), and Gen
AI Playground responses for both models. Later stages added dedicated
subscriptions (`enterprise-rag-autorag`, `model-evaluation`) and the
in-cluster MaaS proxy pattern.

### Open / deferred from Stage 220

| Item | Priority | Notes |
|------|----------|-------|
| MaaS observability | medium | Burn-down item 3 above. |

## Stage 230: Status — COMPLETE (wrapped 2026-07-03)

Metadata-aware enterprise RAG based on the Red Hat Developer OGX/Llama Stack
article: Nemotron through Stage 220 MaaS, PostgreSQL + pgvector for Llama
Stack metadata and vector retrieval, metadata filtering, hybrid search,
CPU-hosted Qwen3 reranking, an Enterprise RAG Workbench, and the modular
upstream-shaped Docling standard KFP pipeline through the stage DSPA. The
corpus is the focused official RHOAI 3.4 product-document explainer corpus
(source PDFs and deterministic prepared chunks in the stage data folder,
mirrored to the project S3 bucket on deploy).

Wrapped state (cluster-qt67m, `validate.sh` 108/0; 110/1/0 after the Stage
240 shield integration):

- **Chatbot is the vendored Llama Stack UI distribution** (not the earlier
  Streamlit direct-chat app): discovery-driven playground, deterministic
  per-guide source attribution, benchmark-backed suggestion chips,
  guardrail shields (fail-closed as of 2026-07-05), and the read-only
  OpenShift MCP connector via the top-level `connectors:` StackConfig
  surface (llama-stack 0.7.x Responses API).
- **AutoRAG extension (Technology Preview)** completed: run f79dab42, 8/8
  patterns across both generation models × both CPU embedding ISVCs;
  Nemotron beat gpt-4o-mini on answer correctness (0.60–0.66 vs 0.46–0.56);
  winning-pattern handoff via `scripts/fetch_autorag_pattern.py`.
- RHOAI product-document RAG smoke passed with hybrid search, reranking,
  and Nemotron answers; hybrid metadata filtering and Docling pipeline
  evidence remain recurring fresh-environment gates (see checklist above).
- **MLflow interaction tracing added 2026-07-16** (user-approved extension):
  every chatbot turn is an MLflow trace in the Stage 250 product MLflow
  (workspace `enterprise-rag`, experiment `private-rag-chatbot`) with full
  prompt/retrieval/response content and guardrail verdicts
  (`guardrail.blocked` trace tags). See the Stage 230 `PLAN.md` decision
  record. Trace UI: dashboard `/mlflow`. Production MLflow (PG+S3) remains
  the `stage-430` candidate below.

### Open / deferred from Stage 230

| Item | Priority | Notes |
|------|----------|-------|
| Qwen3 reranker demo exception | medium | Qwen3 reranker is in scope and deployed on CPU. Keep the modelcar and demo-local serving translation recorded as a demo exception, not a Red Hat-supported artifact claim. |
| ExternalModel `DestinationRule` pool tuning | declined 2026-07-09 | The `gpt-connection-keepalive` CronJob covers the NAT idle-connection drops; patching the operator-owned shared resource is not worth the drift risk. Revisit only if external-model reliability regresses. |
| Guardrails and MCP | done | MCP landed in Stage 230 (OpenShift MCP connector); product-backed guardrails shipped in Stage 240. |
| RAG evaluation | done | Delivered by Stage 250 (EvalHub/LMEval); the assistant-specific collection is burn-down item 2. |

## Stage 240: Guardrails and Safety — COMPLETE

NeMo Guardrails service with an LLM per the RHOAI 3.4 guardrails guide:
Presidio + regex detectors, custom Colang rails with Python actions, LLM
self-check input/output rails through MaaS-governed Nemotron, Llama Stack
shield wiring for the Stage 230 chatbot (guardrail selectors + demo
suggestion chips), and OpenTelemetry traces to a stage-local Tempo.
Deployed and validated on cluster-qt67m 2026-07-05: stage-240 validate.sh
30/0/0 (including live block/pass rail checks and a Tempo span query),
stage-230 validate.sh 110/1/0 after the chatbot integration. Scope,
shared-owner touches, live findings, and the retrospective are recorded in
`stage-240-guardrails-and-safety/PLAN.md`. The Stage 250 guard→prove delta
quantified the rails: raw 24.3% attack-success → guarded 8.4% on the same
OWASP scan.

### Open / deferred from Stage 240

| Item | Priority | Notes |
|------|----------|-------|
| Chatbot fail-closed shield hardening | done 2026-07-05 | The vendored UI now fails closed on a shield error (blocks with a visible "guardrail unavailable" message); `RAG_SHIELD_FAIL_MODE=open` restores answer-anyway. Earlier a silent fail-open hid a broken client call for a full session. |
| Separate self-check model | declined 2026-07-05 | Nemotron self-checks itself; revisit only if latency or policy separation demands it (guide recommends Qwen3-14B as judge starting point). |
| PII masking mode, retrieval rails, library hate/profanity flows | low | Blocking-only demo scope; retrieval rails blocked by the Llama Stack shield API passing messages, not chunks. |
| Guardrails metrics + formal safety measurement | done | Delivered by Stage 250: garak OWASP risk assessment plus the guard→prove delta against the guardrails endpoint. |
| FMS Guardrails / Llama Stack PII via FMS | not adopted | Legacy per the guardrails guide and repo Demo Policy; Stage 230 `trustyai_fms` shields stay empty. |

## Stage 250: Model Evaluation — COMPLETE

EvalHub evaluation control plane + dashboard LMEvalJob + product-managed
MLflow, evaluating the governed Nemotron model with the OOTB
`safety-and-fairness-v1` collection (pass threshold 0.758) and providers
`lm-evaluation-harness`, `garak`, `garak-kfp`, `guidellm`. MLflow is the
minimal dev pattern (SQLite + PVC), pulled forward from stage-430; EvalHub
uses PostgreSQL. Deployed and validated on cluster-qt67m 2026-07-05:
`validate.sh` 22/0/0, with a real LMEval scorecard (arc_easy acc 0.76 /
acc_norm 0.84, truthfulqa_mc1 0.36). The garak-kfp automated risk
assessment (default `owasp_llm_top10`) found real weaknesses (~24%
attack-success — read the garak report, not the EvalHub aggregate) and the
guard→prove delta measured 24.3% → 8.4% through the Stage 240 rails. Scope,
live findings, retrospective, and the garak-kfp implementation assessment
are in `stage-250-model-evaluation/PLAN.md`.

Aligned with the Red Hat Developer EvalHub series (2026-05/06) already:
protected model servers (MaaS proxy + minted key / job SA token),
evaluation-driven development (README framing), OOTB collections with pass
thresholds, and automated risk assessment. Remaining series themes are in
the burn-down (items 1, 2, 4, 5) or below.

### Open / deferred from Stage 250

| Item | Priority | Notes |
|------|----------|-------|
| Kueue-managed evaluation workloads at scale | low | Route EvalHub jobs through the Stage 120 Kueue quotas for fair scheduling — "manage LLM evaluation workloads at scale with EvalHub and Kueue". Candidate scope element for `stage-450-gpu-self-service`. |
| Bring-your-own evaluation framework (BYOF) | low | Custom adapter via the EvalHub SDK `FrameworkAdapter` — "bring your own evaluation framework". |
| Multi-model evaluation (Nemotron vs gpt-4o-mini) | low | User chose Nemotron-only; add a model ref + second job for a head-to-head scorecard. |
| Production MLflow (PostgreSQL + S3, HA) | medium | Core of the `stage-430` candidate below. |

## Candidate Future Stages

These map to the taxonomy ranges defined in
`.agents/skills/project-demo-stage-authoring/references/stage-taxonomy.md`.
Numbers are provisional until a stage is created (refined 2026-07-09).

| Candidate | Theme | Concept |
|-----------|-------|---------|
| `stage-430-mlflow-experiment-tracking` | AI Operations/MLOps | Advanced MLflow lifecycle: production storage (PostgreSQL + S3, HA) and model-registry integration, extending the Stage 250 MLflow foundation. |
| `stage-440-observability-and-governance` | AI Operations/MLOps | The governance gap beyond Stage 240/250: audit records, MaaS showback, consolidated operational-evidence dashboards. |
| `stage-450-gpu-self-service` | AI Operations/MLOps | User-facing GPU request/scheduling application on top of the Stage 120 GPU-as-a-Service layer (Kueue quotas, hardware profiles): request, queue, and schedule GPU capacity as a self-service workflow. Candidate implementation: [gpu-booking-app-plugin](https://github.com/rhai-code/gpu-booking-app-plugin) — an OpenShift Console dynamic plugin (Go backend, React/PatternFly v6 frontend, Helm deploy) with calendar-based GPU reservations, automatic GPU/MIG capacity discovery from node labels, and per-user Kueue ClusterQueues with protected `nominalQuota` enforced via workload preemption. Reworks the taxonomy's `stage-450-distributed-workload-operations` concept; can absorb the Kueue preemption and EvalHub-at-scale low items (the plugin's preemption model covers the former directly). |

Retired candidates (2026-07-09): `stage-250-model-evaluation` shipped;
`stage-320-llama-stack-runtime` was absorbed by Stage 230 (LSD, Responses
API, MCP connector); `stage-410-ai-pipelines` was absorbed by the Stage
230/250 DSPA implementations, with its CI/CD remainder tracked as burn-down
item 4.
