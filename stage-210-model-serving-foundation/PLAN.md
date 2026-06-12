# Stage 210: Model Serving Baseline with vLLM Plan

## Intent

- Stage identifier: `210`
- Stage family: `2xx Production GenAI and Private Data`
- Stage slug: `stage-210-model-serving-foundation`
- Concept introduced: Standard model serving baseline for a GPU-backed LLM.
- Target audience: Platform engineer, solution architect, data scientist.
- Enterprise value: Converts governed GPU capacity into a usable, measurable
  model endpoint path before shared-service governance is introduced.
- Depends on: `stage-110-rhoai-base-platform` and
  `stage-120-gpu-as-a-service`.
- New components: KServe model serving platform through the RHOAI
  `DataScienceCluster`, vLLM NVIDIA GPU runtime availability, idempotent
  `demo-registry` and Nemotron metadata readiness, and a deployment path for
  `nemotron-3-nano-30b-a3b`.
- Existing components reused: Stage 110 OpenShift GitOps, RHOAI Dashboard,
  `demo-sandbox`, ODF MCG, Model Registry, and Stage 120 GPU hardware
  profiles.
- Non-goals:
  - MaaS governance, subscriptions, quotas, external OpenAI model registration,
    or API-key issuance; deferred to `stage-220-models-as-a-service`.
  - EvalHub, MLflow, LMEval, LLM-as-judge, risk assessment, or formal model
    quality evaluation; deferred to later MLOps/evaluation stages.
  - llm-d distributed inference; later scale-out option only.
  - Curated MaaS service configuration; deferred until baseline decisions are
    captured.
  - NVIDIA NIM enablement.

## Acceptance Criteria

- [x] README explains Why and What without runbook detail.
- [x] Why and business value are grounded in Red Hat narrative sources from
  `rh-brain/`.
- [x] KServe/model serving enablement is grounded in active-baseline RHOAI
  official docs and verified live schema.
- [x] Red Hat-linked GitHub reference implementations are captured as patterns,
  not API authority.
- [x] GitOps ownership model is explicit: Stage 110 remains the sole
  `DataScienceCluster` owner.
- [x] The Stage 110 RHOAI overlay renders with a focused Stage 210 KServe patch.
- [x] Deploy script applies the shared owner Application and triggers Argo CD
  reconciliation.
- [x] Validate script proves the model serving platform is enabled, vLLM is
  available, `demo-registry` is available, Nemotron metadata exists, and the
  Nemotron `InferenceService` is ready.
- [x] Fresh-environment deploy path discovers existing manual/dashboard state
  and creates missing registry metadata and endpoint resources when absent.
- [ ] Lightweight GuideLLM benchmark script is added for baseline throughput
  and latency evidence.
- [ ] Grafana dashboard resources are added for vLLM/KServe/GPU metrics.
- [x] Manifest and Red Hat source-alignment reviews pass for the KServe enablement
  slice.

## Source Capture

