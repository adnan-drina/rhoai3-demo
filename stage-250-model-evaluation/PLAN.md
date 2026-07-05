# Stage 250: Model Evaluation Plan

## Intent

Deploy the TrustyAI EvalHub evaluation control plane and MLflow experiment
tracking, and produce a pass/fail safety-and-fairness scorecard plus a
dashboard-driven `LMEvalJob` for the governed Nemotron model, following the
RHOAI 3.4 guide *Evaluating AI systems*. Close the Production-GenAI arc:
serve → govern → RAG → guard → **prove it**.

## Acceptance Criteria

- `DataScienceCluster` `mlflowoperator` is `Managed` (flipped by a
  stage-owned Argo Sync-hook Job); `trustyai` already Managed from Stage 240.
- EvalHub CR `evalhub` in `model-evaluation` is Available; `/api/v1/health`
  responds and `/api/v1/evaluations/providers` lists the OOTB providers.
- PostgreSQL backs EvalHub; `evalhub-db-credentials` holds a `db-url` key
  (never committed).
- MLflow CR `mlflow` is Available with a dashboard route; EvalHub records an
  experiment run via the operator-provided `mlflow.kubeflow.org` RBAC.
- A `safety-and-fairness-v1` EvalHub job reaches `completed` with a weighted
  score vs the pass threshold; the `nemotron-safety-eval` LMEvalJob completes
  and appears on the console Model Evaluation page.
- Governed access: `model-evaluation` MaaSSubscription present; a minted
  `sk-oai-*` key in `model-evaluation-model-token`; no key/URL leaked into
  ConfigMaps.
- `validate.sh` exits 0.

## Source Capture

Primary: RHOAI 3.4 *Evaluating AI systems* (repo PDF at
`stage-230-private-data-rag/data/rhoai-product-docs/source/`). Skills:
`rhoai-evaluation` (EvalHub/LMEval/risk-assessment authority) and
`rhoai-mlflow` (product MLflow CR, RBAC, storage patterns).

### rh-brain Article Selection

User-shared Red Hat Developer articles (2026-05): "How EvalHub manages
two-layer Kubernetes control planes" (control plane + per-job execution
layer, adapter+sidecar, PostgreSQL state, tenant label model) and "EvalHub:
because looks good to me isn't a benchmark" (enterprise framing, collections
with pass criteria, MLflow evidence, EU-AI-Act governance).

## Skill Routing

- `rhoai-evaluation` — EvalHub CR/providers/collections, LMEvalJob, tenant
  RBAC, endpoints.
- `rhoai-mlflow` — product MLflow CR, `mlflow.kubeflow.org` RBAC,
  dev/prod storage patterns.
- `rhoai-maas-governance` / stage-220 — MaaSSubscription + key minting.
- `project-gitops-authoring`, `project-red-hat-operator-gitops` — stage
  layout, DSC patch-Job pattern, Argo Application.

## GitOps Ownership

Stage 250 owns `gitops/stage-250-model-evaluation/` and the Application
`gitops/argocd/app-of-apps/stage-250-model-evaluation.yaml` (sync-wave "7").

Shared resources touched:
- `DataScienceCluster default-dsc` (stage-110 owner): `mlflowoperator` →
  `Managed` via Sync-hook Job (stage-210/230/240 precedent). Stage-110
  `ignoreDifferences` gains `/spec/components/mlflowoperator`.
- `gitops/stage-220-models-as-a-service/policies/base/model-evaluation-access.yaml`
  — dedicated MaaSSubscription (nemotron, 2M tokens/h burst).
- **MLflow is a cluster-scoped singleton** (name `mlflow`); the operator
  deploys its pod/Service/route in `redhat-ods-applications`. Stage 250 owns
  this cluster resource as the MLflow foundation.

Environment-local, never committed: `evaluation-postgres-credentials`,
`evalhub-db-credentials` (db-url), `model-evaluation-model-token` (minted
key), `maas-internal-proxy-config` (generated nginx conf).

## Manifest Inventory

