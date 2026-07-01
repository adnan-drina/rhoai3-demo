# Enterprise RAG Workbench

Open the `enterprise-rag` project in Red Hat OpenShift AI and start the
`Enterprise RAG Workbench`. The workbench startup creates a curated JupyterLab
workspace under `/opt/app-root/src/workspace` with three visible notebooks:

- `Ingestion_pipeline_ag_news.ipynb`
- `retrieval_pipeline_ag_news.ipynb`
- `dutch_publication_rag_smoke.ipynb`

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

Run the Dutch government publication smoke flow from a workbench terminal:

```bash
cd /opt/app-root/src/workspace
python .stage230/scripts/dutch_publication_rag_smoke.py \
  --reset \
  --vector-store stage230-dutch-woo-demo \
  --search-mode hybrid
```

The notebook flow validates AG News ingestion, LLM-driven metadata extraction,
filtered retrieval, Qwen3 reranking, and final Nemotron answer generation. The
Stage 230 acceptance gate uses `--search-mode hybrid` and must fail if
metadata filters are ignored, reranker scores are missing, or the final
Nemotron answer is not grounded in retrieved context. The active implementation
uses pgvector because filtered hybrid search is required for the demo story.
