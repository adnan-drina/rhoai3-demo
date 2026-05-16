# Step 08: Model Evaluation
**"Trust but Verify"** — Quantify RAG value and benchmark model capabilities using RHOAI-native evaluation tools.

## Overview

Building on **RAG** from Step 07 — within the same governed platform — this step adds **evaluation**: quantifying how much document grounding improves answers versus the base model, and benchmarking deployed models on standard tasks. That is how teams move from "it feels right" to evidence stakeholders and compliance can review. **Red Hat OpenShift AI 3.4** provides RAG quality evaluation with Ragas/TrustyAI patterns, **Standard Model Evaluation** with `LMEvalJob`, and **MLflow** experiment tracking. This step uses a KFP RAG evaluation harness and logs durable RAG quality evidence to MLflow when the RHOAI MLflow server is available.

This step demonstrates RHOAI's **Evaluation** capability — repeatable scoring and benchmarking for models and RAG pipelines — while reusing **AI pipelines**, **MLflow**, and **Model observability and governance** to make model quality measurable before production deployment.

## Architecture

![Step 08 capability map](../../docs/assets/architecture/step-08-capability-map.svg)

### What Gets Deployed

```text
Model Evaluation
├── RAG Evaluation (KFP Pipeline — 4 steps)
│   ├── scan_tests           → Discover *_tests.yaml configs from PVC
│   ├── run_and_score_tests  → Execute RAG agent, score via LLM-as-judge, HTML reports
│   ├── eval_summary         → Aggregate results, log pre/post RAG quality + improvement
│   ├── log_rag_mlflow       → Persist metrics, params, tags, references, and JSON evidence
│   ├── run-rag-eval.sh      → Launch via KFP (platform-native, tracked in DSPA)
│   ├── run-eval-report.sh   → Quick eval via lsd-rag pod (debug/demo)
│   └── HTML + MLflow        → Per-scenario reports in MinIO and run evidence in MLflow
├── Standard Benchmarks (LM-Eval)
│   ├── LMEvalJob CRs        → TrustyAI-managed benchmark jobs
│   └── run-lmeval.sh        → Trigger on-demand benchmarks
└── Dependencies
    ├── Candidate model      → Agent model (step-05) generates answers
    ├── Judge model          → Larger model (step-05) evaluates quality
    ├── lsd-rag + pgvector   → RAG infrastructure (step-07)
    └── MLflow server        → Cluster-scoped Step 12 server, optional before MLOps deploy
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **Test YAMLs** | Version-controlled Q&A pairs with expected answers | `enterprise-rag` (ConfigMaps) |
| **`run-rag-eval.sh`** | Launch KFP RAG eval pipeline | `enterprise-rag` |
| **`run-eval-report.sh`** | Quick eval via lsd-rag pod (debug/demo) | `enterprise-rag` |
| **`run-lmeval.sh`** | Trigger LM-Eval standard benchmarks | `enterprise-rag` |
| **MLflowConfig** | Project-specific artifact root for RAG evaluation runs | `enterprise-rag` |
| **LMEvalJob CRs** | TrustyAI-managed benchmark jobs | `enterprise-rag` |
| **HTML + MLflow Evidence** | Per-scenario HTML reports in MinIO plus MLflow metrics/artifacts | `minio-storage`, `enterprise-rag` workspace |

Manifests: [`gitops/step-08-model-evaluation/base/`](../../gitops/step-08-model-evaluation/base/)

<details>
<summary>RHOAI and OCP Features in This Step</summary>

| | Feature | Status |
|---|---|---|
| RHOAI | Evaluation (LM-Eval, LLM-as-Judge) | Introduced |
| RHOAI | Model observability and governance | Used |
| RHOAI | AI pipelines (KFP v2) | Used |
| RHOAI | MLflow tracking server | Technology Preview; used when Step 12 MLflow server is present |
| RHOAI | Optimized model serving (judge model) | Used |

#### Scoring Scale (RAG Evaluation)

| Score | Meaning | Color | Quality |
|-------|---------|-------|---------|
| **(A)** | Exact match — same key facts | Green | Best |
| **(B)** | Superset — all expected points plus additional correct detail | Green | Great |
| **(C)** | Subset — covers some but not all expected points | Yellow | Partial |
| **(D)** | Minor differences that don't affect factual accuracy | Grey | Okay |
| **(E)** | Disagrees with or contradicts the expected response | Red | Fail |

</details>

<details>
<summary>Design Decisions</summary>

> **Two separate models for RAG eval:** `granite-8b-agent` as candidate, `mistral-3-bf16` as judge. Using the same small model for both roles causes hallucinated judgments — it injects biases instead of faithfully comparing texts.

> **Identical test sets:** Pre-RAG and Post-RAG use the same questions and expected answers. The only variable is document context. The score difference directly quantifies RAG value.

> **Judge model hardcoded in pipeline:** `mistral-3-bf16` is called directly via its vLLM endpoint (`http://mistral-3-bf16-predictor.maas.svc.cluster.local:8080/v1/chat/completions`). This bypasses LlamaStack's scoring API for more reliable A–E grading.

