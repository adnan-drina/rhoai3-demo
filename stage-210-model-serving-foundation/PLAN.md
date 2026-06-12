# Stage 210: Model Serving Foundation Plan

## Intent

- Stage identifier: `210`
- Stage family: `2xx Production GenAI and Private Data`
- Stage slug: `stage-210-model-serving-foundation`
- Concept introduced: Standard model serving foundation for a GPU-backed LLM.
- Target audience: Platform engineer, solution architect, data scientist.
- Enterprise value: Converts governed GPU capacity into a usable model endpoint
  path while keeping evaluation and shared-service governance as separate
  evidence-driven stages.
- Depends on: `stage-110-rhoai-base-platform` and
  `stage-120-gpu-as-a-service`.
- New components: KServe model serving platform through the RHOAI
  `DataScienceCluster`, vLLM NVIDIA GPU runtime availability, deployment path
  for `nemotron-3-nano-30b-a3b`.
- Existing components reused: Stage 110 OpenShift GitOps, RHOAI Dashboard,
  `demo-sandbox`, ODF MCG, Model Registry, and Stage 120 GPU hardware
  profiles.
- Non-goals:
  - MaaS governance, subscriptions, quotas, external OpenAI model registration,
    or API-key issuance; deferred to `stage-230-models-as-a-service`.
  - GuideLLM performance baseline or breakpoint analysis; deferred to
    `stage-220-model-performance-baseline`.
  - Curated durable Nemotron service configuration; deferred until MaaS and
    performance-baseline decisions are captured.
  - llm-d distributed inference; later scale-out option only.
  - NVIDIA NIM enablement.

## Acceptance Criteria

- [ ] README explains Why and What without runbook detail.
- [ ] Why and business value are grounded in Red Hat narrative sources from
  `rh-brain/`.
- [ ] KServe/model serving enablement is grounded in active-baseline RHOAI
  official docs and verified live schema.
- [ ] Red Hat-linked GitHub reference implementations are captured as patterns,
  not API authority.
- [ ] GitOps ownership model is explicit: Stage 110 remains the sole
  `DataScienceCluster` owner.
- [ ] The Stage 110 RHOAI overlay renders with a focused Stage 210 KServe patch.
- [ ] Deploy script applies the shared owner Application and triggers Argo CD
  reconciliation.
- [ ] Validate script proves the model serving platform is enabled and a vLLM
  serving runtime is discoverable.
- [ ] Temporary Nemotron smoke test path is planned and bounded, or implemented
  after runtime/API verification.
- [ ] Manifest and Red Hat source-alignment reviews pass.

## Source Capture

| Purpose | Source | Skill | Notes |
|---------|--------|-------|-------|
| Concept/value | `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/wiki/sources/2026-05-12 - From Inference to Agents Scaling AI in the Enterprise with Red Hat AI 3.4.md` | `project-documentation-authoring` | Positions production inference, MaaS, llm-d, and evaluation as the Red Hat AI 3.4 platform progression. |
| Concept/value | `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/wiki/sources/2025-10-30 - Why vLLM Is the Best Choice for AI Inference Today.md` | `project-documentation-authoring` | Supports vLLM as the private LLM inference runtime narrative. |
| Concept/value and artifact governance | `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/raw/Using containers to bring software engineering rigor to AI workloads.md` | `project-documentation-authoring` | Supports ModelCar/OCI model artifact governance. |
| Product config | [RHOAI 3.4 - Configuring your model-serving platform](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/configuring_your_model-serving_platform/index) | `rhoai-model-serving-platform` | KServe platform, ServingRuntime, vLLM runtime, deployment strategy. |
| Product workflow | [RHOAI 3.4 - Deploying models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/deploying_models/index) | `rhoai-model-deployment` | Deploy a model wizard, OCI/modelcar storage, endpoint and token checks. |
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
  `rhoai-hardware-profiles`, `rhoai-nvidia-gpu-accelerators`
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
- Secret and credential handling:
  - No model endpoint tokens or registry pull credentials are committed.
  - Temporary model smoke tests must create runtime-only credentials and remove
    them during cleanup.

## Manifest Inventory

| File | Kind | Source authority | Validation |
|------|------|------------------|------------|
| `gitops/stage-110-rhoai-base-platform/rhoai/aggregate/overlays/demo/patch-datasciencecluster-kserve.yaml` | `DataScienceCluster` patch | RHOAI 3.4 docs plus live `oc explain` for v2 schema | `kustomize build gitops/stage-110-rhoai-base-platform`; `oc get datasciencecluster default-dsc` after sync |
| `gitops/stage-110-rhoai-base-platform/rhoai/aggregate/overlays/demo/kustomization.yaml` | Kustomize overlay | Project shared-owner pattern | `kustomize build gitops/stage-110-rhoai-base-platform/rhoai/aggregate/overlays/demo` |

## Script Plan

### `deploy.sh`

- Guard behavior: loads `.env`, verifies `RHOAI_EXPECTED_API_SERVER` against
  `oc whoami --show-server`, exits on mismatch.
- First action: applies the Stage 110 Argo CD Application with local
  `GIT_REPO_URL` and `GIT_REPO_BRANCH`.
- Wait/report behavior: requests an Argo CD refresh and waits for Stage 110 to
  report `Synced` and `Healthy`, then reports the KServe component state.

### `validate.sh`

- Readiness checks:
  - Stage 110 Argo CD Application is `Synced` and `Healthy`.
  - `DataScienceCluster` is `Ready`.
  - `spec.components.kserve.managementState` is `Managed`.
  - KServe `InferenceService` and `ServingRuntime` CRDs are present.
  - A vLLM `ServingRuntime` is discoverable.
  - Stage 120 GPU hardware profile and GPU capacity are still visible.
- Functional checks:
  - No durable model endpoint is required in this stage.
  - Temporary Nemotron smoke test is deferred until the active runtime template
    and deployment API shape are verified.
- Expected success output: all readiness checks print success and exit 0.

## Operations And Troubleshooting

- `docs/OPERATIONS.md` update needed: yes - Stage 210 deployment sequence,
  validation, and user-led Nemotron dashboard path.
- `docs/TROUBLESHOOTING.md` update needed: yes - model serving component stuck,
  missing runtime, KServe CRDs missing, GPU profile unavailable.
- `docs/BACKLOG.md` update needed: yes - Stage 210 status and deferred
  temporary Nemotron smoke test if not implemented immediately.

## Risks And Deferred Work

| Item | Type | Resolution |
|------|------|------------|
| Runtime template name and enabled state | risk | Verify after KServe is managed; do not hard-code a runtime name before validation. |
| Temporary Nemotron smoke test | deferred | Implement after `ServingRuntime`, `InferenceService` or `LLMInferenceService`, image pull, endpoint, and cleanup path are verified. |
| OCI modelcar pull permissions | risk | The Red Hat registry modelcar may require entitlement/pull credentials; keep credentials out of Git. |
| Scarce GPU capacity | risk | Use Recreate strategy and one replica; Stage 120 scale-to-zero remains available. |
| MaaS and external OpenAI | deferred | Stage 230 owns MaaS, including external `gpt-5.4-nano`. |

## Review Log

- Manifest review: pending.
- Red Hat source-alignment review: pending.
- Live validation: pending.
