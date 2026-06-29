# Argo CD And Kustomize Standards

Use these standards when authoring or changing `gitops/**`,
`kustomization.yaml`, Argo CD Applications, or per-stage deployment flow.

## Golden Rule

Every demo stage must be reproducible from GitOps. A stage normally has:

1. `gitops/stage-YXX-slug/base/` as the Kustomize source of truth.
2. `gitops/argocd/app-of-apps/stage-YXX-slug.yaml` as its Argo CD Application.
3. `stage-YXX-slug/` as the root-level documentation and runtime wrapper.

Do not manage Argo CD-owned resources through direct imperative manifest
application except for documented prerequisites such as locally supplied
secrets.

For a new stage, use `project-demo-stage-authoring` first. That process records
whether the stage owns an independent GitOps path or patches a shared platform
owner before any manifests are written.

## Repository Layout

Use the split layout:

```text
gitops/
  argocd/app-of-apps/
  stage-YXX-slug/base/
  stage-YXX-slug/overlays/<purpose>/
stage-YXX-slug/
scripts/
docs/
```

## Kustomize Structure

- Prefer `base/` plus `overlays/<env-or-purpose>/` within each stage.
- Keep `base/` environment agnostic.
- Put environment-specific deltas in overlays.
- Avoid duplicating full resources across overlays; use patches.
- Prefer `resources:` plus `patches:` with minimal diffs.
- Use consistent naming and labels so rendered output is easy to inspect.

### Namespace Override Trap

Never set a global `namespace:` field in an overlay kustomization when the
resource set spans multiple namespaces. A top-level `namespace:` silently
overrides every resource in the rendered output, including resources that must
stay in a different namespace.

Common bootstrap case: the GitOps operator `Subscription` must remain in
`openshift-operators`, while `ArgoCD` and `AppProject` resources belong in
`openshift-gitops`. Adding `namespace: openshift-gitops` at the kustomization
root moves the Subscription to the wrong namespace, breaking OLM installation.

Instead, set `namespace:` inline in each manifest:

```yaml
# Correct — no global namespace override
resources:
  - ../../base             # Subscription has namespace: openshift-operators inline
  - argocd-instance.yaml  # ArgoCD CR has namespace: openshift-gitops inline
  - argocd-project.yaml   # AppProject has namespace: openshift-gitops inline
```

Verify the rendered output with `kustomize build <path>` before applying.

## Shared Platform Resource Ownership

Some platform resources are global for the demo even when later stages depend
on them. Examples include RHOAI `DataScienceCluster`, `DSCInitialization`,
cluster-scoped Operator Subscriptions, ODF `StorageCluster`, and shared
Gateway or observability resources.

Do not let multiple Argo CD Applications render competing full copies of the
same shared resource. Pick one owning path and evolve that path through patches
or Kustomize Components.

For RHOAI, follow the `project-red-hat-operator-gitops` pattern:

- the foundation RHOAI stage creates the base Operator and minimal DSC/DSCI
  platform layer
- later demo stages add feature components that patch the platform-owned
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

### Manual Pin Health

When a stage intentionally pins an Operator `Subscription` to a specific CSV
with `installPlanApproval: Manual`, Argo CD or OLM can report upgrade-related
conditions when newer InstallPlans exist. Do not treat a newer unapproved plan
as permission to auto-upgrade a compatibility-sensitive component.

For a manually pinned operator, the meaningful stage gate is:

- `spec.installPlanApproval` is `Manual`
- `spec.startingCSV` is the expected pinned CSV
- `status.installedCSV` equals the expected pinned CSV
- only the intended InstallPlan is approved by GitOps automation
- CRDs and user-visible functional validation pass after the CSV is installed

If Argo CD needs custom health behavior for the pinned Subscription, document
the reason and keep validation focused on `installedCSV`, CRD readiness, and
the user-visible capability. Do not hide an actual CSV mismatch with a custom
health rule.

## Naming

- Stage folders: `stage-YXX-descriptive-slug`
- Stage families: `1xx` AI Platform Foundation, `2xx` Production GenAI and
  Private Data, `3xx` Agentic AI and Enterprise Integration, `4xx` AI
  Operations, Evaluation, and MLOps. Use `5xx` only for a separate edge or
  applied AI track.
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
    demo.rhoai.io/stage: "YXX"
  annotations:
    argocd.argoproj.io/sync-wave: "<stage-number>"
    argocd.argoproj.io/manifest-generate-paths: gitops/stage-YXX-slug
