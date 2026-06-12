# Validation Checklist

Use this checklist when authoring docs, GitOps, runbooks, or troubleshooting
notes for Models-as-a-Service.

## Source And Scope

- The work references `docs/PLATFORM_BASELINE.md` and the RHOAI 3.4 MaaS
  guide, not an unversioned latest documentation path.
- MaaS is used only for governed shared model access, not as a replacement for
  direct single-user model serving.
- Technology Preview features are labeled: vLLM with MaaS, external models,
  external OIDC authentication, and the MaaS observability dashboard.
- API support posture is checked with `rhoai-api-tiers` before making upgrade
  durability claims.

## Prerequisites

- OpenShift and RHOAI versions satisfy the active baseline.
- If MaaS CRDs are absent, the implementation is split into a prerequisite
  phase before model-publication and policy resources are committed.
- `DataScienceCluster` has KServe managed and MaaS enabled through the
  documented `modelsAsService` path.
- User Workload Monitoring is enabled.
- cert-manager Operator for Red Hat OpenShift is installed and the
  `CertManager` cluster resource exists when RHCL requires cert-manager.
- Red Hat Connectivity Link Operator is installed at the pinned MaaS-compatible
  CSV for the active demo baseline.
- `Kuadrant` in `kuadrant-system` is ready.
- The MaaS Gateway API resources and annotations are present.
- The MaaS Gateway TLS Secret exists in the same namespace as the Gateway
  before the Gateway resource is applied; for this demo the stable Secret name
  is `maas-gateway-tls` in `openshift-ingress`, generated from the active
  OpenShift ingress certificate by a GitOps sync hook.
- Authorino TLS and service CA trust are configured.
- `maas-db-config` exists in `redhat-ods-applications` with
  `DB_CONNECTION_URL` stored as a Secret value.
- Demo-local PostgreSQL is clearly labeled as demo posture. Production guidance
  should use an operationally managed PostgreSQL 14+ database.
- Dashboard flags are enabled only for features the demo actually uses.

## Resource Review

- `Tenant`, `MaaSModelRef`, `ExternalModel`, `MaaSSubscription`, and
  `MaaSAuthPolicy` manifests use fields confirmed by official docs or
  installed CRD schema.
- Resource namespaces match the active controller behavior and are not guessed
  from mixed examples.
- Each published local model has a healthy underlying serving resource before
  it is exposed through MaaS.
- Each external model has a provider Secret, provider endpoint, target model
  ID, subscription, authorization policy, and explicit Technology Preview
  label.
- External model resource names are valid DNS-1035 labels because the MaaS
  controller creates Kubernetes Services from the `ExternalModel` name. Keep
  provider model IDs containing dots in `spec.targetModel`, not in
  `metadata.name`.
- Each subscription includes at least one token rate limit per model ref and a
  supported time window such as seconds, minutes, or hours.
- Subscription priority is intentional when groups overlap.
- Metering metadata is included on authorization policies when showback or
  cost-center reporting is claimed.
- Authorization policy subjects match the intended groups/users and model refs.

## API Key And Access Review

- Users have both subscription quota and gateway authorization before access is
  claimed.
- Dashboard and Gateway discovery are validated with real demo user tokens, not
  inferred from MaaS CR readiness. The RHOAI dashboard
  `/gen-ai/api/v1/maas/models` path and the Gateway
  `/maas-api/v1/subscriptions` path must return usable model/subscription data
  for an allowed user before claiming the AI asset endpoints experience.
- The Gateway/AuthPolicy path injects `X-MaaS-Username` and `X-MaaS-Group` into
  `maas-api` requests. If `maas-api` logs `Missing or empty username header`,
  investigate Kuadrant/AuthPolicy/EnvoyFilter behavior before changing MaaS
  model or subscription CRs. Do not codify patches against generated Kuadrant
  `AuthPolicy` or EnvoyFilter resources unless official Red Hat documentation
  or support guidance requires that exact change.
