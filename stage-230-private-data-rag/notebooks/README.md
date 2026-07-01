# Enterprise RAG Workbench

Open the `enterprise-rag` project in Red Hat OpenShift AI and start the
`Enterprise RAG Workbench`. The workbench startup creates a curated JupyterLab
workspace under `/opt/app-root/src/workspace` with two visible notebooks:

- `Ingestion_pipeline_ag_news.ipynb`
- `retrieval_pipeline_ag_news.ipynb`

Generated helper scripts, sample data, and dependencies are stored under the
hidden `/opt/app-root/src/workspace/.stage230` directory so the visible
JupyterLab file browser matches the Red Hat article-style notebook flow
instead of exposing the full `rhoai3-demo` implementation repository.

Run the same working flow from a workbench terminal if you need a CLI check:

```bash
cd /opt/app-root/src/workspace
python .stage230/scripts/agnews_rag_acceptance.py \
  --vector-store stage230-agnews-demo \
  --search-mode vector
```

The notebook flow validates AG News ingestion, LLM-driven metadata extraction,
filtered retrieval, Qwen3 reranking, and final Nemotron answer generation. The
stricter Stage 230 acceptance gate still uses `--search-mode hybrid` and must
continue to fail until remote Milvus hybrid search enforces metadata filters
through a supported RHOAI/Llama Stack path.
