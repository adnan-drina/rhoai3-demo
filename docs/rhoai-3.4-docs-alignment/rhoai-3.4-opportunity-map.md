# RHOAI 3.4 Opportunity-Led Second Pass

**Date:** 2026-05-16
**Scope:** second-pass review focused on what Red Hat OpenShift AI 3.4 enables, not only what the current demo already implements.
**Baseline checked:** local repo on `codex/rhoai34-foundation-refactor`; live cluster `default-dsc` reports `Ready`.

## Sources

- [RHOAI 3.4 documentation index](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4)
- [RHOAI 3.4 release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/release_notes)
- [RHOAI 3.4 new features and enhancements](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/release_notes/new-features-and-enhancements_relnotes)
- [RHOAI 3.4 Technology Preview features](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/release_notes/technology-preview-features_relnotes)
- [RHOAI 3.4 Developer Preview features](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/release_notes/developer-preview-features_relnotes)
- [RHOAI 3.4 support removals](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/release_notes/support-removals_relnotes)
- [RHOAI 3.4 connections API](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_on_projects/using-connections_projects)
- `rh-brain` articles under `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/`, used only as narrative and blog alignment input.

## Executive Findings

The first alignment review was too implementation-centered. This second pass treats RHOAI 3.4 as a new product capability set and asks where the demo should evolve.

