# Step 08: Model Evaluation
**"Trust but Verify"** — Quantify RAG value and benchmark model capabilities using RHOAI-native evaluation tools.

## The Business Story

Step-07 proved your RAG system can retrieve and answer. But _how much better_ are the answers compared to the base LLM? And how does your model stack up on standard reasoning benchmarks?

Step-08 provides two evaluation capabilities:

1. **RAG Evaluation** — Runs the same questions in two modes (Pre-RAG without documents, Post-RAG with pgvector retrieval), then uses `mistral-3-bf16` as an LLM-as-judge to score the quality difference. HTML reports are published to MinIO.

2. **Standard Model Evaluation** — On-demand LM-Eval benchmarks (hellaswag, arc_challenge, winogrande, boolq) for any deployed model, using RHOAI 3.3's native `LMEvalJob` CR and TrustyAI operator.

## What It Does

```text
                    RAG Evaluation (KFP Pipeline)              Standard Benchmarks (LM-Eval)
                    ─────────────────────────────              ─────────────────────────────
eval-configs/       run-rag-eval.sh / run-eval-report.sh       run-lmeval.sh / Dashboard UI
(*_tests.yaml)      ┌──────────────────────────────┐           ┌──────────────────────────┐
                    │ For each scenario:            │           │ LMEvalJob CR             │
  GitOps ──────────►│  1. Generate answers (granite)│──► MinIO │  - hellaswag             │
  (ArgoCD)          │  2. Retrieve context (pgvec)  │   HTML   │  - arc_challenge         │──► Dashboard
                    │  3. Judge (mistral-3-bf16)    │  reports │  - winogrande            │   results
                    │  4. Generate HTML report      │          │  - boolq                 │
                    └──────────────────────────────┘           └──────────────────────────┘
                          │         │          │                    │
                     lsd-rag    pgvector  mistral-3-bf16     TrustyAI Operator
                     (step-07)  (step-07)   (step-05)          (step-02)
```

| Component | Purpose | Persona |
|-----------|---------|---------|
| **Test YAMLs** | Version-controlled Q&A pairs with expected answers | QA Engineer |
| **`run-rag-eval.sh`** | Launch KFP RAG eval pipeline | MLOps Engineer |
| **`run-eval-report.sh`** | Quick eval via lsd-rag pod (debug/demo) | AI Engineer |
| **`run-lmeval.sh`** | Trigger LM-Eval standard benchmarks | AI Engineer |
| **Candidate model** | `granite-8b-agent` (8B) — generates answers | Platform |
| **Judge model** | `mistral-3-bf16` (24B) — evaluates answer quality | Platform |
| **LMEvalJob CRs** | TrustyAI-managed benchmark jobs | Platform |
| **HTML Reports** | Per-scenario pre/post RAG results in MinIO | Everyone |

### Scoring Scale (RAG Evaluation)

| Score | Meaning | Color | Quality |
|-------|---------|-------|---------|
| **(A)** | Exact match — same key facts | Green | Best |
| **(B)** | Superset — all expected points plus additional correct detail | Green | Great |
| **(C)** | Subset — covers some but not all expected points | Yellow | Partial |
| **(D)** | Minor differences that don't affect factual accuracy | Grey | Okay |
| **(E)** | Disagrees with or contradicts the expected response | Red | Fail |

## Demo Walkthrough

### Scene 1: Show the Problem — Pre-RAG Hallucination

Ask the LLM about ACME Corp **without** RAG context.

```bash
oc exec deploy/lsd-rag -n private-ai -- curl -s -X POST http://localhost:8321/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"vllm-inference/granite-8b-agent",
       "messages":[{"role":"user","content":"What is ACME Corp?"}],
       "max_tokens":200,"temperature":0,"stream":false}' | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:300])"
```

**Expected result:** The model falls back to internet training data — "ACME Corp is a fictional company from cartoons."

_What to say: "Without documents, the model hallucinates. It thinks ACME is a cartoon company, not our semiconductor client."_

### Scene 2: Run RAG Evaluation

Run the evaluation pipeline to compare pre-RAG and post-RAG answers.

```bash
# Option A: Quick eval via lsd-rag pod (faster, good for demos)
./steps/step-08-model-evaluation/run-eval-report.sh

# Option B: KFP pipeline (platform-native, tracked in DSPA)
./steps/step-08-model-evaluation/run-rag-eval.sh
```