- API keys are never committed or embedded in notebooks/manifests.
- Persistent keys are stored in an approved secret store.
- API key expiration limits are documented and align with the `Tenant` max.
- Group membership changes include API key revocation/recreation guidance when
  immediate access change is required.
- External OIDC users use MaaS API key management flows rather than dashboard
  flows.

## Observability Review

- Kuadrant observability is enabled before claiming rate-limit metrics.
- `Tenant` telemetry is enabled before claiming MaaS model-usage metrics.
- Dashboard observability is labeled Technology Preview.
- Showback language is used instead of billing-grade metering or external
  invoicing claims.
- Privacy-sensitive telemetry fields such as user and group capture are
  reviewed before enablement.

## Readonly Verification Commands

Run only after the OpenShift safety guard in `AGENTS.md` is satisfied:

```bash
oc get dsc default-dsc -n redhat-ods-operator -o yaml
oc get odhdashboardconfig -n redhat-ods-applications
oc get certmanager cluster
oc get deployment cert-manager cert-manager-cainjector cert-manager-webhook -n cert-manager
oc get subscription rhcl-operator -n openshift-operators
oc get subscription rhcl-operator -n openshift-operators \
  -o jsonpath='{.spec.installPlanApproval}{" "}{.spec.startingCSV}{" "}{.status.installedCSV}{"\n"}'
oc get kuadrant kuadrant -n kuadrant-system
oc get authorino authorino -n kuadrant-system
oc get gatewayclass
oc get secret maas-gateway-tls -n openshift-ingress
oc get gateway maas-default-gateway -n openshift-ingress -o yaml
oc get secret maas-db-config -n redhat-ods-applications
oc api-resources | grep -i maas
oc get crd maasauthpolicies.maas.opendatahub.io \
  maasmodelrefs.maas.opendatahub.io \
  maassubscriptions.maas.opendatahub.io \
  externalmodels.maas.opendatahub.io \
  tenants.maas.opendatahub.io
oc get tenants.maas.opendatahub.io -n models-as-a-service
oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
oc get maasmodelrefs -A
oc get maassubscriptions -A
oc get maasauthpolicies -A
oc get externalmodels.maas.opendatahub.io -A
oc get authpolicy,tokenratelimitpolicy -n models-as-a-service
oc get envoyfilter -n openshift-ingress
oc logs -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway --since=10m
oc logs -n redhat-ods-applications deploy/maas-api --since=10m
```

Use schema checks before durable GitOps authoring:

```bash
oc explain maasmodelrefs.maas.opendatahub.io.spec
oc explain maassubscriptions.maas.opendatahub.io.spec
oc explain maasauthpolicies.maas.opendatahub.io.spec
oc explain externalmodels.maas.opendatahub.io.spec
oc explain tenants.maas.opendatahub.io.spec
```

If `oc api-resources` reports `MaaSModelRef`, `MaaSSubscription`, or
`MaaSAuthPolicy` under a group other than `maas.opendatahub.io`, use the
installed group/version for schema validation and record the discrepancy in the
stage `PLAN.md`.

## Failure Conditions

Do not approve a MaaS change when:

- a README claims governed model access but GitOps lacks matching
  subscription and authorization policy
- the implementation bypasses MaaS for shared OpenAI `gpt-5.4-mini` demo access
  without an explicit documented exception
- provider API keys or MaaS API keys appear in repository files
- token limits are absent from a model subscription
- preview features are described as generally available
- external provider limits are ignored in capacity planning
- stale API keys remain after a group removal where immediate revocation is
  required
- exact CR fields are copied from memory instead of official docs or installed
  schema
- dashboard AI asset endpoints cannot load MaaS models for an allowed user
- `maas-api` reports missing `X-MaaS-Username` or `X-MaaS-Group` headers on
  Gateway-routed requests
