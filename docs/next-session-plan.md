# Session Status — Step-08 RAG Evaluation

## Completed

### Step-08: Fully Deployed and Validated

| Component | Status |
|-----------|--------|
| **ArgoCD Application** | `step-08-model-evaluation` — Synced, Healthy |
| **ConfigMaps** | `eval-configs` (judge prompt) + `eval-test-cases` (6 test YAMLs) |
| **Validation** | 12/12 PASS (`validate.sh`) |
| **Pre/Post RAG reports** | 12 HTML reports in MinIO |
| **Judge model** | `mistral-3-bf16` (24B) — faithful text comparison |
| **Candidate model** | `granite-8b-agent` (8B) via lsd-rag |
| **Scoring scale** | A=best (exact match), E=worst (disagrees) |

### Evaluation Results Summary

**Post-RAG (with documents):**
- ACME: B, B, B, B, C, B (5/6 excellent)
- EU AI Act: B, B, B (3/3 excellent)
- Whoami: B, B, B, A (4/4 excellent)

**Pre-RAG (no documents):**
- ACME: E, E, E, E, C, D (4/6 fail — "cartoon company")
- EU AI Act: B, B, C (LLM has training knowledge)
- Whoami: E, E, B, E (3/4 fail — "football coach")

### Key Demo Moments
- "What is ACME Corp?" — Pre-RAG: "fictional cartoon company" → Post-RAG: "technology solutions provider in Amsterdam"
- "Who is Adnan Drina?" — Pre-RAG: "Bosnian football coach" → Post-RAG: "Principal Solution Architect at Red Hat"
- "Managing Director?" — Pre-RAG: "can't provide that" → Post-RAG: "Adnan Drina"

## Current Cluster State

### Healthy
- lsd-rag: Running (v0.4.2.1+rhai0) with eval, localfs, basic, llm-as-judge providers
- Vector stores: acme_corporate (8/8), eu_ai_act (5/5), whoami (1/1)
- granite-8b-agent: Running (1 GPU)
- mistral-3-bf16: Running (4 GPU)
- Chatbot: Running, Direct mode
- Milvus, Docling, DSPA, PostgreSQL: All running

### ArgoCD Apps
| App | Status |
|-----|--------|
| step-01 through step-05 | Synced, Healthy |
| step-06-model-metrics | OutOfSync, Healthy |
| step-07-rag | Unknown, Healthy (DO NOT sync) |
| **step-08-model-evaluation** | **Synced, Healthy** |

### Critical Warnings
- **step-07 ArgoCD: DO NOT sync** — ConfigMap changes restart lsd-rag → vector store data loss
- **lsd-genai-playground + lsd-rag coexist** — do not delete either
- **llama-stack-client must be >=0.4,<0.5** — server is v0.4.2.1+rhai0

## Remaining Work (Lower Priority)

### Chatbot System Prompt
Update to RAG-aware prompt per RHOAI 3.3 docs:
> "You MUST use the knowledge_search tool to obtain updated information."

### Pipeline Pod Cleanup
```bash
oc delete pods -n private-ai --field-selector status.phase==Succeeded
oc delete pods -n private-ai --field-selector status.phase==Failed
```

### step-07 ArgoCD ComparisonError
The `Unknown` state is caused by a schema diff issue with custom CRDs. Fix by adding `ignoreDifferences` for `spec.template.metadata`. **Do NOT force-sync while data is working.**
