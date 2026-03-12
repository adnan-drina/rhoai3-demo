# Next Session Plan

## Current Cluster State (verified)

### Healthy Components
- **lsd-rag**: Running (v0.4.2.1+rhai0) with `eval`, `localfs` datasetio, `basic` + `llm-as-judge` scoring providers
- **Vector stores**: All searchable (acme_corporate 8/8, eu_ai_act 2/2, whoami 1/1)
- **Chatbot**: Running, Direct mode works with context-grounded answers
- **granite-8b-agent**: Running (1 GPU)
- **mistral-3-bf16**: Running (4 GPU)
- **Milvus, Docling, DSPA, PostgreSQL**: All running

### Critical Warnings
- **step-07 ArgoCD app is in Unknown state** — has a ComparisonError on schema diff. Do NOT force-sync — it would apply the updated lsd-rag ConfigMap, restart the pod, and LOSE all vector store file associations. Data must be re-ingested after any LSD restart.
- **step-03 ArgoCD app is OutOfSync** — safe to sync (just the Kueue label removal)
- **lsd-genai-playground** coexists with **lsd-rag** — do NOT delete either
- Pin `llama-stack-client>=0.4,<0.5` everywhere — server is v0.4.2.1+rhai0

### Llama Stack Eval API — Validated Working
The following was validated end-to-end on the live cluster:

```python
# Register dataset
client.beta.datasets.register(purpose='eval/question-answer', source={'type': 'rows', 'rows': [...]}, dataset_id='...', extra_body={'provider_id': 'localfs'})

# Register benchmark
client.alpha.benchmarks.register(benchmark_id='...', dataset_id='...', scoring_functions=['basic::subset_of'], extra_body={'provider_id': 'meta-reference'})

# Run eval
job = client.alpha.eval.run_eval('...', benchmark_config={
    'eval_candidate': {'type': 'model', 'model': 'vllm-granite-agent/granite-8b-agent', 'sampling_params': {...}},
    'scoring_params': {'basic::subset_of': {'type': 'basic', 'aggregation_functions': ['accuracy']}},
})

# LLM-as-judge also works
client.scoring_functions.register(scoring_fn_id='...', provider_id='llm-as-judge', provider_scoring_fn_id='llm-as-judge-base', params={'type': 'llm_as_judge', 'judge_model': 'vllm-granite-agent/granite-8b-agent', 'prompt_template': '...'})
```

---

## Ragas Provider: Architecture Decision

### The Trade-off

Per [RHOAI 3.3 docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate), the inline Ragas provider requires:
- `ENABLE_RAGAS=true` + `EMBEDDING_MODEL=granite-embedding-125m`
- The `rh-dev` distribution template's auto-wiring (no `userConfig`)

**Our constraint:** We use `userConfig` ConfigMap for remote Milvus (the `rh-dev` env-var-only pattern does not support remote Milvus). When `userConfig` is present, it overrides the `rh-dev` template entirely, including Ragas auto-wiring.

**Result:** `ENABLE_RAGAS=true` env var is set but has no effect because `userConfig` bypasses the template. Ragas providers (`trustyai_ragas_inline`, `trustyai_ragas_remote`) do NOT appear.

### Options

| Option | Approach | Trade-off |
|--------|----------|-----------|
| A | Remove `userConfig`, use inline Milvus Lite | Loses remote Milvus (persistent, shared) |
| B | Add Ragas providers explicitly to `userConfig` | Requires knowing the exact provider config schema (not documented for userConfig) |
| C | Create a separate LSD for Ragas evaluation | Extra resource; doesn't have access to our Milvus data |
| D | Use Llama Stack eval API with `basic` + `llm-as-judge` (current) | Production-ready, matches fantaco/rhoai-genaiops patterns |

