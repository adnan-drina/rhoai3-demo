# Next Session Plan

## Priority 1: Kueue Fix (Step-03)

**Problem:** Kueue gates ALL pods in `private-ai` (builds, chatbot, pipelines, workbenches).
Only GPU workloads (InferenceService) should be queued.

**Fix (Option A — Explicit queue labeling):**
1. Remove `kueue.openshift.io/managed=true` from `private-ai` namespace
2. Only pods with `kueue.x-k8s.io/queue-name` label get managed
3. RHOAI auto-adds this to InferenceService/Notebook CRDs
4. Builds, chatbot, pipeline executor pods bypass Kueue
5. Update `gitops/step-03-private-ai/` namespace YAML
6. Test: deploy chatbot, run build, confirm no SchedulingGated

**Ref:**
- RHOAI 3.3: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_openshift_ai/managing-workloads-with-kueue
- Kueue docs: https://kueue.sigs.k8s.io/docs/

## Priority 2: KFP Pipeline Completion (Step-07)

**Current state:** Pipeline works for whoami (1 file). Partial for acme (5/8), eu_ai_act (1/3).

**Remaining fixes:**
1. Increase `processing_timeout` default from 180 to 600 in pipeline.py
2. Run scenarios sequentially (not in parallel) to avoid Docling overload
3. Re-run acme and eu_ai_act individually to complete ingestion
4. Validate all 3 scenarios have full file counts

**After Kueue fix:** Pipeline executor pods won't be SchedulingGated anymore.

## Priority 3: Ingestion Service (Step-07 Addition)

**What:** Port the ingestion service from https://github.com/rh-ai-quickstart/RAG/tree/main/ingestion-service
as an ADDITIONAL ingestion method (not replacing KFP pipeline).

**Why:** Uses Docling Python library directly (no REST API, no timeouts).
Good for ad-hoc document ingestion and BYOD scenarios.

**How:**
1. Copy `ingestion-service/` to `steps/step-07-rag/ingestion-service/`
2. Adapt for our lsd-rag endpoint and Milvus
3. Create OpenShift BuildConfig + Deployment
4. Add to step-07-rag GitOps kustomization

## Priority 4: Step-08 Model Evaluation

### 4a. DeepEval Framework (from RAG quickstart)

**Source:** https://github.com/rh-ai-quickstart/RAG/tree/main/evaluations

**What to adopt:**
- `deep_eval_rag.py` — DeepEval-based metrics (faithfulness, relevancy, etc.)
- `helpers/custom_llm.py` — LLM-as-a-judge wrapper
- Conversation test fixtures (adapt for our scenarios)
- Bad-conversation test data for regression testing

**Metrics available:**
- Answer relevance
- Factual consistency / faithfulness
- Contextual precision / recall / relevancy
- Chunk alignment / deduplication
- Response accuracy (hallucination detection)
- Response completeness

### 4b. RHOAI TrustyAI + Ragas (official Red Hat)

**Ref:** https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate

**What RHOAI 3.3 provides:**
- Ragas inline provider (`ENABLE_RAGAS=true` env var on LSD)
- Ragas remote provider (S3-backed, pipeline execution)
- LlamaStack scoring API integration
- Benchmark registration and execution
- Dataset registration for evaluation

**Implementation plan:**
1. Add `ENABLE_RAGAS=true` + `EMBEDDING_MODEL=granite-embedding-125m` to lsd-rag
2. Clone TrustyAI Ragas demo: https://github.com/trustyai-explainability/llama-stack-provider-ragas
3. Adapt basic_demo.ipynb for our 3 scenarios
4. Create evaluation test cases per scenario
5. Run evaluations from workbench

### 4c. Combined approach

Use BOTH:
- **DeepEval** for detailed per-conversation metrics (from quickstart)
- **TrustyAI/Ragas** for integrated RHOAI evaluation pipeline (official)

This gives the demo two evaluation stories:
1. "Developer evaluates RAG quality with DeepEval in a notebook"
2. "Platform runs automated evaluation with TrustyAI Ragas pipeline"

## Pipeline Cleanup

Before starting next session:
- Delete all stale pipeline runs and experiments from DSPA
- Clean up old pipeline pods (hundreds accumulated)
- Remove duplicate vector stores if any reappear

## Chatbot System Prompt

Current default: "You are a helpful AI assistant."
Should update to a RAG-aware prompt in the Helm values / env var.
Recommended: "You are a knowledgeable AI assistant. When document context
is provided, base your answers strictly on the retrieved content."