**Expected result:** 4 HTML reports in MinIO — `acme_corporate_pre_rag_report.html`, `acme_corporate_post_rag_report.html`, `whoami_pre_rag_report.html`, `whoami_post_rag_report.html`.

### Scene 3: Review HTML Reports in MinIO

Open the MinIO Console and navigate to `rhoai-storage/eval-results/{run-id}/`.

_What to say: "Every evaluation run is versioned and stored in object storage. The team can review exactly which questions improved after adding RAG."_

### Scene 4: Scoring Breakdown

#### Post-RAG (with documents) — should score A/B

| Scenario | Scores | Summary |
|----------|--------|---------|
| **ACME Corporate** | B, B, B, B, B, B | 6/6 excellent — grounded in semiconductor docs |
| **Whoami** | B, B, B, **A** | 4/4 excellent — grounded in actual CV |

#### Pre-RAG (no documents) — should score D/E

| Scenario | Scores | Summary |
|----------|--------|---------|
| **ACME Corporate** | E, E, E, E, E, E | 6/6 fail — thinks ACME is a Looney Tunes company |
| **Whoami** | E, E, B, E | 3/4 fail — thinks Adnan Drina is a football coach |

### Scene 5: Standard Model Benchmarks (LM-Eval)

Trigger an LM-Eval benchmark for granite-8b-agent.

```bash
# Quick benchmark (50 samples per task, ~10 min)
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent

# Medium benchmark (200 samples, ~30 min)
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent 200

# Full benchmark (no limit, hours)
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent 0
```

Monitor progress:

```bash
oc get lmevaljob granite-8b-agent-eval -n private-ai -w
```

View results when complete:

```bash
oc get lmevaljob granite-8b-agent-eval -n private-ai \
  -o template --template='{{.status.results}}' | jq '.results'
```

Or view in the RHOAI Dashboard: **Develop & train > Evaluations**.

_What to say: "LM-Eval is RHOAI's built-in benchmarking service. It runs industry-standard tasks like HellaSwag and ARC Challenge to measure reasoning ability. This is how you baseline a model before deploying it."_

## Operations

### RAG Evaluation

```bash
# Full deploy: ArgoCD app + compile pipeline + launch eval
./steps/step-08-model-evaluation/deploy.sh

# KFP pipeline (tracked in DSPA, 4 reports to MinIO)
./steps/step-08-model-evaluation/run-rag-eval.sh [run_id]

# Quick eval (runs inside lsd-rag pod, good for debugging)
./steps/step-08-model-evaluation/run-eval-report.sh

# Trigger eval after ingestion
./steps/step-07-rag/run-batch-ingestion.sh acme --eval
```

### Standard Model Evaluation

```bash
# Benchmark granite-8b-agent
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent

# Benchmark mistral-3-bf16
./steps/step-08-model-evaluation/run-lmeval.sh mistral-3-bf16

# Custom limit
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent 200
```

### Validation

```bash
./steps/step-08-model-evaluation/validate.sh
```

## What to Verify After Deployment

```bash
# ArgoCD sync
oc get application step-08-model-evaluation -n openshift-gitops \
  -o jsonpath='{.status.sync.status} / {.status.health.status}'
# Expected: Synced / Healthy

# Eval ConfigMaps
oc get configmap eval-configs eval-test-cases -n private-ai
# Expected: both present

# LlamaStack eval provider
oc exec deploy/lsd-rag -n private-ai -- \
  curl -s http://localhost:8321/v1/providers | \
  python3 -c "import json,sys; print([p['provider_id'] for p in json.load(sys.stdin)['data'] if p['api']=='eval'])"
# Expected: at least 1 eval provider

# Judge model ready
oc get inferenceservice mistral-3-bf16 -n private-ai \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Expected: True

# LM-Eval configuration
oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.trustyai.eval.lmeval.permitOnline}'
# Expected: allow
```

Or run the validation script:

```bash
./steps/step-08-model-evaluation/validate.sh
```

## Design Decisions

> **Two separate models for RAG eval:** `granite-8b-agent` as candidate, `mistral-3-bf16` as judge. Using the same small model for both roles causes hallucinated judgments — it injects biases instead of faithfully comparing texts.

