# Step 08: Model Evaluation
**"Trust but Verify"** — Quantify the value of RAG by comparing LLM answers with and without document context.

## The Business Story

Step-07 proved your RAG system can retrieve and answer. But _how much better_ are the answers compared to the base LLM? Step-08 runs the same questions in two modes — **Pre-RAG** (LLM only, no documents) and **Post-RAG** (with pgvector retrieval) — then uses a separate, larger model as judge to score the quality difference. HTML reports are published to MinIO for team review.

## What It Does

```
eval-configs/              run-eval-report.sh                     MinIO
(*_tests.yaml)    ┌─────────────────────────────────────┐
                  │  For each scenario (pre + post RAG): │
  GitOps ────────►│  1. Generate answers (granite-8b)    │──► HTML reports
  (ArgoCD)        │  2. Retrieve context (pgvector)      │    s3://rhoai-storage/
                  │  3. Judge quality (mistral-3-bf16)    │    eval-results/{run-id}/
                  │  4. Generate HTML report              │
                  │  5. Upload to MinIO                   │
                  └─────────────────────────────────────┘
                         │              │            │
                    lsd-rag        pgvector     mistral-3-bf16
                    (step-07)    (step-07)      (step-05)
```

| Component | Purpose | Persona |
|-----------|---------|---------|
| **Test YAMLs** | Version-controlled Q&A pairs with expected answers | QA Engineer |
| **`run-eval-report.sh`** | Generate + score + upload HTML reports | MLOps Engineer |
| **Candidate model** | `granite-8b-agent` (8B) — generates answers | AI Engineer |
| **Judge model** | `mistral-3-bf16` (24B) — evaluates answer quality | Platform |
| **HTML Reports** | Per-scenario pre/post RAG results in MinIO | Everyone |

### Scoring Scale

| Score | Meaning | Color | Quality |
|-------|---------|-------|---------|
| **(A)** | Exact match — same key facts | Green | Best |
| **(B)** | Superset — all expected points plus additional correct detail | Green | Great |
| **(C)** | Subset — covers some but not all expected points | Yellow | Partial |
| **(D)** | Minor differences that don't affect factual accuracy | Grey | Okay |
| **(E)** | Disagrees with or contradicts the expected response | Red | Fail |

## Demo Walkthrough

### Scene 1: Show the Problem — Pre-RAG Hallucination

Ask the LLM about ACME Corp **without** RAG context. It has no internal documents to draw from.

```bash
oc exec deploy/lsd-rag -n private-ai -- curl -s -X POST http://localhost:8321/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"vllm-granite-agent/granite-8b-agent",
       "messages":[{"role":"user","content":"What is ACME Corp?"}],
       "max_tokens":200,"temperature":0,"stream":false}' | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:300])"
```

**Expected result:** "ACME Corp is a fictional company often used in cartoons and comedies, most notably in the Road Runner cartoons."

_What to say: "Without documents, the model falls back on internet training data. It thinks ACME is a cartoon company — not our semiconductor client. This is a hallucination and exactly the problem RAG solves."_

### Scene 2: Show the Solution — Post-RAG Grounded Answer

Run the evaluation pipeline, which sends the same questions **with** retrieved context from pgvector.

```bash
./steps/step-08-model-evaluation/run-eval-report.sh
```

**Expected result:** "ACME Corp is a technology solutions provider specializing in lithography optimization, metrology calibration... headquartered in Amsterdam, The Netherlands."

_What to say: "Same model, same question — but now it answers from our actual semiconductor documents. The answer is grounded in real corporate data, not internet folklore."_

### Scene 3: Review HTML Reports in MinIO

Open the MinIO Console and navigate to `rhoai-storage/eval-results/{run-id}/`.

Reports show side-by-side: question, generated answer, expected answer, and judge score (A–E with color coding). Green = correct, Red = hallucination.

_What to say: "Every evaluation run is versioned and stored in object storage. The team can review exactly which questions improved after adding RAG — and which ones still need work. This is your audit trail for model quality."_

### Scene 4: Scoring Breakdown

These are the observed results across all three document collections.

#### Post-RAG (with documents) — should score A/B

| Scenario | Scores | Summary |
|----------|--------|---------|
| **ACME Corporate** | B, B, B, B, C, B | 5/6 excellent — grounded in semiconductor docs |
| **EU AI Act** | B, B, B | 3/3 excellent — grounded in official EU documents |
| **Whoami** | B, B, B, **A** | 4/4 excellent — grounded in actual CV |

#### Pre-RAG (no documents) — should score D/E

| Scenario | Scores | Summary |
|----------|--------|---------|
| **ACME Corporate** | **E, E, E, E**, C, D | 4/6 fail — thinks ACME is a Looney Tunes company |
| **EU AI Act** | B, B, C | LLM has general EU AI Act knowledge from training |
| **Whoami** | **E, E**, B, **E** | 3/4 fail — thinks Adnan Drina is a football coach |

_What to say: "ACME and Whoami show the strongest RAG value — private and fictional data that the LLM simply cannot answer from training alone. EU AI Act is public knowledge, so the base model already does well. That's expected."_

## Design Decisions

> **Two separate models:** `granite-8b-agent` as candidate, `mistral-3-bf16` as judge. Using the same small model for both roles causes hallucinated judgments — it injects biases instead of faithfully comparing texts.

> **Identical test sets:** Pre-RAG and Post-RAG use the same questions and expected answers. The only variable is document context. The score difference directly quantifies RAG value.

> **Tests in GitOps:** Test YAMLs live in `eval-configs/` and deploy as ConfigMaps via ArgoCD. `run-eval-report.sh` copies them to the lsd-rag pod and executes locally (localhost access, no DNS issues from KFP pods).

> **Llama Stack eval API:** Same scoring pattern as [rhoai-genaiops/evals](https://github.com/rhoai-genaiops/evals) — `basic` + `llm-as-judge` scoring with A–E grades.

## References

- [RHOAI 3.3 — Evaluating RAG Systems with Ragas](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate)
- [RHOAI 3.3 — Overview of Evaluating AI Systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/overview-evaluating-ai-systems_evaluate)
- [rhoai-genaiops/evals](https://github.com/rhoai-genaiops/evals) — KFP pipeline pattern for LlamaStack scoring
- [fantaco-redhat-one-2026](https://github.com/burrsutter/fantaco-redhat-one-2026/tree/main/evals-llama-stack) — Llama Stack eval API examples

## Operations

```bash
./steps/step-08-model-evaluation/deploy.sh          # Full deploy: ArgoCD app + eval pipeline
./steps/step-08-model-evaluation/run-eval-report.sh  # Generate HTML reports (pre/post RAG, all 3 scenarios)
./steps/step-08-model-evaluation/validate.sh         # 12-check validation
```

## Next Steps

- **Step 09**: [Guardrails](../step-09-guardrails/README.md) — AI safety with TrustyAI detectors
