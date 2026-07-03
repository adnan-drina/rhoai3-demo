# Stage 230: Private Data RAG Reimplementation Plan

## Conceptual Foundation

- Stage identifier: `230`
- Stage family: `2xx Production GenAI & Private Data`
- Stage slug: `stage-230-private-data-rag`
- Concept introduced: metadata-aware enterprise RAG
- Target audience: enterprise architects, platform engineers, data scientists,
  and risk owners
- Enterprise value: private knowledge grounding with retrieval precision,
  version/source control, traceability, and governed model access
- Depends on:
  - `stage-110-rhoai-base-platform` for RHOAI, ODF/object storage, users, and
    shared DSC ownership
  - `stage-120-gpu-as-a-service` for GPU platform readiness
  - `stage-210-model-serving-foundation` for model-serving foundation
  - `stage-220-models-as-a-service` for governed Nemotron access through MaaS

## Scope

Active Stage 230 scope:

- `enterprise-rag` OpenShift AI project
- Llama Stack / OGX RAG runtime
- PostgreSQL metadata store for Llama Stack
- PostgreSQL `pgvector` extension through the documented `remote::pgvector`
  provider for metadata-filtered vector, keyword, and hybrid search
- CPU-hosted Qwen3 reranker based on the Red Hat article-linked reference
  implementation
- Llama Stack `userConfig` adapted from the Red Hat article-linked AG News
  implementation
- Enterprise RAG Workbench for notebook-driven ingestion, retrieval inspection,
  and acceptance runs
- deterministic AG News sample and acceptance helpers
- official RHOAI 3.4 product-document explainer corpus with repo-stored source
  PDFs, deterministic prepared chunks, preparation helper, smoke helper, and
  workbench notebook
- GitOps-managed DSPA pipeline server, generated S3 Secret, and Docling KFP
  runner for repeatable RHOAI product-document data preparation
- Streamlit product-document chatbot adapted from the upstream Llama Stack
  UI distribution: discovery-driven playground, distribution inspection, and
  evaluation pages against the Stage 230 Llama Stack service, with
  per-vector-store demo question suggestions for the product-doc corpus
- AutoRAG (Technology Preview) optimization over the RHOAI product-document
  corpus: GitOps-managed remote Milvus for the AutoRAG-required vector
  provider, `remote::milvus` registered in Llama Stack alongside pgvector,
  `BAAI/bge-m3` registered as a second embedding model, a committed
  ground-truth benchmark data set, a GitOps-managed Llama Stack dashboard
  connection type, a generated AutoRAG connection Secret, and a vendored
  `documents-rag-optimization-pipeline` runner through the Stage 230 DSPA
  (scope added 2026-07-02 at explicit user request; AutoRAG was previously
  out of scope)

Out of scope for this stage unless explicitly added later:

- EvalHub/RAGAS evaluation
- guardrails and MCP
- production HA for databases or vector stores
- claiming the adjacent RHOAI product capabilities described by the product
  documentation corpus as implemented in this stage