| ID | Finding | Current demo state | Recommended action |
|---|---|---|---|
| F-01 | Support-status language is stale or inconsistent across docs and step READMEs. | Step 02/05 still describe MaaS broadly as Technology Preview; Step 09 describes NeMo Guardrails as Technology Preview; Step 12 describes MLflow as Developer Preview. Current release notes say MaaS is GA, NeMo Guardrails is fully supported, and MLflow is Technology Preview. Some product books still carry older Technology Preview language for MaaS/NeMo, so this needs an explicit source-of-truth note. | Add a central support-status matrix with release-note source, product-book source, and chosen demo wording. Then update affected READMEs atomically. |
| F-02 | Live Step 09 is not actually running the NeMo implementation that exists locally. | Live Argo CD app `step-09-guardrails` is `Synced/Healthy`, but its tracked resources are legacy `GuardrailsOrchestrator`, detector `InferenceService`s, and `guardrails-orchestrator-config`. No live `NemoGuardrails` resource was found. | Treat as a P0 live adoption gap. Refresh/resync/prune Step 09 after verifying Argo source revision and cache. The demo story should not present NeMo until the cluster shows `NemoGuardrails/nemo-guardrails`. |
| F-03 | MLflow is installed, but not yet demonstrated as a 3.4 MLOps capability. | Step 02 enables `mlflowoperator`; Step 12 deploys `MLflow` and `MLflowConfig`; validation checks infrastructure. The pipeline does not yet prove experiment creation, run logging, artifact logging, prompt/model metadata, or MLflow UI workflow. | Add MLflow run logging to Step 12 KFP components, validate at least one experiment/run/artifact, and show MLflow as the lifecycle record for training and evaluation. |
| F-04 | MaaS is enabled, but the GA governance story is not fully exercised. | Step 02 enables MaaS and Step 05 serves vLLM/KServe models in `maas`. The demo does not yet walk through subscriptions/tiers, self-service API keys, rate limits, token quotas, subscription selection, or usage/showback. | Add a MaaS consumption scene: publish endpoint, create subscription/tier, issue API key as `ai-developer`, call OpenAI-compatible endpoint, show quota/rate behavior and usage metrics where available. |
| F-05 | Product-native Gen AI Studio/Playground is underused. | The custom chatbot is strong, but the RHOAI dashboard Playground, AI Available Assets page, multi-pane comparison, guardrails toggles, MCP server selection, and knowledge-source selection are not first-class demo scenes. | Add a Step 10 or Step 07/09/10 cross-step scene that uses the product UI alongside the custom chatbot. |
| F-06 | Model Catalog 3.4 enhancements are not exploited. | Step 04/05 use catalog/registry narrative and ModelCar serving. The demo does not use embedding model catalog entries, tool-calling metadata, recommended vLLM runtime configs, or ModelCar transfer jobs from the dashboard. | Add a catalog-driven scene: choose a validated tool-calling model or embedding model, explain catalog metadata, and compare with the hand-authored vLLM args in GitOps. |
| F-07 | Llama Stack 3.4 capabilities are partly used but not fully visible. | Step 07 uses Llama Stack, pgvector, Responses API, connectors, files, and RAG. It does not yet make OpenAI-compatible citation annotations, Conversations API, TLS/proxy provider configuration, or RAG knowledge sources in Playground visible. | Add a Llama Stack API capability table and validate one more product-native API path, preferably citations or Conversations API if supported by the live runtime. |
| F-08 | Evaluation Stack/EvalHub is present as a CRD but not deployed. | Live cluster has `evalhubs.trustyai.opendatahub.io`; no `EvalHub` instance exists. Step 08 uses LMEvalJob and custom KFP RAG eval. RAGAS providers are configured in Llama Stack, but there is no visible RAGAS/Garak/EvalHub workflow. | Add an EvalHub/Evaluation Stack track or mark it explicitly as next-wave. Best demo: RAGAS + Garak + GuideLLM results tracked in MLflow. |
| F-09 | llm-d is the largest unclaimed 3.4 serving opportunity. | Live cluster has `llminferenceservices.serving.kserve.io` and `llminferenceserviceconfigs.serving.kserve.io`; no `LLMInferenceService` exists. Current serving uses KServe `InferenceService` with vLLM. | Add an optional Step 05/06 llm-d path for the 4-GPU model: `LLMInferenceService`, RHCL auth, Prometheus metrics, endpoint picker, prefix-cache metrics, and migration notes from vLLM `InferenceService`. |
| F-10 | Feature Store is enabled at the operator layer but unused. | `feastoperator` is `Managed` in the DSC and the live cluster has `featurestores.feast.dev`; no `FeatureStore` instance exists. | Either disable/defer the operator in the story or add a small predictive feature workflow for Step 11/12. The rh-brain Feast/Kubeflow Trainer article supports this path. |
| F-11 | Spark Operator and Trainer v2/JIT checkpointing are missed training/data opportunities. | The DSC schema exposes `sparkoperator`, `trainer`, and `trainingoperator`. Current demo trains YOLO inside KFP components; it does not use `SparkApplication`, `TrainJob`, `TrainingRuntime`, Kueue-backed training, or JIT checkpointing. | Add a future training/data-processing track or mark as out of scope. If added, use a bounded example: Spark preprocessing, then Trainer v2 for distributed/custom model training. |
| F-12 | Connection Secrets should be modernized to the 3.4 connections API. | Existing S3 connection secrets use `opendatahub.io/connection-type: s3`. The 3.4 connections API recommends `opendatahub.io/connection-type-protocol: "s3"` for new connection secrets. | Add the protocol annotation to new/updated connection secrets and verify dashboard visibility plus workload behavior. |
| F-13 | Centralized observability is not represented. | Step 06 uses Grafana and GuideLLM; Step 12 uses TrustyAI; MaaS observability and centralized platform observability are not demonstrated. NeMo OpenTelemetry is not configured. | Add a platform-observability backlog: MaaS usage/showback, NeMo OTel, llm-d metrics if implemented, and RHOAI centralized observability if supported in the target cluster. |
| F-14 | Agent and MCP 3.4 Developer Preview features are not separated from the custom MCP story. | Step 10 deploys MCP servers manually and registers connectors. It does not evaluate MCP Catalog, RHOAI MCP server, AgentCard, or AgentRuntime. | Keep current MCP story, but add a Developer Preview matrix so viewers understand product-native agent management vs custom demo integration. |
| F-15 | Air-gapped/disconnected RAG and catalog readiness are absent. | Demo assumes connected environment and in-cluster MinIO. | Document as an enterprise hardening path: image mirroring, catalog/model availability, disconnected Llama Stack/RAG operation, and external enterprise object storage. |

## RHOAI 3.4 Feature Opportunity Matrix

