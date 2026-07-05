# Model Evaluation

Stage 250 proves the governed GenAI model with **standardized, reproducible
evaluation** instead of "looks good to me." It deploys the TrustyAI EvalHub
evaluation control plane, runs a pass/fail safety-and-fairness scorecard and
a dashboard-driven LMEval job against the governed Nemotron model, and tracks
every run in MLflow.

## Why This Matters

A model that passes a demo can still fail in production — confidently wrong
answers, stale policy, unsafe output. The gap is not catastrophic failure; it
is that the team measured the demo, not the deployment. Enterprises,
especially under the EU AI Act and similar regimes, need **documented,
reproducible evidence** of model behaviour — not a dashboard screenshot.
Evaluation is the step that turns "we think it works" into "here is the
scorecard, the threshold it passed, and the run that produced it."

Stage 250 closes the Production-GenAI arc: Stage 210 served the model, 220
governed it, 230 grounded it in private data, 240 guarded it — and 250
measures it.

## What Enables It

- **EvalHub** (`trustyai.opendatahub.io/v1alpha1`, reconciled by the TrustyAI
  Operator) — a stateless REST evaluation control plane backed by PostgreSQL.
  It dispatches each benchmark as a Kubernetes Job (adapter container +
  ServiceAccount-token sidecar) and aggregates weighted, pass-criteria'd
  scores. Providers and collections ship out of the box with the operator.
- **Providers**: `lm-evaluation-harness` (capability/knowledge), `garak`
  (safety red-teaming), `guidellm` (performance — ties back to the Stage 210
  capacity benchmark).
- **Collection**: `safety-and-fairness-v1` — a weighted set of benchmarks
  (truthfulqa, etc.) with a pass threshold (0.758), producing a single
  scorecard for the governed model.
- **LMEval** — a dashboard-driven `LMEvalJob` visible on the OpenShift AI
  console Model Evaluation page, evaluating Nemotron through the governed MaaS
  endpoint.
- **MLflow** (product-managed, `mlflow.opendatahub.io/v1`) — experiment
  tracking so every evaluation run is a queryable historical record. Deployed
  minimally (SQLite metadata + PVC artifacts); EvalHub records runs through
  the operator-provided `mlflow.kubeflow.org` RBAC.
- **Governed model access** — a dedicated `model-evaluation` MaaSSubscription
  and a minted API key route evaluation traffic through the Stage 220 MaaS
  gateway (via an in-cluster proxy), so even evaluation stays quota'd and
  governed.

## Architecture

```text
EvalHub CR ── TrustyAI operator ──► EvalHub server (REST, X-Tenant, Postgres)
   providers: lm-evaluation-harness, garak, guidellm
   collection: safety-and-fairness-v1  (weighted, pass threshold 0.758)
        │
        ▼  per-benchmark Kubernetes Job (adapter + SA-token sidecar)
   ├─► Nemotron via maas-internal-proxy → MaaS gateway (governed, quota'd)
   └─► MLflow (product operator, SQLite + PVC) — experiment run per evaluation

LMEvalJob (local-completions) ──► Nemotron → console Model Evaluation page
```

Delta on Stage 240: a new `model-evaluation` namespace is both the EvalHub
control plane and the evaluation tenant (label
`evalhub.trustyai.opendatahub.io/tenant=true`, so the operator auto-provisions
tenant RBAC); the shared `DataScienceCluster` gains `mlflowoperator: Managed`
(`trustyai` was already Managed by Stage 240); the Stage 220 policy layer
gains the `model-evaluation` subscription.

## Demo Flow

1. Un-park the environment if needed (GPU + Nemotron), then `./deploy.sh` and,
   after sync, `./validate.sh`.
2. Open the **EvalHub** tile / Swagger UI and submit the
   `safety-and-fairness-v1` collection against Nemotron; watch the job move
   through `pending → running → completed` and read the weighted scorecard
   against its pass threshold.
3. Open the OpenShift AI console **Model Evaluation** page and show the
   `nemotron-safety-eval` LMEvalJob results (truthfulqa / arc_easy).
4. Open **MLflow** and show the evaluation run recorded with its metrics —
   the reproducible evidence artifact.
5. Run `./submit-risk-assessment.sh` to launch the garak-kfp adversarial
   red-team pipeline (visible as a KFP run in the dashboard) and show the
   vulnerability findings — proving the Stage 240 guardrails hold under
   attack.
6. Frame it: this is what turns a governed, guarded model into a
   *deployable* one — a scorecard, a threshold, a tracked run, and an
   adversarial red-team, not a spot check.

## Scope And Limitations

- Evaluates **Nemotron only** (the local governed model powering the RAG
  chatbot and guardrails). Comparing multiple models is a straightforward
  follow-up (add model refs + a second job).
- MLflow is the **minimal dev pattern** (SQLite + PVC, single writer);
  production-scale MLflow (PostgreSQL + S3, HA) is the future
  `stage-430` scope. EvalHub metadata itself uses PostgreSQL.
- **Automated risk assessment** (garak-kfp) is implemented: a stage-owned
  DSPA pipeline server runs the two-phase adversarial red-team (synthetic
  prompt generation via gpt-4o-mini, then garak attack probes against
  Nemotron, judged by gpt-4o-mini). Run it on demand with
  `./submit-risk-assessment.sh`. This is the guard→prove closure — it
  adversarially tests the model the Stage 240 guardrails protect.
- Evaluation is bursty; the demo uses small per-task `limit`s and a generous
  MaaSSubscription quota so a single-GPU run completes without 429s.

## References

- [Evaluating AI systems (RHOAI 3.4)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/evaluating_ai_systems/index)
- [How EvalHub manages two-layer Kubernetes control planes](https://developers.redhat.com/articles/2026/05/12/how-evalhub-manages-two-layer-kubernetes-control-planes)
- [EvalHub: because "looks good to me" isn't a benchmark](https://developers.redhat.com/articles/2026/05/19/evalhub-because-looks-good-me-isnt-benchmark)
- `.agents/skills/rhoai-evaluation/` and `rhoai-mlflow/` — product skills
- `PLAN.md` — implementation plan, source capture, and decision log
