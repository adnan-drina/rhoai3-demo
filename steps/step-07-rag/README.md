# Step 07: RAG Pipeline

**"From Chat to Knowledge-Grounded Answers"** — Ingest your own documents, embed them in pgvector, and let the LLM ground answers in your data.

## The Business Story

Step 05 proved your team can experiment with LLMs via the GenAI Playground. But chat alone hallucinates when asked about internal documents. Step 07 closes that gap: ingest PDFs through Docling, chunk and embed them via LlamaStack, store the vectors in PostgreSQL with pgvector, and query with both direct retrieval and agent-based file search — all orchestrated as a repeatable Kubeflow Pipeline on RHOAI.

## What It Does

```text
RAG Pipeline
├── PostgreSQL + pgvector    → Persistent vector database + metadata store
├── Docling                  → PDF-to-Markdown intelligent conversion
├── DSPA (KFP v2)            → Pipeline orchestration for repeatable ingestion
├── LlamaStack (lsd-rag)     → RAG backend: embedding, vector IO, agent queries
├── RAG Chatbot UI           → Web frontend (direct + agent modes)
└── Ingestion Service        → BuildConfig + ImageStream for KFP components
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **PostgreSQL + pgvector** | Persistent vector database + metadata store | `private-ai` |
| **Docling** | PDF-to-Markdown intelligent conversion | `private-ai` |
| **DSPA (KFP v2)** | Pipeline orchestration for repeatable ingestion | `private-ai` |
| **LlamaStack (lsd-rag)** | RAG backend: embedding, vector IO, agent queries | `private-ai` |
| **RAG Chatbot UI** | Web frontend for interactive RAG queries | `private-ai` |
| **Ingestion Service** | BuildConfig + ImageStream for KFP pipeline components | `private-ai` |

Manifests: [`gitops/step-07-rag/base/`](../../gitops/step-07-rag/base/)

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

## What to Verify After Deployment

```bash
# PostgreSQL + pgvector
oc get deploy llamastack-postgres -n private-ai -o jsonpath='{.status.readyReplicas}'
# Expected: 1

# LlamaStack RAG
oc get llamastackdistribution lsd-rag -n private-ai -o jsonpath='{.status.phase}'
# Expected: Ready

# DSPA
oc get dspa dspa-rag -n private-ai -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Expected: True

# Vector stores populated
oc exec deploy/lsd-rag -n private-ai -- \
  curl -s http://localhost:8321/v1/vector_stores | python3 -m json.tool
# Expected: acme_corporate (8 files) and whoami (1 file)