> **Two eval scripts coexist:** `run-rag-eval.sh` (KFP pipeline, platform-native, tracked) and `run-eval-report.sh` (quick pod-based, localhost access, simpler debugging). KFP is the primary path; the shell script is the fast demo path.

> **Tests in GitOps:** Test YAMLs deploy as ConfigMaps via ArgoCD. A PostSync Job copies them to the shared PVC for the KFP pipeline. `run-eval-report.sh` copies them directly to the lsd-rag pod.

> **LM-Eval via LMEvalJob CR:** RHOAI 3.4's native evaluation service, managed by the TrustyAI operator. Templates are stored in `gitops/step-08-model-evaluation/base/lmeval/` and applied on demand.

> **MLflow evidence for enterprise RAG.** RHOAI 3.4 documents MLflow as the central tracking server for parameters, metrics, and artifacts. The `log_rag_mlflow` component records the same RAG evaluation summary that appears in the Dashboard into an `enterprise-rag` MLflow experiment. This gives teams before/after comparison across prompt, model, retriever, vector-store, and guardrail changes.

> **EvalHub alignment without overclaiming.** RHOAI 3.4 also documents EvalHub with MLflow experiment tracking for evaluation jobs. This step does not deploy EvalHub yet; it implements the same tracking intent directly from the KFP RAG evaluation pipeline and keeps EvalHub as a follow-up platform enhancement.

> **Configurable sample limits:** LMEvalJob templates default to 50 samples per task for fast demo runs (~10 min). Increase via CLI (`run-lmeval.sh model 200`) or remove for full benchmarks.

> **Depends on step-07 vector stores.** Post-RAG evaluation retrieves context from `acme_corporate` and `whoami` vector stores. Run step-07 ingestion pipelines first.

</details>

<details>
<summary>Deploy</summary>

```bash
./steps/step-08-model-evaluation/deploy.sh     # ArgoCD app + compile pipeline + launch eval
./steps/step-08-model-evaluation/validate.sh   # Verify eval ConfigMaps, providers, judge model, fresh results
```

Additional operations:

```bash
# RAG Evaluation
./steps/step-08-model-evaluation/run-rag-eval.sh [run_id]   # KFP pipeline (tracked in DSPA)
./steps/step-08-model-evaluation/run-eval-report.sh          # Quick eval via lsd-rag pod
./steps/step-07-rag/run-batch-ingestion.sh acme --eval       # Trigger eval after ingestion

# Standard Model Evaluation (LM-Eval)
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent      # 50 samples (~10 min)
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent 200  # 200 samples (~30 min)
./steps/step-08-model-evaluation/run-lmeval.sh mistral-3-bf16        # Benchmark second model
```

</details>

<details>
<summary>What to Verify After Deployment</summary>

| Check | What It Tests | Pass Criteria |
|-------|--------------|---------------|
| ArgoCD sync | App synced and healthy | Synced / Healthy |
| Eval ConfigMaps | eval-configs and eval-test-cases | Both present |
| Eval provider | LlamaStack eval provider registered | At least 1 provider |
| Judge model | mistral-3-bf16 InferenceService | READY=True |
| LM-Eval config | DataScienceCluster LM-Eval permissions | `permitOnline: allow` |
| RAG eval reports | HTML reports in MinIO | Latest report within `DEMO_FRESHNESS_HOURS` |
| MLflow workspace | `enterprise-rag` MLflowConfig and pipeline RoleBinding | Present |
| MLflow run evidence | Latest `enterprise-rag` run tagged `rhoai.demo.step=08` | Fresh finished run, or warning if MLflow not deployed yet |
| LM-Eval runs | LMEvalJob CRs | Recent completed job per model |

```bash
oc get applications.argoproj.io step-08-model-evaluation -n openshift-gitops \
  -o jsonpath='{.status.sync.status} / {.status.health.status}'

oc get configmap eval-configs eval-test-cases -n enterprise-rag

oc exec deploy/lsd-rag -n enterprise-rag -- \
  curl -s http://localhost:8321/v1/providers | \
  python3 -c "import json,sys; print([p['provider_id'] for p in json.load(sys.stdin)['data'] if p['api']=='eval'])"

oc get inferenceservice mistral-3-bf16 -n maas \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.trustyai.eval.lmeval.permitOnline}'

oc get mlflowconfig mlflow -n enterprise-rag \
  -o jsonpath='{.spec.artifactRootPath}'
```

</details>

## The Demo

