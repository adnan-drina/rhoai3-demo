# Step 08: RAG Evaluation

**"Trust but Verify"** — Quantify the value of RAG by comparing LLM answers with and without document context.

## The Business Story

Step-07 proved your RAG system can retrieve and answer. But _how much better_ are the answers compared to the base LLM? Step-08 runs the same questions in two modes — **Pre-RAG** (LLM only, no documents) and **Post-RAG** (with Milvus retrieval) — then uses a separate, larger model as judge to score the quality difference. HTML reports are published to MinIO for team review.

| Component | Purpose | Persona |
|-----------|---------|---------|
| **Test YAMLs** | Version-controlled Q&A pairs with expected answers (GitOps-managed) | QA Engineer |
| **`run-eval-report.sh`** | Generate + score + upload HTML reports | MLOps Engineer |
| **Candidate model** | `granite-8b-agent` (8B) — generates answers | AI Engineer |
| **Judge model** | `mistral-3-bf16` (24B) — evaluates answer quality | Platform |
| **HTML Reports** | Per-scenario pre/post RAG results in MinIO | Everyone |

## Architecture

```
eval-configs/              run-eval-report.sh                     MinIO
(*_tests.yaml)    ┌─────────────────────────────────────┐
                  │  For each scenario (pre + post RAG): │
  GitOps ────────►│  1. Generate answers (granite-8b)    │──► HTML reports
  (ArgoCD)        │  2. Retrieve context (Milvus)        │    s3://rhoai-storage/
                  │  3. Judge quality (mistral-3-bf16)    │    eval-results/{run-id}/
                  │  4. Generate HTML report              │
                  │  5. Upload to MinIO                   │
                  └─────────────────────────────────────┘
                         │              │            │
                    lsd-rag        Milvus      mistral-3-bf16
                    (step-07)    (step-07)      (step-05)
```

**Two models, two roles:**
- **Candidate** (`granite-8b-agent` via lsd-rag): generates the answers being evaluated
- **Judge** (`mistral-3-bf16` via direct vLLM): evaluates quality by comparing generated vs expected

> **Why separate models?** Using the same model as both candidate and judge causes bias — granite-8b thinks ACME is a cartoon company and hallucinates in its judge role too. A larger model (24B mistral) is a much more faithful text comparator.

## Scoring Scale

| Score | Meaning | Color | Quality |
|-------|---------|-------|---------|
| **(A)** | Exact match — same key facts | Green | Best |
| **(B)** | Superset — all expected points plus additional correct detail | Green | Great |
| **(C)** | Subset — covers some but not all expected points | Yellow | Partial |
| **(D)** | Minor differences that don't affect factual accuracy | Grey | Okay |
| **(E)** | Disagrees with or contradicts the expected response | Red | Fail |

## Observed Results

### Post-RAG (with documents) — should score A/B

| Scenario | Scores | Summary |
|----------|--------|---------|
| **ACME Corporate** | B, B, B, B, C, B | 5/6 excellent — grounded in semiconductor docs |
| **EU AI Act** | B, B, B | 3/3 excellent — grounded in official EU documents |
| **Whoami** | B, B, B, **A** | 4/4 excellent — grounded in actual CV |

### Pre-RAG (no documents) — should score D/E

| Scenario | Scores | Summary |
|----------|--------|---------|
| **ACME Corporate** | **E, E, E, E**, C, D | 4/6 fail — thinks ACME is a Looney Tunes company |
| **EU AI Act** | B, B, C | LLM has general EU AI Act knowledge from training |
| **Whoami** | **E, E**, B, **E** | 3/4 fail — thinks Adnan Drina is a football coach |

> ACME and Whoami show the strongest RAG value: private/fictional data that the LLM cannot answer from training alone.

## Prerequisites

```bash
# Step-07 RAG infrastructure must be deployed and healthy
oc get llamastackdistribution lsd-rag -n private-ai
oc get dspa dspa-rag -n private-ai

# Both models must be running
oc get inferenceservice granite-8b-agent mistral-3-bf16 -n private-ai

# Vector stores must have data
oc exec deploy/lsd-rag -n private-ai -- curl -s http://localhost:8321/v1/vector_stores | \
  python3 -c "import json,sys; [print(f'{v[\"name\"]}: {v[\"file_counts\"][\"completed\"]} files') for v in json.load(sys.stdin)['data']]"
```

## Deployment

### A) One-shot (recommended)

```bash
./steps/step-08-model-evaluation/deploy.sh
```

This will:
1. Apply the ArgoCD Application (deploys ConfigMaps + sync Job)
2. Copy eval configs to the PVC
3. Compile the eval pipeline
4. Launch an evaluation run

### B) Generate reports only

```bash
./steps/step-08-model-evaluation/run-eval-report.sh
```

Runs pre/post RAG evaluation for all 3 scenarios and uploads HTML reports to MinIO. No KFP pipeline needed — runs directly on the lsd-rag pod.

### C) Re-run after changing tests

Edit files in `eval-configs/`, commit, push, then:
```bash
./steps/step-08-model-evaluation/run-eval-report.sh
```

## Validation

```bash
./steps/step-08-model-evaluation/validate.sh
# Expected: 12/12 PASS
```

## Test YAML Format

Each `*_tests.yaml` defines a scenario with pre-RAG or post-RAG mode:

```yaml
name: "ACME Corporate — Post-RAG Evaluation"
description: "With RAG, the LLM answers from semiconductor docs — not the cartoon company."
vector_db_id: acme_corporate    # null for pre-rag
model_id: granite-8b-agent
mode: post-rag                  # or pre-rag

scoring_params:
  "llm-as-judge::base":
    type: llm_as_judge
    judge_model: granite-8b-agent
    prompt_template: scoring-templates/judge_prompt.txt
    judge_score_regexes: ["Answer: (A|B|C|D|E)"]
  "basic::subset_of": null
  "basic::tool_choice": null    # post-rag only

tests:
  - prompt: "What is ACME Corp?"
    expected_result: "ACME Corp is a technology solutions provider..."
    expected_tools:
      - builtin::rag/knowledge_search   # post-rag only
```

## Demo Walkthrough: Pre-RAG vs Post-RAG

### Step 1: Show the Problem (Pre-RAG Hallucination)

```bash
oc exec deploy/lsd-rag -n private-ai -- curl -s -X POST http://localhost:8321/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"vllm-granite-agent/granite-8b-agent",
       "messages":[{"role":"user","content":"What is ACME Corp?"}],
       "max_tokens":200,"temperature":0,"stream":false}' | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:300])"
```

**Result:** "ACME Corp is a fictional company often used in cartoons and comedies, most notably in the Road Runner cartoons."

### Step 2: Show the Solution (Post-RAG Grounded Answer)

```bash
# Same question, with retrieved context from Milvus → LLM answers from documents
./steps/step-08-model-evaluation/run-eval-report.sh
```

**Result:** "ACME Corp is a technology solutions provider specializing in lithography optimization, metrology calibration... headquartered in Amsterdam, The Netherlands."

### Step 3: Review Reports in MinIO

Open the MinIO Console and navigate to `rhoai-storage/eval-results/{run-id}/`.

Reports show side-by-side: question, generated answer, expected answer, and judge score (A-E with color coding).

## Directory Structure

```
steps/step-08-model-evaluation/
├── deploy.sh                          # ArgoCD app + eval pipeline
├── run-eval-report.sh                 # Generate HTML reports (recommended)
├── validate.sh                        # 12-check validation
├── eval-configs/                      # Test definitions (canonical source)
│   ├── acme_corporate_pre_rag_tests.yaml   # ACME baseline (6 tests)
│   ├── acme_corporate_post_rag_tests.yaml  # ACME with RAG (6 tests)
│   ├── eu_ai_act_pre_rag_tests.yaml        # EU AI Act baseline (3 tests)
│   ├── eu_ai_act_post_rag_tests.yaml       # EU AI Act with RAG (3 tests)
│   ├── whoami_pre_rag_tests.yaml            # Whoami baseline (4 tests)
│   ├── whoami_post_rag_tests.yaml           # Whoami with RAG (4 tests)
│   └── scoring-templates/
│       └── judge_prompt.txt                 # A=best, E=worst judge prompt
├── notebooks/
│   ├── llama_stack_eval.ipynb         # Llama Stack eval API notebook
│   └── deepeval_rag.ipynb             # DeepEval interactive evaluation
├── kfp/
│   ├── eval_pipeline.py               # KFP pipeline (alternative)
│   └── components/
│       ├── scan_tests.py              # Test discovery
│       └── run_and_score_tests.py     # Execute + score + report
└── README.md

gitops/step-08-model-evaluation/
└── base/
    ├── kustomization.yaml
    └── eval-configs/                       # ArgoCD-managed copies
        ├── kustomization.yaml              # configMapGenerator
        ├── configmap-eval-configs.yaml     # Scoring templates
        ├── job-copy-configs.yaml           # PostSync: sync to PVC
        ├── scoring-templates/judge_prompt.txt
        └── *_tests.yaml

gitops/argocd/app-of-apps/
└── step-08-rag-evaluation.yaml             # ArgoCD Application
```

## Key Design Decisions

> **Design Decision:** We use two separate models — `granite-8b-agent` as the candidate and `mistral-3-bf16` as the judge. Using the same small model for both roles causes hallucinated judgments (the model injects its own biases instead of faithfully comparing texts).

> **Design Decision:** Tests live in-tree in `eval-configs/` and are deployed to the cluster as ConfigMaps via ArgoCD. The `run-eval-report.sh` script copies them to the lsd-rag pod and executes locally (localhost access to the eval API, no DNS issues from KFP pods).

> **Design Decision:** Pre-RAG vs Post-RAG evaluation uses identical questions and expected answers. Pre-RAG calls the LLM without document context (baseline). Post-RAG retrieves from Milvus and injects context into the system prompt. The score difference quantifies RAG value.

> **Design Decision (Ragas):** Ragas inline provider requires `rh-dev` auto-wiring without `userConfig`. Since we use `userConfig` for remote Milvus, Ragas providers cannot be activated on `lsd-rag`. We use the Llama Stack eval API with `basic` + `llm-as-judge` scoring — the same pattern as [rhoai-genaiops/evals](https://github.com/rhoai-genaiops/evals) and [fantaco-redhat-one-2026](https://github.com/burrsutter/fantaco-redhat-one-2026/tree/main/evals-llama-stack).

## Official Documentation

- [RHOAI 3.3 — Evaluating RAG Systems with Ragas](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate)
- [RHOAI 3.3 — Overview of Evaluating AI Systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/overview-evaluating-ai-systems_evaluate)
- [rhoai-genaiops/evals](https://github.com/rhoai-genaiops/evals) — KFP pipeline pattern for LlamaStack scoring
- [fantaco-redhat-one-2026](https://github.com/burrsutter/fantaco-redhat-one-2026/tree/main/evals-llama-stack) — Llama Stack eval API examples
- [rhoai-genaiops/lab-instructions RAG eval](https://github.com/rhoai-genaiops/lab-instructions/blob/main/docs/5-grounded-ai/6-eval-rag.md) — Workshop eval configs
