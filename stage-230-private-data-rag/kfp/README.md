# Stage 230 KFP Data Preparation

This directory contains the first Stage 230 KFP source for Dutch government
publication data preparation.

## Source Alignment

- Official product authority: [RHOAI 3.4 Prepare your data for AI consumption](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/customize_models_for_gen_ai_and_agentic_ai_applications/prepare-your-data-for-ai-consumption_custom-models)
- RAG implementation pattern: [Build an enterprise RAG system with OGX](https://developers.redhat.com/articles/2026/05/26/build-enterprise-rag-system-ogx)
- AG News reference implementation: [abdelhamidfg/agnews-rag-demo](https://github.com/abdelhamidfg/agnews-rag-demo)
- Docling KFP reference: [opendatahub-io/data-processing stable branch](https://github.com/opendatahub-io/data-processing/tree/stable/kubeflow-pipelines)

The first implementation adapts the `docling-standard` pattern for a single
public Staatsblad PDF. It does not use `docling-vlm` because the current
document is a normal text publication, not a scanned or image-heavy document.

## Files

| File | Purpose |
|------|---------|
| `dutch_publication_docling_pipeline.py` | KFP v2 pipeline definition for the single-document Docling preparation run |
| `components/dutch_docling_components.py` | Self-contained lightweight KFP component that converts the PDF with Docling and emits Stage 230 RAG chunk JSONL plus metrics |

## Compile

```bash
python stage-230-private-data-rag/kfp/dutch_publication_docling_pipeline.py \
  --output /tmp/stage-230-dutch-publication-docling.yaml
```

Compiled YAML is generated on demand and is not committed as reconciled GitOps
state yet. Pipeline server ownership, DSPA storage, and S3-backed corpus
processing will be added only after the single-document data-preparation
contract is validated.

## Runtime Notes

The component uses the same Docling runtime image reference as the reviewed
`opendatahub-io/data-processing` stable branch:
`quay.io/fabianofranz/docling-ubi9:2.54.0`. Treat this as a reviewed demo
runtime dependency, not an operator-managed Red Hat product operand.

For the larger corpus, the next design step is to add the official
`data-processing-docling-pipeline` Secret contract for S3 input:

- `S3_ENDPOINT_URL`
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`
- `S3_BUCKET`
- `S3_PREFIX`

Those values must be generated from the active project object-storage
connection or local environment. Do not commit them.