```

`manifest-generate-paths` prevents unrelated stage changes from causing
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
| `automated.selfHeal` | `true` by default | Revert drift; specific stages may disable it only for documented intentional scale operations |
| `retry.limit` | `10` | Operators need time to install CRDs |
| `retry.backoff` | `5s`, factor `2`, max `3m` | Exponential backoff |
| `SkipDryRunOnMissingResource` | `true` | CRDs may not exist at first sync |
| `ServerSideDiff` | `true` | Accurate diff for custom resources |
| `RespectIgnoreDifferences` | `true` | Enables ignoreDifferences with ServerSideDiff |

Avoid `ServerSideApply=true` because it can break sync-wave behavior. Avoid
`Replace=true` because it can break PVCs.

## Sync Wave Health Traps

Argo CD evaluates resource health as it advances through waves. A resource that
needs another later-wave resource to become healthy can deadlock the rollout.
Review these patterns before adding new waves:

- A Service that Argo CD health-checks must be created in the same wave as the
  first Deployment or StatefulSet that provides its endpoints, unless the
  Application has a documented health override. Stage 220 learned this with
  `service/maas-postgres` and `statefulset/maas-postgres`.
- Token Secrets for service accounts require the referenced `ServiceAccount` to
  exist first. If an operator can create the service account eventually, that
  is still too late for Argo CD ordering. GitOps-manage the service account
  explicitly when a token Secret or RBAC binding references it.
- CRD-dependent resources belong after the operator/CRD wave or in a separate
  Application with `SkipDryRunOnMissingResource=true`. Do not let a foundation
  stage render later-stage custom resources before the owning operator and
  feature component exist.
- Shared singleton resources, especially `DataScienceCluster`, need one clear
  owner. Later stages should patch the owning path or use controlled hooks; do
  not render competing full copies from multiple Applications.

When a sync appears stuck, inspect both the Argo CD Application operation state
and the health of resources in earlier waves before changing product manifests.

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

## Bootstrap Instance CR Pattern

When bootstrapping the ArgoCD instance via Kustomize, include the full `ArgoCD`
CR as a `resources:` entry — never as a `patches:` target. Kustomize can only
patch resources that exist in the rendered resource set. The `ArgoCD` CR is
created by the OpenShift GitOps operator after the operator installs, so it is
not present in the Kustomize base tree and cannot be patched.

The correct pattern (used by the Red Hat AI Accelerator in `instance/base/`) is
to provide a complete `ArgoCD` manifest with all required settings inline:

```yaml
# gitops/bootstrap/overlays/demo/argocd-instance.yaml
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  resourceTrackingMethod: annotation   # project-required
  rbac:
    policy: |
      g, system:cluster-admins, role:admin
    scopes: '[groups]'
  server:
    route:
      enabled: true
  sso:
    dex:
      openShiftOAuth: true
    provider: dex
```

Add it to `resources:` in the kustomization:

```yaml
resources:
  - ../../base
  - argocd-instance.yaml   # full CR, not a patch
  - argocd-project.yaml
```

The OpenShift GitOps operator reconciles from the existing `ArgoCD` CR once it
is present on the cluster.

### Two-Phase Bootstrap Apply

The operator Subscription and the `ArgoCD`/`AppProject` resources cannot be
applied in one step. Split the bootstrap into two overlays applied in order:

1. `overlays/operator/` — the operator `Subscription` with the baseline-pinned
   channel (base carries a placeholder channel). Apply this first and wait for
   the operator CSV to reach `Succeeded`.
2. `overlays/demo/` — the `ArgoCD` instance config and `AppProject`. These
   depend on CRDs (`argoproj.io`) that exist only after the operator installs,
   so apply them only after phase 1 completes.

Applying a single combined overlay deadlocks: the placeholder channel never
installs the operator, and the `ArgoCD`/`AppProject` resources fail because
their CRDs do not yet exist. Never apply `bootstrap/base` directly — its channel
is intentionally a placeholder patched by `overlays/operator`.

## Bootstrap Script Portability

Per-stage `deploy.sh`/`validate.sh` run on operator (macOS) and CI machines.
Two portability rules learned from stage-110:

- **Export `.env` values.** Source `.env` inside `set -a` / `set +a` so values
  like `KUBECONFIG` and `RHOAI_EXPECTED_API_SERVER` are exported to `oc` child
  processes. A plain `source .env` sets shell variables only; `oc` then falls
  back to the default kubeconfig, which may point at a stale or wrong cluster.
  The safety guard will (correctly) refuse to run, but the real fix is exporting.
- **Do not depend on GNU `timeout`.** macOS does not ship `timeout`. Use a
  portable bash wait loop driven by the `SECONDS` builtin and a deadline check
  instead of `timeout N bash -c '...'`.

## References

- Current RHOAI baseline DSPA docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_ai_pipelines/
- Current OCP baseline GitOps docs: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/gitops/index
- OCP GitOps platform skill: `.agents/skills/ocp-gitops-operator/SKILL.md`
- Argo CD sync options: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/