| RHOAI 3.4 signal | Support posture from docs | Demo coverage | Gap type | Recommended demo enhancement |
|---|---|---|---|---|
| MLflow Operator managed in `DataScienceCluster`; MLflow SDK pre-installed in workbench/runtime images | Release notes describe MLflow integration as Technology Preview and the operator as a managed component. | Operator and CRs deployed; no functional run logging. | Under-demonstrated implementation | Add Step 12 MLflow experiment/run/artifact logging and validator checks. |
| MaaS GA with subscriptions, quotas, self-service API keys, usage tracking | Release notes say MaaS is GA; MaaS product book still carries Technology Preview language in current indexed page. vLLM MaaS, OIDC, external providers, and observability are Technology Preview. | MaaS enabled and vLLM serving present; no subscription/key/quota story. | Product value gap and docs-status discrepancy | Add source-of-truth note, then build a user-facing MaaS consumption flow. |
| NeMo Guardrails fully supported in release notes, with `/v1/guardrails/checks`, OpenAI compatibility, regex rails, replicas, OTel, config reload | Release notes say fully supported; guardrails product book still carries Technology Preview language for NeMo. | Local repo migrated; live cluster still shows legacy FMS resources. | Live drift plus docs-status discrepancy | Reconcile live Step 09, then enhance validation for `/v1/guardrails/checks`, replicas, and config reload. |
| Gen AI Playground redesign, multi-instance comparison, guardrails, MCP servers, knowledge sources | Technology Preview/Developer Preview features vary by subfeature. | Custom chatbot is primary. Dashboard config enables GenAI Studio. | Missing product-native scene | Add product UI scene with two panes: base model vs RAG/guardrails/MCP. |
| AI Available Assets page | Technology Preview in release notes. | Not explicitly demonstrated. | Missing UI adoption | Show deployed models and MCP servers as reusable project assets. |
| Model Catalog embedding models | Technology Preview in release notes. | RAG uses sentence-transformers inline embedding, not catalog embedding endpoint. | Architecture opportunity | Add optional catalog-deployed embedding model and compare retrieval/latency. |
| Tool-calling metadata on model cards | Developer Preview in release notes. | vLLM args are hand-authored in GitOps. | Missed Red Hat validation signal | Add a scene showing model card tool-calling metadata and mapping it to `granite-8b-agent` args. |
| Recommended vLLM runtime configs in model catalog | Technology Preview in release notes. | Step 05 comments include manual GuideLLM tuning. | Missed catalog/PSAP story | Compare current tuning with model-card recommended configs where available. |
| OCI ModelCar registration/transfer jobs | GA feature in release notes. | Step 05 uses ModelCar; Step 12 builds ModelCar with Tekton. Dashboard transfer job is not shown. | UI workflow opportunity | Add an optional dashboard-driven model transfer scene or document why GitOps/Tekton remains the demo path. |
| EvalHub SDK/CLI and Evaluation Stack UI | Technology Preview; control plane Developer Preview in EA notes. | CRD exists; no instance. Step 08 uses LMEvalJob and custom KFP. | Missing new evaluation plane | Add EvalHub as optional Step 08b, with RAGAS/Garak/GuideLLM and MLflow tracking. |
| RAGAS and Garak providers in Llama Stack | RAGAS Technology Preview; Garak release-note feature. | `ENABLE_RAGAS=true` configured; not surfaced in demo. Garak not demonstrated. | Hidden capability | Add RAG quality and safety evaluation scenes. |
| Responses API parity with OpenAI | Technology Preview. | Custom chatbot uses Responses API. | Covered but under-documented | Add official API/support caveat and one deterministic Responses API validation. |
| Conversations API | Technology Preview in release notes. | Chatbot maintains app-level state; no explicit Conversations API scene. | Missing API | Evaluate whether live Llama Stack exposes it; add if stable enough for demo. |
| Llama Stack TLS/proxy config for remote inference providers | EA2 enhancement. | vLLM provider uses TLS verify env; no proxy story. | Production hardening | Document only, unless demo needs private outbound provider integration. |
| llm-d distributed inference | 3.4 docs include full deploy guide; several llm-d features are TP/Developer Preview. | No `LLMInferenceService`. | Strategic serving gap | Add optional scale-out serving path for Mistral or a synthetic large model. |
| vLLM runtime support for MaaS | Technology Preview. | Enabled in dashboard config; vLLM endpoints exist. | Partially used | Tie vLLM endpoint to MaaS subscription/API key path. |
| MaaS observability dashboard | Technology Preview. | Not demonstrated. | Missing cost/showback story | Add usage metrics scene after API calls. |
| External model egress via MaaS | Technology Preview. | Not used. | Optional enterprise governance story | Defer unless demo wants hybrid external-provider governance. |
| External OIDC for MaaS | Technology Preview. | Local users/groups only. | Enterprise IAM gap | Document as hardening path. |
| Feature Store integration and UI | Technology Preview. | Operator managed only. | Installed-but-unused component | Either implement a small FeatureStore or stop presenting it as covered. |
| AutoML | Technology Preview in GA release notes. | Not implemented. | Optional predictive AI expansion | Defer unless Step 11/12 expands beyond face recognition. |
| AutoRAG | Technology Preview in GA release notes. | Not implemented. | Strong RAG quality opportunity | Evaluate as future Step 07/08 enhancement. |
| Kubeflow Spark Operator | Developer Preview. | Not implemented. | Data engineering gap | Add only if ingestion/data prep becomes a core story. |
| Kubeflow Trainer v2 and JIT/S3 checkpointing | Technology Preview / EA2 feature. | Not used; training is KFP component-based. | Training architecture gap | Add future distributed training track, not required for current MLOps story. |
| Hardware Profiles replacing Accelerator Profiles | Supported direction; older selectors deprecated. | Strongly covered in Step 02. | Minor docs polish | Keep. Add supported-config evidence. |
| KServe RawDeployment over Serverless/ModelMesh | Recommended direction; serverless/modelmesh deprecated. | Strong for central model serving. Step 01 still installs Serverless for platform compatibility. | Mostly aligned | Explain why Serverless operator exists even though model deployments use Standard/RawDeployment. |
| New connection annotation `opendatahub.io/connection-type-protocol` | Recommended for new connection Secrets. | Existing connection Secrets use older `opendatahub.io/connection-type`. | API modernization | Add protocol annotation in a focused GitOps cleanup batch. |

