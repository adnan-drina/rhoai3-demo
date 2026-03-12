# Step 07: RAG Pipeline

**"From Chat to Knowledge-Grounded Answers"** - Document ingestion and retrieval with Llama Stack, Milvus, Docling, and Kubeflow Pipelines.

## The Business Story

Step-05 proved your team can experiment with LLMs via the GenAI Playground. But chat alone hallucinates when asked about internal documents. Step-07 closes that gap: ingest your own PDFs, chunk and embed them, store the vectors in a persistent Milvus database, and let the LLM ground its answers in your data — all orchestrated as a repeatable Kubeflow Pipeline.

| Component | Purpose | Persona |
|-----------|---------|---------|
| **Milvus** | Persistent vector database for embeddings | Platform (invisible) |
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
│   │                    port 8321                             │                    │
│   │   Inference:  remote::vllm → granite-8b-agent            │                    │
│   │   Embedding:  inline::sentence-transformers (768d)       │                    │
│   │   Vector IO:  remote::milvus → milvus-standalone:19530   │                    │
│   │   Tools:      rag-runtime (builtin::rag/knowledge_search)│                    │
│   └──────────────┬──────────────────────────┬────────────────┘                    │
│       ┌──────────▼──────────┐    ┌──────────▼──────────┐                          │
│       │   Milvus Standalone  │    │  granite-8b-agent   │                          │
│       │   (gRPC :19530)     │    │    (Step-05)        │                          │
│       │   Embedded etcd      │    └─────────────────────┘                          │
│       └──────────────────────┘                                                    │
│                                                                                   │
│   ┌─────────────────────────────────────────────────────────┐                    │
│   │              MinIO (Step-03)                             │                    │
│   │   s3://rag-documents/whoami/                             │                    │
│   │   s3://rag-documents/acme_corporate/                     │                    │
│   │   s3://rag-documents/eu_ai_act/                          │                    │
│   └─────────────────────────────────────────────────────────┘                    │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Support Status

| Component | Status | Notes |
|-----------|--------|-------|
| **Llama Stack Operator** | Technology Preview (TP) | API may change between versions |
| **Milvus (remote)** | Supported for RAG | Recommended over inline Milvus Lite |
| **DSPA / KFP v2** | GA | `aipipelines: Managed` in DSC |
| **Docling** | Community | Standalone deployment |

> **Ref:** [RHOAI 3.3 Deploying a RAG Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/deploying-a-rag-stack-in-a-project_rag)

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

### 3. Scenario PDFs (optional for first deploy)

Place PDF files in `scenario-docs/` subdirectories. See `scenario-docs/README.md` for instructions.

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
oc wait deploy/milvus-standalone -n private-ai --for=condition=Available --timeout=180s
oc wait llamastackdistribution/lsd-rag -n private-ai --for=jsonpath='{.status.phase}'=Ready --timeout=300s

# 4. Upload documents and run pipelines
cd steps/step-07-rag
./upload-to-minio.sh scenario-docs/scenario2-acme/sample.pdf rag-documents/scenario2-acme/sample.pdf
./run-batch-ingestion.sh acme
```

## Validation

```bash
./steps/step-07-rag/validate.sh
```

### Manual checks

```bash
# Infrastructure
oc get deploy milvus-standalone -n private-ai
oc get dspa dspa-rag -n private-ai
oc get llamastackdistribution lsd-rag -n private-ai

# Milvus health
oc exec deploy/milvus-standalone -n private-ai -- curl -s http://localhost:9091/healthz

# Vector store query
oc exec deploy/lsd-rag -n private-ai -- curl -s http://localhost:8321/v1/vector-io/query \
  -H "Content-Type: application/json" \
  -d '{"vector_db_id":"acme_corporate","query":"lithography"}' | jq '.chunks | length'
