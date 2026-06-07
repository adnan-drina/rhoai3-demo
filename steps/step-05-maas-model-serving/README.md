# Step 05: MaaS Model Serving on vLLM
**"Shared LLMs as a governed internal service"** — serve Red Hat-validated LLMs in the `maas` project, expose them to GenAI users, and prepare them for RHOAI 3.4 Models-as-a-Service workflows.

## Overview

This step moves LLM serving out of the old shared project model and into `maas`, displayed as `MaaS Runtime` in the dashboard, the dedicated namespace for shared model endpoints. The active implementation uses KServe `Standard` deployment mode with the Red Hat AI Inference Server powered by vLLM, and the platform posture is now RHOAI 3.4 MaaS-ready:

- `kserve.modelsAsService.managementState: Managed` is enabled in the DSC.
- The dashboard exposes Model Catalog, Model Registry, GenAI Studio, MaaS, MLflow, and Kueue controls.
- `maas` is the only Kueue-managed workload namespace in this slice.
- InferenceServices carry `kueue.x-k8s.io/queue-name: maas-default`.
- `MaaSModelRef`, `MaaSSubscription`, and `MaaSAuthPolicy` publish the running models for governed MaaS consumption.
- `ExternalModel/gpt-5` routes OpenAI GPT-5 through the same MaaS gateway and subscription model as the local endpoints.

MaaS model publication uses the installed RHOAI 3.4 CRDs. The local model servers still run as KServe `InferenceService` resources, so this step uses `ExternalModel` plus `MaaSModelRef` as a bridge and patches the cluster-generated route hosts during `deploy.sh`. OpenAI GPT-5 uses the product external-model path directly: `ExternalModel` points to `api.openai.com`, the provider key is stored in `maas/openai-provider-api-key`, and `MaaSSubscription` plus `MaaSAuthPolicy` grant the same demo users governed access. The follow-on cleanup is to move the local serving resources to `LLMInferenceService` once the S3-backed Mistral path is fully validated.

Narrative alignment uses `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/wiki/configurations/OpenShift AI vLLM and llm-d Inference Baseline.md` and `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/raw/A guide to Models-as-a-Service.md`. API correctness stays pinned to official RHOAI 3.4 and OCP 4.20 docs.

## Architecture

![Step 05 capability map](../../docs/assets/architecture/step-05-capability-map.svg)

```text
MaaS Model Serving
├── maas namespace
├── vLLM ServingRuntime
├── granite-8b-agent InferenceService      → 1 GPU, OCI ModelCar, FP8
├── mistral-3-bf16 InferenceService        → 4 GPUs, S3/MinIO, BF16
├── MaaSModelRefs + subscription           → governed API key access
├── OpenAI GPT-5 ExternalModel             → external provider access through MaaS
├── maas-usage-heartbeat                   → recent Usage dashboard telemetry
├── deploy.sh upload helper                → one-shot Mistral sync into MinIO
├── maas-default LocalQueue                → Kueue admission for MaaS workloads
└── enterprise-ai-registry links           → model/version metadata
```

| Model | GPUs | Source | Use Case | Namespace |
|-------|------|--------|----------|-----------|
| `granite-8b-agent` | 1 L4 | OCI ModelCar | RAG, MCP tools, guardrails, agentic workflows | `maas` |
| `mistral-3-bf16` | 4 L4 | S3/MinIO | Enterprise chat, benchmarking, evaluation judge | `maas` |
| `gpt-5` | 0 | OpenAI external provider | Frontier model comparison and fallback demos | `maas` |

Manifests: [`gitops/step-05-maas-model-serving/base/`](../../gitops/step-05-maas-model-serving/base/)

<details>
<summary>Design Decisions</summary>

> **MaaS namespace boundary:** LLM runtime ownership is separated from RAG and MLOps workloads. RAG consumers use MaaS API keys and the MaaS gateway, but do not own serving runtime resources.

> **Product MaaS namespace is separate:** RHOAI creates the product-managed `models-as-a-service` namespace for MaaS `Tenant`, `MaaSSubscription`, and `MaaSAuthPolicy` resources. It may be visible to cluster admins, but it is not the runtime project that contains models. The demo runtime namespace is `maas`, displayed as `MaaS Runtime`, to avoid duplicate Models-as-a-Service project names.

> **Verified GitOps for MaaS governance:** The current RHOAI 3.4 Models-as-a-Service guide labels MaaS as Technology Preview. This repo commits only installed, schema-verified MaaS CRDs (`ExternalModel`, `MaaSModelRef`, `MaaSSubscription`, and `MaaSAuthPolicy`) and validates them with `oc explain` and live API-key calls.

> **External model credentials stay outside Git:** OpenAI GPT-5 is registered as `ExternalModel/gpt-5`, but the real provider API key is never committed. `deploy.sh` creates `maas/openai-provider-api-key` from `OPENAI_API_KEY` in this repo's `.env` or, by default, from `../rhoai3-coding-demo/.env`. Override the lookup path with `RHOAI_OPENAI_ENV_FILE`.