**Decision: Option D** — Use the Llama Stack eval API (`/v1alpha/eval/benchmarks`) with `basic::subset_of` + `llm-as-judge` scoring. This is the exact pattern used by:
- [burrsutter/fantaco-redhat-one-2026](https://github.com/burrsutter/fantaco-redhat-one-2026/tree/main/evals-llama-stack)
- [rhoai-genaiops/evals](https://github.com/rhoai-genaiops/evals)
- [rhoai-genaiops/lab-instructions RAG eval](https://github.com/rhoai-genaiops/lab-instructions/blob/main/docs/5-grounded-ai/6-eval-rag.md)

The Ragas inline provider can be demonstrated separately if a non-Milvus LSD is available.

---

## Remaining Work

### Priority 1: Run Pre/Post RAG Evaluation (Ready to Execute)

The notebook `steps/step-08-model-evaluation/notebooks/llama_stack_eval.ipynb` is ready. It uses the official Llama Stack eval API to:
1. Generate pre-RAG answers (LLM only, no context)
2. Generate post-RAG answers (with Milvus retrieval context)
3. Register datasets and benchmarks
4. Run `basic::subset_of` + `llm-as-judge` scoring
5. Compare pre vs post RAG scores

**Execute from:** rag-wb workbench or any pod with `llama-stack-client==0.4.2`

### Priority 2: Sync step-08 GitOps (Safe)

The `gitops/step-08-model-evaluation/` manifests only create ConfigMaps and a sync Job. They do NOT touch the LSD or vector stores. Safe to apply:

```bash
oc apply -k gitops/step-08-model-evaluation/base/
```

Or uncomment `step-08-rag-evaluation.yaml` in `gitops/argocd/app-of-apps/kustomization.yaml`.

### Priority 3: Fix eu_ai_act File Count

eu_ai_act shows 2/2 but should have 3 files. The 3rd PDF (eu-ai-act-official-journal.pdf, 2.5MB) likely timed out during Docling conversion. Options:
- Re-run eu-ai-act ingestion with the v3 pipeline (has 600s timeout and register fix)
- Or use the ingestion service (Docling local, no timeout)

### Priority 4: Step-07 ArgoCD ComparisonError

The `Unknown` state is caused by `spec.template.metadata` schema issue in Argo CD's structured diff engine. This is a known issue with custom CRDs. Fix:
- Add `ignoreDifferences` for the specific field in the ArgoCD Application
- Or wait for the next ArgoCD/LlamaStack operator reconciliation

**Do NOT force-sync step-07 while data is working.**

### Priority 5: Pipeline Cleanup

```bash
# Clean completed/failed pods
oc delete pods -n private-ai --field-selector status.phase==Succeeded
oc delete pods -n private-ai --field-selector status.phase==Failed
```

### Priority 6: Chatbot System Prompt

Update to RAG-aware prompt per [RHOAI 3.3 troubleshooting](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/troubleshooting-playground-issues_rhoai-user):
> "You MUST use the knowledge_search tool to obtain updated information."

---

## Files Changed (Git, Not Yet Committed)

### Modified
- `README.md` — step-08 GitOps in repo structure
- `gitops/step-03-private-ai/base/namespace.yaml` — Kueue label fix
- `gitops/step-07-rag/base/llamastack-rag/llamastack-rag.yaml` — Added eval + localfs providers, ENABLE_RAGAS
- `gitops/step-07-rag/base/kustomization.yaml` — Added ingestion-service
- `steps/step-07-rag/kfp/pipeline.py` — Timeout 600
- `steps/step-07-rag/kfp/components/register_vector_db.py` — Lookup-before-create fix
- `steps/step-08-model-evaluation/README.md` — Rewritten with 3 eval approaches
- `steps/step-08-model-evaluation/deploy.sh` — Step number fixes
- `steps/step-08-model-evaluation/kfp/eval_pipeline.py` — No-cache scan, correct URLs
- `steps/step-08-model-evaluation/kfp/components/run_and_score_tests.py` — Direct HTTP, pre/post RAG
- `.cursor/skills/deploy-and-evaluate/SKILL.md` — Step-08 Ragas details
- `.cursor/skills/rhoai-troubleshoot/SKILL.md` — 6 new troubleshooting patterns

### New
- `gitops/argocd/app-of-apps/step-08-rag-evaluation.yaml` — ArgoCD Application
- `gitops/step-08-model-evaluation/` — Full GitOps structure (ConfigMaps, sync Job)
- `gitops/step-07-rag/base/ingestion-service/` — BuildConfig, ImageStream, ConfigMap
- `steps/step-07-rag/ingestion-service/` — Docling-based ingestion service
- `steps/step-08-model-evaluation/eval-configs/*_pre_rag_tests.yaml` — Pre-RAG baseline tests
- `steps/step-08-model-evaluation/eval-configs/*_post_rag_tests.yaml` — Post-RAG evaluation tests
- `steps/step-08-model-evaluation/eval-configs/scoring-templates/judge_prompt.txt` — A/B/C/D/E judge
- `steps/step-08-model-evaluation/notebooks/llama_stack_eval.ipynb` — Official eval API notebook
- `steps/step-08-model-evaluation/notebooks/deepeval_rag.ipynb` — DeepEval notebook

### Deleted
- `steps/step-08-model-evaluation/eval-configs/acme_corporate_tests.yaml` — Replaced by pre/post
- `steps/step-08-model-evaluation/eval-configs/eu_ai_act_tests.yaml` — Replaced by pre/post
- `steps/step-08-model-evaluation/eval-configs/red_hat_docs_tests.yaml` — Removed (no matching store)
- `steps/step-08-model-evaluation/eval-configs/scoring-templates/answer_correctness.txt` — Replaced by judge_prompt.txt
- `steps/step-08-model-evaluation/eval-configs/scoring-templates/answer_groundedness.txt` — Replaced by judge_prompt.txt
