# Argo CD And Kustomize Standards

Use these standards when authoring or changing `gitops/**`,
`kustomization.yaml`, Argo CD Applications, or per-step deployment flow.

## Golden Rule

Every demo step must be reproducible from GitOps. A step normally has:

1. `gitops/step-XX-name/base/` as the Kustomize source of truth.
2. `gitops/argocd/app-of-apps/step-XX-name.yaml` as its Argo CD Application.
3. `steps/step-XX-name/` as the human-facing documentation and runtime wrapper.

Do not manage Argo CD-owned resources through direct imperative manifest
application except for documented prerequisites such as locally supplied
secrets.

For a new step, use `project-demo-step-authoring` first. That process records
whether the step owns an independent GitOps path or patches a shared platform
owner before any manifests are written.

## Repository Layout

Use the split layout:

```text
gitops/
  argocd/app-of-apps/
  step-XX-name/base/
  step-XX-name/overlays/<purpose>/
steps/
  step-XX-name/
scripts/
docs/
```

## Kustomize Structure

- Prefer `base/` plus `overlays/<env-or-purpose>/` within each step.
- Keep `base/` environment agnostic.
- Put environment-specific deltas in overlays.
- Avoid duplicating full resources across overlays; use patches.
- Prefer `resources:` plus `patches:` with minimal diffs.
- Use consistent naming and labels so rendered output is easy to inspect.

## Shared Platform Resource Ownership

Some platform resources are global for the demo even when later steps depend
on them. Examples include RHOAI `DataScienceCluster`, `DSCInitialization`,
cluster-scoped Operator Subscriptions, ODF `StorageCluster`, and shared
Gateway or observability resources.

Do not let multiple Argo CD Applications render competing full copies of the
same shared resource. Pick one owning path and evolve that path through patches
or Kustomize Components.

For RHOAI, follow the `project-red-hat-operator-gitops` pattern:

- step 1 creates the base RHOAI Operator and minimal DSC/DSCI platform layer
- later demo steps add feature components that patch the platform-owned
  `DataScienceCluster`
- the same Argo CD Application owns the rendered DSC/DSCI objects throughout
  the demo

## Operator Lifecycle Changes

Treat Red Hat Operator lifecycle as GitOps state. Subscription channel,
catalog source, source namespace, package name, and install-plan approval
strategy should be changed through the operator Kustomize base or selected
channel overlay, then reconciled by Argo CD. Do not use live `oc patch
subscription` or web console channel edits as the normal upgrade path.

For regular demo updates, the Git-managed Subscription can use automatic
approval when product docs allow it. For controlled upgrades, change the
channel overlay and product baseline in Git, sync the operator Application
first, validate Subscription/InstallPlan/CSV/CRD readiness, and only then
change operand CR patches that require the new schema.

## Naming

- Step folders: `step-XX-descriptive-name`
- Overlays: `overlays/<purpose>`
- Operator folders: group by operator name, such as `nfd/`, `gpu-operator/`,
  or `rhoai-operator/`

## Argo CD Application Standards

All Applications must use `project: rhoai-demo`, not `default`.

Every Application in `gitops/argocd/app-of-apps/` must include:

```yaml
metadata:
  labels:
    app.kubernetes.io/part-of: rhoai3-demo
    demo.rhoai.io/step: "XX"
  annotations:
    argocd.argoproj.io/sync-wave: "<step-number * 10>"
    argocd.argoproj.io/manifest-generate-paths: gitops/step-XX-name
```

`manifest-generate-paths` prevents unrelated step changes from causing
unnecessary reconciliation.

## Revision Policy

- Active development can use `targetRevision: main`.
- Demo releases should use a tag, such as `v1.0`.
- Never use `HEAD` as an Application target revision.

## Sync Policy

Required pattern:

| Setting | Value | Why |
|---------|-------|-----|
| `automated.prune` | `true` | Remove resources deleted from Git |
| `automated.selfHeal` | `true` by default | Revert drift; steps 01 and 05 may disable it for intentional scale operations |
| `retry.limit` | `10` | Operators need time to install CRDs |
| `retry.backoff` | `5s`, factor `2`, max `3m` | Exponential backoff |
| `SkipDryRunOnMissingResource` | `true` | CRDs may not exist at first sync |
| `ServerSideDiff` | `true` | Accurate diff for custom resources |
| `RespectIgnoreDifferences` | `true` | Enables ignoreDifferences with ServerSideDiff |

Avoid `ServerSideApply=true` because it can break sync-wave behavior. Avoid
`Replace=true` because it can break PVCs.

## Universal Ignore Differences

PVC specs are immutable after creation and clusters add fields such as
`storageClassName` and `volumeName`. Applications should ignore PVC `/spec`
differences where applicable:

```yaml
ignoreDifferences:
  - group: ""
    kind: PersistentVolumeClaim
    jsonPointers:
      - /spec
```

## Resource Tracking

The project bootstrap configures Argo CD `resourceTrackingMethod` as
`annotation`. Keep it as annotation-only to avoid false OutOfSync status from
operator-generated OpenShift resources.

## References

- Current RHOAI baseline DSPA docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_ai_pipelines/
- Current OCP baseline GitOps docs: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/gitops/index
- OCP GitOps platform skill: `.agents/skills/ocp-gitops-operator/SKILL.md`
- Argo CD sync options: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/