> In this demo, we quantify the value of RAG by comparing the same questions with and without document context, then run industry-standard benchmarks to baseline model reasoning capabilities — proving that evaluation is a platform capability, not an afterthought.

### The Problem — Pre-RAG Hallucination

> We start by asking the LLM about ACME Corp without RAG context. This establishes the baseline: what does the model think it knows when it has no access to your documents?

1. Ask the LLM about ACME Corp without RAG context:

```bash
oc exec deploy/lsd-rag -n enterprise-rag -- curl -s -X POST http://localhost:8321/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"vllm-inference/granite-8b-agent",
       "messages":[{"role":"user","content":"What is ACME Corp?"}],
       "max_tokens":200,"temperature":0,"stream":false}' | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:300])"
```

**Expect:** The model falls back to internet training data — "ACME Corp is a fictional company from cartoons."

> Without documents, the model hallucinates. It thinks ACME is a cartoon company, not our semiconductor client. This is the gap RAG fills — and evaluation measures.

### Run RAG Evaluation

> Now we run the evaluation pipeline to systematically compare pre-RAG and post-RAG answers across all test questions. The same questions, the same expected answers — the only variable is document context.

1. Run the evaluation:

```bash
# Option A: Quick eval via lsd-rag pod (faster, good for demos)
./steps/step-08-model-evaluation/run-eval-report.sh

# Option B: KFP pipeline (platform-native, tracked in DSPA)
./steps/step-08-model-evaluation/run-rag-eval.sh
```

**Expect:** A 4-step pipeline: `scan_tests` → `run_and_score_tests` → `eval_summary` → `log_rag_mlflow`. The summary step logs pre/post-RAG quality and RAG improvement metrics to the Dashboard. The `run_and_score_tests` step produces an `Output[HTML]` artifact viewable inline in the Dashboard, plus 4 HTML reports uploaded to MinIO. When the MLflow server is present, `log_rag_mlflow` creates an `enterprise-rag` run with metrics, params, tags, and compact JSON evidence artifacts.

> The evaluation pipeline is a Kubeflow Pipeline — tracked, versioned, and visible in the RHOAI Dashboard. Every run is reproducible and auditable, not a one-off script execution.

### Review Results

> The evaluation summary quantifies the value of RAG in a single number: the quality improvement from document grounding.

1. Check the `eval_summary` Dashboard metrics:
   - `pre_rag_quality` — baseline without documents (expect ~20%)
   - `post_rag_quality` — with RAG context (expect ~90%)
   - `rag_improvement` — quality delta (expect +70pp)
   - `reports` — clickable MinIO console URL to view full HTML reports
2. Check the MLflow experiment:
   - Experiment: `enterprise-rag`
   - Run name: `rag-eval-<run_id>`
   - Tags: `rhoai.demo.step=08`, `rhoai.demo.capability=enterprise-rag-evaluation`
   - Artifacts: `rag-eval-summary.json`, `rag-eval-context.json`, `rag-eval-references.json`

**Expect:** A clear quality gap — ~20% without documents to ~90% with them.

> Every evaluation run is versioned and stored in object storage. The summary shows the quality improvement from RAG — the measurable proof that connecting your model to your data transforms answer quality.

### Scoring Breakdown

> The scoring breakdown shows how the LLM-as-judge evaluated each individual question across both scenarios — demonstrating the A-E grading scale in practice.

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

**Expect:** Post-RAG scores are consistently A/B (grounded in real documents), Pre-RAG scores are consistently D/E (hallucination from training data).

> The contrast is stark. With documents, every answer is grounded and accurate. Without documents, the model confidently fabricates information. This is why evaluation must be automated and repeatable — you need to know the moment your RAG pipeline stops delivering value.

### Standard Model Benchmarks (LM-Eval)

> RAG evaluation measures retrieval quality. Standard benchmarks measure the model itself — reasoning, comprehension, common sense. RHOAI's native LM-Eval service runs industry-standard tasks against any deployed model.

1. Trigger an LM-Eval benchmark for granite-8b-agent:

```bash
# Quick benchmark (50 samples per task, ~10 min)
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent

# Medium benchmark (200 samples, ~30 min)
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent 200

# Full benchmark (no limit, hours)
./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent 0
```

2. Monitor progress:

```bash
oc get lmevaljob granite-8b-agent-eval -n enterprise-rag -w
```

3. View results when complete:

```bash
oc get lmevaljob granite-8b-agent-eval -n enterprise-rag \
  -o template --template='{{.status.results}}' | jq '.results'
```

4. Or view in the RHOAI Dashboard: **Develop & train → Evaluations**

**Expect:** Benchmark results for HellaSwag, ARC Challenge, WinoGrande, and BoolQ — the standard reasoning tasks that baseline a model before production deployment.

> LM-Eval is RHOAI's built-in benchmarking service, managed by the TrustyAI operator. It runs industry-standard tasks to measure reasoning ability — this is how you baseline a model before deploying it, and how you validate that fine-tuning or quantization didn't degrade capabilities.

