# Scenario Documents

Place PDF files in the appropriate scenario subdirectory before running `deploy.sh`.

## Expected Structure

```
scenario-docs/
├── scenario2-acme/        # ACME Corporate lithography docs (~6 PDFs)
│   └── *.pdf
├── scenario3-eu-ai-act/   # EU AI Act official documents (~3 PDFs)
│   └── *.pdf
└── whoami/                # Personal CV / identity doc (1 PDF)
    └── *.pdf
```

## Sourcing Documents

Copy the PDF files from the previous `private-ai-demo` repository:

```bash
git clone https://github.com/adnan-drina/private-ai-demo.git /tmp/private-ai-demo

cp /tmp/private-ai-demo/stages/stage2-model-alignment/scenario-docs/scenario2-acme/*.pdf \
   scenario-docs/scenario2-acme/

cp /tmp/private-ai-demo/stages/stage2-model-alignment/scenario-docs/scenario3-eu-ai-act/*.pdf \
   scenario-docs/scenario3-eu-ai-act/
```

The `deploy.sh` script will automatically upload any PDFs found in these directories
to the `rag-documents` MinIO bucket.
