# Step 07: RAG Pipeline

**"From Chat to Knowledge-Grounded Answers"** - Document ingestion and retrieval with Llama Stack, pgvector, Docling, and Kubeflow Pipelines.

## The Business Story

Step-05 proved your team can experiment with LLMs via the GenAI Playground. But chat alone hallucinates when asked about internal documents. Step-07 closes that gap: ingest your own PDFs, chunk and embed them, store the vectors in a persistent PostgreSQL database with pgvector, and let the LLM ground its answers in your data — all orchestrated as a repeatable Kubeflow Pipeline.

| Component | Purpose | Persona |
|-----------|---------|---------|
| **PostgreSQL + pgvector** | Persistent vector database + metadata store (single instance) | Platform (invisible) |
| **Docling** | PDF-to-Markdown intelligent conversion | Data Engineer |
| **DSPA (KFP v2)** | Pipeline orchestration for repeatable ingestion | MLOps Engineer |
| **LlamaStack (lsd-rag)** | RAG backend: embedding, vector IO, agent queries (v0.4.2.1+rhai0) | AI Engineer |
| **Granite-8B Agent** | Tool-calling LLM for RAG queries | Data Scientist |
| **RAG Chatbot UI** | Web frontend for interactive RAG queries (direct + agent modes) | Demo / End User |

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              Step 07: RAG Pipeline                                │
│                              namespace: private-ai                                │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│   ┌─────────────────────────────────────────────────────────┐                    │
│   │              DSPA (Kubeflow Pipelines v2)                │                    │
│   │   ┌───────────────────────────────────────┐              │                    │
│   │   │     Docling Ingestion Pipeline         │              │                    │
│   │   │  1. Fetch PDFs from MinIO              │              │                    │
│   │   │  2. Convert to Markdown (Docling)      │              │                    │
│   │   │  3. Insert via LlamaStack (vector_stores.files)      │                    │
│   │   └───────────────────────────────────────┘              │                    │
│   └───────────────────────────────────────────────────────────┘                    │
│                               │                                                   │
│                               ▼                                                   │
│   ┌─────────────────────────────────────────────────────────┐                    │
│   │          LlamaStackDistribution (lsd-rag)                │                    │
│   │              port 8321 — NO userConfig                   │                    │
│   │   Inference:  remote::vllm → granite-8b-agent            │                    │
│   │   Embedding:  inline::sentence-transformers (768d)       │                    │
│   │   Vector IO:  remote::pgvector → llamastack-postgres     │                    │
│   │   Safety:     remote::trustyai_fms (auto-wired)          │                    │
│   │   Scoring:    basic + llm-as-judge + braintrust           │                    │
│   │   Tools:      rag-runtime, model-context-protocol         │                    │
│   └──────────────┬──────────────────────────┬────────────────┘                    │
│       ┌──────────▼──────────┐    ┌──────────▼──────────┐                          │
│       │  PostgreSQL+pgvector │    │  granite-8b-agent   │                          │
│       │  (metadata+vectors) │    │    (Step-05)        │                          │
│       │  pgvector/pg16      │    └─────────────────────┘                          │
│       └──────────────────────┘                                                    │
│                                                                                   │
│   ┌─────────────────────────────────────────────────────────┐                    │
│   │              MinIO (Step-03)                             │                    │
│   │   s3://rag-documents/scenario2-acme/                     │                    │
│   │   s3://rag-documents/scenario3-eu-ai-act/               │                    │
│   └─────────────────────────────────────────────────────────┘                    │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Key Design: pgvector + No userConfig

> **Design Decision:** We use `pgvector/pgvector:pg16` as both the metadata store AND the vector store. This eliminates Milvus entirely and allows the `rh-dev` LlamaStack template to auto-wire all providers without `userConfig`.
>
> **Why this matters:** With `userConfig`, the `rh-dev` template's auto-wiring was overridden, breaking vector store persistence, Ragas evaluation providers, and safety provider registration. Removing `userConfig` fixes all of these.
>
> **Ref:** [RHOAI 3.3 — Example D: pgvector with rh-dev template](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/llama-stack-adv-examples_rag)

### What `rh-dev` auto-wires (without `userConfig`):

| Provider | Type | Status |
|----------|------|--------|
| pgvector | `remote::pgvector` | Vector store with persistent embeddings |
| trustyai_fms | `remote::trustyai_fms` | Safety/guardrails (was broken with userConfig) |
| basic + llm-as-judge | `inline::basic`, `inline::llm-as-judge` | Scoring/eval (Ragas works now) |
| sentence-transformers | `inline::sentence-transformers` | Inline embeddings (no GPU) |
| model-context-protocol | `remote::model-context-protocol` | MCP tool runtime |
| rag-runtime | `inline::rag-runtime` | RAG tool (knowledge_search) |

### Vector Store Persistence

Vector stores and their data **survive pod restarts**. Data is stored in PostgreSQL tables via pgvector — not ephemeral in-memory storage. This was validated by restarting `lsd-rag` and confirming search results returned after restart.

## Prerequisites

### 1. Steps 01-05 Completed

