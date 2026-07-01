# Enterprise RAG Implementation Pattern

## Architecture

| Layer | Preferred Stage 230 choice | Notes |
|-------|----------------------------|-------|
| RHOAI project | `enterprise-rag` | Dedicated project for the RAG runtime and notebooks/jobs |
| Generation model | Stage 220 Nemotron through MaaS | Reuse governed model access and policies instead of deploying a duplicate LLM. For Stage 230 notebook and acceptance helpers, pass the MaaS OpenAI-compatible base URL, API key, and unqualified provider model name separately from the Llama Stack base URL. |
| Embedding provider | Use the embedding model listed by the active RHOAI Llama Stack server, currently `sentence-transformers/nomic-ai/nomic-embed-text-v1.5` with dimension 768 | The article notebook defaults to Granite, but the demo must use a model returned by `/v1/models` unless a supported registration path is validated |
| Vector store | Remote PostgreSQL with pgvector | Official RHOAI 3.4 Llama Stack docs document pgvector as a remote vector provider. In the observed Stage 230 RHOAI 3.4 environment, the installed pgvector provider enforces metadata filters for vector, keyword, and hybrid search. |
| Metadata store | PostgreSQL 14+ for Llama Stack metadata | Required for Llama Stack deployments; do not treat vector store and metadata store as interchangeable |
| Reranker | CPU-hosted Qwen3 reranker reference model exposed through the Llama Stack provider-listed ID `vllm-reranker/qwen3-reranker` | Treat the non-Red-Hat modelcar as a demo exception; the initial reference implementation does not require a GPU. Size the CPU request for the active demo worker pool rather than copying an article-linked request that cannot schedule. |
| Ingestion | RHOAI project workbench plus deterministic script derived from AG News reference notebooks | Use Files API and Vector Stores API; avoid manual-only success criteria |
| Unstructured data preparation | Docling plus KFP automation based on `opendatahub-io/data-processing/kubeflow-pipelines` | Required for Dutch government PDFs, HTML, Office documents, images, or complex layouts; start with a compile-ready single-document contract before DSPA/S3 larger-corpus execution |
| Retrieval | Metadata extraction, hybrid search, rerank, final answer | Preserve all four steps in validation |
| First Dutch development corpus | Single public Staatsblad PDF smoke corpus | Use a deterministic source PDF, article-level chunks, and recommended metadata to validate the Dutch path before a larger corpus is available |
| Product-document explainer corpus | Runtime-downloaded official RHOAI 3.4 PDFs | Use the same Files API, Vector Stores API, filtered hybrid retrieval, rerank, and final-answer path to answer demo-audience questions about official product capabilities. Do not commit downloaded PDFs or treat adjacent product topics as implemented stage scope. |
| Future corpus | Larger Dutch government publication set | Replace AG News metadata taxonomy and automate processing after the single-document smoke path works |

## Implementation Phases

1. Reset the old Stage 230 artifacts.
   - Remove old whoami/Docling/DSPA-specific active GitOps and app
     code from the stage.
   - Keep old content only under backup or Git history for reference.
2. Deploy the RAG runtime foundation.
   - Ensure the Llama Stack Operator is enabled through the shared RHOAI DSC
     owner.
   - Create `enterprise-rag` project, RBAC, Secrets, PostgreSQL metadata
     service with pgvector enabled, and `LlamaStackDistribution`.
3. Register providers and models.
   - Register Nemotron generation through the MaaS endpoint returned by the
     active Stage 220 setup.
   - Configure the embedding provider and capture the model ID plus dimension
     returned by `/v1/models`.
   - Deploy the Qwen3 reranker through GitOps-managed KServe/vLLM CPU resources
     after recording the modelcar/runtime image posture as a demo exception,
     and expose it through Llama Stack so notebooks call
     `/v1alpha/inference/rerank` instead of the KServe endpoint directly.
   - Verify the reranker request fits a single schedulable CPU worker node and
     the selected LocalQueue has quota; reduce batching before using GPU
     capacity for the reranker.
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
   - Verify metadata filters are extracted. Prefer the reference repo's
     tool-call pattern only after the active MaaS/Llama Stack model path
     supports it; otherwise use structured JSON chat completion and record the
     tool-call gap.
   - Verify `search_mode="hybrid"` is used.
   - Verify reranker scores are present.
   - Verify the final answer uses retrieved context.
6. Add the audience app only after API validation passes.
   - Start from a small repo-owned app or notebook surface.
   - Do not hide failed retrieval behind a generic chat response.
   - Show model answer, retrieved context, metadata filters, and rerank scores.
7. Add a first Dutch government publication smoke corpus.
   - Use a single deterministic public document when the larger corpus is not
     ready, such as `stb-2022-14.pdf` for the Wet open overheid.
   - Keep the raw source PDF, extracted article-level JSONL chunks, and smoke
     questions under the stage data folder.
   - Apply enterprise metadata consistently: `source_authority`,
     `publication_type`, `ministry`, `topic`, `publication_date`, `language`,
     `jurisdiction`, `access_tier`, `source_url`, and `version`.
   - Use this smoke corpus to validate metadata extraction, filtered hybrid
     search, reranking, language-following answers, and expected legal terms.
   - Add a metadata contract and preparation helper for the single document.
     A local/workbench converter such as `pypdf` can validate article
     detection only; the supported pipeline path should use Docling.
   - Add compile-ready `docling-standard` KFP source once the document contract
     is clear, and validate compilation before introducing DSPA execution.
   - Do not present this single-PDF smoke path as the final Docling/KFP
     ingestion architecture until the Docling component has run and artifacts
     have been reviewed.
