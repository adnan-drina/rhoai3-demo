# Stage 210: Model Serving Baseline with vLLM

**Theme:** Production GenAI and Private Data
**Concept:** Prove that a real LLM can be served on governed GPU capacity before
evaluating or exposing it as a shared enterprise service.

---

## Why This Matters

GPU capacity is useful only after the platform can turn it into a working model
endpoint. For a regulated European enterprise, this is the point where raw
accelerator infrastructure becomes a controlled GenAI capability: model
artifacts, runtime selection, endpoint exposure, authentication, and resource
strategy all need to be explicit before teams can trust the service.

Red Hat positions production inference as a core Red Hat AI 3 capability:
efficient serving with vLLM, distributed inference with llm-d when scale
requires it, governed MaaS access, and accelerator-aware operations. This stage
uses the smallest useful slice of that story. It enables the standard
KServe-based model serving platform, ensures Nemotron can be served with vLLM
on the GPU profiles created in Stage 120, and prepares lightweight benchmark
and metrics evidence before MaaS governance is introduced.

The stage does not yet turn the model into a governed shared service. That is
deliberate. First we prove the platform can host a GPU-backed LLM endpoint;
then this stage captures a simple GuideLLM/Grafana serving baseline, and Stage
220 publishes validated access through Models-as-a-Service.

---

## What Enables It

| Technology | Role in this stage | Source |
|------------|-------------------|--------|
| Red Hat OpenShift AI `DataScienceCluster` | Enables the KServe model serving component through the existing Stage 110 shared owner. | [RHOAI 3.4 - Installing and deploying OpenShift AI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install) |
| KServe model serving platform | Provides the standard per-model runtime server pattern used for production-oriented LLM serving in this demo. | [RHOAI 3.4 - Configuring your model-serving platform](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/configuring_your_model-serving_platform/index) |
| vLLM NVIDIA GPU ServingRuntime | Runtime family used for GPU-backed generative model serving, including OpenAI-compatible inference endpoints. | [RHOAI 3.4 - Configuring your model-serving platform](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/configuring_your_model-serving_platform/index) |
| RHOAI Deploy a model workflow | User-facing dashboard workflow for deploying Nemotron from a model source, selecting a GPU hardware profile, choosing route/auth settings, and testing the endpoint. | [RHOAI 3.4 - Deploying models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/deploying_models/index) |
| OCI modelcar artifact | Preferred reproducible model artifact pattern for the Nemotron vLLM endpoint and later MaaS deployment. | [RHOAI 3.4 - Deploying models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/deploying_models/index) |
| Model Registry | Stores the governed model metadata record, model version, and OCI model artifact pointer used by the demo deployment path. | [RHOAI 3.4 - Managing model registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/managing_model_registries/index) |
| Stage 120 GPU profiles | Provide the governed `nvidia.com/gpu` capacity that the model deployment consumes. | [RHOAI 3.4 - Working with accelerators](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_accelerators/index) |

This stage uses direct model serving, not Models-as-a-Service and not llm-d.
MaaS governance and external OpenAI `gpt-5.4-nano` registration belong to
Stage 220. Distributed inference with llm-d remains a later scale-out option.
EvalHub, MLflow, LMEval, judge-based evaluation, and risk assessment remain
deferred to later MLOps/evaluation stages.

---

## Architecture

```text
Stage 110 RHOAI shared owner
  DataScienceCluster default-dsc
        |
        | Stage 210 patch
        v
  kserve.managementState: Managed
        |
        v
KServe model serving platform
        |
        v
vLLM NVIDIA GPU ServingRuntime
        |
        v
Nemotron registry metadata and endpoint in demo-sandbox
        |
        v
GPU hardware profile from Stage 120
        |
        v
OpenAI-compatible inference endpoint
        |
        v
GuideLLM benchmark script + Grafana metrics
```

- New in this stage: KServe model serving platform enablement and the
  dashboard-ready or script-created vLLM deployment path.
- Already available: OpenShift GitOps, ODF MCG object storage, RHOAI Dashboard,
  Model Registry, `demo-sandbox`, NFD, NVIDIA GPU Operator, Kueue queues, and
  GPU hardware profiles.
- Argo CD visibility: open `stage-110-rhoai-base-platform` to confirm this
  stage; there is intentionally no separate
  `stage-210-model-serving-foundation` Application because Stage 110 owns the
  single `DataScienceCluster`.
- Value of the integration: GPU capacity becomes usable by a model endpoint,
  while MaaS exposure stays separated into the next stage.

For repeatable redeployments, the deploy script uses an idempotent
discover-or-create flow:

1. Use `demo-registry` when it already exists; otherwise rely on the Stage 110
   GitOps desired state to create it.
2. Use the existing Nemotron model/version/artifact metadata when present;
   otherwise create metadata through the Model Registry REST API.
3. Use the existing Nemotron `InferenceService` when present; otherwise create
   the vLLM runtime and endpoint from the active RHOAI template and OCI
   modelcar source.

---

## References

| Source | Role |
|--------|------|
| [Red Hat AI 3.4 blog](https://www.redhat.com/en/blog/inference-agentic-ai-scaling-enterprise-foundation-red-hat-ai-34) | Production inference, MaaS, llm-d, evaluation, and agentic platform narrative |
| [Red Hat Developer - Why vLLM is the best choice for AI inference today](https://developers.redhat.com/articles/2025/10/30/why-vllm-best-choice-ai-inference-today) | vLLM value and OpenShift AI integration narrative |
| [Red Hat - Using containers to bring software engineering rigor to AI workloads](https://www.redhat.com/en/blog/using-containers-bring-software-engineering-rigor-ai-workloads) | ModelCar/OCI artifact governance narrative |
| [RHOAI 3.4 - Configuring your model-serving platform](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/configuring_your_model-serving_platform/index) | Product authority for KServe, ServingRuntime, and platform enablement |
| [RHOAI 3.4 - Deploying models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/deploying_models/index) | Product authority for model deployment workflows and inference requests |
| [RHOAI 3.4 - Managing model registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/managing_model_registries/index) | Product authority for registry provisioning and access |
| [Kubeflow Model Registry REST API v1alpha3](https://www.kubeflow.org/docs/components/hub/reference/rest-api/) | API shape for idempotent metadata checks and creation |
| [redhat-cop/gitops-catalog - openshift-ai](https://github.com/redhat-cop/gitops-catalog/tree/main/openshift-ai) | Curated GitOps layout pattern for operator, instance, component, and overlay separation |
| [redhat-ai-services/modelcar-catalog](https://github.com/redhat-ai-services/modelcar-catalog) | Example ModelCar implementation catalog; not product API authority |
| `docs/PLATFORM_BASELINE.md` | Active product version targets |
