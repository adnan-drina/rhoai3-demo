# Stage 230: Private Data RAG Reimplementation Plan

## Conceptual Foundation

- Stage identifier: `230`
- Stage family: `2xx Production GenAI & Private Data`
- Stage slug: `stage-230-private-data-rag`
- Concept introduced: metadata-aware enterprise RAG
- Target audience: enterprise architects, platform engineers, data scientists,
  and risk owners
- Enterprise value: private knowledge grounding with better retrieval
  precision, tenant/version control, traceability, and governed model access
- Depends on:
  - `stage-110-rhoai-base-platform` for RHOAI, ODF/object storage, users, and
    shared DSC ownership
  - `stage-120-gpu-as-a-service` for GPU platform readiness
  - `stage-210-model-serving-foundation` for model-serving foundation
  - `stage-220-models-as-a-service` for governed Nemotron access through MaaS
- New components:
  - `enterprise-rag` OpenShift AI project
  - Llama Stack / OGX RAG runtime
  - PostgreSQL metadata store for Llama Stack
  - PostgreSQL `pgvector` extension used through the documented
    `remote::pgvector` provider for metadata-filtered vector, keyword, and
    hybrid search
  - CPU-hosted Qwen3 reranker based on the Red Hat article-linked reference
    implementation
  - Llama Stack `userConfig` adapted from the Red Hat article-linked reference
    implementation to configure generation, embedding, vector, and reranker
    providers
  - RHOAI project workbench for notebook-driven ingestion and acceptance runs
  - `enterprise-rag` CPU LocalQueue for the Stage 120 `cpu-default` hardware
    profile and CPU reranker scheduling
  - deterministic AG News sample and smoke-test helper
- Existing components reused:
  - Stage 220 Nemotron MaaS endpoint
  - Stage 110 RHOAI dashboard and shared DSC owner
  - Stage 110 object storage when the Dutch publication corpus is added
- Non-goals for the first rebuild:
  - AutoRAG optimization
  - Docling document processing for AG News text rows
  - DSPA/KFP ingestion before the base RAG API path works
  - guardrails and MCP
  - production HA for databases or vector stores

The previous Stage 230 whoami/Docling/DSPA/chatbot implementation is being
retired as active design. It can be used as historical reference only. The new
baseline starts by reproducing the Red Hat Developer AG News enterprise RAG
pattern, replacing the article's Llama generation model with our governed
Nemotron model.

## Layered Architecture Analysis

| Layer | Stage 230 design | Rationale |
|-------|------------------|-----------|
| Infrastructure | Reuse Stage 120 GPU capacity for existing Nemotron; deploy storage-backed PostgreSQL with pgvector in the RAG project | Keeps scarce GPU capacity governed while providing RAG state in a dedicated project |
| Platform | RHOAI Llama Stack / OGX, MaaS, KServe/vLLM for the Qwen3 reranker, and project workbench | Aligns with RHOAI 3.4 Llama Stack, model deployment, and workbench documentation plus Stage 220 governance |
| Application | AG News ingestion plus retrieval pipeline using Files API, Vector Stores API, metadata filtering, hybrid search, rerank, final answer | Matches the Red Hat article and gives deterministic validation before custom data |
| Governance | Vector-store metadata, document metadata, MaaS policy, API keys, explicit demo exceptions | Shows how private data and model access are controlled separately |

## Metrics And Strategy

The first rebuild validates RAG mechanics, not business-domain quality. Success
is measured by:

- vector store creation with `tenant_id`, `version_no`, corpus, and environment
  metadata
- successful file upload and vector-store attachment for AG News records
- metadata filter extraction for category-specific queries
- hybrid search returning category-relevant candidates
- reranker scores from the Qwen3 reranker
- final Nemotron answer generated only after retrieved context is provided

Dutch government publication quality metrics, RAGAS, citation scoring, and
evaluation dashboards are deferred until the reference pattern works. Docling
conversion quality and KFP run evidence become required metrics once the
corpus shifts from AG News text rows to unstructured public documents.

