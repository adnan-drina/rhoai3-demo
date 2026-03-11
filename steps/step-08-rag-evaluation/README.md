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
steps/step-08-rag-evaluation/
├── deploy.sh                          # Full deployment + run
├── run-eval.sh                        # Standalone eval trigger
├── validate.sh                        # Check results
├── eval-configs/                      # Test definitions
│   ├── acme_corporate_tests.yaml      # ACME scenario (6 tests)
│   ├── red_hat_docs_tests.yaml        # Red Hat scenario (6 tests)
│   ├── eu_ai_act_tests.yaml           # EU AI Act scenario (8 tests)
│   └── scoring-templates/
│       ├── answer_correctness.txt     # LLM-as-judge prompt
│       └── answer_groundedness.txt    # LLM-as-judge prompt
├── kfp/
│   ├── eval_pipeline.py               # Pipeline orchestration
│   └── components/
│       ├── scan_tests.py              # Test discovery
│       └── run_and_score_tests.py     # Execute + score + report
└── README.md
```

## Key Design Decisions

> **Design Decision:** We use Llama Stack `scoring.score()` (stable v1 API) instead of the alpha Ragas `eval` API. This avoids adding Ragas providers to the LSD and uses the `basic` + `llm-as-judge` providers already configured in lsd-rag. Ragas can be layered on later when the API stabilizes.

> **Design Decision:** Tests live in-tree in `eval-configs/` rather than a separate Git repo. This keeps the demo self-contained. Migrating to a Git-cloned test repo is a trivial change later (add a `git_clone_op` step).

> **Design Decision:** We evaluate the full RAG chain (Agent API) rather than just the model. The eval calls `agent.create_turn()` which triggers retrieval, tool calling, and generation -- testing the entire pipeline.

## Official Documentation

- [RHOAI 3.3 -- Evaluating RAG Systems with Ragas](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate)
- [RHOAI 3.3 -- Overview of Evaluating AI Systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/overview-evaluating-ai-systems_evaluate)
- [Llama Stack Scoring API](https://llama-stack.readthedocs.io/en/latest/references/api_reference/)
- [TrustyAI Ragas Provider](https://github.com/trustyai-explainability/llama-stack-provider-ragas)
- [KFP v2 User Guides](https://www.kubeflow.org/docs/components/pipelines/user-guides/)

---

## Next Steps

- **Ragas Integration**: Add Ragas providers (`trustyai_ragas_inline`, `trustyai_ragas_remote`) to lsd-rag for faithfulness and context_precision metrics
- **CI/CD Quality Gates**: Schedule eval runs as CronJobs and fail builds when scores drop below thresholds
- **Grafana Dashboard**: Publish eval metrics to Prometheus and visualize score trends over time
- **Comparative Evaluations**: Run the same tests against different chunk sizes or embedding models to optimize RAG configuration
