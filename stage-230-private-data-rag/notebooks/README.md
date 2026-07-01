# Enterprise RAG Workbench

Open the `enterprise-rag` project in Red Hat OpenShift AI and start the
`Enterprise RAG Workbench`. The workbench clones this repository into
`/opt/app-root/src/rhoai3-demo` and installs the notebook dependencies from
`stage-230-private-data-rag/notebooks/requirements.txt`.

Run the acceptance flow from a workbench terminal:

```bash
cd /opt/app-root/src/rhoai3-demo/stage-230-private-data-rag
python scripts/agnews_rag_acceptance.py --reset
```

The script validates AG News ingestion, LLM-driven metadata extraction, hybrid
retrieval, Qwen3 reranking, and final Nemotron answer generation. It is a real
acceptance gate, not a demo-only notebook helper: it fails if hybrid metadata
filtering, reranking, or grounded answer generation is broken.
