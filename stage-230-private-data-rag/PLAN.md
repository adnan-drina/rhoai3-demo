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
  - demo-local Milvus endpoint used through the documented remote Milvus
    provider
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

The previous Stage 230 whoami/Docling/DSPA/pgvector implementation is being
retired as active design. It can be used as historical reference only. The new
baseline starts by reproducing the Red Hat Developer AG News enterprise RAG
pattern, replacing the article's Llama generation model with our governed
Nemotron model.

## Layered Architecture Analysis

| Layer | Stage 230 design | Rationale |
|-------|------------------|-----------|
| Infrastructure | Reuse Stage 120 GPU capacity for existing Nemotron; deploy storage-backed PostgreSQL and a demo-local Milvus endpoint in the RAG project | Keeps scarce GPU capacity governed while providing RAG state in a dedicated project |
| Platform | RHOAI Llama Stack / OGX, MaaS, KServe/vLLM only if reranker is deployed | Aligns with RHOAI 3.4 Llama Stack documentation and Stage 220 governance |
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
- reranker scores when the reranker is enabled
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
| Vector store | Remote Milvus provider with a demo-local Milvus service | Official RHOAI 3.4 Llama Stack docs document remote Milvus and the Red Hat article uses Milvus; the Milvus deployment itself is a demo exception |
| Metadata store | PostgreSQL for Llama Stack metadata | Required by official Llama Stack guidance; not the same decision as vector storage |
| Embeddings | Start with the article/repo embedding path if compatible; otherwise select and document a supported provider and dimension | Embedding dimensions must be explicit and validated before indexing |
| Reranker | Use the article's Qwen3 reranker pattern only after artifact provenance and runtime fields are reviewed | Reranker improves precision but introduces non-Red Hat artifact posture |
| Deployment style | Re-author reference Helm resources into Kustomize/GitOps | This repo uses Argo CD and local curation, not direct Helm installs |
| Ingestion interface | Notebook plus deterministic validation job/script | Keeps the Red Hat demo feel while allowing repeatable redeploy validation |
| Data preparation automation | Add Docling and KFP after AG News compatibility passes | RHOAI 3.4 documents Docling for unstructured data and KFP for automating multi-step Docling processing |
| Old implementation | Remove active whoami/Docling/DSPA/pgvector resources during implementation | Avoids mixed architectures and stale claims |

## Source Capture

