# Stage 230 KFP Data Preparation

Stage 230 uses this DSPA/KFP automation to process the committed RHOAI 3.4
product PDF corpus from the Stage 230 S3 bucket and produce reviewed JSONL
chunks for the same Files API / Vector Stores API ingestion path used by the
workbench.

## Source Alignment

- Official product authority: [RHOAI 3.4 Prepare your data for AI consumption](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/customize_models_for_gen_ai_and_agentic_ai_applications/prepare-your-data-for-ai-consumption_custom-models)
- Official pipeline authority: [RHOAI 3.4 Working with AI pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_ai_pipelines/index)
- Docling KFP reference: [opendatahub-io/data-processing stable branch](https://github.com/opendatahub-io/data-processing/tree/stable/kubeflow-pipelines)

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

Useful development options:

```bash
./stage-230-private-data-rag/run-rhoai-docs-pipeline.sh \
  --max-documents=1 \
  --output-s3-key=processed/rhoai-product-docs/rhoai-3.4-product-docs-docling-kfp-smoke.jsonl
```

The pipeline adapts the `docling-standard` pattern for ordinary text-native
PDFs. It disables OCR by default, enables table structure extraction, writes
converted Markdown and Docling JSON artifacts under
`processed/rhoai-product-docs/docling-artifacts/`, and writes the JSONL RAG
chunk contract to:

```text
processed/rhoai-product-docs/rhoai-3.4-product-docs-docling-kfp-chunks.jsonl
```

The Docling component image is an explicit KFP runtime dependency, not an
operator-managed operand. The currently selected image is a documented demo
exception until replaced by a reviewed Red Hat image or custom image.

Downstream RAG validation reads this full JSONL output. Normal redeploy
validation indexes a bounded per-topic subset for the selected smoke questions
so that the gate remains fast and repeatable. Use the smoke helper's
`--full-corpus` flag only when intentionally validating full-corpus indexing.
