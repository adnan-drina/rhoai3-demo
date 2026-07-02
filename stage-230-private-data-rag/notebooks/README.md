# Enterprise RAG Workbench

Open the `enterprise-rag` project in Red Hat OpenShift AI and start the
`Enterprise RAG Workbench`. The workbench startup creates a curated JupyterLab
workspace under `/opt/app-root/src/workspace` with five visible notebooks:

**AG News reference** (from the Red Hat OGX blog post):

- `Ingestion_pipeline_ag_news.ipynb`
- `retrieval_pipeline_ag_news.ipynb`

**RHOAI product documentation** (main demo use case):

- `Docling_data_preparation_rhoai_docs.ipynb` -- PDF conversion, chunking,
  metadata enrichment with Docling
- `Ingestion_pipeline_rhoai_docs.ipynb` -- vector store creation, Files API
  upload, metadata attachment
- `Retrieval_pipeline_rhoai_docs.ipynb` -- metadata extraction, hybrid search,
  reranking, grounded answer generation

The RHOAI docs notebooks read source PDFs from S3 (uploaded during deployment),
process them with Docling, and follow the same Llama Stack API pattern as the
AG News notebooks. Each step maps to a future KFP pipeline component.

Generated helper scripts, sample data, and dependencies are stored under the
hidden `/opt/app-root/src/workspace/.stage230` directory so the visible
JupyterLab file browser matches the Red Hat article-style notebook flow
instead of exposing the full `rhoai3-demo` implementation repository.

Run the AG News acceptance flow from a workbench terminal if you need a CLI
check:

```bash
cd /opt/app-root/src/workspace
python .stage230/scripts/agnews_rag_acceptance.py \
  --vector-store stage230-agnews-demo \
  --search-mode hybrid
```

The RHOAI product-document flow reads official Red Hat PDFs committed under
the stage data folder and mirrored to the Stage 230 S3 bucket during
deployment. It indexes focused chunks about Llama Stack RAG, AutoRAG, RAGAS,
EvalHub, guardrails, AI Pipelines, and Docling. It is an audience explainer
corpus, not a claim that every referenced product capability is implemented in
Stage 230.

The notebook flow validates AG News ingestion, LLM-driven metadata extraction,
filtered retrieval, Qwen3 reranking, and final Nemotron answer generation. The
Stage 230 acceptance gate uses `--search-mode hybrid` and must fail if
metadata filters are ignored, reranker scores are missing, or the final
Nemotron answer is not grounded in retrieved context. The active implementation
uses pgvector because filtered hybrid search is required for the demo story.
