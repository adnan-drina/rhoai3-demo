# Enterprise RAG Workbench

Open the `enterprise-rag` project in Red Hat OpenShift AI and start the
`Enterprise RAG Workbench`. The workbench startup creates a curated JupyterLab
workspace under `/opt/app-root/src/workspace` with three visible notebooks:

- `Ingestion_pipeline_ag_news.ipynb`
- `retrieval_pipeline_ag_news.ipynb`
- `rhoai_product_docs_rag_smoke.ipynb`

Generated helper scripts, sample data, and dependencies are stored under the
hidden `/opt/app-root/src/workspace/.stage230` directory so the visible
JupyterLab file browser matches the Red Hat article-style notebook flow
instead of exposing the full `rhoai3-demo` implementation repository.

Run the same working flow from a workbench terminal if you need a CLI check:

```bash
cd /opt/app-root/src/workspace
python .stage230/scripts/agnews_rag_acceptance.py \
  --vector-store stage230-agnews-demo \
  --search-mode hybrid
```

Prepare and query the focused RHOAI 3.4 product-document explainer corpus:

```bash
cd /opt/app-root/src/workspace
python .stage230/scripts/rhoai_product_docs_prepare.py \
  --manifest .stage230/data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json \
  --source-dir .stage230/data/rhoai-product-docs/source \
  --output .stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl
python .stage230/scripts/rhoai_product_docs_rag_smoke.py \
  --reset \
  --manifest .stage230/data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json \
  --sample .stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl \
  --vector-store stage230-rhoai-34-product-docs \
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
