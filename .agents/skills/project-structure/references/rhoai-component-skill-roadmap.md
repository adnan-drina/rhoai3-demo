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
| Architecture, service layer, management layer, default projects | Install | Added: `rhoai-architecture-overview` |
| Update channels, release cadence, preview support boundaries | Install, lifecycle, support scope | Added: `rhoai-update-channels` |
| API tier support posture, deprecation windows, customer-accessible endpoint stability, Tier 4 boundaries, Beta/Alpha API handling, and KServe wildcard exceptions | What's New, supported APIs, supported configurations | Added: `rhoai-api-tiers` |
| Release cadence, component support phases, lifecycle dates, EUS, GA, Early Access, and upgrade support windows | What's New, lifecycle | Added: `rhoai-release-and-support-posture` |
| Platform planning, validated models, hardware | Plan | Added: `rhoai-platform-planning` |
| Self-managed install, Operator Subscription, DataScienceCluster component management | Install | Added: `rhoai-self-managed-installation` |
| Disconnected self-managed install, image mirroring, private registry, custom namespaces, components, certificates, logs, troubleshooting, and uninstall | Install | Missing: `rhoai-disconnected-installation` |
| DSCI/DSC configuration deep dive | Install, Administer | Added: `rhoai-dsci-dsc-configuration` |
| Distributed workloads component installation: Kueue, Ray, Training Operator, dashboard, pipelines, and workbenches DSC states | Install | Added: `rhoai-distributed-workloads` |
| Kueue workload management, namespace queue enforcement, dashboard enablement, queue labels, troubleshooting, and embedded Kueue migration | Administer | Added: `rhoai-kueue-workload-management` |
| Distributed workload quota resources, NVIDIA Kueue ResourceFlavor/ClusterQueue/LocalQueue examples, RDMA setup, and Ray administrator troubleshooting | Administer | Added: `rhoai-distributed-workload-operations` |
| Distributed workload user workflows: workbench and training image preparation, Ray/CodeFlare, Training Operator PyTorchJob, Kubeflow Trainer v2 TrainJob, fine-tuning, checkpointing, monitoring, and user troubleshooting | Develop | Added: `rhoai-distributed-workload-workflows` |
| NVIDIA GPU accelerator enablement, NFD, KMM, NVIDIA GPU Operator, and hardware profiles | Install, Administer | Added: `rhoai-nvidia-gpu-accelerators` |
| Certificate management, DSCI trusted CA bundle, component CA bundles, Llama Stack TLS trust, and CA removal | Install, Administer | Added: `rhoai-certificate-management` |
| Observability stack, DSCI monitoring, OpenTelemetry Collector, Prometheus, Alertmanager, Tempo, dashboard menu, user workload scrape labels, exporters, traces, and built-in alerts | Administer | Added: `rhoai-observability` |
| Operator logger configuration, Operator pod logs, and audit records for DSC/DSCI changes | Administer | Added: `rhoai-logs-and-audit-records` |
| Installation troubleshooting, support escalation, must-gather evidence, and common Operator install failure signals | Install | Added: `rhoai-installation-troubleshooting` |
| Self-managed uninstall, Operator-managed resource removal, retained user resources, and CLI decommission procedure | Install | Added: `rhoai-uninstallation` |
| User and administrator access, OpenShift AI groups, user cleanup, PVC/ConfigMap cleanup boundaries | Administer | Added: `rhoai-users-groups-access` |
| Selecting existing administrator and user groups in the OpenShift AI dashboard | Administer, Managing resources | Added: `rhoai-access-group-selection` |
| Central authentication service, external OIDC provider configuration, GatewayConfig OIDC fields, service account token API access, provider CA trust, and auth troubleshooting | Administer | Added: `rhoai-central-authentication-service` |
| Dashboard application tiles, OdhApplication, OdhDashboardConfig application visibility, support labels, information panels, and default basic workbench tile visibility | Administer | Added: `rhoai-dashboard-applications` |
| Connected applications user workflows: Applications Explore and Enabled pages, SaaS enablement, endpoint tile handling, disabled tile removal, and Start basic workbench as an enabled application | Develop | Added: `rhoai-connected-applications` |
| Dashboard customization, OdhDashboardConfig feature flags, navigation visibility, preview dashboard controls, size profiles, and template ordering | Administer, Managing resources | Added: `rhoai-dashboard-customization` |
| Cluster default PVC size, restore to 20GiB default, workbench pod restart impact, and new-PVC verification | Administer, Managing resources | Added: `rhoai-cluster-pvc-size` |
| Storage class visibility, display names, access modes, OpenShift AI default storage class selection, and RWX shared storage safety | Administer, Managing resources | Added: `rhoai-storage-classes` |
| Connection type templates, dashboard form previews, category labels, enablement, duplication, editing, and deletion boundaries | Administer, Managing resources | Added: `rhoai-connection-types` |
| Workbench data access to S3-compatible object storage, Boto3 client setup, bucket/object operations, endpoint formatting, troubleshooting, and self-signed CA trust handoff | Develop | Added: `rhoai-s3-object-storage-data` |
| Project-scoped workbench images, hardware profiles, KServe serving-runtime templates, and `disableProjectScoped` dashboard behavior | Administer | Added: `rhoai-project-scoped-resources` |
| OpenShift AI Operator-related component Deployment CPU/memory requests and limits, `opendatahub.io/managed` behavior, and restore/re-enable workflow | Administer | Added: `rhoai-component-resource-customization` |
| Telemetry and broader admin settings | Administer | Added: `rhoai-telemetry-admin-settings` |
| Basic workbench administration, starting/accessing/stopping other users' workbenches, idle timeout, workbench pod tolerations, and administrator troubleshooting | Administer, Managing resources | Added: `rhoai-basic-workbenches` |
| Workbenches, custom workbench image build/import, ImageStream, Notebook CRD, dashboard discovery, and optional Kueue queueing | Administer, Develop | Added: `rhoai-workbenches-custom-images` |
| Dashboard import of an existing custom workbench image, support boundary, image metadata, accelerator metadata, and workbench selection verification | Administer, Managing resources | Added: `rhoai-workbench-image-import` |
| Custom workbench image migration to Kubernetes Gateway API path-based routing, `NB_PREFIX`, health and culling endpoints, relative URLs, and NGINX translation | Administer, Managing resources | Added: `rhoai-workbench-gateway-api-migration` |
| Data science project workflows: project lifecycle, project workbenches, connections and connection API annotations, cluster storage, project access, and project-scoped resource handoff | Develop | Added: `rhoai-project-workflows` |
| Data science IDE workflows: accessing workbench IDEs, JupyterLab notebooks and Git, code-server notebooks and Git, Python package management, code-server extensions, and user-facing workbench troubleshooting | Develop | Added: `rhoai-data-science-ide-workflows` |
| AI Pipelines product workflows: pipeline servers, KFP SDK compilation, Kubernetes API pipeline storage, pipeline versions, caching, experiments, runs, schedules, workspaces, logs, Elyra, and DSPA troubleshooting | Develop | Added: `rhoai-ai-pipelines`; repo KFP code authoring remains covered by `rhoai-kfp-pipeline-authoring` |
| MLflow platform and SDK workflows: shared cluster instance, project/workspace mapping, RBAC pseudo-resources, MLflow and MLflowConfig CRs, PostgreSQL/S3 storage, SDK auth, experiment tracking, and project artifact overrides | Develop | Added: `rhoai-mlflow` |
| Model catalog source governance, Hugging Face and YAML sources, allow/disallow visibility patterns, `model-catalog-sources` ConfigMap, and catalog-source validation | Administer, Develop | Added: `rhoai-model-catalog-sources` |
| Model catalog user workflows: discover, evaluate validated performance, compare tensor variants, register catalog models, and deploy catalog models | Develop | Added: `rhoai-model-catalog-workflows` |
| Gen AI studio playground: AI asset endpoints, model experimentation, custom endpoints, playground RAG uploads, reusable prompts, MCP tool testing, export templates, and troubleshooting | Develop | Added: `rhoai-gen-ai-playground` |
| Model registry component enablement, registry creation/editing, default and external databases, CA certificates, permissions, generated RBAC, deletion, and admin lifecycle | Administer | Added: `rhoai-model-registry` |
| Model registry user workflows: register models and versions, store OCI ModelCar images, transfer jobs, metadata edits, deployment handoff, archive, and restore | Develop | Added: `rhoai-model-registry-workflows` |
| Model serving platform configuration, KServe `ServingRuntime` and `InferenceService`, runtime enablement, custom/tested runtimes, NVIDIA NIM enablement, vLLM runtime parameters, and default deployment strategy | Administer, Deploy | Added: `rhoai-model-serving-platform` |
| Model deployment user workflows: model storage in S3/URI/PVC/OCI modelcars, Deploy a model wizard, runtime auto-selection, hardware profiles, deployment strategies, AI asset endpoint registration, external routes, token authentication, OCI CLI `InferenceService` deployment, NIM deployment, and runtime-specific inference endpoints | Deploy | Added: `rhoai-model-deployment` |
| Deployed model management and monitoring, KServe timeouts, multi-node vLLM, Kueue routing, performance metrics, KEDA/CMA autoscaling, UWM/Grafana dashboards, and NIM model/metrics operations | Administer, Monitor | Added: `rhoai-model-management-monitoring` |
| Models-as-a-Service governance, subscription quota, model references, authorization policies, API keys, observability, external OIDC, and external provider models | Deploy | Added: `rhoai-maas-governance` |
| Distributed Inference with llm-d, `LLMInferenceService`, Gateway discovery, Connectivity Link auth, scheduler settings, WVA autoscaling, flow control, priority queuing, and llm-d observability | Deploy | Added: `rhoai-distributed-inference-llmd` |
| Llama Stack platform, RAG stack, OpenAI-compatible APIs, vector stores, providers, OAuth/ABAC, CA trust, HA/autoscaling, and file citations | Administer, Develop | Added: `rhoai-llama-stack` |
| Model customization and training: Red Hat Python index, Docling data preparation, SDG Hub synthetic data, Training Hub SFT/OSFT/LoRA/QLoRA, memory estimation, MLflow tracking, Kubeflow Trainer distributed fine-tuning, ITS Hub inference-time scaling, and support posture | Train | Added: `rhoai-model-customization-training` |
| Official evaluation workflows: EvalHub deployment/API/SDK/CLI, providers, benchmarks, collections, multi-tenancy, tenant RBAC, MLflow/OCI exports, LM-Eval `LMEvalJob`, dashboard evaluations, custom Unitxt, S3/PVC/KServe scenarios, and automated risk assessment with Garak/KFP/SDG | Evaluate | Added: `rhoai-evaluation`; legacy repo-specific evaluation remains covered by `rhoai-model-evaluation` |
| Guardrails and AI safety: NeMo Guardrails, `NemoGuardrails`, validation-only checks, guarded chat completions, built-in detectors, custom rails, self-check policies, OpenTelemetry, FMS legacy orchestrator, detectors, gateway, and Llama Stack PII handoff | Maintain Safety | Added: `rhoai-guardrails-safety` |
| TrustyAI model monitoring: component enablement, `TrustyAIService`, OVMS support boundary, database/PVC storage, KServe RawDeployment logger handoff, training data upload, field mappings, bias metrics, data drift metrics, and `trustyai_*` OpenShift metrics | Monitor | Added: `rhoai-monitoring-trustyai` |
| Feature Store, Feast Operator, FeatureStore CRs, offline/online stores, registry, UI, workbench integration, compute engines, and CLI | Develop, Administer | Added: `rhoai-feature-store` |
| AutoRAG user workflows: Technology Preview posture, RAG pattern optimization, JSON evaluation data, Llama Stack and remote Milvus prerequisites, Gen AI studio AutoRAG runs, leaderboard evaluation, generated indexing/inference notebooks, metrics, and search-space defaults | Develop | Added: `rhoai-autorag` |
| AutoML user workflows: Technology Preview posture, CSV/S3 data prerequisites, AI Pipelines-backed optimization runs, leaderboard evaluation, model registry handoff, saved prediction notebooks, AutoGluon serving runtime deployment, and task metrics | Develop | Added: `rhoai-automl` |
| Kubeflow Spark Operator distributed data processing: KSO activation, Spark 4.0.1+ image review, SparkApplication CRs, custom namespace RBAC, and Alpha API tier handling | Develop | Added: `rhoai-kubeflow-spark-operator` |