```

## Using RAG in the GenAI Playground

After step-07 deploys, the GenAI Playground (step-05) automatically connects to the same remote Milvus instance. This means you can test RAG queries directly from the RHOAI Dashboard UI:

1. Open **RHOAI Dashboard** > **GenAI Studio** > **Playground**
2. Select a model with tool-calling support (e.g., `granite-8b-agent`)
3. In the Playground, the RAG tool (`builtin::rag/knowledge_search`) is available with the 3 ingested collections: `whoami`, `acme_corporate`, `eu_ai_act`
4. Ask a question that relates to the ingested content

> **How it works:** Step-05's `lsd-genai-playground` uses `remote::milvus` pointing to `milvus-standalone.private-ai.svc.cluster.local:19530` — the same Milvus instance that step-07 deploys and populates. Both the Playground and the `lsd-rag` backend share the same vector data.

> **Note:** If step-07 is not deployed, the Playground will log Milvus connection errors for RAG operations, but inference and chat will work normally. RAG features become available once Milvus is running and collections are populated.

## Demo Scenarios

Three validated scenarios (the `red_hat_docs` scenario was removed — its content overlapped with general knowledge the model already has):

| Scenario | Collection | Documents | Description |
|----------|------------|-----------|-------------|
| **whoami** | `whoami` | 1 file | Simple identity doc — fast ingestion, used for pipeline validation |
| **acme_corporate** | `acme_corporate` | 5 files | Manufacturing/lithography internal docs |
| **eu_ai_act** | `eu_ai_act` | 1 file | EU AI Act regulatory text |

### Scenario 1: whoami (Pipeline Validation)

**Story:** "Quick identity test — validates the full KFP pipeline end-to-end."

Sample prompt: `"Who is the author and what is their role?"`

> This is the recommended first scenario for pipeline validation. It ingests in seconds and confirms the full chain: MinIO → Docling → LlamaStack → Milvus.

### Scenario 2: ACME Corporate

**Story:** "Manufacturing engineers query internal lithography documentation."

Sample query:
```python
from llama_stack_client import Agent, AgentEventLogger
import uuid

rag_agent = Agent(
    client,
    model="granite-8b-agent",
    instructions="You are a helpful assistant for ACME manufacturing.",
    tools=[{
        "name": "builtin::rag/knowledge_search",
        "args": {"vector_store_ids": ["acme_corporate"]},
    }],
)
prompt = "What are the key lithography calibration procedures?"
session_id = rag_agent.create_session(session_name=f"s{uuid.uuid4().hex}")
response = rag_agent.create_turn(
    messages=[{"role": "user", "content": prompt}],
    session_id=session_id,
    stream=True,
)
for log in AgentEventLogger().log(response):
    log.print()
```

### Scenario 3: EU AI Act

**Story:** "Compliance officers query official EU AI Act text for regulatory guidance."

Sample prompt: `"What are the requirements for high-risk AI systems under the EU AI Act?"`

## RAG Chatbot UI

A web-based chatbot frontend provides interactive RAG queries against the ingested document collections.

**Source:** Adapted from [rh-ai-quickstart/RAG](https://github.com/rh-ai-quickstart/RAG) frontend (MIT license), customized for this demo's LlamaStack backend.

**URL pattern:** `https://rag-chatbot-private-ai.apps.<cluster>/`

### Two Query Modes

| Mode | How it works | Status |
|------|-------------|--------|
| **Direct** (recommended) | `vector_stores.search()` → `chat.completions()` with context injection | Works perfectly with v0.4.2.1 server |
| **Agent** | Responses API with `file_search` tool | Tool invocation works, but `file_search` returns empty results with custom-config LSD |

> **Design Decision:** Direct mode is recommended for demos. The agent-based mode correctly invokes the `file_search` tool, but the Responses API `file_search` does not return results when the LSD uses `userConfig` (custom config). This is a known limitation of LlamaStack v0.4.2.1 with custom config — the `rh-dev` template wires file_search differently. Direct mode bypasses this by performing explicit vector search followed by context-augmented completion.

### Deployment

The chatbot is built as a container image using an OpenShift BuildConfig and deployed as a Deployment + Route:

