# Scenario Documents

Place PDF files in the appropriate scenario subdirectory before running `deploy.sh`.

## Expected Structure

```
scenario-docs/
├── acme/         # ACME Corporate lithography docs (~8 PDFs)
│   └── *.pdf
└── whoami/       # Personal CV / identity doc (1 PDF)
    └── *.pdf
```

## Sourcing Documents

Copy the PDF files from the previous `private-ai-demo` repository:

```bash
git clone https://github.com/adnan-drina/private-ai-demo.git /tmp/private-ai-demo

cp /tmp/private-ai-demo/stages/stage2-model-alignment/scenario-docs/scenario2-acme/*.pdf \
   scenario-docs/acme/
# Source uses old naming (scenario2-acme) — our directory is just 'acme'
```

The `deploy.sh` script will automatically upload any PDFs found in these directories
to the `rag-documents` MinIO bucket.
