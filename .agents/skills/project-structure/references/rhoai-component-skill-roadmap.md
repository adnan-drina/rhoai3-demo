# RHOAI Platform Skill Roadmap

This roadmap identifies component skills to build from the official Red Hat
OpenShift AI documentation for the active baseline in
`docs/PLATFORM_BASELINE.md`. Official docs are authoritative; Red Hat articles
and `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` provide narrative framing
and concrete examples only after official behavior is verified.

## Official Documentation Map

Current baseline index; update this when `docs/PLATFORM_BASELINE.md` changes:
https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/

| RHOAI area | Official docs category | Skill status |
|----------------|------------------------|--------------|
| Release posture and support tiers | What's New, supported APIs | Missing: `rhoai-release-and-support-posture` |
| Platform planning, validated models, hardware | Plan | Missing: `rhoai-platform-planning` |
| Operator installation and DSCI/DSC configuration | Install, Administer | Missing: `rhoai-installation-and-operators` |
| User access, dashboard, storage, telemetry | Administer | Missing: `rhoai-access-dashboard-storage` |
| Projects, workbenches, IDE images, connected apps | Develop | Missing: `rhoai-projects-workbenches` |
| Data science pipelines and KFP | Develop | Partly covered by `rhoai-kfp-pipeline-authoring`; missing broader `rhoai-pipelines` |
| MLflow | Develop | Missing: `rhoai-mlflow` |
| Model registry and model catalog | Administer, Develop | Missing: `rhoai-model-registry-catalog` |
| KServe RawDeployment and serving runtimes | Deploy | Missing: `rhoai-model-serving-kserve` |
| Models-as-a-Service governance | Deploy | Missing: `rhoai-maas-governance` |
| Distributed inference with llm-d | Deploy | Missing: `rhoai-distributed-inference-llmd` |
| Llama Stack and RAG | Administer, Develop | Partly covered by `rhoai-chatbot-customization`; missing: `rhoai-llamastack-rag` |
| Gen AI Playground and MCP connectors | Develop | Missing: `rhoai-genai-playground-mcp` |
| Model customization and training | Train | Missing: `rhoai-model-customization-training` |
| EvalHub, LM-Eval, RAGAS, external providers | Evaluate | Partly covered by `rhoai-model-evaluation`; missing: `rhoai-evaluation` |
| Guardrails and AI safety | Maintain Safety | Missing: `rhoai-guardrails-safety` |
| TrustyAI monitoring, bias, drift, model metrics | Monitor | Missing: `rhoai-monitoring-trustyai` |
| Feature Store | Administer | Optional backlog: `rhoai-feature-store` |
| AutoRAG | Develop | Optional backlog: `rhoai-autorag` |
| AutoML | Develop | Optional backlog: `rhoai-automl` |
| Kubeflow Spark Operator | Develop | Optional backlog: `rhoai-spark-operator` |

## Skill Build Standard

Each `rhoai-*` skill should include:

- official docs URLs and baseline metadata that points to
  `docs/PLATFORM_BASELINE.md`
- exact product versions only in `docs/PLATFORM_BASELINE.md` or
  version-specific reference notes
- supported/TP/developer-preview posture when relevant
- required CRDs and verification commands such as `oc explain`
- Red Hat recommended configuration patterns
- explicit "do not invent fields" guidance
- demo repo examples only after they are tied back to official docs
- `rh-brain` search hints for Red Hat articles or code examples

## Recommended First Component Skills

Build these first because they map directly to implemented demo steps:

1. `rhoai-installation-and-operators` for steps 01-02.
2. `rhoai-model-serving-kserve` for local model serving and vLLM.
3. `rhoai-maas-governance` for MaaS subscriptions, model refs, auth policy, and external models.
4. `rhoai-llamastack-rag` for Llama Stack, RAG, vector stores, and Responses/OpenAI-compatible APIs.
5. `rhoai-evaluation` for EvalHub, LM-Eval, RAGAS, and MLflow-backed evidence.
6. `rhoai-guardrails-safety` for NeMo guardrails and safety validation.
7. `rhoai-genai-playground-mcp` for Gen AI Playground assets and MCP connector posture.
8. Broaden `rhoai-kfp-pipeline-authoring` or add `rhoai-pipelines-mlflow` for full AI Pipelines and MLflow experiment tracking.