```bash
# Image is built in-cluster via BuildConfig
oc get build -n private-ai -l app=rag-chatbot

# Access the chatbot
oc get route rag-chatbot -n private-ai -o jsonpath='{.spec.host}'
```

> **Known Issue:** Build pods may get stuck in `SchedulingGated` state due to Kueue admission. See Troubleshooting section for the fix.

## LlamaStack Version & Client Compatibility

> **Note (RHOAI 3.3):** LlamaStack **v0.4.2.1+rhai0** is the version shipped with RHOAI 3.3 — this is not a choice but the platform-provided version.

> **Client pinning:** `llama-stack-client>=0.4,<0.5` is required for compatibility. The 0.5.x client introduces breaking protocol changes (HTTP 426 "Upgrade Required" errors against the 0.4.x server).

```
# In requirements.txt or pip install:
llama-stack-client>=0.4,<0.5
```

## Pipeline Architecture

```
List PDFs from S3     Split into groups     ParallelFor (groups x PDFs)
      │                      │                        │
      ▼                      ▼                  ┌─────┴──────┐
 [download_from_s3]   [split_pdf_list]     [process_with_docling]
                                                     │
                                            [insert_via_llamastack]
                                                     │
                                            [pipeline_completion]
```

Key features:
- **Parallel processing** via configurable `num_splits` (default: 2 groups)
- **Server-side embedding** — LlamaStack computes embeddings via granite-embedding-125m
- **K8s secret injection** — MinIO credentials from `minio-connection` secret, never in pipeline params
- **Shared PVC** — documents and processed markdown transferred via `rag-pipeline-workspace` PVC
- **Docling API fallback** — two-format attempt handles API drift across Docling builds

## Troubleshooting

### Milvus Pod Not Starting

**Symptom:** `milvus-standalone` pod stuck in Pending or CrashLoopBackOff.

**Solution:**
```bash
oc describe pod -l app=milvus -n private-ai
oc logs deploy/milvus-standalone -n private-ai --tail=50
# Check PVC is bound:
oc get pvc milvus-pvc -n private-ai
```

### LlamaStack lsd-rag CrashLoopBackOff

**Symptom:** LSD pod keeps restarting.

**Root Cause:** ConfigMap syntax error or Milvus not reachable.

**Solution:**
```bash
oc logs deploy/lsd-rag -n private-ai --tail=100
oc get configmap llama-stack-rag-config -n private-ai -o yaml
# Verify Milvus is accessible from the LSD pod:
oc exec deploy/lsd-rag -n private-ai -- curl -s http://milvus-standalone:9091/healthz
```

### DSPA Not Ready

**Symptom:** `dspa-rag` shows no Ready condition.

**Solution:**
```bash
oc get dspa dspa-rag -n private-ai -o yaml
oc get pods -n private-ai -l app=ds-pipeline-dspa-rag
# Verify the pipelines bucket exists in MinIO
```

### Pipeline Run Fails

**Symptom:** Pipeline pods fail or show errors.

**Solution:**
```bash
# Check pipeline pod logs
oc get pods -n private-ai -l pipeline/runid --sort-by=.metadata.creationTimestamp
oc logs <pod-name> -n private-ai

# Common issues:
# - Docling service not ready (first start takes ~10 min)
# - MinIO credentials not injected (check minio-connection secret)
# - LlamaStack not reachable from pipeline pods
```

### Chatbot Build Pod Stuck in SchedulingGated

**Symptom:** `rag-chatbot-1-build` pod shows `SchedulingGated` and never starts.

**Root Cause:** Kueue adds scheduling gates to all pods in the namespace. Build pods don't have Kueue queue-name labels, so they're gated indefinitely.

**Solution:**
```bash
# Remove the Kueue scheduling gate from the build pod
oc patch pod rag-chatbot-1-build -n private-ai --type=json \
  -p '[{"op":"remove","path":"/spec/schedulingGates"}]'
```

