# Working Configuration And Design Decisions

Use this reference before changing or rebuilding the rhoai3-demo
Models-as-a-Service stage. It captures the configuration that was validated in
the live RHOAI 3.4 demo environment and the implementation traps discovered
during Stage 220.

## Validated Demo Configuration

Validated on `cluster-klvxt` for Stage 220 on 2026-06-12 and refreshed on
`cluster-xgg8t` during fresh-environment redeploy on 2026-06-29:

| Area | Working decision |
|------|------------------|
| RHOAI enablement | `DataScienceCluster.spec.components.kserve.managementState: Managed` and `spec.components.kserve.modelsAsService.managementState: Managed` |
| Gen AI dashboard path | `DataScienceCluster.spec.components.llamastackoperator.managementState: Managed` when Gen AI Studio, Playground, and AI asset endpoints are in scope |
| Dashboard flags | `modelAsService`, `vLLMDeploymentOnMaaS`, `genAiStudio`, `maasAuthPolicies`, and `observabilityDashboard` are enabled only when the stage validates those surfaces |
| MaaS API group | `maas.opendatahub.io/v1alpha1` for `Tenant`, `MaaSModelRef`, `ExternalModel`, `MaaSSubscription`, and `MaaSAuthPolicy` on the active RHOAI 3.4 cluster |
| Tenant namespace | `models-as-a-service` |
| Gateway | `maas-default-gateway` in `openshift-ingress`, with `opendatahub.io/managed: "false"` and `security.opendatahub.io/authorino-tls-bootstrap: "true"` |
| Gateway TLS | stable `maas-gateway-tls` Secret in `openshift-ingress`, generated from the active OpenShift ingress certificate by deploy automation |
| Connectivity Link | `rhcl-operator.v1.3.4`, manual InstallPlan approval, with the approval job accepting only the pinned CSV |
| Kuadrant and Authorino | `Kuadrant` and `Authorino` are managed in `kuadrant-system`; Authorino TLS and service CA trust are configured through GitOps |
| PostgreSQL | demo-local PostgreSQL 16 StatefulSet in `models-as-a-service-db`, outside the Kueue-managed MaaS model namespace |
| MaaS DB Secret | `maas-db-config` in `redhat-ods-applications`, with key `DB_CONNECTION_URL`; generated from local secrets and never committed; for this demo it must point to `maas-postgres.models-as-a-service-db.svc.cluster.local` |
| Local model backend | Nemotron `LLMInferenceService` in `models-as-a-service`, then `MaaSModelRef` in the same namespace with `spec.modelRef.kind: LLMInferenceService` |
| External OpenAI model | `ExternalModel.metadata.name: gpt-5-4-mini`, `ExternalModel.spec.targetModel: gpt-5.4-mini`, and matching `MaaSModelRef.metadata.name: gpt-5-4-mini` |
| Provider credential | `openai-provider-api-key` Secret in `models-as-a-service`, with data key `api-key` and label `inference.networking.k8s.io/bbr-managed=true`; generated or copied by deploy automation, not committed |
| Access policy | Users need both `MaaSSubscription` quota and `MaaSAuthPolicy` gateway authorization before model access is claimed |
| Developer access | `ai-developer` does not get direct namespace access to `models-as-a-service`; the user path is AI asset endpoints, MaaS API keys, and OpenAI-compatible MaaS endpoints |
| Admin access | `ai-admin` maps to `rhods-admins` and can administer the MaaS namespace and MaaS dashboard policy surfaces |
| Gen AI Playground | dashboard-created `LlamaStackDistribution` in `demo-sandbox`, Secret-backed MaaS API key, Nemotron through `remote::vllm`, external `gpt-5.4-mini` through `remote::openai` pointed at the MaaS Gateway while preserving the dashboard-created GPT provider id |

## Design Decisions

- Use the native RHOAI 3.4 MaaS `ExternalModel` path for OpenAI provider
  registration. Red Hat Developer LiteLLM examples can inform narrative and
  model selection, but they do not replace the product-documented MaaS CRs.
- Publish the local Nemotron model from `models-as-a-service`, not
  `demo-sandbox`. MaaS-published models must have the `MaaSModelRef` in the
  backend namespace, and the demo needs a clean separation between provider
  administration and user consumption.
- Remove stale direct Nemotron deployments from `demo-sandbox` during Stage
  220 deployment. A fresh environment might not have manual dashboard-created
  resources, but a reused environment often will.
