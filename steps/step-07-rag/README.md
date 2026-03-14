# Step 07: RAG Pipeline

**"From Chat to Knowledge-Grounded Answers"** — Ingest your own documents, embed them in pgvector, and let the LLM ground answers in your data.

## The Business Story

Step 05 proved your team can experiment with LLMs via the GenAI Playground. But chat alone hallucinates when asked about internal documents. Step 07 closes that gap: ingest PDFs through Docling, chunk and embed them via LlamaStack, store the vectors in PostgreSQL with pgvector, and query with both direct retrieval and agent-based file search — all orchestrated as a repeatable Kubeflow Pipeline on RHOAI.

## What It Does

```
 DSPA (Kubeflow Pipelines v2)
   │  Docling Ingestion Pipeline
   │  1. Fetch PDFs from MinIO
   │  2. Convert to Markdown (Docling)
   │  3. Insert via LlamaStack (vector_stores.files)
   │
   ▼
 LlamaStackDistribution (lsd-rag)
   Inference:  remote::vllm → granite-8b-agent
   Embedding:  inline::sentence-transformers (768d)
   Vector IO:  remote::pgvector → llamastack-postgres
   │
   ├──► PostgreSQL + pgvector (metadata + vectors)
   └──► RAG Chatbot UI (direct + agent modes)
```

| Component | Purpose | Persona |
|-----------|---------|---------|
| **PostgreSQL + pgvector** | Persistent vector database + metadata store | Platform (invisible) |
| **Docling** | PDF-to-Markdown intelligent conversion | Data Engineer |
| **DSPA (KFP v2)** | Pipeline orchestration for repeatable ingestion | MLOps Engineer |
| **LlamaStack (lsd-rag)** | RAG backend: embedding, vector IO, agent queries | AI Engineer |
| **Granite-8B Agent** | Tool-calling LLM for RAG queries | Data Scientist |
| **RAG Chatbot UI** | Web frontend for interactive RAG queries | Demo / End User |

## Demo Walkthrough

### Scene 1: Show the Vector Stores

Open a terminal and list the vector stores that were populated during deployment.

```bash
oc exec deploy/lsd-rag -n private-ai -- \
  curl -s http://localhost:8321/v1/vector_stores | python3 -m json.tool
```

**What to expect:** Two vector stores — `acme_corporate` (semiconductor manufacturing docs) and `whoami` (personal CV for identity queries).

| Scenario | Collection | Documents | Description |
|----------|------------|-----------|-------------|
| **acme_corporate** | `acme_corporate` | 8 files | Manufacturing/lithography internal docs (ACME Semiconductor) |
| **whoami** | `whoami` | 1 file | Personal CV — strong pre/post RAG contrast |

*What to say: "Both document sets were ingested through Kubeflow Pipelines and stored in pgvector. These aren't ephemeral — they're persisted in PostgreSQL, so they survive pod restarts. Let me show you what querying them looks like."*

---

### Scene 2: RAG Chatbot — Direct Mode

Open the RAG Chatbot UI and select **Direct** mode.

**URL:** `https://rag-chatbot-private-ai.apps.<cluster>/`

Ask: *"What products does ACME Corp manufacture?"*

**What to expect:** The chatbot calls `vector_stores.search()` to find relevant chunks, injects them as context into the prompt, and calls `chat.completions()`. The answer references specific ACME Corp products from the ingested PDFs.

*What to say: "Direct mode is the simplest RAG pattern. It does a vector search, finds the top chunks, stuffs them into the prompt, and asks the model to answer. No tool calls, no agent loop — just search and generate. Fast and predictable."*

---

### Scene 3: RAG Chatbot — Agent-Based Mode

Switch to **Agent-based** mode in the chatbot. Ask the same question.

**What to expect:** The chatbot uses the Responses API with `file_search` as a tool. The agent decides when and how to search, potentially making multiple retrieval calls to refine the answer.

*What to say: "Agent-based mode is where it gets interesting. Instead of us hardcoding the retrieval, we give the model a `file_search` tool and let it decide when to search. It can make multiple searches, refine its query, and combine results. This is the pattern you'd use in production — the model becomes an autonomous retriever."*

Ask a follow-up: *"Who is the Managing Director of ACME Corp?"*

**What to expect:** The agent searches the `acme_corporate` vector store and returns the name and role from the corporate profile document.

*What to say: "The agent autonomously decided to search the corporate docs to find the answer. In step 09 we'll add guardrails so the response doesn't leak personal contact details like phone numbers and emails."*

---

### Scene 4: Run the Ingestion Pipeline

Open the RHOAI Dashboard and navigate to **Data Science Pipelines > Runs**.

**URL:** RHOAI Dashboard → Data Science Projects → `private-ai` → Pipelines

**What to expect:** Completed pipeline runs showing the three-stage flow: fetch from MinIO → convert with Docling → insert via LlamaStack.