## Design Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Generation model | Use Stage 220 Nemotron through MaaS | Preserves the demo story: governed model first, private data second |
| Initial corpus | AG News | The Red Hat article and repo use it, so it is the best compatibility test |
| Future corpus | Dutch government publications | This becomes the real enterprise use case after the reference flow works |
| Vector store | Remote PostgreSQL with pgvector | Official RHOAI 3.4 Llama Stack docs document `remote::pgvector`, and live validation showed pgvector enforces metadata filters for vector, keyword, and hybrid search in the active environment |
| Metadata store | PostgreSQL for Llama Stack metadata | Required by official Llama Stack guidance; this stage intentionally uses the same PostgreSQL service for metadata and pgvector vector storage while keeping the concerns distinct in configuration |
| Embeddings | Use `sentence-transformers/nomic-ai/nomic-embed-text-v1.5` through the inline sentence-transformers provider | This is the embedding model listed by the active RHOAI 3.4 Llama Stack server; the article notebook's Granite default is not assumed unless `/v1/models` lists it or registration is validated |
| Reranker | Use the article's Qwen3 reranker pattern on CPU | Reranker improves precision; the non-Red-Hat modelcar remains a documented demo exception |
| Reranker registration | Register Qwen3 in Llama Stack as `vllm-reranker/qwen3-reranker` and call `/v1alpha/inference/rerank` | Matches the reference notebook flow better than calling the KServe/vLLM endpoint directly |
| Reranker demo sizing | Request `4` CPU and `10Gi` memory, limit `8` CPU and `16Gi`, and use reduced CPU vLLM batching (`max-num-seqs=4`, `max-num-batched-tokens=512`) | Fresh demo worker nodes did not have enough requested CPU headroom for the article-linked `8` CPU request; this keeps reranking available without requiring GPU capacity |
| Deployment style | Re-author reference Helm resources into Kustomize/GitOps | This repo uses Argo CD and local curation, not direct Helm installs |
| Workbench dependencies | Preinstall notebook dependencies into the shared workbench PVC and expose them through `PYTHONPATH` instead of requiring `%pip` cells | The reference notebook uses `%pip install`; this demo needs a repeatable ready-to-run workbench after GitOps deployment |
| Ingestion interface | Notebook plus deterministic validation job/script | Keeps the Red Hat demo feel while allowing repeatable redeploy validation |
| Data preparation automation | Add Docling and KFP after AG News compatibility passes | RHOAI 3.4 documents Docling for unstructured data and KFP for automating multi-step Docling processing |
| Old implementation | Remove active whoami/Docling/DSPA/chatbot resources during implementation | Avoids mixed architectures and stale claims |

## Source Capture