- Keep PostgreSQL outside the Kueue-managed MaaS namespace. Kueue should manage
  model workloads, not long-lived support infrastructure with immutable
  workload labels.
- Restart `deployment/maas-api` after changing `maas-db-config` in a cluster
  where MaaS is already managed. CR readiness and model discovery can pass while
  API key storage still fails against an old database hostname until the API
  process reloads the configuration.
- The demo-local PostgreSQL connection uses an internal cluster service and
  `sslmode=disable`. Treat this as a demo exception only. For production-like
  MaaS guidance, follow the official database-secret posture with a managed
  PostgreSQL 14+ service and TLS-protected connection, typically
  `sslmode=require`.
- Treat generated Kuadrant resources as controller output. GitOps owns the
  source MaaS, Kuadrant, Authorino, Gateway, and RHCL configuration; it should
  not patch generated `AuthPolicy`, `TokenRateLimitPolicy`, or `EnvoyFilter`
  resources unless official Red Hat documentation or support guidance requires
  that exact change.
- Treat dashboard-created Gen AI Playground resources as product-generated
  project resources that still need validation. MaaS CR readiness, dashboard
  model listing, and direct MaaS inference do not prove the Llama Stack
  playground can use the models.
- Treat dashboard model-selection changes as Playground regeneration events.
  Checking or unchecking a MaaS model can recreate the project
  `LlamaStackDistribution`, ConfigMap, and generated deployment, resetting
  Secret-backed token references and provider mappings until the Stage 220
  Playground helper is rerun.
- Pin RHCL until the end-to-end RHOAI/RHCL/Gateway path is validated on a
  newer CSV. Automatic operator upgrades are normal for many demo components,
  but MaaS Gateway policy generation is a compatibility boundary. On the
  active baseline, use `rhcl-operator.v1.3.4` as the latest supported 1.3.z
  compatibility hold because RHCL 1.4.0 is deprecated in the official release
  notes.
- Enable `Tenant.spec.telemetry.metrics.captureUser` only as an explicit demo
  choice. The official guide defaults user capture off for privacy and
  cardinality reasons.

## Traps That Delayed Stage 220

- The official RHOAI 3.4 MaaS guide contains an API group inconsistency: the
  verification sections list `*.maas.opendatahub.io` CRDs, while some YAML
  examples use `models.opendatahub.io/v1alpha1`. The installed CRD schema is
  authoritative for GitOps authoring on the target cluster.
- Dotted external model names such as `gpt-5.4-mini` are not safe Kubernetes
  aliases. The MaaS controller creates Kubernetes networking resources from the
  `ExternalModel` name, so use a DNS-safe resource name like `gpt-5-4-mini` and
  keep the provider model ID in `spec.targetModel`.
- MaaS dashboard visibility can fail even when CRs look ready. Validate the
  real dashboard API and Gateway API paths with demo user tokens.
- A subscription alone is not enough. A matching `MaaSAuthPolicy` is required;
  otherwise users can receive `403 Forbidden` even with quota.
- Dashboard and `/maas-api/v1/subscriptions` checks do not prove inference is
  ready. A complete MaaS validation creates a temporary `sk-oai-*` API key,
  calls the OpenAI-compatible Nemotron endpoint, calls the external OpenAI model
  endpoint, verifies token usage and tool call output where relevant, and
  revokes the key.
- Raw OpenShift OAuth tokens are not the inference credential. They can be valid
  for discovery paths such as `/v1/models`, but `/v1/chat/completions` must use
  a MaaS API key for this demo policy.
- Dashboard-created Gen AI Playground Llama Stack deployments can contain
  placeholder MaaS tokens such as `fake`. That can make the UI load while model
  prompts receive `401 Unauthorized` from the MaaS Gateway. Bind the
  `LlamaStackDistribution` token env vars to a project Secret that contains a
  real MaaS API key, then validate `/v1/responses` from inside the Llama Stack
  pod.
- A recreated dashboard Playground can leave an existing project Secret and
  persistent MaaS API key behind. Before creating the replacement
  `genai-playground-<project>` key, search and revoke old active keys with the
  same name; then store only the newly issued key in the project Secret.
- The Llama Stack operator can fail to merge `valueFrom` Secret refs over
  existing literal placeholder env values in the generated deployment. If the
  `LlamaStackDistribution` is correct but the deployment still has literal
  token values, delete the generated deployment and let the operator recreate
  it from the corrected spec.