## Key Takeaways

**For business stakeholders:**

- Replace "it feels right" with evidence stakeholders can review
- Measure whether grounding actually improves answer quality
- Create a repeatable basis for governance and production decisions

**For technical teams:**

- Evaluate RAG quality in a tracked pipeline and persist the run in MLflow
- Benchmark served models with standard tasks using TrustyAI tooling
- Keep evaluation results versioned, reviewable, and tied to the deployed platform

<details>
<summary>Troubleshooting</summary>

### LM-Eval job fails with "online access denied"

**Root Cause:** The DataScienceCluster doesn't have LM-Eval permissions enabled.

**Solution:**

```bash
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.trustyai.eval.lmeval}'
```

Should show `permitOnline: allow` and `permitCodeExecution: allow`. If not, redeploy step-02.

### Post-RAG scores are low (D/E) when they should be A/B

**Root Cause:** Vector stores are empty — step-07 ingestion hasn't run.

**Solution:**

```bash
oc exec deploy/lsd-rag -n enterprise-rag -- curl -s http://localhost:8321/v1/vector_stores | \
  python3 -c "import json,sys; [print(f\"{v['name']}: {v['file_counts']['completed']} files\") for v in json.load(sys.stdin)['data']]"
```

If stores show 0 files, run ingestion: `./steps/step-07-rag/run-batch-ingestion.sh acme && ./steps/step-07-rag/run-batch-ingestion.sh whoami`

### KFP eval pipeline can't reach mistral-3-bf16

**Root Cause:** The judge model's InferenceService is not ready or the service DNS isn't resolving from KFP pods.

**Solution:**

```bash
oc get inferenceservice mistral-3-bf16 -n maas
oc get svc -n maas | grep mistral
```

The KFP pipeline connects to `http://mistral-3-bf16-predictor.maas.svc.cluster.local:8080`. Verify the service exists in maas and the model is Ready.

### MLflow run evidence is missing

**Root Cause:** Step 08 can run before the Step 12 MLflow server exists, or the `pipeline-runner-dspa-rag` ServiceAccount does not yet have the MLflow integration RoleBinding.

**Solution:**

```bash
oc get mlflow mlflow
oc get mlflowconfig mlflow -n enterprise-rag
oc get rolebinding rag-eval-pipeline-mlflow-client -n enterprise-rag
./steps/step-08-model-evaluation/run-rag-eval.sh
```

If the MLflow server is not deployed yet, deploy Step 12 and rerun the RAG evaluation.

### Evaluations page not visible in Dashboard

**Root Cause:** `disableLMEval` is `true` in `OdhDashboardConfig`.

**Solution:** Already set to `false` in `gitops/step-02-rhoai/base/rhoai-operator/dashboard-config.yaml`. If not applied, redeploy step-02.

</details>

## References

- [RHOAI 3.4 — Evaluating Large Language Models (LM-Eval)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/evaluating_ai_systems/evaluating-large-language-models_evaluate)
- [RHOAI 3.4 — Evaluating RAG Systems with Ragas](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate)
- [RHOAI 3.4 — Working with MLflow](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow/index)
- [RHOAI 3.4 — Configure MLflow experiment tracking for EvalHub evaluation jobs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/evaluating_ai_systems/evaluating-llms-with-evalhub_evaluate)
- [RHOAI 3.4 — Overview of Evaluating AI Systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/evaluating_ai_systems/overview-evaluating-ai-systems_evaluate)
- [rhoai-genaiops/evals](https://github.com/rhoai-genaiops/evals) — KFP pipeline pattern for LlamaStack scoring
- [fantaco-redhat-one-2026](https://github.com/burrsutter/fantaco-redhat-one-2026/tree/main/evals-llama-stack) — Llama Stack eval API examples
- [EleutherAI/lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness) — Engine behind RHOAI LM-Eval
- [TrustyAI Documentation](https://trustyai.org/docs/main/main) — Tutorials for LM-Eval setup
- `rh-brain`: `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/raw/Synthetic data for RAG evaluation Why your RAG system needs better testing.md`
- `rh-brain`: `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/raw/Evaluation Quickstart  MLflow AI Platform.md`
- `rh-brain`: `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/raw/Evaluating (Production) Traces  MLflow AI Platform 1.md`
- `rh-brain`: `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/raw/Build resilient guardrails for OpenClaw AI agents on Kubernetes 1.md`
- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Production AI datasheet](https://www.redhat.com/en/resources/production-ai-for-cloud-environments-datasheet)
- [Get started with AI for enterprise organizations — Red Hat](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)

## Next Steps

- **Step 09**: [Guardrails](../step-09-guardrails/README.md) — AI safety with TrustyAI detectors
