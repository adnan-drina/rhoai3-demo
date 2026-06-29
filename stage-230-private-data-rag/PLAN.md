# Stage 230 Plan - Private Data RAG

## Intent

Create a repeatable private enterprise RAG baseline on top of the existing demo
platform. The stage should show how internal documents can ground a governed
Nemotron model without bypassing MaaS access control. The first use case is the
`whoami` RAG scenario from the previous implementation: a private CV PDF is
processed with Docling and used to answer identity and expertise questions.

## Scope

In scope:

- create a dedicated OpenShift AI project named `Enterprise RAG`
  (`enterprise-rag`) as the private knowledge boundary
- create a project-scoped ODF/NooBaa source bucket and dashboard-visible S3
  connection for private RAG documents
- deploy a stage-owned PostgreSQL with pgvector runtime service
- deploy a stage-owned `LlamaStackDistribution` named `lsd-private-rag`
- deploy a stage-owned Streamlit RAG chatbot named `private-rag-chatbot`
  reused from the Red Hat AI Enterprise RAG quickstart UI
- deploy a stage-owned DSPA/KFP pipeline server backed by a fixed NooBaa
  artifact bucket
- create environment-local secrets for pgvector and MaaS access
- seed the whoami source PDF into the project bucket
- convert the source PDF to Markdown with a stage-owned Docling service through
  a KFP v2 pipeline
- register and populate a Llama Stack vector database
- validate retrieval and Nemotron answer generation through Llama Stack
- validate that the chatbot route serves the RAG UI

Out of scope for this first RAG stage:

- external web search
- AutoRAG/Milvus optimization workflow
- guardrails and safety shields
- production database HA

## Source Capture

| Source | Use |
|--------|-----|
| RHOAI 3.4 Working with Llama Stack | `LlamaStackDistribution`, remote vLLM provider, inline sentence-transformers, pgvector provider, ingestion/query APIs |
| RHOAI 3.4 Working with data in S3-compatible object store | project object storage and connection posture |
| RHOAI 3.4 MaaS docs | governed Nemotron endpoint, subscription, API-key use |
| Previous main-branch Step 07 RAG implementation | whoami scenario, Docling conversion boundary, and repeatable ingestion pipeline pattern |
| Red Hat AI Enterprise RAG quickstart | reference architecture and reusable Streamlit chatbot path |
| rh-ai-quickstart/RAG main commit `d1f0847ae92a9c17e827a854334e035e2750a660` | Streamlit frontend image and UI behavior |
| rh-brain Enterprise RAG notes | Why/What narrative for private enterprise knowledge grounding |

## Implementation Decisions

- Nemotron remains the response-generation model. It is consumed through the
  Stage 220 MaaS gateway and is not redeployed by this stage.
- `sentence-transformers/all-MiniLM-L6-v2` is used for embeddings because it is the quickstart
  baseline and is supported by the documented Llama Stack inline
  `sentence-transformers` provider. The vector store is configured for 384
  dimensions, matching the runtime embeddings produced by this model. Nemotron
  is not used as an embedding model.
- PostgreSQL with pgvector is the durable vector store. The demo uses
  `docker.io/pgvector/pgvector:pg16` as an explicit demo exception because the
  pgvector extension is not provided by a RHOAI product image in the active
  baseline.
- The first implementation uses the previous `whoami` PDF corpus and converts
  it with Docling before ingestion. The old implementation's MinIO dependency
  is intentionally replaced by the Stage 230 `enterprise-rag-bucket`
  ObjectBucketClaim.
- The KFP pipeline uses the old implementation's component boundaries, but runs
  through a RHOAI `DataSciencePipelinesApplication` in `enterprise-rag`.
- KFP task-to-task exchange uses the AI Pipelines per-run workspace with an
  explicit `ReadWriteOnce` workspace PVC patch, not a GitOps-managed static PVC.
- `quay.io/docling-project/docling-serve:latest` is a demo/reference image
  carried forward from the previous implementation and Red Hat RAG quickstart
  pattern. Treat it as an external dependency to pin or replace before making
  production-support claims.
- `quay.io/rh-ai-quickstart/llamastack-dist-ui:0.2.45` provides the Streamlit
  chatbot reused from the Red Hat quickstart implementation. It is a demo
  reference image, not a RHOAI product image.
- External search is intentionally excluded for the private enterprise baseline.

## Acceptance Criteria

- Stage 230 Argo CD Application is `Synced` and `Healthy`.
- `enterprise-rag` appears as an OpenShift AI project for `ai-admin` and
  `ai-developer`.
- `enterprise-rag-bucket` and `private-rag-pipelines-bucket` are Bound.
- `private-rag-postgres` is running and has the `vector` extension.
- `lsd-private-rag` is running and exposes Llama Stack on port `8321`.
- Llama Stack lists the Nemotron model and a pgvector vector provider.
- The whoami PDF is present in the project S3 bucket.
- The `whoami` vector database exists.
- A whoami RAG query retrieves relevant identity context and produces a
  Nemotron-backed answer.
- The `private-rag-chatbot` deployment is ready, the route responds, and the UI
  can be used to select the `whoami` vector store for demo questions.

## Follow-Up Candidates

- extend Gen AI Playground workflow with the same `whoami` vector-store use case
- move the Docling ingestion flow into a Kubeflow Pipelines/DSPA pipeline
- add guardrails/safety as `stage-240-guardrails-and-safety`
- compare AutoRAG with the manual pgvector baseline
- add RAG evaluation and citation-quality metrics