- Llama Stack registered model entries use `provider_model_id` for the provider
  target model ID in the validated RHOAI 3.4 demo environment. Do not use
  guessed fields such as `provider_resource_id` without checking the installed
  schema or product code path.
- For external `gpt-5.4-mini` through MaaS, the Llama Stack `remote::vllm`
  provider sends `max_tokens` and fails against the OpenAI provider. Use
  `remote::openai` with the MaaS Gateway base URL so governance remains MaaS
  controlled while the client payload matches OpenAI's expected shape.
- Llama Stack `/v1/models` exposes provider-qualified model IDs such as
  `maas-vllm-inference-2/gpt-5.4-mini`; the generated provider number depends
  on dashboard model selection order, so use the IDs returned by `/v1/models`
  in Playground `/v1/responses` checks.
- Preserve dashboard-created provider aliases when patching a project
  `LlamaStackDistribution`. A browser session can keep sending the old
  provider-qualified model id, for example
  `maas-vllm-inference-*/gpt-5-4-mini`, after the backend is corrected. Switch
  the GPT provider type to `remote::openai` and set `provider_model_id:
  gpt-5.4-mini`, but keep the generated provider id stable unless the
  playground is recreated. Do not try to make the old model alias work through
  MaaS; MaaS correctly rejects request bodies whose model is not the external
  `targetModel`. Refresh the page or reselect the GPT model after repair.
- External OpenAI requests for `gpt-5.4-mini` must use
  `max_completion_tokens`; `max_tokens` produces an OpenAI provider error even
  when MaaS routing, credential lookup, and policy enforcement are healthy.
- If external inference returns `provider 'openai' credentials not found`, check
  that the provider Secret has both data key `api-key` and label
  `inference.networking.k8s.io/bbr-managed=true`.
- If API key creation logs an old hostname such as
  `maas-postgres.models-as-a-service.svc.cluster.local`, the DB Secret and
  `maas-api` process are out of sync even when `maas-db-config` now contains
  the corrected `models-as-a-service-db` hostname.
- Generated Gateway resources can be stale after model renames or failed
  operator versions. Validate source CR status and functional user paths rather
  than relying on one generated `EnvoyFilter` name as a durable contract.
- A newer RHCL CSV can generate Gateway WASM configuration rejected by the
  OpenShift gateway Envoy. Fix the operator lifecycle boundary first instead of
  papering over generated-resource failures.
- On the active RHOAI 3.4 build, the generated `maas-api-key-cleanup` CronJob
  can point to `http://maas-api:8080` while the generated `maas-api` Service
  and Deployment expose HTTPS on `8443`. The generated
  `maas-api-cleanup-restrict` NetworkPolicy can also restrict cleanup pods to
  the wrong port. If recurring cleanup Jobs fail with timeouts, verify the
  generated Service, CronJob, and NetworkPolicy before blaming RHCL. For live
  demo recovery, suspend the broken generated CronJob and create a clearly
  annotated replacement CronJob that calls
  `https://maas-api:8443/internal/v1/api-keys/cleanup` with `curl -k`; remove
  that replacement after Red Hat fixes the generated resources.
- Argo CD health for a manually pinned OLM `Subscription` can be misleading
  when newer InstallPlans remain unapproved. The meaningful gate is that
  `status.installedCSV` equals the pinned `spec.startingCSV`, plus CRD and
  functional validation.
- Legacy namespace labels matter. If an old `kueue-managed=true` label remains
  on a namespace, automation can re-add `kueue.openshift.io/managed=true` and
  mutate workloads unexpectedly.
- Argo CD sync waves can deadlock when a Service that needs endpoints is in an
  earlier wave than the workload that creates those endpoints. Keep
  `service/maas-postgres` and `statefulset/maas-postgres` in the same sync wave
  so Argo CD can create both before evaluating Service health.
- A fresh llm-d `LLMInferenceService` can take several minutes after MaaS
  policy resources are healthy because the generated router/scheduler
  deployment pulls the modelcar image, the inference scheduler image, and the
  tokenizer image on a non-GPU worker. Validation must wait for
  `LLMInferenceService.status.conditions[Ready=True]`, not only for model
  access through the Gateway. A transient registry `ImagePullBackOff` can
  recover on retry; inspect events before changing manifests.
