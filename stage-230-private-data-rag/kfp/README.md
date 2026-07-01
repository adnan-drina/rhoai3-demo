# Stage 230 KFP Data Preparation

Stage 230 now focuses on RHOAI product-document RAG. This directory is reserved
for the DSPA/KFP automation that will process the committed RHOAI 3.4 product
PDF corpus from the Stage 230 S3 bucket and produce reviewed JSONL chunks for
the same Files API / Vector Stores API ingestion path used by the workbench.

## Source Alignment

- Official product authority: [RHOAI 3.4 Prepare your data for AI consumption](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/customize_models_for_gen_ai_and_agentic_ai_applications/prepare-your-data-for-ai-consumption_custom-models)
- Official pipeline authority: [RHOAI 3.4 Working with AI pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_ai_pipelines/index)
- Docling KFP reference: [opendatahub-io/data-processing stable branch](https://github.com/opendatahub-io/data-processing/tree/stable/kubeflow-pipelines)

## Active Status

The next KFP implementation must target `data/rhoai-product-docs/` and must
keep source PDFs and prepared chunks aligned with the committed manifest:

```text
data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json
data/rhoai-product-docs/source/*.pdf
data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl
```

The GitOps-managed `dspa-enterprise-rag` pipeline server and
`data-processing-docling-pipeline` Secret remain the intended automation
foundation.