| Purpose | Source | Skill | Notes |
|---------|--------|-------|-------|
| Concept/value | [Build an enterprise RAG system with OGX](https://developers.redhat.com/articles/2026/05/26/build-enterprise-rag-system-ogx) | `project-documentation-authoring`, `rhoai-enterprise-rag` | Explains metadata filtering, hybrid search, reranking, and enterprise RAG value |
| Product config | [RHOAI 3.4: Working with Llama Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_llama_stack/index) | `rhoai-llama-stack`, `rhoai-enterprise-rag` | Product authority for Llama Stack, vector stores, ingestion, query, PostgreSQL metadata, and Milvus |
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
  - Milvus token, PostgreSQL password, MaaS token, and optional Hugging Face
    token must be generated or loaded locally and not committed

## Manifest Inventory

Planned first implementation inventory:

| Path | Kind | Source authority | Validation |
|------|------|------------------|------------|
| `gitops/stage-230-private-data-rag/project/` | Namespace and RBAC | RHOAI project workflow docs and repo standards | `oc get project`, RHOAI dashboard visibility |
| `gitops/stage-230-private-data-rag/postgresql/` | StatefulSet and Service; Secret generated by deploy script | RHOAI Llama Stack PostgreSQL metadata guidance | Pod readiness and Llama Stack metadata connection |
| `gitops/stage-230-private-data-rag/milvus/` | PVC, etcd Deployment, Milvus Deployment, Services; Secret generated by deploy script | RHOAI remote Milvus provider guidance plus curated reference repo | gRPC endpoint reachable and vector store registration succeeds |
| `gitops/stage-230-private-data-rag/llamastack/` | `LlamaStackDistribution` using official `rh-dev` distribution | RHOAI Llama Stack docs and installed CRD schema | Server-side dry run, `LlamaStackDistribution` Ready, and `/v1/models` works |
| `stage-230-private-data-rag/data/agnews-sample/` | Small deterministic AG News-compatible sample | Red Hat article-linked repo pattern, locally adapted | Stable ingestion smoke input without external dataset dependency |
| `stage-230-private-data-rag/scripts/` | AG News smoke helper | RHOAI Llama Stack APIs and Red Hat article-linked notebook pattern | Python compile now; full ingestion/search run after runtime is deployed |

Deferred implementation inventory:

| Path | Kind | Source authority | Validation |
|------|------|------------------|------------|
| `gitops/stage-230-private-data-rag/reranker/` | Optional model serving resources | RHOAI model deployment docs plus reviewed artifact provenance | Rerank endpoint responds and model appears in Llama Stack |
| `stage-230-private-data-rag/notebooks/` | AG News notebooks and later Docling data-preparation notebooks | Red Hat article-linked repo plus RHOAI data-processing examples, locally adapted | Workbench execution and scripted smoke validation |
| `stage-230-private-data-rag/pipelines/` | Later Docling KFP pipeline definitions adapted from `opendatahub-io/data-processing/kubeflow-pipelines` | RHOAI data-preparation chapter and `opendatahub-io/data-processing` examples | Branch choice recorded, compile check, imported pipeline, successful run, artifact review |

## Script Plan

### `deploy.sh`

- Load `.env` and run the OpenShift safety guard.
- Apply the Stage 230 Argo CD Application first.
- Wait for the `enterprise-rag` namespace.
- Create or update non-committed Secrets from local environment values,
  generated database credentials, generated Milvus credentials, and the
  Stage 220 MaaS API-key flow.
- Refresh the Argo CD Application after Secret creation.
- Do not run ingestion until runtime readiness is confirmed.

### `validate.sh`

- Confirm Stage 230 Argo CD sync/health.
- Confirm `enterprise-rag` project and RBAC.
- Confirm environment-local Secrets exist.
- Confirm PostgreSQL, etcd, and Milvus availability.
- Confirm Llama Stack readiness and model list.
- Confirm the AG News smoke-test helper compiles.
- Next gate: run AG News ingestion for the deterministic sample, resolve the
  vector store by metadata, run category-targeted hybrid search, and generate a
  final Nemotron answer using retrieved context.
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
| Milvus and etcd image/lifecycle posture | risk | Recorded as a demo exception for the first rebuild; replace with a Red Hat-advised Milvus service or managed vector database before production-positioned delivery |
| Reranker artifact provenance | risk | Treat as optional until model artifact and serving runtime are validated |
| Hugging Face dataset egress | risk | Include a small deterministic AG News sample for validation; make full dataset download optional |
| Embedding provider mismatch | risk | List active Llama Stack models and capture embedding dimension before vector store creation |
| Dutch publication ingestion | deferred | Implement after AG News-compatible reference path passes |
| RAGAS / evaluation | deferred | Keep for a later evaluation-focused stage |
| Docling/KFP data preparation | planned phase | Add after AG News compatibility passes; use the official RHOAI data-preparation chapter and `opendatahub-io/data-processing/kubeflow-pipelines` examples |
| Guardrails and MCP | deferred | Keep for later safety and agentic stages |

## Review Needed

- Confirm whether the first user-visible surface should be notebooks only or a
  small Streamlit app after API validation passes.
- Confirm whether the reranker is mandatory for the first live rebuild or can
  be introduced after base metadata/hybrid retrieval is working.

## Retrospective And Skill Updates

- New skill added: `rhoai-enterprise-rag`.
- The skill captures the Red Hat article, linked AG News repository, official
  Llama Stack source hierarchy, GitOps translation rules, and validation gates.