| Purpose | Source | Skill | Notes |
|---------|--------|-------|-------|
| Concept/value | `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/wiki/sources/2026-05-12 - From Inference to Agents Scaling AI in the Enterprise with Red Hat AI 3.4.md` | `project-documentation-authoring` | Positions production inference, MaaS, llm-d, and evaluation as the Red Hat AI 3.4 platform progression. |
| Concept/value | `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/wiki/sources/2025-10-30 - Why vLLM Is the Best Choice for AI Inference Today.md` | `project-documentation-authoring` | Supports vLLM as the private LLM inference runtime narrative. |
| Concept/value and artifact governance | `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/raw/Using containers to bring software engineering rigor to AI workloads.md` | `project-documentation-authoring` | Supports ModelCar/OCI model artifact governance. |
| Product config | [RHOAI 3.4 - Configuring your model-serving platform](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/configuring_your_model-serving_platform/index) | `rhoai-model-serving-platform` | KServe platform, ServingRuntime, vLLM runtime, deployment strategy. |
| Product workflow | [RHOAI 3.4 - Deploying models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/deploying_models/index) | `rhoai-model-deployment` | Deploy a model wizard, OCI/modelcar storage, endpoint and token checks. |
| Product config | [RHOAI 3.4 - Managing model registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/managing_model_registries/index) | `rhoai-model-registry` | `modelregistry` component, `demo-registry`, generated registry RBAC, default database demo posture. |
| Product workflow | [RHOAI 3.4 - Working with model registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_model_registries/index) | `rhoai-model-registry-workflows` | Registering models, model versions, model artifacts, and deployment handoff. |
| API shape | [Kubeflow Model Registry REST API v1alpha3](https://www.kubeflow.org/docs/components/hub/reference/rest-api/) | `rhoai-model-registry-workflows`, `rhoai-api-tiers` | Registry REST endpoints used for idempotent metadata checks and creation. |
| Product config | [RHOAI 3.4 - Working with accelerators](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_accelerators/index) | `rhoai-hardware-profiles`, `rhoai-nvidia-gpu-accelerators` | GPU hardware profile selection and `nvidia.com/gpu` capacity. |
| Schema verification | `oc explain datasciencecluster.spec.components.kserve --api-version=datasciencecluster.opendatahub.io/v2` | `rhoai-dsci-dsc-configuration` | Verified `managementState: Managed|Removed`; active docs say only RawDeployment mode is supported. |
| Pattern | [redhat-cop/gitops-catalog/openshift-ai](https://github.com/redhat-cop/gitops-catalog/tree/main/openshift-ai) | `project-red-hat-operator-gitops` | Operator/instance/components/overlay structure only. |
| Reference implementation | [redhat-ai-services/modelcar-catalog](https://github.com/redhat-ai-services/modelcar-catalog) | `rhoai-model-deployment` | ModelCar examples only; product fields still come from RHOAI docs/schema. |

### `rh-brain` Article Selection

- Candidate articles reviewed: Red Hat AI 3.4 inference-to-agents blog, vLLM
  inference article, ModelCar/OCI governance article, OpenShift AI vLLM and
  llm-d inference baseline.
- Selected articles: Red Hat AI 3.4 inference-to-agents blog, vLLM article,
  and ModelCar/OCI governance article.
- Reason selected: together they explain why production inference matters, why
  vLLM is the runtime path, and why OCI model artifacts fit enterprise
  governance.
- Links to GitHub/code examples: yes.
- Linked implementation source: `redhat-ai-services/modelcar-catalog` for
  ModelCar examples; Red Hat CoP `gitops-catalog/openshift-ai` for GitOps
  layout pattern.

## Skill Routing

- Coordinator: `project-demo-stage-authoring`
- Documentation: `project-documentation-authoring`
- GitOps: `project-gitops-authoring`, `project-red-hat-operator-gitops`
- Product skills: `rhoai-dsci-dsc-configuration`,
  `rhoai-model-serving-platform`, `rhoai-model-deployment`,
  `rhoai-model-registry`, `rhoai-model-registry-workflows`,
  `rhoai-model-management-monitoring`, `rhoai-hardware-profiles`,
  `rhoai-nvidia-gpu-accelerators`
- Review skills: `project-manifest-review`,
  `project-red-hat-doc-alignment-review`, `rhoai-api-tiers`
- Environment skills: `openshift-project-safety`,
  `env-deploy-and-evaluate`, `env-troubleshoot`

## GitOps Ownership

- Ownership model: shared-owner.
- Owning Application: `stage-110-rhoai-base-platform`.
- Source path: `gitops/stage-110-rhoai-base-platform`.
- Shared resources touched: the single `DataScienceCluster` named
  `default-dsc`.
- Argo CD sync or ordering requirements:
  - Stage 110 must be installed and healthy first.
  - Stage 120 should be healthy before deploying a GPU model.
  - Stage 210 patches the Stage 110 RHOAI aggregate overlay; no separate
    Argo CD Application owns the DSC.
  - Argo CD console visibility is through `stage-110-rhoai-base-platform`;
    there is intentionally no `stage-210-model-serving-foundation` tile.
- Secret and credential handling:
  - No model endpoint tokens, registry pull credentials, or provider API keys
    are committed.
  - The deploy script may copy the cluster pull-secret into `demo-sandbox` as a
    runtime Kubernetes Secret when the Nemotron modelcar pull secret is absent.
  - Endpoint auth is disabled for the Stage 210 controlled baseline endpoint;
    MaaS provides governed shared access in Stage 220.

## Manifest Inventory

| File | Kind | Source authority | Validation |
|------|------|------------------|------------|
| `gitops/stage-110-rhoai-base-platform/rhoai/aggregate/overlays/demo/patch-datasciencecluster-kserve.yaml` | `DataScienceCluster` patch | RHOAI 3.4 docs plus live `oc explain` for v2 schema | `kustomize build gitops/stage-110-rhoai-base-platform`; `oc get datasciencecluster default-dsc` after sync |
| `gitops/stage-110-rhoai-base-platform/rhoai/registry/base/modelregistry-demo.yaml` | `ModelRegistry` | RHOAI 3.4 managing model registries plus live `oc explain modelregistries.modelregistry.opendatahub.io` | `kustomize build gitops/stage-110-rhoai-base-platform`; `oc get modelregistries.modelregistry.opendatahub.io demo-registry -n rhoai-model-registries` |
| `gitops/stage-110-rhoai-base-platform/rhoai/registry/base/rolebinding-demo-registry-*.yaml` | `RoleBinding` | RHOAI generated registry RBAC model | `oc get role registry-user-demo-registry -n rhoai-model-registries`; user dashboard access |
| `gitops/stage-110-rhoai-base-platform/rhoai/aggregate/overlays/demo/kustomization.yaml` | Kustomize overlay | Project shared-owner pattern | `kustomize build gitops/stage-110-rhoai-base-platform/rhoai/aggregate/overlays/demo` |

## Script Plan

### `deploy.sh`

- Guard behavior: loads `.env`, verifies `RHOAI_EXPECTED_API_SERVER` against
  `oc whoami --show-server`, exits on mismatch.
- First action: applies the Stage 110 Argo CD Application with local
  `GIT_REPO_URL` and `GIT_REPO_BRANCH`.
- Wait/report behavior: requests an Argo CD refresh and waits for Stage 110 to
  report `Synced` and `Healthy`, then reports the KServe component state.
- Registry behavior:
  - waits for `demo-registry` to become `Available`
  - uses existing Nemotron registered model, model version, and artifact
    metadata when present
  - creates missing Nemotron metadata through the Model Registry REST API
- Endpoint behavior:
  - uses an existing Nemotron `InferenceService` when present
  - creates the vLLM `ServingRuntime` from the active RHOAI template when
    absent
  - creates the Nemotron `InferenceService` when absent
  - waits for the endpoint to become `Ready`

### `validate.sh`

- Readiness checks:
  - Stage 110 Argo CD Application is `Synced` and `Healthy`.
  - `DataScienceCluster` is `Ready`.
  - `spec.components.kserve.managementState` is `Managed`.
  - KServe `InferenceService` and `ServingRuntime` CRDs are present.
  - A vLLM `ServingRuntime` is discoverable.
  - Stage 120 GPU hardware profile and GPU capacity are still visible.
  - `demo-registry` is available and has a route host.
  - Nemotron registered model, version, and OCI artifact metadata exist.
  - Nemotron `InferenceService` is `Ready`, has a runtime, and uses the
    expected OCI modelcar source.
- Expected success output: all readiness checks print success and exit 0.

## Operations And Troubleshooting

- `docs/OPERATIONS.md` update needed: yes - Stage 210 deployment sequence,
  validation, and user-led Nemotron dashboard path.
- `docs/TROUBLESHOOTING.md` update needed: yes - model serving component stuck,
  missing runtime, KServe CRDs missing, GPU profile unavailable.
- `docs/BACKLOG.md` update needed: yes - Stage 210 status and deferred
  GuideLLM/Grafana baseline work.

## Risks And Deferred Work

| Item | Type | Resolution |
|------|------|------------|
| Runtime template name and enabled state | risk | Verify after KServe is managed; do not hard-code a runtime name before validation. |
| GuideLLM benchmark script | deferred | Add a lightweight benchmark runner after endpoint readiness is repeatable. Do not introduce EvalHub or MLflow in this stage. |
| Grafana metrics dashboard | deferred | Add GitOps-managed Grafana resources for vLLM/KServe/GPU metrics. |
| OCI modelcar pull permissions | risk | The Red Hat registry modelcar may require entitlement/pull credentials; keep credentials out of Git. |
| Scarce GPU capacity | risk | Use Recreate strategy and one replica; Stage 120 scale-to-zero remains available. |
| MaaS and external OpenAI | deferred | Stage 220 owns MaaS, including external `gpt-5.4-nano`. |

## Review Log

- Local render: passed 2026-06-12.
  `kustomize build gitops/stage-110-rhoai-base-platform`
  rendered `kserve.managementState: Managed`.
- Script syntax: passed 2026-06-12.
  `bash -n stage-210-model-serving-foundation/deploy.sh stage-210-model-serving-foundation/validate.sh`.
- Red Hat source-alignment review: passed for KServe enablement scope; product
  fields are from RHOAI 3.4 docs plus live
  `oc explain datasciencecluster.spec.components.kserve`.
- Live deploy: succeeded on cluster-klvxt 2026-06-12; Argo CD Application
  `stage-110-rhoai-base-platform` synced revision
  `df241586684739f8d1610e8a43bd875d686db896`.
- Live validation: PASSED 2026-06-12 -
  `stage-210-model-serving-foundation/validate.sh` 9/9.
- Regression validation: PASSED 2026-06-12 -
  Stage 110 `validate.sh` 17/17 and Stage 120 `validate.sh` 23/23 after KServe
  became `Managed`.
- Manual dashboard validation: user created `demo-registry` in
  `rhoai-model-registries`, registered Nemotron 3, and manually deployed
  `nvidia-nemotron-3-nano-30b-a3b` in `demo-sandbox` from
  `oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0`.
  Guarded read-only check confirmed a ready `serving.kserve.io/v1beta1`
  `InferenceService` and matching `ServingRuntime` using model format `vLLM`.
- Idempotent deploy validation: PASSED 2026-06-12.
  `stage-210-model-serving-foundation/deploy.sh` reused existing
  `demo-registry`, Nemotron registered model id `1`, version id `2`, artifact
  id `1`, serving environment id `3`, and the existing
  `demo-sandbox/nvidia-nemotron-3-nano-30b-a3b` `InferenceService`.
- Expanded live validation: PASSED 2026-06-12 -
  `stage-210-model-serving-foundation/validate.sh` 17/17 for KServe, vLLM,
  registry availability, Nemotron metadata, and endpoint readiness.
- Regression validation after idempotent bootstrap changes: PASSED 2026-06-12 -
  Stage 110 `validate.sh` 17/17 and Stage 120 `validate.sh` 23/23.