- Stage scope was broad: prerequisites, operator lifecycle, Gateway, DB,
  dashboard flags, local model, external model, subscriptions, auth policies,
  user RBAC, and validation all changed together. Future stages should split
  prerequisite enablement, model publication, and user experience validation
  unless the dependency chain forces one rollout.

## Required Regression Gates

Before declaring MaaS ready in a new or upgraded environment:

1. Confirm the active product baseline and rerun schema checks:

   ```bash
   oc api-resources | grep -i maas
   oc get crd tenants.maas.opendatahub.io \
     maasmodelrefs.maas.opendatahub.io \
     externalmodels.maas.opendatahub.io \
     maassubscriptions.maas.opendatahub.io \
     maasauthpolicies.maas.opendatahub.io
   oc explain maasmodelrefs.maas.opendatahub.io.spec
   oc explain externalmodels.maas.opendatahub.io.spec
   oc explain maassubscriptions.maas.opendatahub.io.spec
   oc explain maasauthpolicies.maas.opendatahub.io.spec
   oc explain tenants.maas.opendatahub.io.spec
   ```

2. Confirm RHCL compatibility:

   ```bash
   oc get subscription rhcl-operator -n openshift-operators \
     -o jsonpath='{.spec.installPlanApproval}{" "}{.spec.startingCSV}{" "}{.status.installedCSV}{"\n"}'
   ```

3. Confirm Kueue and database namespace separation:

   ```bash
   oc get namespace models-as-a-service -o jsonpath='{.metadata.labels.kueue\.openshift\.io/managed}{"\n"}'
   oc get namespace models-as-a-service-db -o jsonpath='{.metadata.labels.kueue\.openshift\.io/managed}{"\n"}'
   oc get statefulset maas-postgres -n models-as-a-service-db
   oc get secret maas-db-config -n redhat-ods-applications \
     -o jsonpath='{.data.DB_CONNECTION_URL}' | base64 -d
   ```

   The PostgreSQL Service and StatefulSet must be created in the same Argo CD
   sync wave to avoid waiting for Service endpoints before the StatefulSet
   exists.

4. Confirm model-publication and access-policy resources:

   ```bash
   oc get tenant,maasmodelref,externalmodel,maassubscription,maasauthpolicy -n models-as-a-service
   oc get authpolicy,tokenratelimitpolicy -n models-as-a-service
   ```

5. Confirm functional access with real users:

   - Dashboard AI asset endpoint listing as `ai-developer`.
   - Gateway `/maas-api/v1/subscriptions` as `ai-developer`.
   - Dashboard model listing from the MaaS project as `ai-admin`.
   - MaaS-local Nemotron `LLMInferenceService` `Ready=True`.
   - Temporary MaaS API key creation as `ai-developer`.
   - Nemotron `/v1/chat/completions` through the MaaS Gateway with the temporary
     `sk-oai-*` key, including structured tool-call output and token usage.
   - External OpenAI `/v1/chat/completions` through the MaaS Gateway with the
     same temporary `sk-oai-*` key, `max_completion_tokens`, and token usage.
   - If a Gen AI Playground exists, Secret-backed Llama Stack MaaS tokens,
     provider/model mapping for Nemotron and external GPT, Llama Stack
     `/v1/models` discovery, and `/v1/responses` completions for both models.
   - Unauthenticated Nemotron inference returns `401`.
   - Temporary MaaS API key revocation.
   - An unauthorized subject receives a controlled denial.

6. Confirm no generated Gateway-policy rejection:

   ```bash
   oc logs -n openshift-ingress \
     -l gateway.networking.k8s.io/gateway-name=maas-default-gateway --since=10m
   oc logs -n redhat-ods-applications deploy/maas-api --since=10m
   ```

## Upgrade And Redeploy Notes

- Re-run the schema checks after every RHOAI, RHCL, OpenShift, Gateway API, or
  Kuadrant upgrade.
- Keep quickstarts and blogs as implementation evidence, not API authority.
- If the provider model ID changes, choose a DNS-safe Kubernetes alias first
  and then set the exact provider model ID in `ExternalModel.spec.targetModel`.
- If model, prompt, GPU shape, vLLM arguments, or provider limits change,
  re-run the Stage 210/220 benchmark and update MaaS token limits from measured
  behavior.
- After each live issue, add the reusable lesson here before closing the stage.