## Skill Build Standard

Each `rhoai-*` skill should include:

- creation through
  `.agents/skills/project-rhoai-doc-chapter-skill-authoring/SKILL.md` when it
  is derived from an official RHOAI documentation chapter
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

1. `rhoai-update-channels`, `rhoai-self-managed-installation`,
   `rhoai-nvidia-gpu-accelerators`, `rhoai-distributed-workloads`,
   `rhoai-certificate-management`, `rhoai-logs-and-audit-records`,
   `rhoai-installation-troubleshooting`, and `rhoai-uninstallation` for the
   initial platform install and operations baseline.
2. `rhoai-model-serving-platform` for local model serving, KServe, and vLLM.
3. `rhoai-maas-governance` for MaaS subscriptions, model refs, auth policy, and external models.
4. `rhoai-distributed-inference-llmd` for scalable llm-d serving, scheduler,
   autoscaling, and priority-queuing workflows.
5. `rhoai-llama-stack` for Llama Stack, RAG, vector stores, and Responses/OpenAI-compatible APIs.
6. `rhoai-evaluation` for EvalHub, LM-Eval, RAGAS, and MLflow-backed evidence.
7. `rhoai-guardrails-safety` for NeMo guardrails and safety validation.
8. `rhoai-gen-ai-playground` for Gen AI Playground assets and MCP connector posture.
9. Use `rhoai-ai-pipelines` for AI Pipelines product workflows and pair it
   with `rhoai-kfp-pipeline-authoring` for repo KFP implementation work.