> **Kueue on MaaS only:** Queue enforcement applies only to `maas`; every GitOps-managed model-serving workload in this namespace is labeled for `maas-default`.

> **OCI ModelCar for small models, S3 for large models:** Granite uses OCI ModelCar from `registry.redhat.io`. Mistral BF16 uses S3/MinIO because the model is large enough that object storage remains the safer demo path.

> **Upload helper outside Argo desired state:** The Mistral upload PVC and Job are applied by `deploy.sh` before the Argo CD app syncs. They are not part of the steady-state Kustomize base because bound PVC specs do not safely round-trip through GitOps after dynamic provisioning.

> **Sharded safetensors only:** The Mistral upload helper ignores and prunes `consolidated.safetensors` when `model.safetensors.index.json` and the sharded safetensors files are present. That keeps KServe's S3 storage initializer from copying a redundant ~47 GiB payload on every cold start.

> **Pinned helper image:** The model registration job uses a pinned `quay.io/curl/curl` tag so MaaS registration behavior does not change when upstream `latest` moves.

> **AI asset endpoint shape:** RHOAI 3.4 surfaces MaaS-published models under Gen AI studio → AI asset endpoints → Models. Published models show as Ready and expose a Model as a Service badge plus MaaS endpoint/API-key controls in the endpoint dialog; persistent MaaS API keys are managed from Gen AI studio → API keys. The API Keys table is per user, so an empty table is expected until that user creates a persistent key. `validate.sh` checks both the public MaaS API and the GenAI BFF MaaS model-discovery API so the UI model list is not treated as healthy unless the backend discovery path works.

> **Demo API key lifecycle:** `deploy.sh` creates user-owned MaaS API keys for `ai-admin` and `ai-developer` with a default `60d` expiry and stores copies in `maas/ai-admin-maas-api-key` and `maas/ai-developer-maas-api-key` for repeatable validation. Override the lifetime with `RHOAI_DEMO_MAAS_KEY_TTL`. `validate.sh` uses these durable keys for `/v1/models` and `/v1/chat/completions` instead of minting throwaway validation keys.

> **MaaS Usage monitoring:** Once Step 01 Kuadrant observability, detailed Limitador telemetry, and Step 02 MaaS Tenant telemetry are enabled, this step's validation traffic should produce the product Usage dashboard metrics. `validate.sh` calls the gateway with `X-Gateway-Model-Name: granite-8b-agent` so traffic goes through the MaaS model route where token-rate policies are enforced, then checks the Limitador scrape target plus `authorized_calls` and `authorized_hits` with user, subscription, and model labels.

> **vLLM workload scrape opt-in:** The vLLM `ServingRuntime` exposes `/metrics` on port `8080`, so each active KServe `InferenceService` opts generated predictor pods into the RHOAI observability stack with `spec.predictor.labels.monitoring.opendatahub.io/scrape: "true"`. The KServe CRD documents predictor `labels` as labels added to component pods; `validate.sh` checks the InferenceService, generated predictor Deployment template, and generated pods.

> **Dashboard freshness heartbeat:** The RHOAI Usage dashboard is time-windowed. Step 06 GuideLLM benchmarks intentionally hit predictor services directly, which is useful for model performance but bypasses the MaaS gateway telemetry path. This step includes `maas-usage-heartbeat`, a low-rate CronJob that calls the published MaaS route every 10 minutes with the durable `ai-admin` demo API key so a fresh demo environment keeps recent MaaS Usage data visible.

> **Recreate deployment strategy:** LLM InferenceServices use `deploymentStrategy.type: Recreate` to avoid double-allocating scarce L4 GPUs during updates.

> **Fixed serving capacity:** These demo endpoints set KServe autoscaling scale-down policy to `Disabled`. That keeps long cold-starting GPU models from being scaled down by generated HPAs before metrics samples exist.

> **GPU scale-up guard:** `deploy.sh` checks the cluster-specific `g6.4xlarge` and `g6.12xlarge` MachineSets created by Step 01. If they were scaled to zero for cost control, the script scales them back to one replica and waits until the nodes report 1 and 4 L4 GPUs respectively. Set `RHOAI_SKIP_GPU_SCALE=true` when intentionally validating manifests without starting GPU capacity.

</details>

<details>
<summary>Deploy</summary>

```bash
./steps/step-05-maas-model-serving/deploy.sh
./steps/step-05-maas-model-serving/validate.sh
```

</details>

<details>
<summary>What to Verify</summary>

