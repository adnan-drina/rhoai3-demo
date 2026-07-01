# Enterprise RAG Workbench

Open the `enterprise-rag` project in Red Hat OpenShift AI and start the
`Enterprise RAG Workbench`. The workbench startup creates a curated workspace
under `/opt/app-root/src` with two visible notebooks:

- `Ingestion_pipeline_ag_news.ipynb`
- `retrieval_pipeline_ag_news.ipynb`

Generated helper scripts, sample data, and dependencies are stored under the
hidden `/opt/app-root/src/.stage230` directory so the visible JupyterLab file
browser matches the Red Hat article-style notebook flow instead of exposing the
full `rhoai3-demo` implementation repository.

Run the acceptance flow from a workbench terminal if you need a CLI check:

```bash
cd /opt/app-root/src
python .stage230/scripts/agnews_rag_acceptance.py \
  --vector-store stage230-agnews-demo \
  --search-mode hybrid
```

The script validates AG News ingestion, LLM-driven metadata extraction, hybrid
retrieval, Qwen3 reranking, and final Nemotron answer generation. It is a real
acceptance gate, not a demo-only notebook helper: it fails if hybrid metadata
filtering, reranking, or grounded answer generation is broken.
