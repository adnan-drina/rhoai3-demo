# Stage 230 KFP End-to-End RAG Pipeline

Stage 230 uses this DSPA/KFP automation to process the committed RHOAI 3.4
product PDF corpus from S3, enrich the chunks with RHOAI product-document
metadata, and ingest them into a Llama Stack vector store -- producing a
query-ready RAG corpus in a single pipeline run.

## Source Alignment

- Official product authority: [RHOAI 3.4 Prepare your data for AI consumption](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/customize_models_for_gen_ai_and_agentic_ai_applications/prepare-your-data-for-ai-consumption_custom-models)
- Official pipeline authority: [RHOAI 3.4 Working with AI pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_ai_pipelines/index)
- Docling KFP reference: [opendatahub-io/data-processing `main` branch](https://github.com/opendatahub-io/data-processing/tree/main/kubeflow-pipelines)

The official RHOAI documentation points to the `stable` branch, but this stage
intentionally follows the newer `main/kubeflow-pipelines` implementation
because it exposes the current modular standard/VLM pipeline layout,
`ParallelFor` split pattern, Secret-mounted S3 input, and HybridChunker output
that we want to demonstrate.

## Active Implementation

The active pipeline targets `data/rhoai-product-docs/` and keeps source PDFs,
prepared chunks, and generated pipeline output aligned with the committed
manifest:

```text
data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json
data/rhoai-product-docs/source/*.pdf
data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl
```

The GitOps-managed `dspa-enterprise-rag` pipeline server and generated
`data-processing-docling-pipeline` Secret provide the runtime. The runner
compiles `rhoai_product_docs_docling_pipeline.py`, creates a reviewed
Pipeline/PipelineVersion in the DSPA namespace, starts a run, and records
evidence in `ConfigMap/stage230-rhoai-docs-pipeline-evidence`.

```bash
./stage-230-private-data-rag/run-rhoai-docs-pipeline.sh
```

In the OpenShift AI dashboard, select the `Enterprise RAG` project and open
`Pipelines`. The pipeline display name is `RHOAI Product Docs Docling
Pipeline`. Docling does not appear in the project `Deployments` tab because
this stage uses Docling as a KFP data-preparation component, not as a KServe
model-serving endpoint.

Useful development options:

```bash
./stage-230-private-data-rag/run-rhoai-docs-pipeline.sh \
  --max-documents=1 \
  --output-s3-key=processed/rhoai-product-docs/rhoai-3.4-product-docs-docling-kfp-smoke.jsonl
```

The pipeline adapts the `docling-standard` pattern for ordinary text-native
PDFs and extends it with Llama Stack vector store ingestion. Source selection
is handled at compile time via `--max-documents`, producing a clean six-node
top-level DAG:

```text
import-pdfs
  -> create-pdf-splits
  -> download-docling-models
  -> process-pdf-splits (ParallelFor):
       docling-convert-standard -> docling-chunk-and-upload
  -> enrich-and-publish-rhoai-chunks
  -> ingest-to-vector-store
```

`docling-convert-standard` writes converted Markdown and Docling JSON artifacts
as KFP artifacts. `docling-chunk-and-upload` combines Docling HybridChunker
chunking with per-split S3 artifact publishing in a single step, writing
converted Markdown, Docling JSON, and HybridChunker JSONL under deterministic
S3 keys. `enrich-and-publish-rhoai-chunks` reads those S3 artifacts, maps them
to the RHOAI product-document metadata contract, and writes the combined JSONL
to S3. `ingest-to-vector-store` reads the enriched JSONL, creates a pgvector-
backed Llama Stack vector store, uploads each chunk via the Files API with
per-chunk metadata attributes, verifies ingestion file counts, and runs a
search smoke test.

The final JSONL is written to:

```text
processed/rhoai-product-docs/rhoai-3.4-product-docs-docling-kfp-chunks.jsonl
```

The Docling component image is an explicit KFP runtime dependency, not an
operator-managed operand. The currently selected image is a documented demo
exception until replaced by a reviewed Red Hat image or custom image.

The chunk-and-upload step inside the ParallelFor loop intentionally mounts the
GitOps-owned deterministic `data-processing-docling-pipeline` Secret by literal
name. In the active RHOAI 3.4 KFP runtime, Kubernetes Secret mounts on tasks
nested inside `dsl.ParallelFor` are resolved from the parent DAG and cannot
safely use the pipeline-level `pipeline_s3_secret_name` parameter.