## Architecture Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Generation model | Use Stage 220 Nemotron through MaaS | Preserves the demo story: governed model first, private data second |
| Reference corpus | AG News | The Red Hat article and repo use it, so it remains the best compatibility test |
| Audience corpus | Selected official RHOAI 3.4 PDFs committed under `data/rhoai-product-docs/` | Lets the same RAG system answer audience questions about the product docs behind this demo from reviewed, repeatable source material |
| Vector store | Remote PostgreSQL with pgvector | Official RHOAI 3.4 Llama Stack docs document `remote::pgvector`, and live validation showed pgvector enforces metadata filters for vector, keyword, and hybrid search |
| Metadata store | PostgreSQL for Llama Stack metadata | Required by official Llama Stack guidance; this stage uses the same PostgreSQL service for metadata and pgvector while keeping the concerns distinct in configuration |
| Embeddings | Use `sentence-transformers/nomic-ai/nomic-embed-text-v1.5` through the inline sentence-transformers provider | This is the embedding model listed by the active RHOAI 3.4 Llama Stack server |
| Reranker | Use the article's Qwen3 reranker pattern on CPU | Reranker improves precision; the non-Red-Hat modelcar remains a documented demo exception |
| Reranker registration | Register Qwen3 in Llama Stack as `vllm-reranker/qwen3-reranker` and call `/v1alpha/inference/rerank` | Matches the reference notebook flow better than calling the KServe/vLLM endpoint directly |
| Workbench dependencies | Preinstall notebook dependencies into the shared workbench PVC and expose them through `PYTHONPATH` | The reference notebook uses `%pip install`; this demo needs a repeatable ready-to-run workbench after GitOps deployment |
| KFP posture | Use an end-to-end `docling-standard` KFP pipeline for the committed RHOAI product PDFs with Llama Stack vector store ingestion | Follows the OpenDataHub data-processing pattern for data preparation (import, split, model-download, convert, chunk, enrich) and extends it with Llama Stack ingestion to produce a query-ready vector store in a single pipeline run, without mixing in AutoRAG, RAGAS, or guardrails scope |
| Docling dashboard placement | Show Docling in the OpenShift AI Pipelines run graph, not the project Deployments tab | The Red Hat-documented and OpenDataHub reference pattern uses Docling as a KFP data-preparation component. The Deployments tab is reserved here for served endpoints such as the Qwen3 reranker. |
| Docling workbench pre-install | Pre-install Docling and pre-cache layout models and HybridChunker tokenizer in the workbench init container | Follows the official RHOAI 3.4 data preparation pattern (Docling as a library in notebooks) while ensuring zero runtime downloads during demos. Docling layout models and `sentence-transformers/all-MiniLM-L6-v2` tokenizer are cached on the PVC. PVC increased to 20Gi to accommodate Docling dependencies and model cache. |
| AutoRAG vector database | Re-add the demo-grade remote Milvus (standalone + etcd) alongside pgvector | The official RHOAI 3.4 AutoRAG guide requires a remote Milvus vector database registered with Llama Stack; inline Milvus is unsupported. pgvector remains the application retrieval path because filtered hybrid search is a stage requirement; Milvus serves the AutoRAG search space only, which does not use metadata-filtered retrieval. |
| AutoRAG embedding models | Serve `granite-embedding-30m` and `all-minilm-l6-v2` as dedicated vLLM CPU KServe `InferenceService`s (reranker pattern) registered as `remote::vllm` embedding providers; keep `BAAI/bge-m3` registered inline but out of CPU runs | ai4rag sends embedding batches of up to 2048 chunks per request with a fixed 60s client timeout and no tuning knobs. Live measurements on the inline 14-CPU server: nomic 5.7 texts/s, bge-m3 3.0, granite-30m 5.2 (silently failing every AutoRAG evaluation), MiniLM 22.8. Dedicated vLLM CPU serving gives each embedding model its own CPU allocation and optimized kernels, keeps all served models on the same KServe pattern, and restores the granite-vs-MiniLM leaderboard comparison. nomic remains the inline app-path model. |
| AutoRAG generation comparison | Run AutoRAG with both `vllm-inference/nemotron-3-nano-30b-a3b` and `vllm-gpt/gpt-4o-mini` through MaaS | The leaderboard quantifies the private-local vs governed-external generation trade-off on the stage corpus under identical retrieval settings, closing the Stage 220 governance narrative. The corpus is public Red Hat documentation, so governed egress to the external model is acceptable and explicitly a demo talking point. |
| AutoRAG MaaS quota | Dedicated Stage 220 `enterprise-rag-autorag` MaaSSubscription (Nemotron 2M tokens/h, gpt-4o-mini 1M tokens/h) | Optimization runs burst many generation calls; the interactive subscription budgets caused silent 429 pattern failures on the leaderboard (observed live). Governance stays enforced through a subscription sized for the workload rather than a bypass. |
| AutoRAG input corpus and benchmark theme | Scope the AutoRAG input to the Evaluating AI systems, Guardrails, and AutoRAG guides (~1,000 chunks) under `autorag/rhoai-product-docs/input/`, with a 12-question validate-and-protect benchmark | The benchmark theme (how to evaluate and protect RAG) makes optimization results read as enterprise concerns and previews the next demo stages (guardrails, EvalHub evaluation). ~1,000 chunks keep retrieval settings statistically distinguishable while fitting CPU embedding throughput; 1-2 documents would saturate context correctness and blur the leaderboard. The full 6-guide corpus remains the chatbot/pgvector application path. AutoRAG itself samples input (1 GiB cap), so scoping input is aligned product behavior. |
| AutoRAG pipeline source | Vendor the compiled `documents-rag-optimization-pipeline` from `red-hat-data-services/pipelines-components` branch `rhoai-3.4` | The Red Hat build pins the supported `registry.redhat.io/rhoai/odh-autorag-rhel9` image and the exact 3.4 parameter contract (`llama_stack_vector_io_provider_id`, S3/Llama Stack secret env keys). Importing with the documented pipeline name keeps runs visible on the Gen AI studio AutoRAG page. |
| AutoRAG run posture | KFP-native runs through the Stage 230 DSPA via `run-autorag-pipeline.sh`, defaulting to 4 RAG patterns and the faithfulness metric | Scriptable, evidence-producing runs match the stage validation pattern; the dashboard AutoRAG UI remains the demo surface for reviewing leaderboards and generated notebooks. |