### Responses API file_search Returns Empty Results

**Symptom:** Agent mode invokes the `file_search` tool correctly, but zero results are returned from vector stores.

**Root Cause:** The Responses API `file_search` tool does not work properly when the LSD uses `userConfig` (custom config for remote Milvus). The `rh-dev` template wires the file_search provider differently than custom config.

**Solution:** Use Direct mode instead (explicit `vector_stores.search()` → `chat.completions()` with context). This is the recommended RAG pattern for custom-config LSDs.

> **Known Limitation (RHOAI 3.3):** Responses API `file_search` requires `rh-dev` template wiring. Custom config LSDs should use direct vector search + completion pattern.

### llama-stack-client 0.5.x Incompatible with RHOAI 3.3 Server

**Symptom:** HTTP 426 "Upgrade Required" errors when calling LlamaStack APIs.

**Root Cause:** `llama-stack-client>=0.5` uses a newer protocol version incompatible with the v0.4.2.1+rhai0 server shipped with RHOAI 3.3.

**Solution:**
```bash
pip install "llama-stack-client>=0.4,<0.5"
```

### Insert Component: files.create / vector_stores.files.create Errors

**Symptom:** Insert step fails with `AttributeError`, `TypeError`, or "rag_tool" / "RAGDocument" not found.

**Root Cause:** Pipeline uses `llama_stack_client>=0.4,<0.5`. The 0.3.x API (`rag_tool.insert()`, `RAGDocument`) was deprecated; 0.4.x uses `files.create()` + `vector_stores.files.create()`.

**Solution:** Ensure components use the updated API. If you see `tool_runtime.rag_tool` or `RAGDocument` in logs, the component code may be outdated — recompile the pipeline (`python kfp/pipeline.py` or `./deploy.sh`) and re-run ingestion.

> **Note (0.4.x):** Document-level metadata (source, original_filename, scenario) is no longer passed via RAGDocument. The files API stores file content; metadata support may differ. Verify retrieval behavior if you rely on metadata filters.

## GitOps Structure

```
gitops/step-07-rag/
├── base/
│   ├── kustomization.yaml
│   ├── milvus/                    # Milvus standalone (embedded etcd)
│   │   ├── deployment.yaml
│   │   ├── pvc.yaml
│   │   └── service.yaml
│   ├── docling/                   # Docling PDF processing service
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── minio-rag-bucket/          # Init job for rag-documents bucket
│   │   └── init-job.yaml
│   ├── dspa/                      # Kubeflow Pipelines v2
│   │   ├── dspa.yaml
│   │   ├── dspa-minio-secret.yaml
│   │   └── pipeline-pvc.yaml
│   └── llamastack-rag/            # LSD with remote Milvus
│       └── llamastack-rag.yaml

steps/step-07-rag/
├── deploy.sh
├── validate.sh
├── run-batch-ingestion.sh
├── upload-to-minio.sh
├── scenario-docs/                 # PDF documents per scenario
├── kfp/                           # KFP v2 pipeline code
│   ├── pipeline.py
│   ├── components/
│   └── parameters/
└── README.md
```

## Rollback / Cleanup

```bash
# Delete ArgoCD Application (cascading delete of all resources)
oc delete application step-07-rag -n openshift-gitops

# Or delete individual components
oc delete llamastackdistribution lsd-rag -n private-ai
oc delete dspa dspa-rag -n private-ai
oc delete deploy milvus-standalone docling-service -n private-ai
oc delete svc milvus-standalone docling-service -n private-ai
oc delete pvc milvus-pvc rag-pipeline-workspace -n private-ai
oc delete secret dspa-minio-credentials -n private-ai
oc delete configmap llama-stack-rag-config -n private-ai
```

## Key Design Decisions

> **Design Decision:** We use embedded etcd (`ETCD_USE_EMBED=true`) rather than a separate etcd service. This is simpler and proven at demo scale. For production, deploy a separate etcd per the RHOAI documentation.