# Chatbot accessible
oc get route rag-chatbot -n private-ai -o jsonpath='{.spec.host}'
# Expected: HTTPS route URL
```

Or run the validation script:

```bash
./steps/step-07-rag/validate.sh
```

## Design Decisions

> **Known Limitation (RHOAI 3.3):** The DSPA operator creates 6-7 child Deployments (`ds-pipeline-*`, `mariadb-dspa-rag`) without `app.kubernetes.io/part-of` labels. The DSPA CRD has no field for label propagation, so these resources appear ungrouped in the OpenShift Topology view. The DSPA CR itself carries `part-of: rag`, but the operator does not propagate it to child resources.

> **pgvector replaces Milvus.** A single PostgreSQL instance (`pgvector/pgvector:pg16`) serves as both metadata store and vector database via `ENABLE_PGVECTOR=true`. This eliminates Milvus, etcd, and simplifies configuration.

> **Minimal `userConfig` for annotation override.** The `rh-dev` template auto-wires all providers from env vars. A `userConfig` ConfigMap (`lsd-rag-config`) is used solely to override the `annotation_instruction_template` — preventing LlamaStack from injecting `<|file-xxx|>` citation markers into model responses. Based on the [Lightspeed team's approach](https://github.com/redhat-ai-dev/lightspeed-configs). The full auto-generated config is preserved; only the annotation template is changed.

> **MCP tool_groups are registered via the LlamaStack API at deploy time** (not in config files). They persist in PostgreSQL across restarts.

> **Server-side chunking and embedding** via `vector_stores.files.create()`. LlamaStack handles both using `granite-embedding-125m` (768d).

> **PDF upload via port-forward + boto3.** The MinIO `mc` image is distroless (no shell). `upload-to-minio.sh` uses `oc port-forward` + Python boto3 to upload PDFs from the local machine to MinIO S3.

> **KFP v2 requires `version_id`.** The `run-batch-ingestion.sh` script uses `list_pipeline_versions()` to obtain the version ID after uploading — KFP v2 `run_pipeline()` requires both `pipeline_id` and `version_id`.

> **Agent-based system prompt uses grounding, retry, tool hints, and Sources suppression.** The prompt combines: (1) grounding instruction, (2) retry on failure, (3) execute_sql hint for database, (4) OpenShift hint for pod queries, (5) concise answers, and (6) `"don't print Sources"` to suppress citation skeletons. See `docs/prompt-engineering-session.md` for the full prompt and test results.

> **`max_output_tokens=512` prevents vLLM context overflow.** MCP tool results (especially file_search with 5 document chunks + MCP tool schemas for 31 tools) consume 12-16K of the 16K context window. Without explicitly passing `max_output_tokens`, LlamaStack defaults to requesting 4096 tokens from vLLM, which exceeds the remaining context space and causes `response.failed: Unknown error`. The chatbot now passes `max_output_tokens` from the sidebar slider (default 512) to the Responses API.

> **Max inference iterations default is 20.** MCP multi-step chains (e.g., `list_schemas` → `list_objects` → `get_object_details` → `execute_sql`) require 4-5 iterations. The original default of 10 caused the model to stop mid-chain before reaching the final SQL execution. 20 provides headroom without excessive runtime.

> **pgvector requires `anyuid` SCC via a dedicated ServiceAccount.** The `pgvector/pgvector:pg16` image entrypoint runs `chown`/`chmod` as root to set data directory ownership. OpenShift's restricted SCC blocks this. A dedicated `llamastack-postgres` ServiceAccount with `anyuid` SCC is used instead of granting `anyuid` to the default SA (which would break KServe modelcar FUSE mounts on inference pods sharing the namespace).

> **File citations controlled via LlamaStack annotation template.** LlamaStack's `annotation_instruction_template` tells the model how to cite sources. The default instructs `<|file-id|>` format which produces opaque markers. The `lsd-rag-config` ConfigMap overrides this to instruct "Never include any citation that is in the form file-id" — eliminating the markers. The ingestion pipeline also sets `attributes={"source": upload_name}` for clean filenames in the File Search Results panel.

> **rag-chatbot build trigger.** The `rag-chatbot` BuildConfig may not auto-trigger on first deploy. `deploy.sh` checks `lastVersion` and runs `oc start-build` if needed.

> **RAG dropdown visibility.** The chatbot UI's RAG collection dropdown only appears when vector stores contain data. If the KFP ingestion pipelines haven't run, the dropdown is hidden.

> **DSPA readiness gates pipeline steps.** `deploy.sh` waits up to 600s for DSPA to reach Ready. If DSPA is not ready, it skips PDF upload, pipeline compilation, and batch ingestion — these can be run manually later. This prevents silent failures where the KFP API server isn't available but the script continues to launch pipelines.

> **DSPA readiness check uses condition status, not type.** `deploy.sh` checks `status.conditions[?(@.type=="Ready")].status == "True"` rather than `conditions[0].type == "Ready"`. The first condition in the array is not guaranteed to be the Ready condition, and even if it is, the type name "Ready" does not indicate readiness — the `status` field does.

> **PostgreSQL PVC sync wave aligned with Deployment.** The `llamastack-postgres-pvc` PVC uses sync wave `"2"` (same as the Deployment) to avoid the `WaitForFirstConsumer` deadlock where ArgoCD waits for the PVC to bind before creating the pod that triggers binding.

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

## Troubleshooting

### pgvector pod CrashLoopBackOff: "data directory has wrong ownership"

**Symptom:** `llamastack-postgres` pod crashes with:
```
chmod: changing permissions of '/var/lib/postgresql/data/pgdata': Operation not permitted
FATAL: data directory "/var/lib/postgresql/data/pgdata" has wrong ownership
```

**Root Cause:** The `pgvector/pgvector:pg16` image runs its entrypoint as root (UID 0) to set data directory permissions. OpenShift's restricted SCC blocks this.

**Solution:** The deployment uses a dedicated `llamastack-postgres` ServiceAccount with `anyuid` SCC. Verify:
```bash
oc get sa llamastack-postgres -n private-ai
oc adm policy who-can use scc anyuid -n private-ai | grep llamastack-postgres
```
If the SCC grant is missing (fresh cluster), run:
```bash
oc adm policy add-scc-to-user anyuid -z llamastack-postgres -n private-ai
```

> **Warning:** Do NOT grant `anyuid` to the `default` ServiceAccount — this breaks KServe modelcar FUSE mounts for inference pods (granite-8b-agent, etc.) in the same namespace.

### Agent response empty or "Response failed: Unknown error" with MCP tools

**Symptom:** The chatbot shows an empty bot response or the logs show `Response failed: Unknown error`. Tool calls (MCP or file_search) execute successfully but the model's text response never appears.

**Root Cause:** vLLM's `max_tokens` defaults to 4096 when not specified. After MCP tool results and file_search chunks are injected into the context, the input tokens can reach 12-16K of the 16K context window. Requesting 4096 output tokens exceeds the remaining space: `ValueError: max_tokens is too large: 4096 > 16384 - 12356`.

**Solution:** The chatbot passes `max_output_tokens` from the sidebar "Max Tokens" slider (default 512) to the Responses API. Verify in `agent.py`:
```python
"max_output_tokens": config.sampling.max_tokens,
```
If responses still fail, reduce the Max Tokens slider in the chatbot sidebar.

### Agent stops mid-chain without completing MCP multi-step queries

**Symptom:** Database MCP queries call `list_schemas` and `list_objects` but never reach `execute_sql`. The response describes what it would do next instead of executing.

**Root Cause:** `max_infer_iters` was too low. Each tool call + response consumes one iteration.

**Solution:** Increase the "Max Inference Iterations" slider to 20+ in the chatbot sidebar. The default is 20.

### ParallelFor group shows "Running" after pipeline completes

**Symptom:** In the Dashboard pipeline graph, the `process-pdf` ParallelFor group node shows a spinner/running status even after the downstream `ingestion_summary` step has completed successfully.

**Root Cause:** KFP backend bug where sub-DAG group status updates when the first task completes instead of waiting for all tasks. Tracked as [kubeflow/pipelines#10830](https://github.com/kubeflow/pipelines/issues/10830), fixed in [PR #11651](https://github.com/kubeflow/pipelines/pull/11651) (KFP 2.5.0, Feb 2025). RHOAI 3.3's DSPA may not include the full fix for dynamic ParallelFor groups.

**Impact:** Cosmetic only. Pipeline execution order is correct — the `ingestion_summary` step properly waits for all ParallelFor iterations via `.after(insert)`, as confirmed by the compiled YAML `dependentTasks: [for-loop-1]`.

**Workaround:** None from pipeline code. Verify actual completion by checking the `ingestion_summary` step's metrics or the pipeline run status (which correctly shows "Succeeded").

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