## Source Capture

| Purpose | Source | Skill | Notes |
|---------|--------|-------|-------|
| Concept/value | [Build an enterprise RAG system with OGX](https://developers.redhat.com/articles/2026/05/26/build-enterprise-rag-system-ogx) | `project-documentation-authoring`, `rhoai-enterprise-rag` | Explains metadata filtering, hybrid search, reranking, and enterprise RAG value |
| Product config | [RHOAI 3.4: Working with Llama Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_llama_stack/index) | `rhoai-llama-stack`, `rhoai-enterprise-rag` | Product authority for Llama Stack, vector stores, ingestion, query, PostgreSQL metadata, and pgvector |
| Product explainer corpus | [RHOAI 3.4 documentation landing page](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4) | `rhoai-enterprise-rag`, `rhoai-llama-stack`, `rhoai-autorag`, `rhoai-evaluation`, `rhoai-guardrails-safety`, `rhoai-ai-pipelines` | Repo-stored PDFs used as the primary focused audience Q&A corpus |
| Product config | [RHOAI 3.4: Govern LLM access with Models-as-a-Service](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/govern_llm_access_with_models-as-a-service/index) | `rhoai-maas-governance` | Product authority for governed Nemotron access |
| Product config | [RHOAI 3.4: Prepare your data for AI consumption](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/customize_models_for_gen_ai_and_agentic_ai_applications/prepare-your-data-for-ai-consumption_custom-models) | `rhoai-model-customization-training`, `rhoai-ai-pipelines`, `rhoai-kfp-pipeline-authoring` | Product authority for Docling data preparation and future KFP automation |
| Reference implementation | [abdelhamidfg/agnews-rag-demo](https://github.com/abdelhamidfg/agnews-rag-demo) | `rhoai-enterprise-rag` | Red Hat article-linked repo; example-only source for chart and notebooks |
| Reference implementation | [llama-stack UI distribution](https://github.com/llamastack/llama-stack-client-python) and the upstream Llama Stack playground UI | `rhoai-chatbot-customization` | Vendored and adapted as the Stage 230 chatbot: discovery-driven playground, distribution inspection, and evaluation pages with ConfigMap-driven question suggestions |
| Reference implementation | [opendatahub-io/data-processing `main` KFP tree](https://github.com/opendatahub-io/data-processing/tree/main/kubeflow-pipelines) | `rhoai-model-customization-training`, `rhoai-kfp-pipeline-authoring` | Newer Red Hat-documented Docling KFP example selected for its modular standard/VLM layout, Secret-mounted S3 input, `ParallelFor` conversion, and HybridChunker output |
| Product config | [RHOAI 3.4: Working with AutoRAG](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_autorag/index) | `rhoai-autorag` | Product authority for AutoRAG Technology Preview posture, prerequisites, remote Milvus requirement, test data format, metrics, and search space |
| Reference implementation | [red-hat-ai-examples AutoRAG example](https://github.com/red-hat-data-services/red-hat-ai-examples/tree/main/examples/autorag) | `rhoai-autorag` | Tutorial-grade reference for the Llama Stack connection type, S3 layout, benchmark data shape, and both UI and KFP-native run paths |
| Reference implementation | [pipelines-components `rhoai-3.4` AutoRAG pipeline](https://github.com/red-hat-data-services/pipelines-components/tree/rhoai-3.4/pipelines/training/autorag/documents_rag_optimization_pipeline) | `rhoai-autorag`, `rhoai-kfp-pipeline-authoring` | Authoritative compiled pipeline definition and parameter contract vendored into this stage |

## Manifest Inventory

| Path | Kind | Source authority | Validation |
|------|------|------------------|------------|
| `gitops/stage-230-private-data-rag/project/` | Namespace, RBAC, CPU LocalQueue, ObjectBucketClaim | RHOAI project workflow docs, Kueue docs, ODF object bucket docs | Project exists, OBC is bound, namespace is Kueue-managed |
| `gitops/stage-230-private-data-rag/postgresql/` | StatefulSet and Service; Secret generated by deploy script | RHOAI Llama Stack PostgreSQL metadata and pgvector guidance | Pod readiness, pgvector extension installed, Llama Stack metadata connection |
| `gitops/stage-230-private-data-rag/llamastack/` | `LlamaStackDistribution` and `userConfig` ConfigMap | RHOAI Llama Stack docs and reviewed article-linked config pattern | `LlamaStackDistribution` Ready and `/v1/models` lists Nemotron, embedding model, and reranker |
| `gitops/stage-230-private-data-rag/reranker/` | Qwen3 reranker `ServingRuntime`, `InferenceService`, and Route | RHOAI model deployment docs plus reviewed article-linked artifact/runtime pattern | Rerank endpoint scores returned candidates |
| `gitops/stage-230-private-data-rag/workbench/` | Project workbench `Notebook`, ServiceAccount, and PVC | RHOAI project workbench and Notebook CR docs | Workbench resource exists, pod starts, and visible workspace contains AG News notebooks plus RHOAI product docs notebook |
| `gitops/stage-230-private-data-rag/rhoai-dsc/` | Shared DSC patch job enabling `aipipelines` | RHOAI DSC component configuration and AI Pipelines docs | `default-dsc.spec.components.aipipelines.managementState=Managed` |
| `gitops/stage-230-private-data-rag/pipelines/` | DSPA pipeline server backed by Stage 230 NooBaa bucket | RHOAI AI Pipelines docs | DSPA Ready, route exists, object storage condition passes |
| `gitops/stage-230-private-data-rag/dashboard/` | OpenShift AI dashboard `OdhApplication` tile for the RAG chatbot | RHOAI dashboard application docs | Tile exists in `redhat-ods-applications`, uses documented dashboard labels, and points at the chatbot Route |
| `stage-230-private-data-rag/data/agnews-sample/` | Small deterministic AG News-compatible sample | Red Hat article-linked repo pattern, locally adapted | Stable ingestion smoke input without external dataset dependency |
| `stage-230-private-data-rag/data/rhoai-product-docs/` | Source manifest, selected official RHOAI 3.4 PDFs, deterministic prepared chunks | RHOAI 3.4 docs landing page and guide PDFs | Manifest JSON parses; source PDFs exist in Git; prepared JSONL parses; deploy uploads PDFs to project bucket |
| `stage-230-private-data-rag/kfp/` | RHOAI product-doc Docling KFP source | RHOAI data-preparation docs and `opendatahub-io/data-processing` `main/kubeflow-pipelines` | KFP source compiles, exposes modular Docling tasks in the Dashboard run graph, and pipeline runs through DSPA |
| `gitops/stage-230-private-data-rag/app/` | Streamlit chatbot build/runtime resources plus the gpt-connection-keepalive CronJob | Upstream Llama Stack UI distribution, adapted to Stage 230 | Python compile; BuildConfig in `enterprise-rag-build`; Deployment and route health in `enterprise-rag` |
| `stage-230-private-data-rag/chatbot/` | Vendored Llama Stack UI distribution source | Upstream Llama Stack playground UI, adapted to Stage 230 | Python compile; OpenShift binary build; route health; question suggestions target the product-doc store |
| `stage-230-private-data-rag/run-rhoai-docs-pipeline.sh` | KFP compile/upload/run/evidence helper | RHOAI AI Pipelines docs and repo KFP standards | PipelineVersion created, run succeeds, S3 artifacts reviewed |
| `stage-230-private-data-rag/scripts/` | AG News and RHOAI product-doc preparation/smoke helpers | RHOAI Llama Stack APIs and official RHOAI PDFs | Python compile; optional workbench smoke runs |
| `gitops/stage-230-private-data-rag/milvus/` | Milvus standalone Deployment, etcd, PVC, Services; Secret generated by deploy script | RHOAI AutoRAG remote Milvus requirement and Llama Stack `remote::milvus` provider docs | Deployments available, Llama Stack lists the `milvus` vector_io provider |
| `gitops/stage-230-private-data-rag/embeddings/` | `granite-embedding-30m` and `all-minilm-l6-v2` vLLM CPU ServingRuntimes and InferenceServices (`hf://` storage, pooling/embed runner, chunked pooling, Recreate strategy) | RHOAI model deployment docs plus the stage reranker serving pattern | InferenceServices Ready, Kueue-queued, Llama Stack lists both `remote::vllm` embedding models |
| `gitops/stage-230-private-data-rag/app/base/cronjob-gpt-keepalive.yaml` | Two-minute governed 1-token completion keeping the MaaS external-model gateway connection pool warm | Live NAT idle black-holing finding; ExternalModel CRD exposes no connection-pool tuning | CronJob exists; gpt-4o-mini responds sub-second after warm-up |
| `gitops/stage-220-models-as-a-service/policies/base/autorag-optimization-access.yaml` | Dedicated `enterprise-rag-autorag` MaaSSubscription sized for optimization bursts | Stage 220 MaaS governance model | Subscription exists; stage key minted against it |
| `gitops/stage-230-private-data-rag/dashboard/base/connectiontype-llama-stack.yaml` | Dashboard connection type for Llama Stack connections | AutoRAG example connection-type pattern over documented RHOAI connection types | ConfigMap exists in `redhat-ods-applications` with connection-type labels |
| `stage-230-private-data-rag/data/rhoai-product-docs/autorag/` | Committed AutoRAG ground-truth benchmark data | RHOAI AutoRAG test data format | JSON parses; document IDs match committed PDF base names; deploy uploads to project bucket |
| `stage-230-private-data-rag/kfp/vendor/` | Vendored compiled `documents-rag-optimization-pipeline` (rhoai-3.4) | `pipelines-components` branch `rhoai-3.4` | Pipeline name matches documented AutoRAG naming; runner imports and runs it through DSPA |
| `stage-230-private-data-rag/run-autorag-pipeline.sh` | AutoRAG import/run/evidence helper | RHOAI AutoRAG docs and pipelines-components parameter contract | PipelineVersion created, run succeeds, leaderboard and pattern artifacts reviewed |

## Script Plan

### `deploy.sh`

- Load `.env` and run the OpenShift safety guard.
- Apply the Stage 230 Argo CD Application first.
- Wait for the `enterprise-rag` namespace.
- Wait for the Stage 230 `ObjectBucketClaim` to bind.
- Create the `enterprise-rag-s3` dashboard S3 connection Secret and
  `data-processing-docling-pipeline` Secret from OBC-generated credentials.
- Run an in-cluster upload Job that clones the same Git branch as Argo CD and
  uploads repo-stored RHOAI product source PDFs to the project bucket under
  `raw/rhoai-product-docs/` plus the AutoRAG benchmark JSON under
  `autorag/rhoai-product-docs/`.
- Create or update non-committed Secrets from local environment values,
  generated database credentials, and the Stage 220 MaaS API-key flow,
  including the Milvus credentials Secret and the AutoRAG Llama Stack
  connection Secret (`LLAMA_STACK_CLIENT_BASE_URL`,
  `LLAMA_STACK_CLIENT_API_KEY`).
- Refresh the Argo CD Application after Secret creation.
- Start the `private-rag-chatbot` binary BuildConfig in `enterprise-rag-build`
  from the local `stage-230-private-data-rag/chatbot/` source and wait for the
  runtime Deployment in `enterprise-rag` to become available.
- Leave ingestion to validation or explicit user-triggered smoke runs.

### `validate.sh`

- Confirm Stage 230 Argo CD sync/health.
- Confirm `enterprise-rag` project, RBAC, LocalQueue, and OBC.
- Confirm environment-local Secrets exist.
- Confirm the dashboard S3 connection and pipeline S3 Secret exist.
- Confirm the shared DSC has AI Pipelines enabled.
- Confirm the `dspa-enterprise-rag` pipeline server exists, reports Ready, and
  exposes a route.
- Confirm the `RHOAI Product Docs Docling Pipeline` `Pipeline` and latest
  `PipelineVersion` are visible to the DSPA/KFP API with readable dashboard
  display names.
- Confirm repo-stored RHOAI product source PDFs and prepared chunks exist.
- Confirm PostgreSQL availability and `pgvector` extension installation.
- Confirm Milvus and etcd availability and the Milvus and AutoRAG connection
  Secrets.
- Confirm Llama Stack readiness, the model list including the bge-m3 AutoRAG
  embedding model, and the `milvus` vector_io provider.
- Confirm Gen AI studio is enabled, the Llama Stack dashboard connection type
  exists, the AutoRAG benchmark data is valid, and the vendored AutoRAG
  pipeline keeps the documented name.
- Confirm the Qwen3 reranker `InferenceService` and route.
- Confirm Docling is represented by AI Pipelines tasks and is not expected as a
  KServe `InferenceService` in the Deployments tab.
- Confirm the Enterprise RAG Workbench exists, reports Ready when available,
  exposes the curated AG News and RHOAI product-doc workspace, and does not
  expose the full implementation repository.
- Confirm the Streamlit chatbot source compiles, the build namespace exists,
  BuildConfig/ImageStream exist there, the image tag has been built, the
  runtime Deployment is available, the route health endpoint responds, and
  config points at the Stage 230 Llama Stack service and product-document
  vector store.
- Confirm the OpenShift AI dashboard `OdhApplication` tile exists in
  `redhat-ods-applications`, preserves the documented `odh-dashboard` labels,
  and points at `enterprise-rag/private-rag-chatbot`.
- Confirm the AG News and RHOAI product-document helpers compile.
- Optional gate: run AG News full acceptance with
  `RHOAI_STAGE230_RUN_ACCEPTANCE=true`.
- Optional gate: run RHOAI product-document smoke with
  `RHOAI_STAGE230_RUN_RHOAI_DOCS_SMOKE=true`.
- Optional gate: run RHOAI product-document Docling KFP automation with
  `RHOAI_STAGE230_RUN_RHOAI_DOCS_PIPELINE=true`.
- Optional gate: run the AutoRAG optimization pipeline with
  `RHOAI_STAGE230_RUN_AUTORAG=true`.
- When both optional RHOAI product-document gates are enabled, use the
  pipeline-generated JSONL output for the RAG smoke vector store.

### `run-autorag-pipeline.sh`

- Load `.env` and enforce the OpenShift safety guard.
- Require the dashboard S3 connection Secret and the AutoRAG connection Secret
  created by `deploy.sh`.
- Import the vendored `documents-rag-optimization-pipeline` (rhoai-3.4
  compiled IR) as a reviewed `Pipeline` and timestamped
  `documents-rag-optimization-pipeline-3.4-<ts>` `PipelineVersion` so runs
  appear on the Gen AI studio AutoRAG page.
- Pre-warm each AutoRAG embedding model with a single `/v1/embeddings` call,
  and flush the MaaS external-model gateway connection pool with short
  completions until each generation model answers three times consecutively.
- Submit a DSPA run with the Stage 230 parameters: the scoped
  `autorag/rhoai-product-docs/input/` document set (Evaluating AI systems,
  Guardrails, AutoRAG guides), the committed validate-and-protect benchmark
  JSON as test data, `milvus` as `llama_stack_vector_io_provider_id`,
  Nemotron plus gpt-4o-mini as generation models, and the vLLM-served
  granite-embedding-30m plus all-minilm-l6-v2 as embedding models (metric
  `faithfulness`, 4 patterns by default).
- Review the run's S3 artifacts for leaderboard and RAG pattern outputs.
- Store run evidence in `stage230-autorag-pipeline-evidence`.

### `run-rhoai-docs-pipeline.sh`

- Load `.env` and enforce the OpenShift safety guard.
- Create or reuse `.venv-kfp` with `kfp==2.14.6` and
  `kfp-kubernetes==2.14.6`.
- Compile `kfp/rhoai_product_docs_docling_pipeline.py`.
- Create a reviewed `Pipeline` and timestamped `PipelineVersion` using
  Kubernetes API pipeline storage.
- Submit a DSPA run against `dspa-enterprise-rag`.
- Process source PDFs from the `data-processing-docling-pipeline` Secret's
  S3 prefix, normally `raw/rhoai-product-docs/`.
- Run end-to-end KFP tasks: `import-pdfs`, `create-pdf-splits`,
  `download-docling-models`,
  `process-pdf-splits(docling-convert-standard -> docling-chunk-and-upload)`,
  `enrich-and-publish-rhoai-chunks`, and `ingest-to-vector-store`.
- Write Docling Markdown/JSON evidence and JSONL chunks under
  `processed/rhoai-product-docs/`.
- Ingest the enriched chunks into a Llama Stack vector store via Files API.
- Review the S3 output and store run evidence in
  `stage230-rhoai-docs-pipeline-evidence`.

## Risks And Deferred Work

| Item | Type | Resolution |
|------|------|------------|
| Remote Milvus native hybrid filtering | resolved design finding | Filtered `vector` and `keyword` search worked in the observed Milvus path, but filtered `hybrid` search returned mixed categories. Stage 230 uses pgvector because filtered hybrid search is required. |
| Qwen3 reranker artifact provenance | risk | Accepted as a demo exception based on the Red Hat article-linked implementation; do not present the modelcar as Red Hat-supported. |
| Qwen3 reranker CPU sizing | finding | GitOps uses a `4` CPU / `10Gi` request with reduced batching for the demo worker shape. |
| Nemotron tool calling for metadata extraction | finding | Tool-call requests returned HTTP 500 in the current MaaS/Llama Stack path; use structured JSON chat completion until a supported tool-call path is verified. |
| Hugging Face dataset egress | risk | Include a small deterministic AG News sample for validation; make full dataset download optional. |
| Embedding provider mismatch | risk | List active Llama Stack models and capture embedding dimension before vector store creation. |
| RHOAI product-document ingestion | active | Focused official RHOAI 3.4 PDF corpus is the audience Q&A corpus; source PDFs and deterministic chunks are committed and mirrored to S3. |
| RHOAI product-document KFP automation | validated | Docling KFP source and runner compile, run through DSPA, review S3 artifacts, and feed pipeline-generated chunks into the RAG smoke helper. |
| AutoRAG inline-vs-remote Milvus source conflict | recorded finding | The older red-hat-ai-examples tutorial says only `inline::milvus` is supported; the official RHOAI 3.4 AutoRAG guide says only remote Milvus is supported. The official guide wins per repo policy; Stage 230 registers `remote::milvus`. Verify the accepted provider id on the first live run. |
| CPU embedding throughput vs ai4rag batch contract | resolved finding | ai4rag embeds up to 2048 chunks per request with a fixed 60s client timeout. Measured inline throughput (8 CPU): nomic 5.7 texts/s, bge-m3 3.0 texts/s — the full 6-guide corpus (~2,690 chunks at 1024 chars) cannot pass on CPU with mid/large models; a 12Gi server was also OOMKilled before the sizing fix. Resolution: ~30M-class embedding models, LSD at 14 CPU / 24Gi, scoped ~1,000-chunk AutoRAG input, and runner pre-warm. GPU-served vLLM embeddings are the documented upgrade path for full-corpus optimization. |
| Embedding model first-use download | mitigated | sentence-transformers models download to the Llama Stack PVC (10Gi) on first embedding call; `run-autorag-pipeline.sh` pre-warms each AutoRAG embedding model so downloads happen outside the pipeline's fixed timeout. |
| Unauthenticated Llama Stack API key | finding | The Stage 230 LSD has no API auth; the AutoRAG connection Secret carries a placeholder `LLAMA_STACK_CLIENT_API_KEY`. Verify the pipeline accepts it on the first live run. |
| AutoRAG optimization run duration and sizing | risk | Pipeline tasks request 2 CPU / 8Gi each and the optimization loop drives CPU embedding plus MaaS generation; default gate uses 4 patterns and a 7200s timeout. |
| MaaS external-model gateway connection black-holing | mitigated finding | Envoy pools long-lived TLS connections to the external provider; AWS NAT silently drops idle mappings, hanging requests for the 60s route timeout. The ExternalModel CRD exposes no connection-pool tuning. Mitigations: the `gpt-connection-keepalive` CronJob plus the runner's pre-run pool flush. Upstream ask: connection-pool tuning (idle timeout below NAT, TCP keepalive) on the generated DestinationRule. |
| vLLM lenient argument parsing | recorded finding | The vLLM OpenAI server silently consumes unknown flags as the positional model tag (observed with a misspelled pooler flag), so misconfigured args produce no error. Verify engine startup config lines, not just pod args. |
| ai4rag silent evaluation failures | recorded finding | ai4rag 0.5.4 exports only successful evaluations; embedding timeouts, length rejections, and generation errors remove patterns from the leaderboard without any UI trace, and pattern.json `max_combinations` is the exported count, not the search-space size. Review the rag-templates-optimization pod logs when a leaderboard looks thinner than the requested budget. |
| Llama Stack startup coupling to registered backends | recorded finding | Startup-time model registration requires each registered provider backend to be reachable; an unschedulable embedding InferenceService crash-looped the server. Order deployments accordingly or expect recovery after backends come up. |
| RAGAS / evaluation | deferred | Keep for a later evaluation-focused stage. |
| Guardrails and MCP | deferred | Keep for later safety and agentic stages. |

## Review Needed

- Validate the Llama Stack UI chatbot in a fresh environment after the next
  full deploy: playground chat and direct RAG against the product-document
  vector store, model and vector-store discovery, and the seeded question
  suggestions.
- Walk the AutoRAG demo path end to end once in the dashboard: leaderboard
  for run `f79dab42`, pattern detail with sample Q&A, and the fetched
  `workspace/autorag/Pattern8/` notebooks in the Enterprise RAG Workbench.
  (Display-name contract confirmed live: the AutoRAG page matches the
  documented `documents-rag-optimization-pipeline` display name; readability
  lives in the pipeline description.)

## First Live AutoRAG Run (2026-07-03, resolved)

The first successful optimization run (`documents-rag-optimization-pipeline`,
run `4713d11a`, validate.sh 101/0) settled the recorded verifications:

- placeholder `LLAMA_STACK_CLIENT_API_KEY` accepted end to end
- vector provider id `milvus` accepted (ai4rag reports `ls_milvus`
  datasource); Milvus collections created and queried with hybrid search
- LSD PVC expanded to 10Gi; embedding caches persist
- leaderboard: two evaluated patterns, both MiniLM at 2048/256 chunking with
  hybrid top-10 retrieval; weighted ranker scored answer_correctness 0.672
  vs RRF 0.645, faithfulness ~0.65-0.66 both, context_correctness 1.0
  (saturated on the scoped corpus, as predicted for small corpora)
- artifacts per pattern: pattern.json, evaluation_results.json, indexing and
  inference notebooks, and /v1/responses request bodies

## Full Comparison Run (2026-07-03, resolved)

The first complete four-way optimization run (`f79dab42`) evaluated and
exported all 8 requested patterns with zero silent failures, spanning both
generation models (Nemotron and governed gpt-4o-mini) and both vLLM-served
embedding models (granite-embedding-30m and all-minilm-l6-v2):

- answer correctness: Nemotron patterns scored 0.60-0.66 vs gpt-4o-mini
  0.46-0.56 on this corpus — the measured private-vs-external evidence the
  stage narrative is built on
- answer faithfulness: best pattern overall was Nemotron with
  granite-embedding-30m, hybrid top-3 RRF (0.727); gpt-4o-mini patterns
  clustered at 0.67-0.70
- context correctness saturated at 1.0 across patterns, as expected for the
  scoped corpus
- network hardening required for the governed external model, all verified
  by measurement: the in-cluster MaaS proxy (load-balancer hairpin dropped
  ~40% of fresh in-cluster connections), the pool-breadth keepalive
  (gateway-to-provider connections NAT-black-holed after idle), explicit
  model registration (no /v1/models on the external-model proxy), and
  max_tokens: 0 on the provider (adapter default collides with
  max_completion_tokens at the OpenAI backend)
- open upstream ask: connection-pool tuning (idle timeout, TCP keepalive)
  on the ExternalModel-generated DestinationRule; a live patch was
  intentionally not applied to the operator-owned shared resource

## Fresh Pipelines Rebuild (2026-07-03, resolved)

At the user's request the pipelines and AutoRAG state were scraped and
rebuilt fresh with all learnings applied (validate.sh 101/0 on the rebuilt
stack; Docling run `311fdd04`, AutoRAG run `578a836d`, both SUCCEEDED, and
the AutoRAG results-page backend listing verified server-side):

- AutoRAG dashboard results contract: HTTPS DSPA object storage, no
  `basePath`, artifacts at `<bucket>/documents-rag-optimization-pipeline/
  <run-id>/...` via explicit `pipeline_root=s3://<bucket>` at run
  submission (the DSP API server otherwise stamps `<bucket>/pipelines`),
  and the documented pipeline display name.
- Launcher artifact TLS: `SSL_CERT_FILE=/kfp/certs/ca.crt` on every task
  plus DSPA `cABundle` from `openshift-service-ca.crt`.
- Scrape scope: workflows, Pipeline/PipelineVersion resources, evidence
  ConfigMaps, stale S3 artifact prefixes, and orphaned Milvus vector stores
  from failed runs; corpus data, benchmark data, and app-path pgvector
  stores were preserved. DSPA recreation resets run history by design.
- Runner works for project-admin users (CSV image lookup reads the
  OLM-copied CSV in the stage namespace).