> **Design Decision:** Two LSDs coexist in `private-ai`: `lsd-genai-playground` (Dashboard-created,
> inline Milvus, multi-model for Playground) and `lsd-rag` (GitOps-created, remote Milvus, production
> RAG). The LlamaStack operator supports multiple LSDs per namespace — the 1-LSD restriction is only
> in the Dashboard's "Create playground" UI flow (bypassed since `lsd-genai-playground` is already created).
> The RAG workbench connects to `lsd-rag-service:8321`, the Playground connects to `lsd-genai-playground`.

> **Design Decision:** Server-side chunking and embedding via `vector_stores.files.create()`. LlamaStack handles both using `granite-embedding-125m` (768d), keeping the pipeline lightweight. Uses llama_stack_client 0.4.x API (files.create + vector_stores.files.create); the deprecated rag_tool.insert() / RAGDocument API is not used.

> **Design Decision:** `userConfig` with `image_name: custom` is used because we need `remote::milvus`. The `rh-dev` env-var-only pattern only supports inline Milvus (`MILVUS_DB_PATH`) or pgvector (`ENABLE_PGVECTOR`). For remote Milvus, custom config is the only option per RHOAI 3.3 documentation.

### RHOAI 3.3 Alignment

The `lsd-rag` configuration follows these RHOAI 3.3 documented patterns:

| Pattern | Status | Notes |
|---------|--------|-------|
| `INFERENCE_MODEL` from Secret | Aligned | Required by `rh-dev` template |
| `VLLM_URL` / credentials from Secret | Aligned | All vLLM config via `llamastack-vllm-secret` |
| PostgreSQL metadata (all from Secret) | Aligned | `llamastack-postgres-secret` with HOST/PORT/DB/USER/PASSWORD |
| `ENABLE_SENTENCE_TRANSFORMERS=true` | Aligned | Inline embeddings, no GPU needed |
| `storage.size: 5Gi` | Aligned | Persistent vector data and file cache |
| `FMS_ORCHESTRATOR_URL` | Aligned | Points to guardrails (step-09) |
| Resource limits `cpu: 4, memory: 12Gi` | Aligned | Matches documented examples |
| `userConfig` for remote Milvus | Necessary | No env-var support for remote Milvus endpoints |

> **Alternative:** To eliminate `userConfig` entirely, switch from Milvus to **pgvector** (`ENABLE_PGVECTOR=true`). This reuses the existing PostgreSQL and allows full env-var-only configuration. See [RHOAI 3.3 — Deploying with pgvector](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/llama-stack-adv-examples_rag#deploying-a-llamastackdistribution-with-pgvector_rag).

> **Known Limitation (RHOAI 3.3):** The `remote::milvus` provider configuration may differ between LlamaStack versions. Verify the exact config schema with `oc exec deploy/lsd-rag -- llama stack list-providers vector_io` if registration fails.

## Official Documentation

- [RHOAI 3.3 — Deploying a RAG Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/deploying-a-rag-stack-in-a-project_rag)
- [RHOAI 3.3 — Overview of Milvus Vector Databases](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/deploying-a-rag-stack-in-a-project_rag#overview-of-milvus-vector-databases_rag)
- [RHOAI 3.3 — Preparing Documents with Docling](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/deploying-a-rag-stack-in-a-project_rag#preparing-documents-with-docling-for-llama-stack-retrieval_rag)
- [Llama Stack — RAG Demo Samples](https://github.com/opendatahub-io/llama-stack-rag-demo)
- [KFP v2 User Guides](https://www.kubeflow.org/docs/components/pipelines/user-guides/)

---

## Next Steps

- **MCP Integration**: Configure Model Context Protocol servers for tool-calling workflows
- **Guardrails**: Add FMS Guardrails Orchestrator for safety filtering on RAG responses
- **RAG Evaluation**: Use TrustyAI + Ragas for RAG quality metrics
- **Continuous Ingestion**: Schedule pipeline runs as recurring jobs for data freshness