| Path | Content |
|------|---------|
| `project/base/` | Namespace (tenant + dashboard labels), developer/admin RoleBindings |
| `rhoai-dsc/base/patch-dsc-mlflowoperator.yaml` | SA+ClusterRole+CRB + Sync-hook Job → mlflowoperator Managed |
| `postgresql/base/` | EvalHub PostgreSQL StatefulSet + Service |
| `mlflow/base/mlflow.yaml` | cluster-scoped MLflow (SQLite + PVC, serveArtifacts) |
| `evalhub/base/` | EvalHub CR (postgres, providers, collection, MLflow env) + jobs SA + view/mlflow-integration RoleBindings |
| `maas-proxy/base/` | vendored nginx hairpin proxy |
| `lmeval/base/lmevaljob-nemotron.yaml` | dashboard-driven LMEvalJob (truthfulqa_mc1 + arc_easy, limit 50, key via secretKeyRef) |
| `dashboard/base/` | EvalHub OdhApplication tile + EvalHub/MLflow ConsoleLinks + discovery patch Job |
| `gitops/argocd/app-of-apps/stage-250-model-evaluation.yaml` | Application, wave "7", ignoreDifferences for minted Secrets + ConsoleLink hrefs |
| `gitops/stage-220-…/policies/base/model-evaluation-access.yaml` | MaaSSubscription (shared-owner touch) |

## Script Plan

### deploy.sh
Guards + `RHOAI_STAGE250_*` overrides; `ensure_nemotron_available` preflight;
`apply_argocd_application` (+ refresh stage-220, stage-110); waits for
namespace + MaaSSubscription; `ensure_db_secrets` (postgres creds + EvalHub
`db-url`); `ensure_maas_proxy_config`; `ensure_model_token` (mint sk-oai key);
`wait_for_mlflow` (DSC Managed + MLflow Available); `wait_for_evalhub`
(deployment available).

### validate.sh
Argo Synced/Healthy; namespace + tenant label + RBAC; DSC trustyai +
mlflowoperator Managed; PostgreSQL ready + `db-url` present; MaaSSubscription;
proxy deployment; model token `sk-oai-*` + no secret leak into ConfigMaps;
MLflow Available + route; EvalHub deployment + `/health` + providers list;
LMEvalJob state (Complete / in-progress / skipped-if-parked).

## Operations And Troubleshooting

`docs/OPERATIONS.md`: EvalHub tenant/token usage, submitting a job, MLflow
route, quota rotation. `docs/TROUBLESHOOTING.md`: missing `db-url`, X-Tenant
errors, model-endpoint 401/429, MLflow auth, LMEvalJob stuck pending.

## Risks And Deferred Work

| Item | Status |
|------|--------|
| Automated risk assessment (garak-kfp) | Deferred — needs a KFP pipeline server + judge model; strongest guardrails tie-back, backlog |
| Production MLflow (PostgreSQL + S3, HA) | Deferred — minimal SQLite+PVC now; future stage-430 |
| Multi-model comparison (Nemotron vs gpt-4o-mini) | Deferred — user chose Nemotron-only; add a model ref + job later |
| EvalHub OCI result export / S3 custom data | Deferred — not needed for the core scorecard demo |

Risks:
- EvalHub→MLflow auth uses `mlflow.kubeflow.org` pseudo-resource RBAC
  (operator-provided ClusterRoles); verified the roles exist, verify the run
  records live.
- EvalHub→Nemotron uses the minted MaaS key via the in-cluster proxy; confirm
  the job model-config field carries the key at deploy.
- MLflow cluster singleton owned by 250; a future stage-430 takes over.

## Review Log

- 2026-07-05: Plan approved. Scope: EvalHub + benchmark jobs + dashboard
  LMEvalJob; Nemotron-only; minimal product MLflow deployed now.
  Live-verified: EvalHub/MLflow/LMEvalJob schemas, OOTB provider/collection
  names, EvalHub↔MLflow operator RBAC, KServe RawDeployment prereq met,
  MLflow deploys in redhat-ods-applications (Service :8443, dashboard route
  /mlflow).

## Retrospective And Skill Updates

To be completed at stage wrap.
