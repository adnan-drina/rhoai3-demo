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
- **LMEval** — a dashboard-driven `LMEvalJob` evaluating Nemotron through the
  governed MaaS endpoint; results are read from the job's `.status.results`
  (this 3.4.2 dashboard build has no reliable standalone page for them).
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

LMEvalJob (local-completions) ──► Nemotron → LMEvalJob .status.results
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
3. Show the `nemotron-safety-eval` LMEvalJob capability scorecard
   (arc_easy 0.76 / 0.84, truthfulqa_mc1 0.36). This 3.4.2 dashboard build
   has no reliable standalone page for it, so read it from the resource —
   `oc get lmevaljob nemotron-safety-eval -n model-evaluation
   -o jsonpath='{.status.results}' | jq` — or put the numbers on a slide.
4. Open **MLflow** and show the evaluation run recorded with its metrics —
   the reproducible evidence artifact.
5. Run `./submit-risk-assessment.sh` to launch the garak-kfp OWASP LLM
   Top 10 scan (visible as a KFP run under the `evalhub-garak` experiment in
   the dashboard Pipelines → Runs). Open the garak HTML report (the
   `html_report` artifact, served over HTTP) and walk the OWASP module
   scorecard — it surfaces **real** weaknesses (false-assertion acceptance,
   prompt-injection hijacking, latent injection), which is the point:
   evaluation finds what "looks good to me" misses, and gives Stage 240 a
   concrete risk register to mitigate.
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
- **Automated risk assessment** (garak-kfp) is implemented and verified: a
  stage-owned DSPA pipeline server runs a garak adversarial scan against the
  governed Nemotron and records the run in MLflow. Run it
  on demand with `./submit-risk-assessment.sh`. The default benchmark is
  `owasp_llm_top10` — a standard garak probe suite (prompt injection, data
  leakage, package hallucination, XSS/web injection, misleading assertions)
  scored by garak's built-in detectors, running entirely on the target
  model. **Live result (garak report, authoritative): across 1,750 attack
  attempts the model resisted 1,324 and was compromised on 426 — a ~24%
  attack-success rate, with garak's calibrated DEFCON grading flagging 4 of
  7 OWASP modules below DC-3 (3 Critical, 1 Very High).** Concrete findings
  include accepting false assertions (`misleading.FalseAssertion` 0/45),
  prompt-injection hijacking (`promptinject.HijackHateHumans` 0/7), and weak
  latent-injection resilience (~21–41%). This is the guard→prove closure —
  the scan surfaces the real weaknesses that Stage 240's guardrails exist to
  mitigate. The richer context-aware `intents` benchmark (SDG + multilingual
  translation + LLM judge) is selectable via
  `RHOAI_STAGE250_RISK_BENCHMARK=intents` where that machinery is provisioned.
  **Caveat**: do not cite EvalHub's aggregate `attack_success_rate` field —
  it reported `0.0` for this run, inconsistent with the ~0.24 the scan
  actually produced. Read the garak HTML report, not the aggregate.
- **Guard→prove delta** (the closing evidence): re-running the same OWASP scan
  against the Stage 240 NeMo Guardrails endpoint
  (`RHOAI_STAGE250_RISK_TARGET_URL=http://nemo-guardrails-internal.ai-safety.svc.cluster.local:8000/v1`)
  cuts attack-success from **~24% to ~8%** (resilience 76% → 92%). The rails
  fully block prompt-injection hijacking (0% → 100% resisted) and latent
  injection (28% → 100%), but do **not** catch misinformation
  (`misleading.FalseAssertion` stays 0%) and one evasion regresses
  (`phrasing.PastTense` 29% → 0%). That residual risk is the point — evaluation
  measures both the mitigation and what it misses. *Caveat: garak ran more
  attempts against the guarded endpoint (~11.7k vs 1.75k), so compare the
  rates, not the raw counts — it is a directional before/after, not a
  controlled A/B.*
- **Risk-assessment model roles**: the OWASP scan needs only the target
  model. For `intents`, the SDG and judge roles default to the **local
  Nemotron** as well (`RHOAI_STAGE250_RISK_SDG_MODEL` /
  `_JUDGE_MODEL`). This makes target and judge the same model — deliberately,
  because routing those roles to the external gpt-4o-mini through the MaaS
  gateway failed (SDG 120s timeout; detector loop on truncated streaming
  bodies). An independent external judge is the preferred posture and is a
  one-variable override where the gateway supports sustained streaming; the
  self-judge trade-off is accepted here for a reliable in-cluster demo.
- Evaluation is bursty; the demo uses small per-task `limit`s and a generous
  MaaSSubscription quota so a single-GPU run completes without 429s.

## References

- [Evaluating AI systems (RHOAI 3.4)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/evaluating_ai_systems/index)
- [How EvalHub manages two-layer Kubernetes control planes](https://developers.redhat.com/articles/2026/05/12/how-evalhub-manages-two-layer-kubernetes-control-planes)
- [EvalHub: because "looks good to me" isn't a benchmark](https://developers.redhat.com/articles/2026/05/19/evalhub-because-looks-good-me-isnt-benchmark)
- `.agents/skills/rhoai-evaluation/` and `rhoai-mlflow/` — product skills
- `PLAN.md` — implementation plan, source capture, and decision log