To trigger a new run from the CLI:

```bash
./steps/step-07-rag/run-batch-ingestion.sh
```

*What to say: "This is the repeatable part. Every time your team adds new documents to MinIO, this pipeline runs — Docling converts the PDFs to Markdown, LlamaStack chunks and embeds them, and pgvector stores the vectors. It's a standard Kubeflow Pipeline, so it shows up in the RHOAI Dashboard alongside your training pipelines."*

## Design Decisions

> **pgvector replaces Milvus.** A single PostgreSQL instance (`pgvector/pgvector:pg16`) serves as both metadata store and vector database via `ENABLE_PGVECTOR=true`. This eliminates Milvus, etcd, and the need for `userConfig`.

> **No `userConfig`.** The `rh-dev` LlamaStack template auto-wires all providers (pgvector, trustyai_fms, Ragas scoring, MCP tool runtime) from environment variables alone. This ensures vector store persistence across restarts, working Ragas evaluation, and safety provider integration.

> **MCP tool_groups are registered via the LlamaStack API at deploy time** (not in config files). They persist in PostgreSQL across restarts.

> **Server-side chunking and embedding** via `vector_stores.files.create()`. LlamaStack handles both using `granite-embedding-125m` (768d).

> **PDF upload via port-forward + boto3.** The MinIO `mc` image is distroless (no shell). `upload-to-minio.sh` uses `oc port-forward` + Python boto3 to upload PDFs from the local machine to MinIO S3.

> **KFP v2 requires `version_id`.** The `run-batch-ingestion.sh` script uses `list_pipeline_versions()` to obtain the version ID after uploading — KFP v2 `run_pipeline()` requires both `pipeline_id` and `version_id`.

> **rag-chatbot build trigger.** The `rag-chatbot` BuildConfig may not auto-trigger on first deploy. `deploy.sh` checks `lastVersion` and runs `oc start-build` if needed.

> **RAG dropdown visibility.** The chatbot UI's RAG collection dropdown only appears when vector stores contain data. If the KFP ingestion pipelines haven't run, the dropdown is hidden.

### LlamaStack Configuration (RHOAI 3.3 Example D — pgvector with `rh-dev`)

| Env Var | Value / Source | Purpose | RHOAI 3.3 Ref |
|---------|---------------|---------|---------------|
| `ENABLE_PGVECTOR` | `true` | Activates pgvector vector store provider | Example D |
| `PGVECTOR_HOST/PORT/DB/USER/PASSWORD` | `llamastack-pgvector-secret` | pgvector connection (same PostgreSQL instance) | Example D |
| `POSTGRES_HOST/PORT/DB/USER/PASSWORD` | `llamastack-postgres-secret` | Metadata store | Production pattern |
| `ENABLE_SENTENCE_TRANSFORMERS` | `true` | Inline embeddings (no GPU needed) | Example D |
| `EMBEDDING_PROVIDER` | `sentence-transformers` | Routes to sentence-transformers (not vllm-embedding) | Required |
| `INFERENCE_MODEL` | `llamastack-vllm-secret` | granite-8b-agent | — |
| `VLLM_URL` | `llamastack-vllm-secret` | vLLM endpoint | — |
| `ENABLE_RAGAS` | `true` | Ragas evaluation providers (auto-wired by `rh-dev`) | Ragas docs |
| `FMS_ORCHESTRATOR_URL` | Service URL | Guardrails safety (auto-wired by `rh-dev`) | Guardrails docs |
| No `userConfig` | — | `rh-dev` template manages all provider wiring | Recommended for pgvector |
| PostgreSQL image | `pgvector/pgvector:pg16` | Dual-purpose: metadata + vector store | Documented image |

> Ref: [RHOAI 3.3 — Example D: pgvector with rh-dev template](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/llama-stack-adv-examples_rag)

## References

- [RHOAI 3.3 — Deploying a RAG Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/deploying-a-rag-stack-in-a-project_rag)
- [RHOAI 3.3 — Example D: pgvector with rh-dev](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/llama-stack-adv-examples_rag)
- [RHOAI 3.3 — Deploying PostgreSQL with pgvector](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/llama-stack-adv-examples_rag#deploying-a-postgresql-instance-with-pgvector_rag)
- [Llama Stack — pgvector Provider](https://llama-stack.readthedocs.io/en/latest/providers/vector_io/remote_pgvector.html)

## Operations

```bash
./steps/step-07-rag/deploy.sh              # Deploy pgvector, LlamaStack, DSPA, chatbot
./steps/step-07-rag/validate.sh            # Verify all components + vector store health
```

## Next Steps

- [Step 08: Model Evaluation](../step-08-model-evaluation/README.md) — Pre/Post RAG evaluation with LLM-as-Judge
- [Step 09: Guardrails](../step-09-guardrails/README.md) — AI safety with TrustyAI