| Check | Pass Criteria |
|-------|---------------|
| Namespace | `maas` exists and is Kueue-managed |
| Queue | `LocalQueue/maas-default` exists in `maas` |
| Runtime | vLLM `ServingRuntime` exists in `maas` |
| Models | `granite-8b-agent` and `mistral-3-bf16` InferenceServices exist |
| External model | `ExternalModel/gpt-5` points to `api.openai.com`, `MaaSModelRef/gpt-5` is Ready, and the OpenAI provider secret exists |
| AI asset endpoints | Local models carry `opendatahub.io/dashboard=true` and `opendatahub.io/genai-asset=true`; MaaS `/v1/models` and GenAI MaaS API list local and external models |
| User API keys | `ai-admin-maas-api-key` and `ai-developer-maas-api-key` exist in `maas`, record `MAAS_EXPIRES_IN=60d`, list the local and external models, complete a granite chat call, and route one low-token GPT-5 request |
| MaaS observability | Prometheus scrapes Limitador and sees user/subscription/model-labeled MaaS Usage metrics after validation traffic or the heartbeat CronJob |
| vLLM workload scraping | Predictor Deployment and pods carry `monitoring.opendatahub.io/scrape=true` |
| MaaS | both `MaaSModelRef` objects are `Ready`, subscription and auth policy are `Active` |
| Registry linkage | deployed models have model registry labels after `deploy.sh` linking |
| Playground | deployed model appears in GenAI Playground / AI assets |

```bash
oc get localqueue maas-default -n maas
oc get servingruntime -n maas
oc get inferenceservice -n maas
oc get inferenceservice -n maas -o custom-columns=NAME:.metadata.name,DASHBOARD:.metadata.labels.opendatahub\\.io/dashboard,GENAI:.metadata.labels.opendatahub\\.io/genai-asset
oc get maasmodelref -n maas
oc get externalmodel gpt-5 -n maas
oc get maassubscription,maasauthpolicy -n models-as-a-service
oc get cronjob maas-usage-heartbeat -n maas
oc get pods -n maas -l serving.kserve.io/inferenceservice -o wide
```

</details>

## The Demo

Start with the `maas` project in the RHOAI dashboard. The first message is governance: shared LLM endpoints now live in a platform-owned namespace, not inside the RAG or predictive AI teams' projects.

Then open GenAI Studio and select a running model. The user experience is simple, but the platform story is richer:

- Model metadata comes from the enterprise registry.
- Serving is backed by vLLM/KServe.
- GPU placement is explicit through hardware profiles and node selectors.
- MaaS is enabled for governed publishing and API-key consumption.
- Kueue admission is scoped to this serving namespace.

For API validation:

```bash
oc exec deploy/granite-8b-agent-predictor -n maas -c kserve-container -- \
  curl -s http://localhost:8080/v1/models
```

### Product Playground Model Comparison

> The Red Hat product UI should be part of the demo, not only the custom ACME chatbot. Here we prove that the same governed endpoints can be compared directly in GenAI Studio before developers package them into an application.

1. Open **GenAI Studio** → **Playground**
2. Create a new playground in the `MaaS Runtime` (`maas`) project
3. Add `granite-8b-agent` in the first chat instance
4. Add `mistral-3-bf16` in a second chat instance
5. Set temperature to `0.1` and leave streaming enabled so the comparison is deterministic and visibly responsive
6. Use the same prompt in both panes:

```text
Explain how a governed private AI platform should expose shared LLMs to application teams.
```

**Expect:** Both models answer from the RHOAI Dashboard. Granite is the lower-cost agentic model used later for RAG/MCP; Mistral is the larger model used for enterprise chat, benchmarking, and evaluation judging.

> Product-native comparison lets platform teams discuss cost, latency, model quality, and governance before an application is built. The same assets are then reused by the Step 07 chatbot, Step 08 evaluation jobs, and Step 10 MCP workflow.

For cluster-side readiness before presenting this scene:

```bash
./scripts/validate-genai-playground-readiness.sh
```

## References

- [RHOAI 3.4 — Deploy large models with KServe](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploying_models/deploying-large-models_serving-large-models)
- [RHOAI 3.4 — Govern LLM access with Models-as-a-Service](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service_maas)
- [RHOAI 3.4 — Configure external models for Models-as-a-Service](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/govern_llm_access_with_models-as-a-service/index#configure-external-models-for-models-as-a-service)
- [RHOAI 3.4 — GenAI Playground prerequisites](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user)
- [Red Hat Developer — Centralized routing for external and self-hosted LLMs on OpenShift AI](https://developers.redhat.com/articles/2026/05/25/route-external-and-local-llms-models-as-a-service)
- `rh-brain`: `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/wiki/configurations/OpenShift AI vLLM and llm-d Inference Baseline.md`
- `rh-brain`: `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/raw/A guide to Models-as-a-Service.md`

## Next Steps

- **Step 06**: [Model Performance Metrics](../step-06-model-metrics/README.md) — Grafana dashboards and GuideLLM benchmarks for MaaS endpoints.
- **Step 07**: [Enterprise RAG](../step-07-rag/README.md) — RAG workloads consume shared MaaS endpoints from `enterprise-rag`.