## Live Cluster Evidence

Commands run against the live environment on 2026-05-16:

```bash
oc whoami
oc get datasciencecluster default-dsc \
  -o jsonpath='{.status.phase}{"\n"}{.spec.components.mlflowoperator.managementState}{"\n"}{.spec.components.kserve.modelsAsService.managementState}{"\n"}{.spec.components.llamastackoperator.managementState}{"\n"}{.spec.components.feastoperator.managementState}{"\n"}'
oc get crd | rg -i 'mlflow|nemo|llminference|spark|evalhub|featurestore|lmeval|llamastack'
oc get applications.argoproj.io -n openshift-gitops | rg 'step-(02|05|07|08|09|10|12)'
```

Observed:

| Area | Live evidence | Interpretation |
|---|---|---|
| DSC | `Ready`; `mlflowoperator`, `modelsAsService`, `llamastackoperator`, and `feastoperator` are `Managed`. | Platform layer has several 3.4 operators enabled. |
| CRDs | `evalhubs`, `featurestores`, `llminferenceservices`, `llminferenceserviceconfigs`, `mlflows`, `mlflowconfigs`, `nemoguardrails`, `lmevaljobs`, `llamastackdistributions`. | The cluster can host more 3.4 features than the demo currently exercises. |
| EvalHub | No `EvalHub` resources found. | CRD available, feature not adopted. |
| Feature Store | No `FeatureStore` resources found. | Operator/CRD available, feature not adopted. |
| llm-d | No `LLMInferenceService` resources found. | CRD available, distributed inference not adopted. |
| MLflow | `MLflow/mlflow` exists. | Infrastructure present; functional lifecycle usage still needs proof. |
| Step 09 | Argo reports `Synced/Healthy`, but resources are legacy FMS `GuardrailsOrchestrator` and detector `InferenceService`s. | Local NeMo migration is not represented in the live app graph. |
| Step 10 | Argo reports `Degraded`. | Expected because `acme-equipment-0007` is intentionally broken for the demo story. |

## Prioritized Remediation

### P0: Correct What the Demo Claims

| Item | Action | Acceptance |
|---|---|---|
| Support-status matrix | Create a central table for MaaS, vLLM-on-MaaS, NeMo, MLflow, Llama Stack, Responses API, MCP, EvalHub, AutoRAG, AutoML, Feature Store, llm-d, MLServer, Trainer v2, Spark, TrustyAI, and Model Registry APIs. Include release-note status and product-book status where they conflict. | Every README claim points to the matrix or an exact official doc link. |
| Step 09 live mismatch | Force a hard Argo refresh/resync after confirming the source branch and commit. Prune legacy FMS resources and verify `NemoGuardrails/nemo-guardrails`. | `oc get nemoguardrails -A` shows `nemo-guardrails`; Argo resource list no longer shows `GuardrailsOrchestrator`. |
| README stale status | After the matrix is agreed, update Step 02/05/09/12 wording: MaaS no longer blanket-TP if release notes are source of truth, NeMo status needs current wording, MLflow should be Technology Preview rather than Developer Preview. | Step docs stop underselling or misclassifying 3.4 features. |

