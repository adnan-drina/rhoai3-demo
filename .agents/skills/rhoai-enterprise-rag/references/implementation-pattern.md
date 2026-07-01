# Enterprise RAG Implementation Pattern

## Architecture

| Layer | Preferred Stage 230 choice | Notes |
|-------|----------------------------|-------|
| RHOAI project | `enterprise-rag` | Dedicated project for the RAG runtime and notebooks/jobs |
| Generation model | Stage 220 Nemotron through MaaS | Reuse governed model access and policies instead of deploying a duplicate LLM |
| Embedding provider | Start with the reference `sentence-transformers/ibm-granite/granite-embedding-125m-english` path if compatible with installed Llama Stack; otherwise select a documented embedding provider and record dimensions | Embedding dimension must match vector-store registration |
| Vector store | Remote Milvus | Matches the Red Hat article and official Llama Stack remote Milvus pattern |
| Metadata store | PostgreSQL 14+ for Llama Stack metadata | Required for Llama Stack deployments; do not treat vector store and metadata store as interchangeable |
| Reranker | Qwen3 reranker reference model or a later Red Hat-validated reranker | Treat non-Red Hat model artifacts as demo exceptions until validated |
| Ingestion | Notebook and/or Kubernetes Job derived from AG News reference notebook | Use Files API and Vector Stores API; avoid manual-only success criteria |
| Unstructured data preparation | Docling plus KFP automation based on `opendatahub-io/data-processing/kubeflow-pipelines` | Required for Dutch government PDFs, HTML, Office documents, images, or complex layouts; not needed for AG News text rows |
| Retrieval | Metadata extraction, hybrid search, rerank, final answer | Preserve all four steps in validation |
| Future corpus | Dutch government publications | Replace AG News metadata taxonomy after the reference pattern works |

## Implementation Phases

1. Reset the old Stage 230 artifacts.
   - Remove old whoami/Docling/DSPA/pgvector-specific active GitOps and app
     code from the stage.
   - Keep old content only under backup or Git history for reference.
2. Deploy the RAG runtime foundation.
   - Ensure the Llama Stack Operator is enabled through the shared RHOAI DSC
     owner.
   - Create `enterprise-rag` project, RBAC, Secrets, PostgreSQL metadata
     service, remote Milvus service, and `LlamaStackDistribution`.
3. Register providers and models.
   - Register Nemotron generation through the MaaS endpoint returned by the
     active Stage 220 setup.
   - Register the embedding provider and capture model ID plus dimension.
   - Register the reranker model if the artifact and runtime are accepted.
4. Ingest AG News.
   - Prefer a deterministic small AG News sample checked into the repo or
     stored as a ConfigMap for validation.
   - Optionally support full Hugging Face AG News ingestion when egress and
     tokens are available.
   - Create vector store metadata including `tenant_id`, `version_no`, corpus,
     environment, and language.
   - Attach each uploaded file with category and document metadata.
5. Validate retrieval quality mechanically.
   - Resolve vector store by name plus metadata.
   - Ask category-targeted questions.
   - Verify metadata filters are extracted.
   - Verify `search_mode="hybrid"` is used.
   - Verify reranker scores are present.
   - Verify the final answer uses retrieved context.
6. Add the audience app only after API validation passes.
   - Start from a small repo-owned app or notebook surface.
   - Do not hide failed retrieval behind a generic chat response.
   - Show model answer, retrieved context, metadata filters, and rerank scores.
7. Replace the corpus with Dutch government publications.
   - Define Dutch metadata: source authority, publication type, ministry,
     publication date, jurisdiction, language, topic, version, and access tier.
   - Add Docling conversion for unstructured documents such as PDFs, HTML,
     Office files, scanned images, or documents with tables and layout.
   - Use Docling chunking and extraction where they improve retrieval quality
     or metadata completeness.
   - Use subset selection when the corpus is too large for fast iteration and
     the sample must preserve diversity and coverage.
8. Automate document processing with AI Pipelines when the corpus is no longer
   a small deterministic sample.
   - Use the official-doc-linked `opendatahub-io/data-processing` stable branch
     as the first implementation reference.
   - Compare the current `main/kubeflow-pipelines` tree when the user asks for
     that reference implementation, but record any decision to use `main`
     instead of `stable`.
   - Start from the standard Docling KFP pipeline for ordinary PDFs, OCR, table
     structure, Markdown output, Docling JSON output, and optional
     HybridChunker output.
   - Evaluate the VLM Docling KFP pipeline only for complex layouts, scanned
     or image-heavy documents, custom page-level instructions, remote VLM
     conversion, or documents that require image descriptors.
   - Preserve the reference pipeline's S3 input model when processing staged
     private documents: mount `data-processing-docling-pipeline` with
     `S3_ENDPOINT_URL`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET`, and
     `S3_PREFIX`, generated from the Stage 110/230 object-storage connection
     at deploy or run time.
   - Enable `docling_chunk_enabled=True` only after converted Markdown and
     Docling JSON output have been inspected; use chunk JSONL output as the
     handoff to Files API / Vector Stores API ingestion.
   - Build or select a runtime image that contains required Docling
     dependencies, and record image provenance before committing manifests.
     The upstream `DOCLING_BASE_IMAGE` is an implementation reference, not a
     product-supported image claim until reviewed.

## GitOps Translation Rules

- Do not commit remote Helm references.
- Re-author Helm examples into local manifests.
- Keep credentials in Secrets created from environment-local values.
- Avoid hardcoded sample passwords from the reference repo.
- Validate `LlamaStackDistribution` fields through official docs and `oc
  explain` before live deployment.
- Do not duplicate shared `DataScienceCluster` ownership from Stage 110.
- Use Argo CD for long-lived resources; use scripts/jobs only for ingestion and
  validation actions that are naturally procedural.

## Demo Exceptions To Record

Record these before claiming support:

- Milvus and etcd images if deployed directly rather than provided by a Red Hat
  product or operator.
- Reranker model artifact and serving image.
- Hugging Face dataset download dependency.
- Inline embedding provider if used beyond development or validation.

## Excluded From The AG News Compatibility Phase

- Docling for AG News text rows.
- KFP automation before the notebook/job ingestion path proves the RAG API
  flow.
- AutoRAG optimization.
- Guardrails or MCP tool calling.
- External web search.

Docling and KFP are expected for the Dutch government publication phase, not
for the AG News compatibility phase. Keep this distinction clear in README,
PLAN, deploy scripts, and validation output.
