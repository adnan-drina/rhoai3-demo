# Step 09: RAG Pipeline

**"From Chat to Knowledge-Grounded Answers"** - Document ingestion and retrieval with Llama Stack, Milvus, Docling, and Kubeflow Pipelines.

## The Business Story

Step-06 proved your team can experiment with LLMs via the GenAI Playground. But chat alone hallucinates when asked about internal documents. Step-09 closes that gap: ingest your own PDFs, chunk and embed them, store the vectors in a persistent Milvus database, and let the LLM ground its answers in your data — all orchestrated as a repeatable Kubeflow Pipeline.

| Component | Purpose | Persona |
|-----------|---------|---------|
| **Milvus** | Persistent vector database for embeddings | Platform (invisible) |
| **Docling** | PDF-to-Markdown intelligent conversion | Data Engineer |
| **DSPA (KFP v2)** | Pipeline orchestration for repeatable ingestion | MLOps Engineer |
| **LlamaStack (lsd-rag)** | RAG backend: embedding, vector IO, agent queries | AI Engineer |
| **Granite-8B Agent** | Tool-calling LLM for RAG queries | Data Scientist |

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              Step 09: RAG Pipeline                                │
│                              namespace: private-ai                                │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│   ┌─────────────────────────────────────────────────────────┐                    │
│   │              DSPA (Kubeflow Pipelines v2)                │                    │
│   │   ┌───────────────────────────────────────┐              │                    │
│   │   │     Docling Ingestion Pipeline         │              │                    │
│   │   │  1. Fetch PDFs from MinIO              │              │                    │
│   │   │  2. Convert to Markdown (Docling)      │              │                    │
│   │   │  3. Insert via LlamaStack rag_tool     │              │                    │
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
│   │   s3://rag-documents/scenario1-red-hat/                  │                    │
│   │   s3://rag-documents/scenario2-acme/                     │                    │
│   │   s3://rag-documents/scenario3-eu-ai-act/                │                    │
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

### 1. Steps 01-06 Completed

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
./steps/step-08-rag-pipeline/deploy.sh
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
oc apply -f gitops/argocd/app-of-apps/step-08-rag-pipeline.yaml

# 3. Wait for components
oc wait deploy/milvus-standalone -n private-ai --for=condition=Available --timeout=180s
oc wait llamastackdistribution/lsd-rag -n private-ai --for=jsonpath='{.status.phase}'=Ready --timeout=300s

# 4. Upload documents and run pipelines
cd steps/step-08-rag-pipeline
./upload-to-minio.sh scenario-docs/scenario2-acme/sample.pdf rag-documents/scenario2-acme/sample.pdf
./run-batch-ingestion.sh acme
```

## Validation

```bash
./steps/step-08-rag-pipeline/validate.sh
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

After step-09 deploys, the GenAI Playground (step-06) automatically connects to the same remote Milvus instance. This means you can test RAG queries directly from the RHOAI Dashboard UI:

1. Open **RHOAI Dashboard** > **GenAI Studio** > **Playground**
2. Select a model with tool-calling support (e.g., `granite-8b-agent`)
3. In the Playground, the RAG tool (`builtin::rag/knowledge_search`) is available with the 3 ingested collections: `red_hat_docs`, `acme_corporate`, `eu_ai_act`
4. Ask a question that relates to the ingested content

> **How it works:** Step-06's `lsd-genai-playground` uses `remote::milvus` pointing to `milvus-standalone.private-ai.svc.cluster.local:19530` — the same Milvus instance that step-09 deploys and populates. Both the Playground and the `lsd-rag` backend share the same vector data.

> **Note:** If step-09 is not deployed, the Playground will log Milvus connection errors for RAG operations, but inference and chat will work normally. RAG features become available once Milvus is running and collections are populated.

## Demo Scenarios

### Scenario 1: ACME Corporate

**Story:** "Manufacturing engineers query internal lithography documentation."

| Collection | Documents | Chunks |
|------------|-----------|--------|
| `acme_corporate` | 6 PDFs | ~32 |

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

### Scenario 2: Red Hat RHOAI Docs

**Story:** "Platform engineers ask questions about RAG configuration in RHOAI."

| Collection | Documents | Chunks |
|------------|-----------|--------|
| `red_hat_docs` | 1 PDF | ~135 |

Sample prompt: `"How do I configure a LlamaStackDistribution for RAG?"`

### Scenario 3: EU AI Act

**Story:** "Compliance officers query official EU AI Act text for regulatory guidance."

| Collection | Documents | Chunks |
|------------|-----------|--------|
| `eu_ai_act` | 3 PDFs | ~953 |

Sample prompt: `"What are the requirements for high-risk AI systems under the EU AI Act?"`

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

## GitOps Structure

```
gitops/step-08-rag-pipeline/
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

steps/step-08-rag-pipeline/
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
oc delete application step-08-rag-pipeline -n openshift-gitops

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

> **Design Decision:** We deploy a separate `LlamaStackDistribution` (`lsd-rag`) rather than modifying step-06's `lsd-genai-playground`. This keeps steps independent and both can coexist.

> **Design Decision:** Server-side chunking and embedding via `rag_tool.insert()`. LlamaStack handles both using `granite-embedding-125m` (768d), keeping the pipeline lightweight.

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