| Purpose | Source | Skill | Notes |
|---------|--------|-------|-------|
| Concept/value | [Build an enterprise RAG system with OGX](https://developers.redhat.com/articles/2026/05/26/build-enterprise-rag-system-ogx) | `project-documentation-authoring`, `rhoai-enterprise-rag` | Explains metadata filtering, hybrid search, reranking, and enterprise RAG value |
| Product config | [RHOAI 3.4: Working with Llama Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_llama_stack/index) | `rhoai-llama-stack`, `rhoai-enterprise-rag` | Product authority for Llama Stack, vector stores, ingestion, query, PostgreSQL metadata, pgvector, and Milvus |
| Product config | [RHOAI 3.4: Govern LLM access with Models-as-a-Service](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/govern_llm_access_with_models-as-a-service/index) | `rhoai-maas-governance` | Product authority for governed Nemotron access |
| Product config | [RHOAI 3.4: Prepare your data for AI consumption](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/customize_models_for_gen_ai_and_agentic_ai_applications/prepare-your-data-for-ai-consumption_custom-models) | `rhoai-model-customization-training`, `rhoai-ai-pipelines`, `rhoai-kfp-pipeline-authoring` | Product authority for Docling data preparation and KFP automation |
| Reference implementation | [abdelhamidfg/agnews-rag-demo](https://github.com/abdelhamidfg/agnews-rag-demo) | `rhoai-enterprise-rag` | Red Hat article-linked repo; example-only source for chart and notebooks |
| Reference implementation | [opendatahub-io/data-processing stable branch](https://github.com/opendatahub-io/data-processing/tree/stable) | `rhoai-model-customization-training`, `rhoai-kfp-pipeline-authoring` | Red Hat-documented Docling notebook and KFP examples |
| Reference implementation | [opendatahub-io/data-processing KFP tree](https://github.com/opendatahub-io/data-processing/tree/main/kubeflow-pipelines) | `rhoai-model-customization-training`, `rhoai-kfp-pipeline-authoring` | Current Docling KFP implementation to compare with `stable`; use `main` only with an explicit branch decision |

### GitHub Reference Implementation Reviewed

The `agnews-rag-demo` repository provides:

- Helm templates for Llama Stack config, Milvus, PostgreSQL, Llama vLLM, and
  Qwen3 reranker
- `Ingestion_pipeline_ag_news.ipynb`
- `retrieval_pipeline_ag_news.ipynb`

Reusable ideas:

- AG News category metadata
- vector-store metadata for tenant and version
- Files API upload plus Vector Stores API attachment
- `search_mode="hybrid"`
- LLM-driven metadata filter extraction
- rerank before final answer

Boundaries:

- product fields still come from RHOAI docs or schema checks
- hardcoded sample credentials are not reused
- the Llama model is replaced with Nemotron through MaaS
- Helm output is translated into local GitOps manifests
- the article's Milvus provider is not copied as the active vector store
  because the Stage 230 acceptance gate requires metadata-filtered hybrid
  search and pgvector is the verified supported path in the active environment
- the Qwen3 reranker uses CPU resources in this demo; no GPU is required for
  the initial reranking workload
- the GitOps manifest sizes the reranker for the demo cluster worker shape
  rather than copying the article-linked CPU request verbatim

### Data Processing Reference Reviewed

The `opendatahub-io/data-processing` stable branch is the official-doc-linked
starting point for unstructured data preparation. It provides:

- Docling notebooks for conversion, chunking, extraction, subset selection, and
  RAG preparation
- `kubeflow-pipelines/common` for shared PDF import, splitting, model download,
  and Docling HybridChunker components
- `kubeflow-pipelines/docling-standard` for scalable standard document
  conversion, OCR, table structure, Markdown output, Docling JSON output, and
  optional chunk JSONL output
- `kubeflow-pipelines/docling-vlm` for complex layouts, custom instructions,
  remote VLM conversion, scanned/image-heavy documents, and image descriptors
- subset-selection scripts for reducing larger corpora while preserving
  diversity and coverage

For Stage 230, use this only after the AG News compatibility path proves the
RAG runtime. The Dutch government publication phase should adopt Docling and
KFP from this source instead of resurrecting the old whoami pipeline design.
The default branch for implementation is `stable`; the `main/kubeflow-pipelines`
tree is a useful newer reference and must be recorded explicitly if selected.

Docling KFP adoption rules:

- start with `docling-standard` for ordinary Dutch publication PDFs
- use `docling-vlm` only when layout or scanned/image-heavy content requires it
- use S3 input from the stage object-storage connection through a generated
  `data-processing-docling-pipeline` Secret
- enable chunking only after converted Markdown and Docling JSON are inspected
- treat upstream component images as runtime dependencies that require
  provenance review before adoption

## Skill Routing

- Coordinator: `project-demo-stage-authoring`
- Documentation: `project-documentation-authoring`
- GitOps: `project-gitops-authoring`
- Product skills:
  - `rhoai-enterprise-rag`
  - `rhoai-llama-stack`
  - `rhoai-maas-governance`
  - `rhoai-model-customization-training`
  - `rhoai-model-serving-platform`
  - `rhoai-s3-object-storage-data` for the later Dutch corpus
  - `rhoai-ai-pipelines`
  - `rhoai-kfp-pipeline-authoring`
- Review skills:
  - `project-manifest-review`
  - `project-red-hat-doc-alignment-review`
  - `rhoai-api-tiers`
- Environment skills:
  - `env-deploy-and-evaluate`
  - `env-troubleshoot`

## GitOps Ownership

- Ownership model: stage-owned, with shared-owner checks
- Owning Application: `stage-230-private-data-rag`
- Source path: `gitops/stage-230-private-data-rag/`
- Shared resources touched:
  - Llama Stack Operator enablement belongs to the shared RHOAI DSC owner if
    not already enabled
  - Nemotron model access belongs to Stage 220 MaaS resources
- Secret handling:
  - PostgreSQL password, MaaS token, and optional Hugging Face
    token must be generated or loaded locally and not committed

## Manifest Inventory

Planned first implementation inventory:

| Path | Kind | Source authority | Validation |
|------|------|------------------|------------|
| `gitops/stage-230-private-data-rag/project/` | Namespace, RBAC, and CPU LocalQueue | RHOAI project workflow docs, Kueue workload management docs, and repo standards | `oc get project`, RHOAI dashboard visibility, namespace Kueue label, `lq-cpu-default` readiness |
| `gitops/stage-230-private-data-rag/postgresql/` | StatefulSet and Service; Secret generated by deploy script; StatefulSet startup hook enables the `vector` extension through local PostgreSQL superuser access | RHOAI Llama Stack PostgreSQL metadata and pgvector guidance | Pod readiness, pgvector extension installed, Llama Stack metadata connection, and vector store registration succeeds |
| `gitops/stage-230-private-data-rag/llamastack/` | `LlamaStackDistribution` using official `rh-dev` distribution plus curated `userConfig` ConfigMap for AG News provider configuration | RHOAI Llama Stack docs, installed CRD schema, and reviewed article-linked config pattern | Server-side dry run, `LlamaStackDistribution` Ready, and `/v1/models` lists Nemotron, Nomic embedding, and Qwen3 reranker |
| `gitops/stage-230-private-data-rag/reranker/` | Qwen3 reranker `ServingRuntime`, `InferenceService`, and Route | RHOAI model deployment docs plus reviewed article-linked artifact/runtime pattern | Rerank endpoint responds and scores returned candidates |
| `gitops/stage-230-private-data-rag/workbench/` | Project workbench `Notebook`, ServiceAccount, and PVC | RHOAI project workbench and Notebook CR docs | Workbench resource exists, pod starts, and the visible workspace contains only the two AG News notebooks plus hidden generated helper content |
| `stage-230-private-data-rag/data/agnews-sample/` | Small deterministic AG News-compatible sample | Red Hat article-linked repo pattern, locally adapted | Stable ingestion smoke input without external dataset dependency |
| `stage-230-private-data-rag/scripts/` | AG News smoke and acceptance helpers | RHOAI Llama Stack APIs and Red Hat article-linked notebook pattern | Python compile now; full ingestion/search/rerank/answer run after runtime is deployed |

Deferred implementation inventory:

| Path | Kind | Source authority | Validation |
|------|------|------------------|------------|
| `stage-230-private-data-rag/pipelines/` | Later Docling KFP pipeline definitions adapted from `opendatahub-io/data-processing/kubeflow-pipelines` | RHOAI data-preparation chapter and `opendatahub-io/data-processing` examples | Branch choice recorded, compile check, imported pipeline, successful run, artifact review |

## Script Plan

### `deploy.sh`

- Load `.env` and run the OpenShift safety guard.
- Apply the Stage 230 Argo CD Application first.
- Wait for the `enterprise-rag` namespace.
- Create or update non-committed Secrets from local environment values,
  generated database credentials and the Stage 220 MaaS API-key flow.
- Refresh the Argo CD Application after Secret creation.
- Do not run ingestion until runtime readiness is confirmed.

### `validate.sh`

- Confirm Stage 230 Argo CD sync/health.
- Confirm `enterprise-rag` project and RBAC.
- Confirm environment-local Secrets exist.
- Confirm PostgreSQL availability and `pgvector` extension installation.
- Confirm Llama Stack readiness and model list.
- Confirm the Qwen3 reranker `InferenceService` and route.
- Confirm the Enterprise RAG Workbench `Notebook` exists and reports Ready
  when the RHOAI notebook controller sets status.
- Confirm the Enterprise RAG Workbench exposes the curated two-notebook
  workspace and does not expose the full `rhoai3-demo` implementation repo.
- Confirm the AG News smoke-test helper compiles.
- Confirm the AG News acceptance helper compiles.
- Keep storage consumers in the same Argo CD sync wave as PVCs when the
  cluster storage class uses `WaitForFirstConsumer`.
- Expose Llama Stack through a GitOps-managed OpenShift Route to the
  operator-managed Service; do not patch generated Ingress resources.
- Next gate: run the AG News acceptance path with metadata-filtered hybrid
  search and final Nemotron answer generation. Use the provider-qualified
  Llama Stack model ID `vllm-inference/nemotron-3-nano-30b-a3b` for Responses
  API calls.
- Full acceptance is run from the Enterprise RAG Workbench with
  `.stage230/scripts/agnews_rag_acceptance.py --reset --search-mode hybrid`;
  `validate.sh` uses the same workbench execution path when
  `RHOAI_STAGE230_RUN_ACCEPTANCE=true`. It must fail if metadata extraction,
  hybrid filtering, reranking, or grounded answer generation is broken.
- When Dutch publications are introduced, validate Docling conversion output,
  chunk quality, extracted metadata, KFP run status, branch choice, Secret
  contract, and artifact output before indexing.

## Operations And Troubleshooting

- `docs/OPERATIONS.md` update needed: yes, after implementation details settle.
- `docs/TROUBLESHOOTING.md` update needed: yes, after first live deployment.
- `docs/BACKLOG.md` update needed: yes, to mark Stage 230 as replanned and
  track Dutch publication ingestion.

## Risks And Deferred Work

| Item | Type | Resolution |
|------|------|------------|
| Remote Milvus native hybrid filtering | resolved design finding | Filtered `vector` and `keyword` search worked in the observed Milvus path, but filtered `hybrid` search returned mixed categories. Stage 230 now uses pgvector because filtered hybrid search is a required acceptance gate. Revisit Milvus only after a future RHOAI/Llama Stack path proves equivalent behavior. |
| Qwen3 reranker artifact provenance | risk | Accepted as a demo exception based on the Red Hat article-linked implementation; do not present the modelcar as Red Hat-supported |
| Qwen3 reranker CPU sizing | finding | The article-linked `8` CPU request did not schedule on the fresh demo cluster because no worker had enough unallocated requested CPU. GitOps uses a `4` CPU / `10Gi` request with reduced batching for the demo. Revisit if the reranker becomes a throughput-sensitive component. |
| Nemotron tool calling for metadata extraction | finding | Tool-call requests returned HTTP 500 in the current MaaS/Llama Stack path; use structured JSON chat completion for metadata extraction until a supported tool-call path is verified |
| Hugging Face dataset egress | risk | Include a small deterministic AG News sample for validation; make full dataset download optional |
| Embedding provider mismatch | risk | List active Llama Stack models and capture embedding dimension before vector store creation |
| Dutch publication ingestion | deferred | Implement after AG News-compatible reference path passes |
| RAGAS / evaluation | deferred | Keep for a later evaluation-focused stage |
| Docling/KFP data preparation | planned phase | Add after AG News compatibility passes; use the official RHOAI data-preparation chapter and `opendatahub-io/data-processing/kubeflow-pipelines` examples |
| Guardrails and MCP | deferred | Keep for later safety and agentic stages |

## Review Needed

- Confirm whether the first user-visible surface should remain notebooks only
  or add a small Streamlit app after API validation passes.
- Validate the pgvector-backed hybrid path in a fresh environment before
  claiming the stage complete.

## Retrospective And Skill Updates

- New skill added: `rhoai-enterprise-rag`.
- The skill captures the Red Hat article, linked AG News repository, official
  Llama Stack source hierarchy, GitOps translation rules, and validation gates.
