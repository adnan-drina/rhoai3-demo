# Step 08: RAG Evaluation

**"Trust but Verify"** - Automated quality gates for RAG answer grounding and tool-use correctness.

## The Business Story

Step-07 proved your RAG system can retrieve and answer. But how do you know the answers stay grounded after you change chunk sizes, swap embedding models, or ingest new documents? Step-08 adds a repeatable evaluation pipeline that scores faithfulness, relevancy, and tool behavior -- then publishes human-readable reports.

| Component | Purpose | Persona |
|-----------|---------|---------|
| **Test YAMLs** | Version-controlled Q&A pairs with expected answers | QA Engineer, AI Engineer |
| **KFP Eval Pipeline** | Discover tests, execute RAG agent, score, report | MLOps Engineer |
| **Llama Stack Scoring** | `llm-as-judge` for answer quality assessment | Platform (invisible) |
| **Custom Tool Scorer** | Verify `knowledge_search` was invoked correctly | AI Engineer |
| **HTML Reports** | Per-scenario results in S3 for team review | Everyone |

## Architecture

```
Test Configs            KFP Eval Pipeline              Results
(*_tests.yaml)    ┌──────────────────────────┐
                  │  1. Scan: discover YAMLs  │
  eval-configs/ ──│  2. For each test:        │── HTML reports
                  │     a. Call RAG agent      │   s3://pipelines/
                  │     b. Score via LlamaStack│   eval-results/
                  │     c. Score tool_choice   │   {run_id}/
                  │  3. Generate HTML          │
                  │  4. Upload to S3           │
                  └──────────────────────────┘
                         │           │
                    lsd-rag      granite-8b-agent
                    (step-07)      (step-05)
```

No new infrastructure is deployed. This step reuses `lsd-rag` (step-07) for both
RAG execution and scoring, and `dspa-rag` (step-07) for pipeline orchestration.

## Prerequisites

```bash
# Step-07 RAG infrastructure must be deployed and healthy
oc get llamastackdistribution lsd-rag -n private-ai
oc get dspa dspa-rag -n private-ai
oc get pvc rag-pipeline-workspace -n private-ai

# At least one Milvus collection should be populated
oc exec deploy/lsd-rag -n private-ai -- curl -s http://localhost:8321/v1/vector-io/query \
  -H "Content-Type: application/json" \
  -d '{"vector_db_id":"acme_corporate","query":"test"}' | jq '.chunks | length'
```

## Deployment

### A) One-shot (recommended)

```bash
./steps/step-08-rag-evaluation/deploy.sh
```

This will:
1. Copy eval configs to the cluster PVC
2. Compile the eval pipeline
3. Launch an evaluation run against all 3 scenarios
4. Print the S3 location of HTML reports

### B) Run evaluation manually

```bash
# Copy configs to cluster (first time only)
./steps/step-08-rag-evaluation/deploy.sh  # or manually oc cp

# Trigger a new eval run
./steps/step-08-rag-evaluation/run-eval.sh my-run-id
```

### C) Re-run after changing tests

Edit files in `eval-configs/`, then:
```bash
./steps/step-08-rag-evaluation/deploy.sh
```

The deploy script re-copies configs and launches a fresh run.

## Validation

```bash
./steps/step-08-rag-evaluation/validate.sh
```

### Manual checks

```bash
# Pipeline run status
oc get pods -n private-ai -l pipeline/runid --sort-by=.metadata.creationTimestamp | tail -5

# List HTML reports in MinIO
oc exec deploy/minio -n minio-storage -- \
  mc ls --recursive myminio/pipelines/eval-results/
```

## Test YAML Format

Each `*_tests.yaml` file defines a set of evaluation cases for one RAG scenario:

```yaml
name: "ACME Corporate RAG Quality"
description: "Evaluate RAG answers against ACME documentation"
vector_db_id: acme_corporate
model_id: granite-8b-agent
llamastack_url: http://lsd-rag.private-ai.svc:8321

scoring_params:
  llm-as-judge::answer-correctness:
    judge_model: granite-8b-agent
    prompt_template: scoring-templates/answer_correctness.txt
  llm-as-judge::answer-groundedness:
    judge_model: granite-8b-agent
    prompt_template: scoring-templates/answer_groundedness.txt
  basic::tool_choice: null

tests:
  - prompt: "What are the key calibration procedures?"
    expected_result: "Calibration involves alignment, dose, and focus."
    expected_tools:
      - builtin::rag/knowledge_search
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Human-readable scenario name |
| `vector_db_id` | Yes | Milvus collection to query |
| `model_id` | Yes | LLM for RAG agent (must support tool-calling) |
| `scoring_params` | Yes | Map of scorer name to config (null for defaults) |
| `tests[].prompt` | Yes | Question to ask the RAG agent |
| `tests[].expected_result` | Yes | Reference answer for scoring |
| `tests[].expected_tools` | No | List of tools the agent should invoke |

### Scoring prompt templates

Long prompts are stored as `.txt` files in `scoring-templates/` and referenced by relative path in the YAML. The pipeline resolves these automatically.

## Scoring Model

| Scorer | What it measures | Scale |
|--------|-----------------|-------|
| `llm-as-judge::answer-correctness` | Factual accuracy vs expected answer | 0.0 - 1.0 |
| `llm-as-judge::answer-groundedness` | Whether the answer is grounded (not hallucinated) | 0.0 - 1.0 |
| `basic::tool_choice` | Whether expected RAG tools were invoked | 0.0 - 1.0 |

### Tool Choice Scoring

| Score | Meaning |
|-------|---------|
| 1.0 | All expected tools called, no extras |
| 0.8 | All expected tools called, plus extra tools |
| 0.5 | Some expected tools called |
| 0.0 | No expected tools called |

## Adding New Tests

1. Create a new file in `eval-configs/` ending in `_tests.yaml`
2. Set the `vector_db_id` to the Milvus collection to query
3. Add test cases with `prompt`, `expected_result`, and optionally `expected_tools`
4. Re-run `deploy.sh` to copy and execute

The pipeline discovers tests by globbing `**/*_tests.yaml` -- no manifest to update.

## Interpreting Results

### Recommended Thresholds

| Metric | Excellent | Acceptable | Needs Work |
|--------|-----------|------------|------------|
| answer-correctness | > 0.8 | 0.6 - 0.8 | < 0.6 |
| answer-groundedness | > 0.8 | 0.6 - 0.8 | < 0.6 |
| tool_choice | 1.0 | 0.8 | < 0.8 |

### Common patterns

- **High correctness, low groundedness**: Model is getting the right answer but may be hallucinating details not in the source documents. Check chunk quality.
- **Low correctness, high groundedness**: Retrieval is working but the wrong chunks are being retrieved. Check Milvus collection content and embedding quality.
- **tool_choice < 1.0**: The agent is not consistently invoking `knowledge_search`. Check if the model supports tool-calling and if the system prompt is correct.

## Troubleshooting

### Pipeline run fails immediately

**Symptom:** Pod exits with error.

**Solution:**
```bash
oc logs <pod-name> -n private-ai
# Common: eval configs not copied to PVC, or lsd-rag not reachable
```

### LlamaStack scoring timeout

**Symptom:** `scoring.score()` times out after 600s.

**Solution:** The `llm-as-judge` scorer calls the LLM for each test row. If `granite-8b-agent` InferenceService is not running (minReplicas: 0), scale it up first.

### All scores are ERROR

**Symptom:** HTML report shows ERROR for all scoring functions.

**Solution:** Check that lsd-rag has the `scoring` providers configured:
```bash
oc get configmap llama-stack-rag-config -n private-ai -o yaml | grep -A5 scoring
```

### Empty Milvus collections

**Symptom:** RAG answers are generic (not grounded in documents).

**Solution:** Run the step-07 ingestion pipeline first to populate Milvus collections.

## Directory Structure

```
steps/step-08-model-evaluation/
├── deploy.sh                          # Full deployment + run
├── run-eval.sh                        # Standalone eval trigger
├── validate.sh                        # Check results
├── eval-configs/                      # Test definitions (canonical source)
│   ├── acme_corporate_pre_rag_tests.yaml   # ACME baseline (6 tests)
│   ├── acme_corporate_post_rag_tests.yaml  # ACME with RAG (6 tests)
│   ├── eu_ai_act_pre_rag_tests.yaml        # EU AI Act baseline (5 tests)
│   ├── eu_ai_act_post_rag_tests.yaml       # EU AI Act with RAG (5 tests)
│   ├── whoami_pre_rag_tests.yaml            # Whoami baseline (2 tests)
│   ├── whoami_post_rag_tests.yaml           # Whoami with RAG (2 tests)
│   └── scoring-templates/
│       └── judge_prompt.txt                 # A/B/C/D/E judge prompt
├── notebooks/
│   └── deepeval_rag.ipynb             # DeepEval interactive evaluation
├── kfp/
│   ├── eval_pipeline.py               # Pipeline orchestration
│   └── components/
│       ├── scan_tests.py              # Test discovery
│       └── run_and_score_tests.py     # Execute + score + report
└── README.md

gitops/step-08-model-evaluation/
└── base/
    ├── kustomization.yaml
    └── eval-configs/
        ├── kustomization.yaml                  # configMapGenerator
        ├── configmap-eval-configs.yaml          # Scoring templates
        ├── job-copy-configs.yaml                # PostSync: sync to PVC
        └── *_tests.yaml                         # Copies of test configs

gitops/argocd/app-of-apps/
└── step-08-rag-evaluation.yaml                  # ArgoCD Application
```

## Key Design Decisions

> **Design Decision:** We implement two complementary evaluation approaches: (1) LlamaStack `scoring.score()` with `basic` + `llm-as-judge` providers for custom metrics and tool-choice validation, and (2) the official RHOAI 3.3 TrustyAI Ragas integration for standardized RAG metrics (`answer_relevancy`, `faithfulness`, `context_precision`). Both run through KFP via the step-07 DSPA.

> **Design Decision:** Tests live in-tree in `eval-configs/` and are deployed to the cluster as ConfigMaps via ArgoCD. A PostSync Job syncs them to the shared PVC. This keeps configs GitOps-managed while allowing the pipeline to read from PVC.

> **Design Decision (RHOAI 3.3):** Ragas is a Technology Preview feature. We configure both inline provider (for development) and remote provider (for production-scale evaluations via KFP). See [RHOAI 3.3 — Evaluating RAG Systems with Ragas](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate).

> **Design Decision:** Pre-RAG vs Post-RAG evaluation uses identical questions. Pre-RAG calls the LLM without document context (baseline). Post-RAG retrieves from Milvus and injects context. The score difference demonstrates RAG value quantitatively.

## Official Documentation

- [RHOAI 3.3 -- Evaluating RAG Systems with Ragas](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate)
- [RHOAI 3.3 -- Overview of Evaluating AI Systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/overview-evaluating-ai-systems_evaluate)
- [Llama Stack Scoring API](https://llama-stack.readthedocs.io/en/latest/references/api_reference/)
- [TrustyAI Ragas Provider](https://github.com/trustyai-explainability/llama-stack-provider-ragas)
- [KFP v2 User Guides](https://www.kubeflow.org/docs/components/pipelines/user-guides/)

---

## Evaluation Approaches

### Approach 1: TrustyAI Ragas (Official RHOAI 3.3)

The recommended approach per [RHOAI 3.3 — Evaluating RAG Systems with Ragas](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate).

**Inline provider** (development): `ENABLE_RAGAS=true` + `EMBEDDING_MODEL=granite-embedding-125m` on the LSD. Runs Ragas metrics in-process.

**Remote provider** (production): Ragas evaluations submitted as KFP pipeline runs. Requires `kubeflow-ragas-config` ConfigMap and `kubeflow-pipelines-token` Secret.

**Ragas metrics:**

| Metric | What it measures |
|--------|-----------------|
| `answer_relevancy` | Whether the answer matches the question |
| `faithfulness` | Consistency with retrieved context (hallucination detection) |
| `context_precision` | Precision of retrieved chunks |
| `context_recall` | Whether all needed info is in retrieved contexts |
| `answer_correctness` | Accuracy vs reference answer |

**API flow:**
1. Register dataset via `/v1beta/datasets` (Ragas format: `user_input`, `response`, `retrieved_contexts`, `reference`)
2. Register benchmark via `/v1alpha/eval/benchmarks` with scoring functions
3. Run evaluation via `/v1alpha/eval/benchmarks/<id>/jobs`
4. Retrieve results

**Demo notebook:** Clone [trustyai-explainability/llama-stack-provider-ragas](https://github.com/trustyai-explainability/llama-stack-provider-ragas) and run `demos/basic_demo.ipynb`.

> **Note (RHOAI 3.3):** Ragas is a Technology Preview feature.

### Approach 2: Custom KFP Pipeline (LlamaStack Scoring + Tool Choice)

Complementary approach using the stable LlamaStack scoring API:

- **`basic::subset_of`** — exact substring matching
- **`llm-as-judge::base`** — LLM-as-judge with A/B/C/D/E comparison (from [rhoai-genaiops/evals](https://github.com/rhoai-genaiops/evals))
- **`basic::tool_choice`** — custom scorer verifying RAG tool invocation

Runs pre-RAG and post-RAG tests for all 3 scenarios. HTML reports uploaded to S3.

### Approach 3: DeepEval Notebook (Developer)

Interactive notebook (`notebooks/deepeval_rag.ipynb`) for per-conversation analysis using DeepEval metrics with the vLLM endpoint as judge model.

> **Source:** Adapted from [rh-ai-quickstart/RAG evaluations](https://github.com/rh-ai-quickstart/RAG/tree/main/evaluations)

---

## Next Steps

- **CI/CD Quality Gates**: Schedule eval runs as CronJobs and fail builds when scores drop below thresholds
- **Grafana Dashboard**: Publish eval metrics to Prometheus and visualize score trends over time
- **Comparative Evaluations**: Run the same tests against different chunk sizes or embedding models to optimize RAG configuration
