# Source Capture

## Official Product Source

| Field | Value |
|-------|-------|
| Product baseline | `docs/PLATFORM_BASELINE.md` |
| Document title | Working with AutoRAG |
| Guide URL | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_autorag/index |
| Documentation category | Develop / Working with AutoRAG |
| Retrieved date | 2026-06-10 |
| Sections used | Preface; 1 AutoRAG overview; 1.1 AutoRAG workflow; 1.2 AutoRAG terminology; 1.3 Technology Preview limitations; 1.4 Viewing externally created runs; 2 Prepare test data for AutoRAG; 3 Create an AutoRAG optimization run; 4 Evaluate AutoRAG results; 5 Run the RAG pattern; 6 AutoRAG evaluation metrics; 6.1 Metric combinations; 7 AutoRAG configuration parameters; 7.1 User-configurable parameters; 7.2 Search space defaults; 7.3 Recommended embedding models |

## Related Official Sources

| Source | Role |
|--------|------|
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_llama_stack/index | Llama Stack provider, vector database, model, connection, RAG, and API context |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/experimenting_with_models_in_the_gen_ai_playground/index | Gen AI studio feature context and adjacent playground RAG boundary |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_ai_pipelines/index | Imported pipeline naming and underlying run lifecycle context |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_data_in_an_s3-compatible_object_store/index | S3-compatible object storage and workbench data access context |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_on_projects | Project, workbench, and connection lifecycle context |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_in_your_data_science_ide/index | Generated indexing and inference notebook execution in a workbench |
| https://access.redhat.com/support/offerings/techpreview | Technology Preview support scope |

## Supporting Project Sources

| Source | Role |
|--------|------|
| `docs/PLATFORM_BASELINE.md` | Active RHOAI/OCP baseline and source hierarchy |
| `AGENTS.md` | OpenShift safety guard and GitOps operating constraints |
| `.agents/skills/rhoai-llama-stack/SKILL.md` | Llama Stack, model, provider, and vector database boundary |
| `.agents/skills/rhoai-gen-ai-playground/SKILL.md` | Gen AI studio playground boundary |
| `.agents/skills/rhoai-ai-pipelines/SKILL.md` | Pipeline server and run lifecycle boundary |
| `.agents/skills/rhoai-s3-object-storage-data/SKILL.md` | S3-compatible data boundary |
| `.agents/skills/rhoai-project-workflows/SKILL.md` | Project, workbench, and connection boundary |
| `.agents/skills/rhoai-data-science-ide-workflows/SKILL.md` | Generated notebook execution boundary |
| `.agents/skills/rhoai-model-evaluation/SKILL.md` | Formal evaluation evidence boundary outside AutoRAG |

## Source Boundaries

- Product authority: the official Red Hat OpenShift AI 3.4 Working with
  AutoRAG guide above.
- The guide defines dashboard workflows for AutoRAG optimization runs,
  evaluation data preparation, leaderboard review, generated indexing and
  inference notebooks, and metric interpretation.
- AutoRAG is Technology Preview in the captured guide.
- The guide does not replace the Llama Stack guide, Gen AI playground guide,
  AI Pipelines guide, S3 object storage guide, or workbench IDE guide.
- Verification: AutoRAG page run status, completed leaderboard, pattern
  details, generated notebook download, workbench notebook execution, grounded
  responses, and metric interpretation.

## Unresolved Or Environment-Specific Items

- Active demo document corpus and source ownership.
  Verification: define in the future demo step README and confirm documents
  are English and in supported formats before creating runs.
- Active ground-truth evaluation data set.
  Verification: review JSON validity, question coverage, expected answers, and
  document ID mapping before the optimization run.
- Active Llama Stack distribution, foundation models, embedding models, and
  remote Milvus registration.
  Verification: use `rhoai-llama-stack` before running AutoRAG.
- Active S3-compatible bucket layout.
  Verification: confirm multi-document S3 inputs live in a single folder when
  the run selects multiple documents.
- Imported AutoRAG pipeline version string.
  Verification: align imported pipeline version names with the active RHOAI
  product version in `docs/PLATFORM_BASELINE.md`.