> **Identical test sets:** Pre-RAG and Post-RAG use the same questions and expected answers. The only variable is document context. The score difference directly quantifies RAG value.

> **Judge model hardcoded in pipeline:** `mistral-3-bf16` is called directly via its vLLM endpoint (`http://mistral-3-bf16-predictor.private-ai.svc.cluster.local:8080/v1/chat/completions`). This bypasses LlamaStack's scoring API for more reliable A–E grading.

> **Two eval scripts coexist:** `run-rag-eval.sh` (KFP pipeline, platform-native, tracked) and `run-eval-report.sh` (quick pod-based, localhost access, simpler debugging). KFP is the primary path; the shell script is the fast demo path.

> **Tests in GitOps:** Test YAMLs deploy as ConfigMaps via ArgoCD. A PostSync Job copies them to the shared PVC for the KFP pipeline. `run-eval-report.sh` copies them directly to the lsd-rag pod.

> **LM-Eval via LMEvalJob CR:** RHOAI 3.3's native evaluation service, managed by the TrustyAI operator. Templates are stored in `gitops/step-08-model-evaluation/base/lmeval/` and applied on demand.

> **Configurable sample limits:** LMEvalJob templates default to 50 samples per task for fast demo runs (~10 min). Increase via CLI (`run-lmeval.sh model 200`) or remove for full benchmarks.

> **Depends on step-07 vector stores.** Post-RAG evaluation retrieves context from `acme_corporate` and `whoami` vector stores. Run step-07 ingestion pipelines first.

## Troubleshooting

### LM-Eval job fails with "online access denied"

**Root Cause:** The DataScienceCluster doesn't have LM-Eval permissions enabled.

**Solution:**

```bash
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.trustyai.eval.lmeval}'
```

Should show `permitOnline: allow` and `permitCodeExecution: allow`. If not, redeploy step-02.

### KFP eval pipeline can't reach mistral-3-bf16

**Root Cause:** The judge model's InferenceService is not ready or the service DNS isn't resolving from KFP pods.

**Solution:**

```bash
oc get inferenceservice mistral-3-bf16 -n private-ai
oc get svc -n private-ai | grep mistral
```

The KFP pipeline connects to `http://mistral-3-bf16-predictor.private-ai.svc.cluster.local:8080`. Verify the service exists and the model is Ready.

### Post-RAG scores are low (D/E) when they should be A/B

**Root Cause:** Vector stores are empty — step-07 ingestion hasn't run.

**Solution:**

```bash
oc exec deploy/lsd-rag -n private-ai -- curl -s http://localhost:8321/v1/vector_stores | \
  python3 -c "import json,sys; [print(f\"{v['name']}: {v['file_counts']['completed']} files\") for v in json.load(sys.stdin)['data']]"
```

If stores show 0 files, run ingestion: `./steps/step-07-rag/run-batch-ingestion.sh acme && ./steps/step-07-rag/run-batch-ingestion.sh whoami`

### Evaluations page not visible in Dashboard

**Root Cause:** `disableLMEval` is `true` in `OdhDashboardConfig`.

**Solution:** Already set to `false` in `gitops/step-02-rhoai/base/rhoai-operator/dashboard-config.yaml`. If not applied, redeploy step-02.

## References

- [RHOAI 3.3 — Evaluating Large Language Models (LM-Eval)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-large-language-models_evaluate)
- [RHOAI 3.3 — Evaluating RAG Systems with Ragas](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate)
- [RHOAI 3.3 — Overview of Evaluating AI Systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/overview-evaluating-ai-systems_evaluate)
- [rhoai-genaiops/evals](https://github.com/rhoai-genaiops/evals) — KFP pipeline pattern for LlamaStack scoring
- [fantaco-redhat-one-2026](https://github.com/burrsutter/fantaco-redhat-one-2026/tree/main/evals-llama-stack) — Llama Stack eval API examples
- [EleutherAI/lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness) — Engine behind RHOAI LM-Eval
- [TrustyAI Documentation](https://trustyai.org/docs/main/main) — Tutorials for LM-Eval setup

## Next Steps

- **Step 09**: [Guardrails](../step-09-guardrails/README.md) — AI safety with TrustyAI detectors
