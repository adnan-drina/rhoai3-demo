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
- `DataScienceCluster` has KServe managed and MaaS enabled through the
  documented `modelsAsService` path.
- User Workload Monitoring is enabled.
- Red Hat Connectivity Link Operator is installed.
- `Kuadrant` in `kuadrant-system` is ready.
- The MaaS Gateway API resources and annotations are present.
- Authorino TLS and service CA trust are configured.
- `maas-db-config` exists in `redhat-ods-applications` with
  `DB_CONNECTION_URL` stored as a Secret value.
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
- Each subscription includes at least one token rate limit per model ref and a
  supported time window such as seconds, minutes, or hours.
- Subscription priority is intentional when groups overlap.
- Metering metadata is included on authorization policies when showback or
  cost-center reporting is claimed.
- Authorization policy subjects match the intended groups/users and model refs.

## API Key And Access Review

- Users have both subscription quota and gateway authorization before access is
  claimed.
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
oc get kuadrant kuadrant -n kuadrant-system
oc get gatewayclass
oc get gateway maas-default-gateway -n openshift-ingress -o yaml
oc get secret maas-db-config -n redhat-ods-applications
oc get tenants.maas.opendatahub.io -n models-as-a-service
oc get tenants.maas.opendatahub.io default-tenant -n models-as-a-service -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
oc get maasmodelrefs -A
oc get maassubscriptions -A
oc get maasauthpolicies -A
oc get externalmodels.maas.opendatahub.io -A
```

Use schema checks before durable GitOps authoring:

```bash
oc explain maasmodelrefs.models.opendatahub.io.spec
oc explain maassubscriptions.models.opendatahub.io.spec
oc explain maasauthpolicies.models.opendatahub.io.spec
oc explain externalmodels.maas.opendatahub.io.spec
oc explain tenants.maas.opendatahub.io.spec
```

## Failure Conditions

Do not approve a MaaS change when:

- a README claims governed model access but GitOps lacks matching
  subscription and authorization policy
- the implementation bypasses MaaS for shared OpenAI `gpt-5` demo access
  without an explicit documented exception
- provider API keys or MaaS API keys appear in repository files
- token limits are absent from a model subscription
- preview features are described as generally available
- external provider limits are ignored in capacity planning
- stale API keys remain after a group removal where immediate revocation is
  required
- exact CR fields are copied from memory instead of official docs or installed
  schema