### P1: Turn Installed Components Into Demo Value

| Item | Action | Acceptance |
|---|---|---|
| MLflow lifecycle story | Add MLflow experiment/run/artifact logging to Step 12 KFP, plus validator checks for an experiment and fresh run. | Step 12 shows MLflow UI/API evidence for the latest training run. |
| MaaS governed consumption | Implement a dashboard/API scene for subscriptions/tiers, API key generation, rate/quota policy, and endpoint call. | A non-admin user can generate/use a scoped key and hit a governed endpoint. |
| Product-native Playground | Add a scene comparing base model, RAG, MCP tools, and guardrails in the RHOAI Playground. | Demo can show both custom chatbot and Red Hat product UI. |
| EvalHub/Evaluation Stack | Deploy EvalHub or explicitly mark it as next-wave. Prefer RAGAS/Garak/GuideLLM with MLflow result tracking. | Step 08 gains a product-native evaluation path beyond LMEvalJob. |
| Model Catalog 3.4 enhancements | Add a catalog walkthrough for embedding models, tool-calling metadata, and recommended vLLM configs. | Step 04/05 explain how Red Hat validation metadata informs GitOps serving choices. |

### P2: Add Optional Advanced Tracks

| Item | Action | Acceptance |
|---|---|---|
| llm-d distributed inference | Add an optional Step 05/06 path using `LLMInferenceService` and `LLMInferenceServiceConfig`, RHCL auth, and metrics. | Current vLLM/KServe path remains stable; optional llm-d path is clear and separately validated. |
| Feature Store | Add a small FeatureStore scenario or stop presenting Feast as an active capability. | `FeatureStore` resource exists and is used, or docs mark it operator-enabled only. |
| AutoRAG | Evaluate a future RAG optimization step after the baseline RAG/eval path is stable. | AutoRAG is either implemented or classified as future product exploration. |
| Spark/Trainer v2 | Add only if the demo needs distributed data processing/training. | No unsupported training claims; deprecated Trainer v1 paths remain absent. |
| Connections API cleanup | Add `opendatahub.io/connection-type-protocol: "s3"` to new/updated S3 connections. | Dashboard still shows connections and workloads still consume them. |
| Centralized observability | Evaluate RHOAI centralized observability, MaaS usage dashboard, NeMo OTel, and llm-d metrics. | Demo has one coherent observability story instead of separate Grafana/TrustyAI fragments. |

## rh-brain Narrative Alignment

The second pass also identifies Red Hat blog themes that can strengthen the demo:

| Theme | Relevant `rh-brain` material | Demo implication |
|---|---|---|
| llm-d production inference | `Demystifying llm-d and vLLM The race to production.md`, `Combining KServe and llm-d for optimized generative AI inference.md`, `Introduction to distributed inference with llm-d.md` | Strong support for an optional distributed-inference track. |
| Evaluation-driven development | `Eval-driven development Build and evaluate reliable AI agents.md`, `GuideLLM Evaluate LLM deployments for real-world inference.md` | Step 08 should grow toward EvalHub/RAGAS/Garak and Step 06 GuideLLM should feed MLflow. |
| MLflow as AI platform memory | `MLflow Documentation  MLflow AI Platform.md`, `Evaluating (Production) Traces  MLflow AI Platform.md`, `Evaluation Quickstart  MLflow AI Platform.md` | Step 12 should make MLflow the record of training/evaluation, not just an installed server. |
| Guardrails | `Build resilient guardrails for OpenClaw AI agents on Kubernetes.md` | Step 09 should show NeMo policy evolution, checks endpoint, and telemetry/config-reload behavior after live migration. |
| Feature Store and Trainer | `Improve RAG retrieval and training with Feast and Kubeflow Trainer.md` | Useful future path for Feature Store + Trainer v2 if predictive/RAG optimization expands. |

## Conclusion

The demo is technically broad, but the 3.4 opportunity gap is now clear: several new features are **enabled but not activated as stories**. The highest-value next batch is not more manifest cleanup; it is turning MLflow, MaaS, Gen AI Playground, EvalHub, Model Catalog metadata, and live NeMo Guardrails into observable demo workflows with validators.
