# Validation Checklist

Use this checklist before accepting Stage 230 RAG changes.

## Source And Scope

- Active baseline versions match `docs/PLATFORM_BASELINE.md`.
- Llama Stack / OGX is labeled Technology Preview.
- Official Llama Stack docs are used for product fields and API behavior.
- Red Hat Developer article and `agnews-rag-demo` are labeled as implementation
  evidence only.
- AutoRAG, Docling, KFP, guardrails, and MCP are not claimed unless actually
  implemented and validated.
- If Docling or KFP is introduced, the official RHOAI 3.4 "Prepare your data
  for AI consumption" chapter is captured as product authority.
- If Docling KFP examples are adapted, the `opendatahub-io/data-processing`
  branch is recorded. Prefer `stable`; using `main` requires an explicit stage
  decision.

## Runtime

- `enterprise-rag` namespace exists and is dashboard-visible.
- Llama Stack Operator is enabled through the shared DSC owner.
- `LlamaStackDistribution` is Ready.
- PostgreSQL metadata storage is reachable from Llama Stack.
- Milvus gRPC endpoint and token are configured when using `milvus-remote`.
- Qwen3 reranker `InferenceService` is Ready when AG News compatibility is in
  scope.
- Enterprise RAG Workbench exists and can open JupyterLab when notebook-driven
  ingestion or inspection is in scope.
- Enterprise RAG Workbench exposes the curated notebook workspace expected by
  the stage. For the AG News compatibility phase, the visible workspace should
  show `Ingestion_pipeline_ag_news.ipynb` and
  `retrieval_pipeline_ag_news.ipynb`, with helper scripts and sample data kept
  in hidden generated workspace content, and JupyterLab should be rooted at
  the curated workspace directory rather than the PVC root or full repo clone.
- Enterprise RAG Workbench can import the required notebook client libraries
  from the same Python environment used by Jupyter kernels. Validate
  `llama_stack_client` from the running workbench container before asking a
  user to run the ingestion notebook.
- Enterprise RAG Workbench passes MaaS generation settings to notebook helpers
  through environment variables sourced from a Kubernetes Secret. Do not print
  or commit the MaaS API key.
- Notebook helper cells use `subprocess.run(..., check=True)` or an equivalent
  checked execution path so `nbconvert --execute` fails when the helper fails.
- If the workbench selects a Kueue-enabled hardware profile, the target
  namespace is labeled `kueue.openshift.io/managed=true`, the referenced
  `LocalQueue` exists in the same namespace, and the Notebook includes
  `kueue.x-k8s.io/queue-name`.
- If the CPU reranker runs in a Kueue-managed namespace, its `InferenceService`
  includes `kueue.x-k8s.io/queue-name` for a LocalQueue with sufficient CPU and
  memory quota.
- Secrets contain no committed real values.
- Llama Stack `/v1/models` and `LlamaStackClient.models.list()` show:
  - Nemotron generation model
  - embedding model
  - `vllm-reranker/qwen3-reranker`

## Ingestion

- Vector store is created with expected name and metadata.
- Embedding model ID and dimension are captured.
- For AG News, raw text ingestion does not pretend to validate Docling.
- For Dutch government publications or other unstructured corpora, Docling
  conversion output is validated before vector-store attachment.
- KFP automation is validated only after the Docling notebook/job path works.
- Docling KFP implementation declares whether it adapts `docling-standard` or
  `docling-vlm` and why.
- `docling-vlm` is used only when layout/image complexity or remote VLM
  conversion justifies it.
- S3-backed pipeline runs mount the `data-processing-docling-pipeline` Secret
  with `S3_ENDPOINT_URL`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET`, and
  `S3_PREFIX`; values are generated from local object-storage connection data
  and are not committed.
- Remote VLM pipeline runs mount the same Secret with
  `REMOTE_MODEL_ENDPOINT_URL`, `REMOTE_MODEL_API_KEY`, and
  `REMOTE_MODEL_NAME`; values are not committed.
- Upstream KFP component base images are reviewed and classified as Red Hat
  image, reviewed custom image, or demo exception before pipeline adoption.
- `docling_chunk_enabled=True` is enabled only after Markdown and Docling JSON
  output quality is inspected.
- Chunk JSONL output records source document and chunk index and is inspected
  before Files API / Vector Stores API ingestion.
- Files API upload succeeds.
- Vector Stores API attachment succeeds with chunking configuration.
- File metadata includes at least category, document type, tenant, version, and
  source.
- Indexed chunk count or equivalent vector-store evidence is captured.

## Retrieval

- Metadata extraction returns no invented filters.
- If tool/function calling is used for metadata extraction, validate it against
  the active MaaS/Llama Stack model path. If tool calling fails, use structured
  JSON chat completion only with an explicit recorded finding.
- Hybrid search is used for the main retrieval path.
- Metadata filters narrow results for category-specific queries. Validate this
  per search mode; do not assume `hybrid`, `vector`, and `keyword` enforce
  filters identically.
- If the current `hybrid` path ignores filters, keep the user-facing notebook
  on the verified filtered mode and keep the hybrid path as a documented
  unresolved acceptance gate.
- Qwen3 reranker scores are present for AG News compatibility validation.
- Reranking is invoked through Llama Stack `/v1alpha/inference/rerank`, not
  directly against the KServe/vLLM endpoint, unless the stage plan explicitly
  records a temporary fallback.
- Final answer uses retrieved context and does not claim unsupported citations.
- Validation includes a negative or out-of-scope query.

## GitOps And Operations

- Old Stage 230 active resources are removed or clearly replaced.
- Manifests render locally.
- Shared resources are patched only through the shared owner path.
- Deploy script applies Argo CD Application first and uses the environment
  safety guard.
- Validate script proves end-to-end RAG, not only pod readiness.
- Workbench notebook or terminal flow can run the same acceptance script as
  automated validation.
- Deferred Dutch government publication ingestion is tracked in
  `docs/BACKLOG.md` until implemented.
- If KFP is used, pipeline server readiness, compiled pipeline artifact,
  pipeline run status, task logs, and artifact output are checked through
  `rhoai-ai-pipelines` and `rhoai-kfp-pipeline-authoring`.

## Fail Conditions

- Llama Stack is presented as GA production-supported.
- RAG success is claimed from a model-only answer.
- Direct Llama deployment is introduced without explaining why MaaS Nemotron is
  not used.
- The reference Helm chart is applied directly without local curation.
- Hardcoded passwords or API keys are committed.
- Milvus, reranker, or dataset artifacts are presented as Red Hat-supported
  without source evidence.