8. Add a focused RHOAI product-document explainer corpus when the demo needs
   source-grounded answers about platform capabilities.
   - Use a manifest of official RHOAI PDFs from the active baseline, such as
     Llama Stack, AutoRAG, evaluating AI systems, guardrails, AI Pipelines, and
     model-customization/data-preparation guides.
   - Download PDFs at runtime from `docs.redhat.com`; if programmatic PDF GET
     is blocked, fall back to the matching official `html-single` guide. Do
     not commit large product-document binaries.
   - Preserve product version, guide title, documentation category, page,
     topic, source URL, tenant, and version metadata on each uploaded chunk.
   - Keep this corpus scoped to audience explanation. It does not by itself
     implement AutoRAG optimization, EvalHub jobs, guardrails, or DSPA/KFP
     execution.
9. Replace the corpus with a larger Dutch government publication set.
   - Define Dutch metadata: source authority, publication type, ministry,
     publication date, jurisdiction, language, topic, version, and access tier.
   - Add Docling conversion for unstructured documents such as PDFs, HTML,
     Office files, scanned images, or documents with tables and layout.
   - Use Docling chunking and extraction where they improve retrieval quality
     or metadata completeness.
   - Use subset selection when the corpus is too large for fast iteration and
     the sample must preserve diversity and coverage.
10. Automate document processing with AI Pipelines when the corpus is no longer
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
   - Add DSPA, S3 Secret generation, pipeline import/version handling, run
     submission, task-log checks, metrics checks, and artifact review before
     indexing larger-corpus output.

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
- Keep RHOAI workbench `Notebook`, PVC, and ServiceAccount resources
  GitOps-managed when the workbench is part of the repeatable demo.
- Keep the data scientist's visible workbench workspace curated. For the AG
  News compatibility phase, expose the two article-style notebooks
  `Ingestion_pipeline_ag_news.ipynb` and `retrieval_pipeline_ag_news.ipynb`;
  root JupyterLab at a dedicated directory such as
  `/opt/app-root/src/workspace`, and place generated helper scripts, sample
  data, and requirements under hidden workspace content such as `.stage230`.
- If the workbench fetches source from Git, use sparse checkout or another
  curated copy process. Do not expose the full implementation repository in
  JupyterLab unless the stage explicitly teaches repository internals.
- Install notebook dependencies into the active workbench Python environment;
  avoid `pip install --user` because RHOAI notebook images can run in a
  virtualenv where user site packages are not visible.
- When dependency installation runs from a bootstrap init container, install
  packages into a shared PVC path and expose that path to the main notebook
  container with `PYTHONPATH`. Installing into the init container's default
  Python environment does not persist into the Jupyter container.
- The article-linked notebooks use `%pip install` cells for
  `llama-stack-client`; for this repo, a GitOps-managed workbench should be
  ready when opened and validation must import `llama_stack_client` inside the
  running workbench container.
- Use checked Python subprocess cells, not unchecked `!python ...` shell
  escapes, for notebook validation helpers. IPython shell escapes can print a
  traceback while `nbconvert --execute` still exits successfully.
- For reasoning-enabled generation models such as Nemotron, structured
  metadata extraction must require the JSON object in `message.content` and
  allocate enough completion tokens for the model to finish after any internal
  reasoning. Do not parse the `reasoning` field as the answer; if
  `finish_reason=length` appears before content is emitted, tighten the prompt
  or increase the extraction token budget.
- Keep the workbench notebook path runnable with the current supported
  retrieval mode. For the active pgvector path, `hybrid` is the acceptance
  mode because metadata filters are enforced in vector, keyword, and hybrid
  search. If a future provider change breaks filtered hybrid search, stop and
  record the provider-specific finding before changing user-facing notebooks.
- Pin notebook dependencies to versions available from the active RHOAI Python
  package index; verify the Llama Stack client version against the active
  server and package index before committing.
- Treat any generated workbench helper content under the PVC as disposable:
  refresh it from the GitOps source on startup and clean older generated
  layouts, such as a previous full `rhoai3-demo` checkout.
- Keep workbench `Notebook` resources in the same Argo CD sync wave as their
  PVCs when the storage class binds on `WaitForFirstConsumer`; placing the PVC
  in an earlier wave can deadlock sync because no consumer pod exists yet.
- Include the RHOAI workbench trusted-CA and pipeline-runtime environment and
  volume shape in the GitOps `Notebook` manifest once verified live, rather
  than fighting the notebook controller's injected defaults.

## Demo Exceptions To Record

Record these before claiming support:

- Milvus and etcd images if a future revision reintroduces them directly
  rather than using a Red Hat product, operator, or supported managed service.
- Qwen3 reranker model artifact and any serving/runtime image that is not a
  Red Hat product image or operator-owned operand.
- Hugging Face dataset download dependency.
- Inline embedding provider if used beyond development or validation.

## Excluded From The AG News Compatibility Phase

- Docling for AG News text rows.
- KFP automation before the notebook/job ingestion path proves the RAG API
  flow.
- AutoRAG optimization.
- Guardrails or MCP tool calling.
- External web search.

Docling and KFP are expected before indexing a larger Dutch government
publication corpus, not for the AG News compatibility phase and not as a
blocker for a single preprocessed smoke PDF. Keep this distinction clear in
README, PLAN, deploy scripts, and validation output.
