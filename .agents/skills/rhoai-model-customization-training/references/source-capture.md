# Source Capture

## Official Product Source

| Field | Value |
|-------|-------|
| Product baseline | `docs/PLATFORM_BASELINE.md` |
| Document title | Customize Models for Gen AI and Agentic AI Applications |
| Guide URL | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/customize_models_for_gen_ai_and_agentic_ai_applications/index |
| Documentation category | Train / Customize Models for Gen AI and Agentic AI Applications |
| Retrieved date | 2026-06-10 |
| Sections used | Preface; 1 Overview of the model customization workflow; 2 Set up your working environment; 2.1 About the Red Hat Python index; 2.2 Mirror the Python index for your disconnected environment; 2.3 Install packages and JupyterLab; 2.4 Import example notebooks; 3 Prepare your data for AI consumption; 3.1 Process data by using Docling; 3.2 Explore data processing examples; 3.3 Automate data processing steps by building AI pipelines; 3.4 Explore Kubeflow Pipeline examples; 4 Generate synthetic data; 4.1 SDG Hub examples; 4.2 Performance benchmarks for knowledge tuning; 4.3 KFP pipeline for SDG; 5 Train the model by using prepared data; 5.1 Training Hub examples; 5.2 Training Hub algorithm and model support matrix; 5.3 Estimate memory usage; 5.4 OSFT/SFT/LoRA comparison; 5.5 Training Hub in OpenShift AI; 5.6 MLflow tracking; 5.7 Kubeflow Trainer distributed fine-tuning; 6 Inference-time scaling; 7 End-to-end model customization workflow; 8 Support philosophy |

## Related Official Sources

| Source | Role |
|--------|------|
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_in_your_data_science_ide/index | JupyterLab and workbench IDE workflow context |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_on_projects | Project, workbench, connection, and storage lifecycle context |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_ai_pipelines/index | AI Pipelines product lifecycle, imports, runs, schedules, and logs |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_distributed_workloads/index | Distributed workload and Kubeflow Trainer user workflow context |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_mlflow/index | MLflow platform and SDK tracking context |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/configuring_your_model-serving_platform | Model serving and OpenAI-compatible endpoint context |
| https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_model_registries/index | Registering customized models and deployment handoff context |

## Supporting Project Sources

| Source | Role |
|--------|------|
| `docs/PLATFORM_BASELINE.md` | Active RHOAI/OCP baseline and source hierarchy |
| `AGENTS.md` | OpenShift safety guard and GitOps operating constraints |
| `.agents/skills/rhoai-project-workflows/SKILL.md` | Project and workbench lifecycle boundary |
| `.agents/skills/rhoai-data-science-ide-workflows/SKILL.md` | JupyterLab and notebook workflow boundary |
| `.agents/skills/rhoai-ai-pipelines/SKILL.md` | AI Pipelines product boundary |
| `.agents/skills/rhoai-kfp-pipeline-authoring/SKILL.md` | Repo KFP implementation boundary |
| `.agents/skills/rhoai-distributed-workload-workflows/SKILL.md` | Distributed fine-tuning workflow boundary |
| `.agents/skills/rhoai-mlflow/SKILL.md` | MLflow tracking boundary |
| `.agents/skills/rhoai-model-serving-platform/SKILL.md` | Serving endpoint boundary |
| `.agents/skills/rhoai-model-registry-workflows/SKILL.md` | Register/deploy trained model boundary |
| `.agents/skills/rhoai-model-evaluation/SKILL.md` | Formal evaluation evidence boundary |

## Source Boundaries

- Product authority: the official Red Hat OpenShift AI 3.4 Customize Models
  for Gen AI and Agentic AI Applications guide above.
- The guide defines Red Hat's model customization workflow, package supply
  chain posture, example repositories, Docling, SDG Hub, Training Hub,
  Training Hub MLflow tracking, Kubeflow Trainer handoff, inference-time
  scaling, and support philosophy.
- The guide does not replace narrower product guides for projects,
  workbenches, AI Pipelines, distributed workloads, MLflow platform setup,
  model serving, model registry, or formal evaluation.
- Verification: correct Red Hat Python index usage, workbench image selection,
  package installation source, example repository branch, data processing
  output, Training Hub run output, MLflow logging, distributed job status, ITS
  response behavior, and support posture language.

## Unresolved Or Environment-Specific Items

- Active demo base model for fine-tuning.
  Verification: select based on active model-serving and accelerator plan.
- Active GPU profile for Training Hub examples.
  Verification: use the memory estimator and `rhoai-nvidia-gpu-accelerators`
  once active GitOps is rebuilt.
- Whether the demo will include actual fine-tuning or only describe model
  customization as a future extension.
  Verification: decide during step design.
- Active disconnected package mirror target.
  Verification: define only if the fresh environment is disconnected.
- Active MLflow tracking server and artifact storage.
  Verification: use `rhoai-mlflow` before promising training evidence.