```bash
oc get inferenceservice granite-8b-agent -n private-ai
oc get llamastackdistribution -n private-ai
oc get secret minio-connection -n private-ai
```

### 2. aipipelines Managed in DataScienceCluster

```bash
oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.aipipelines.managementState}'
# Expected: Managed
```

## Deployment

### A) One-shot (recommended)

```bash
./steps/step-07-rag/deploy.sh
```

### B) Step-by-step (manual)

```bash
# 1. Create DSPA credentials secret
ACCESS_KEY=$(oc get secret minio-connection -n private-ai -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
SECRET_KEY=$(oc get secret minio-connection -n private-ai -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
oc create secret generic dspa-minio-credentials -n private-ai \
  --from-literal=accesskey="$ACCESS_KEY" \
  --from-literal=secretkey="$SECRET_KEY" \
  --dry-run=client -o yaml | oc apply -f -

# 2. Apply ArgoCD application
oc apply -f gitops/argocd/app-of-apps/step-07-rag.yaml

# 3. Wait for components
oc wait deploy/llamastack-postgres -n private-ai --for=condition=Available --timeout=180s
oc wait llamastackdistribution/lsd-rag -n private-ai --for=jsonpath='{.status.phase}'=Ready --timeout=300s

# 4. Verify pgvector extension
oc exec deploy/llamastack-postgres -n private-ai -- \
  psql -U llamastack -d llamastack -c "SELECT extname FROM pg_extension WHERE extname='vector';"
```

## Validation

```bash
./steps/step-07-rag/validate.sh
```

### Manual checks

```bash
# Infrastructure
oc get deploy llamastack-postgres -n private-ai
oc get dspa dspa-rag -n private-ai
oc get llamastackdistribution lsd-rag -n private-ai

# pgvector health
oc exec deploy/llamastack-postgres -n private-ai -- \
  psql -U llamastack -d llamastack -c "SELECT extname, extversion FROM pg_extension WHERE extname='vector';"

# Providers (should include pgvector, trustyai_fms, scoring)
oc exec deploy/lsd-rag -n private-ai -- curl -s http://localhost:8321/v1/providers | \
  python3 -c "import json,sys; [print(f'{p[\"api\"]:15s} {p[\"provider_id\"]}') for p in json.load(sys.stdin)['data']]"

# Vector stores
oc exec deploy/lsd-rag -n private-ai -- curl -s http://localhost:8321/v1/vector_stores
```

## Demo Scenarios

Three validated scenarios:

| Scenario | Collection | Documents | Description |
|----------|------------|-----------|-------------|
| **whoami** | `whoami` | 1 file | Simple identity doc — fast ingestion, pipeline validation |
| **acme_corporate** | `acme_corporate` | 5 files | Manufacturing/lithography internal docs |
| **eu_ai_act** | `eu_ai_act` | 1 file | EU AI Act regulatory text |

## RAG Chatbot UI

A web-based chatbot frontend provides interactive RAG queries.

**URL:** `https://rag-chatbot-private-ai.apps.<cluster>/`

### Two Query Modes

| Mode | How it works | Status |
|------|-------------|--------|
| **Direct** | `vector_stores.search()` → `chat.completions()` with context injection | Works |
| **Agent-based** | Responses API with `file_search` tool + MCP tools | Works (pgvector + no userConfig enables proper wiring) |

> **Note:** Agent-based mode now works correctly because the `rh-dev` template auto-wires the file_search provider without `userConfig` overriding it.

## LlamaStack Configuration

The `lsd-rag` LlamaStackDistribution uses pure `rh-dev` env vars — **no `userConfig`**:

| Env Var | Value | Purpose |
|---------|-------|---------|
| `ENABLE_SENTENCE_TRANSFORMERS` | `true` | Inline embeddings (no GPU) |
| `EMBEDDING_PROVIDER` | `sentence-transformers` | Routes embeddings to sentence-transformers (not vllm-embedding) |
| `ENABLE_PGVECTOR` | `true` | Activates pgvector vector store provider |
| `PGVECTOR_HOST/PORT/DB/USER/PASSWORD` | From `llamastack-pgvector-secret` | pgvector connection (same PostgreSQL instance) |
| `POSTGRES_HOST/PORT/DB/USER/PASSWORD` | From `llamastack-postgres-secret` | Metadata store |
| `INFERENCE_MODEL` | From `llamastack-vllm-secret` | granite-8b-agent |
| `VLLM_URL` | From `llamastack-vllm-secret` | vLLM endpoint |
| `ENABLE_RAGAS` | `true` | Ragas evaluation providers (auto-wired) |
| `FMS_ORCHESTRATOR_URL` | Service URL | Guardrails (auto-wired by `rh-dev`) |

## Troubleshooting

### PostgreSQL Pod Not Starting

```bash
oc describe pod -l app=llamastack-postgres -n private-ai
oc logs deploy/llamastack-postgres -n private-ai --tail=20
```

Common: PVC provisioning delay on AWS EBS, or `PGDATA` subdirectory issue with pgvector image.

### pgvector Extension Not Enabled

