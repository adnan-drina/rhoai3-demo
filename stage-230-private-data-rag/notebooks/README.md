# Enterprise RAG Workbench

Open the `enterprise-rag` project in Red Hat OpenShift AI and start the
`Enterprise RAG Workbench`. The workbench startup creates a curated JupyterLab
workspace under `/opt/app-root/src/workspace` with three visible notebooks:

- `Docling_data_preparation_rhoai_docs.ipynb` -- PDF conversion, chunking,
  metadata enrichment with Docling
- `Ingestion_pipeline_rhoai_docs.ipynb` -- vector store creation, Files API
  upload, metadata attachment
- `Retrieval_pipeline_rhoai_docs.ipynb` -- metadata extraction, hybrid search,
  reranking, grounded answer generation

The notebooks read official RHOAI product documentation PDFs from S3 (uploaded
during deployment), process them with Docling, and use the Llama Stack Files
and Vector Stores APIs for ingestion and retrieval. Each step maps to a KFP
pipeline component.

Generated helper scripts, sample data, and dependencies are stored under the
hidden `/opt/app-root/src/workspace/.stage230` directory so the visible
JupyterLab file browser matches the Red Hat article-style notebook flow
instead of exposing the full `rhoai3-demo` implementation repository.

The RHOAI product-document flow reads official Red Hat PDFs committed under
the stage data folder and mirrored to the Stage 230 S3 bucket during
deployment. It indexes focused chunks about Llama Stack RAG, AutoRAG, RAGAS,
EvalHub, guardrails, AI Pipelines, and Docling. It is an audience explainer
corpus, not a claim that every referenced product capability is implemented in
Stage 230.

The Stage 230 acceptance gate uses `--search-mode hybrid` and must fail if
metadata filters are ignored, reranker scores are missing, or the final
Nemotron answer is not grounded in retrieved context. The active implementation
uses pgvector because filtered hybrid search is required for the demo story.

## AutoRAG pattern handoff

After an AutoRAG optimization run completes (see the stage README's AutoRAG
flow), fetch the winning pattern's artifacts into this workspace from a
workbench terminal:

```bash
cd /opt/app-root/src/workspace
python .stage230/scripts/fetch_autorag_pattern.py
```

This ranks the latest run's patterns (faithfulness by default) and downloads
`pattern.json`, `evaluation_results.json`, and the generated `indexing.ipynb`
and `inference.ipynb` into `workspace/autorag/<Pattern>/`. The generated
notebooks run against the same Llama Stack service as the hand-built flow, so
the demo can compare the manual pipeline with the measured-best configuration
side by side.
