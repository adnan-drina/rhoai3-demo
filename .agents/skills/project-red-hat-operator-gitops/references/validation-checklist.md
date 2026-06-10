# Validation Checklist

Use this checklist before accepting GitOps-managed Red Hat Operator resources.

## Source Validation

- The active product baseline is read from `docs/PLATFORM_BASELINE.md`.
- The Red Hat CoP GitOps Catalog is used only as a pattern source.
- Official OCP Operator lifecycle docs are used for Subscription, InstallPlan,
  CSV, channel, approval, and OLM behavior.
- Operator package name, channel, catalog source, and namespace are verified
  against official Red Hat docs, package metadata, or live cluster schema.
- Operand CR fields are verified against official docs or `oc explain`.
- Any catalog-derived helper job or RBAC is reviewed with the matching OCP
  security skill.

## Kustomize Review

- `operator/base` is reusable and does not encode environment-specific channel
  choices.
- `operator/overlays/<channel>` patches the Subscription channel.
- `instance/base` and `instance/overlays/<profile>` are separated from
  operator install resources.
- Optional components are modeled as Kustomize Components or small patches.
- For RHOAI, there is a single GitOps owner for the rendered
  `DataScienceCluster` and `DSCInitialization`.
- Later RHOAI demo steps patch the platform-owned DSC overlay instead of
  creating competing full DSC resources in separate Applications.
- Component patches are minimal and do not reset unrelated
  `spec.components` entries.
- Aggregate overlays select the intended channel and profile.
- No committed Kustomize resource references
  `github.com/redhat-cop/gitops-catalog`.

## Lifecycle Review

- Subscription channel, source, source namespace, package name, and
  `installPlanApproval` are represented in Git.
- Channel changes are made through `operator/overlays/<channel>` patches or
  selected overlay paths, not direct live `oc patch` commands.
- `installPlanApproval: Automatic` is intentional and matches the product
  posture; `Manual` is used only when required or deliberately documented.
- Generated InstallPlans, CSVs, and copied CSVs are not committed as desired
  state.
- `startingCSV` is absent unless official docs or a controlled install plan
  require it.
- Product baseline changes update `docs/PLATFORM_BASELINE.md` in the same
  lifecycle work.
- Operator Application sync happens before operand CR fields that depend on
  new CRDs or schema.
- Rollback language does not claim that reverting Git will downgrade an
  already-upgraded Operator.

## Argo CD Review

- Operator and operand ordering is explicit through sync waves or separate
  Applications.
- Applications use project-standard labels, annotations, target revisions, and
  sync options from `project-gitops-authoring`.
- `SkipDryRunOnMissingResource=true` is used only where CRDs can be absent
  during first sync.
- Retry/backoff is configured for operator readiness.

## Local Validation Commands

Run these from the repo root:

```sh
kustomize build gitops/<path-to-operator-overlay>
kustomize build gitops/<path-to-instance-overlay>
kustomize build gitops/<path-to-aggregate-overlay>
rg -n 'github.com/redhat-cop/gitops-catalog' gitops
rg -n '^kind: DataScienceCluster$|^kind: DSCInitialization$' gitops
```

Run these only after the OpenShift safety guard confirms the target cluster:

```sh
oc get packagemanifest -n openshift-marketplace <operator-package> -o yaml
oc get subscription,installplan,csv -A
oc explain subscription.operators.coreos.com.spec
oc describe subscription -n <operator-namespace> <subscription-name>
```

For operand validation, use the product-specific CRDs:

```sh
oc explain datasciencecluster.spec
oc explain dscinitialization.spec
oc explain storagecluster.spec
oc explain objectbucketclaim.spec
```