```bash
oc exec deploy/llamastack-postgres -n private-ai -- \
  psql -U llamastack -d llamastack -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

The `postStart` lifecycle hook handles this automatically, but can fail silently if PostgreSQL isn't ready when the hook runs.

### LlamaStack lsd-rag CrashLoopBackOff

```bash
oc logs deploy/lsd-rag -n private-ai --tail=50
```

Common causes:
- `Provider 'vllm-embedding' not found` — missing `EMBEDDING_PROVIDER=sentence-transformers` env var
- PostgreSQL not reachable — check `llamastack-postgres` service
- Secret values empty — verify `llamastack-postgres-secret` and `llamastack-pgvector-secret`

### DSPA Not Ready

```bash
oc get dspa dspa-rag -n private-ai -o yaml
oc get pods -n private-ai -l app=ds-pipeline-dspa-rag
```

### Chatbot Build Pod Stuck in SchedulingGated

```bash
oc patch pod <build-pod-name> -n private-ai --type=json \
  -p '[{"op":"remove","path":"/spec/schedulingGates"}]'
```

### llama-stack-client Incompatible

```bash
pip install "llama-stack-client>=0.4,<0.5"
```

Client 0.5.x causes HTTP 426 errors against the v0.4.2.1+rhai0 server.

## GitOps Structure

```
gitops/step-07-rag/
├── base/
│   ├── kustomization.yaml
│   ├── postgresql/                # PostgreSQL with pgvector (metadata + vectors)
│   │   ├── postgresql.yaml        # Deployment (pgvector/pgvector:pg16), PVC, Service
│   │   └── secrets.yaml           # POSTGRES_* + PGVECTOR_* + VLLM credentials
│   ├── docling/                   # Docling PDF processing service
│   ├── minio-rag-bucket/          # Init job for rag-documents bucket
│   ├── dspa/                      # Kubeflow Pipelines v2
│   └── llamastack-rag/            # LSD with pgvector (no userConfig)
│       └── llamastack-rag.yaml

steps/step-07-rag/
├── deploy.sh
├── validate.sh
├── run-batch-ingestion.sh
├── upload-to-minio.sh
├── chatbot/                       # RAG Chatbot UI source
├── kfp/                           # KFP v2 pipeline code
└── README.md
```

## Rollback / Cleanup

```bash
oc delete application step-07-rag -n openshift-gitops

# Or individual components
oc delete llamastackdistribution lsd-rag -n private-ai
oc delete dspa dspa-rag -n private-ai
oc delete deploy llamastack-postgres docling-service -n private-ai
oc delete pvc llamastack-postgres-pvc rag-pipeline-workspace -n private-ai
```

## Design Decisions

> **Design Decision:** pgvector replaces Milvus. A single PostgreSQL instance (`pgvector/pgvector:pg16`) serves as both metadata store and vector database, configured via `ENABLE_PGVECTOR=true`. This eliminates Milvus, etcd, and the need for `userConfig`.

> **Design Decision:** No `userConfig`. The `rh-dev` LlamaStack template auto-wires all providers (pgvector, trustyai_fms, Ragas scoring, MCP tool runtime) from environment variables alone. This ensures vector store persistence across restarts, working Ragas evaluation, and safety provider integration.

> **Design Decision:** MCP tool_groups are registered via the LlamaStack API at deploy time (not in config files). They persist in PostgreSQL across restarts.

> **Design Decision:** Server-side chunking and embedding via `vector_stores.files.create()`. LlamaStack handles both using `granite-embedding-125m` (768d).

## RHOAI 3.3 Alignment

| Pattern | Status | Notes |
|---------|--------|-------|
| `ENABLE_PGVECTOR=true` with `PGVECTOR_*` env vars | Aligned | RHOAI 3.3 Example D |
| `EMBEDDING_PROVIDER=sentence-transformers` | Aligned | Required for inline embeddings |
| `POSTGRES_*` from Secret | Aligned | RHOAI 3.3 production pattern |
| `FMS_ORCHESTRATOR_URL` for guardrails | Aligned | Auto-wired by `rh-dev` |
| `ENABLE_RAGAS=true` | Aligned | Auto-wired by `rh-dev` |
| No `userConfig` | Aligned | RHOAI 3.3 recommended for pgvector |
| `pgvector/pgvector:pg16` image | Aligned | RHOAI 3.3 documented image |

## References

- [RHOAI 3.3 — Deploying a RAG Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/deploying-a-rag-stack-in-a-project_rag)
- [RHOAI 3.3 — Example D: pgvector with rh-dev](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/llama-stack-adv-examples_rag)
- [RHOAI 3.3 — Deploying PostgreSQL with pgvector](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/llama-stack-adv-examples_rag#deploying-a-postgresql-instance-with-pgvector_rag)
- [Llama Stack — pgvector Provider](https://llama-stack.readthedocs.io/en/latest/providers/vector_io/remote_pgvector.html)

## Next Steps

- **Step 08**: [Model Evaluation](../step-08-model-evaluation/README.md) — Pre/Post RAG evaluation with LLM-as-Judge
- **Step 09**: [Guardrails](../step-09-guardrails/README.md) — AI safety with TrustyAI
