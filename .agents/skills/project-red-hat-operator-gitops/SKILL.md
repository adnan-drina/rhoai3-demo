---
name: project-red-hat-operator-gitops
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "red-hat"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Author, refactor, or review GitOps-managed Red Hat Operator installation
  patterns for rhoai3-demo using the Red Hat Community of Practice GitOps
  Catalog style: curated local Kustomize operator bases, channel overlays,
  Namespace, OperatorGroup, Subscription, instance resources, aggregate
  overlays, progressive RHOAI DataScienceCluster component patching, Argo CD
  Application ordering, sync options, operator readiness handoff, and
  GitOps-native Operator lifecycle management through Subscription channel and
  approval-strategy changes. Use when deploying or upgrading RHOAI, ODF, NFD,
  NVIDIA GPU Operator, OpenShift GitOps, cert-manager, Kueue, OpenTelemetry,
  Tempo, or other Red Hat Operators through GitOps, and for approved
  community-operator exceptions such as Grafana when support boundaries are
  documented. Do NOT use as product authority for Subscription channels, CR
  fields, API versions, or support posture; use official Red Hat docs, active
  cluster schema, and the matching rhoai-*, ocp-*, or odf-* skill. Do NOT
  reference the Community of Practice catalog directly as a remote base in
  committed GitOps; curate the pattern locally.
---

# Red Hat Operator GitOps

Use this skill to deploy Red Hat Operators through GitOps in a way that follows
the Red Hat Community of Practice GitOps Catalog pattern while remaining
curated, reproducible, and aligned with the active baseline in
`docs/PLATFORM_BASELINE.md`.

## Source Grounding

Read `references/source-capture.md` first. The Red Hat CoP GitOps Catalog is an
implementation pattern source, not product support authority. Official Red Hat
product documentation and cluster schema verification remain authoritative for
operator channels, operands, CR fields, API versions, namespaces, and support
posture. Use `references/operator-lifecycle.md` for the GitOps-native lifecycle
model for install, update, approval, verification, rollback, and drift.

## Catalog Pattern

Adopt the pattern, not the external repository reference:

```text
<operator>/
  operator/
    base/
      namespace.yaml
      operator-group.yaml
      subscription.yaml
      kustomization.yaml
    overlays/
      <channel>/
        patch-channel.yaml
        kustomization.yaml
  instance/
    base/
    components/
    overlays/
      <profile>/
  aggregate/
    overlays/
      <profile>/
```

The `operator/base` layer declares the OLM installation primitives with a
placeholder channel. The `operator/overlays/<channel>` layer patches the
Subscription channel. The `instance` layer holds operand custom resources after
the operator is installed. The `aggregate` layer combines the selected operator
overlay and instance overlay for a profile such as `fast`, `fast-nvidia-gpu`,
or `aws`.

Lifecycle changes are also Git changes. A channel move, approval-strategy
change, or product baseline upgrade should update the operator overlay and the
project baseline in Git, then let Argo CD reconcile the Subscription and let OLM
create the required InstallPlan and CSV. Do not patch Subscriptions directly in
the cluster as the normal upgrade path.

For RHOAI specifically, follow the CoP `openshift-ai/instance` pattern:

- `instance/base` owns the baseline `DSCInitialization`, `DataScienceCluster`,
  RHOAI applications namespace, and dashboard config.
- `instance/components/<feature>` uses Kustomize `kind: Component` plus
  minimal patches that target the same `DataScienceCluster` or
  `DSCInitialization`.
- `instance/overlays/<profile>` includes `../../base` and composes feature
  components such as serving, distributed compute, training, TrustyAI, model
  registry, dashboard access, and NVIDIA accelerator profile.
- The same Argo CD Application should own the rendered DSC/DSCI objects. Later
  demo stages should add component patches to that platform overlay instead of
  creating separate Applications that also manage the same DSC/DSCI resources.

## Demo Rules

- Curate catalog-inspired manifests into this repo; do not commit remote
  Kustomize bases that point directly to `redhat-cop/gitops-catalog`.
- Keep `base/` reusable and environment-neutral. Put operator channel,
  provider, platform, or profile choices in overlays.
- For the current demo posture, RHOAI Operator channel selection belongs to
  `rhoai-update-channels`; ODF channel selection belongs to the ODF baseline
  and `odf-storagecluster`.
- Keep lifecycle policy in Git: Subscription channel, catalog source, source
  namespace, install-plan approval strategy, and any deliberate `startingCSV`
  exception.
- Keep operator-managed images operator-owned. Do not pin images solely for
  repeatability; Red Hat Operators carry the operational knowledge needed to
  install, configure, and manage platform components repeatably. Explicit image
  tags or digests are exceptions that require Red Hat documentation, validated
  artifact guidance, or a documented non-operator demo-app exception.
  Generated operand images, CSV `relatedImages`, copied CSVs, and
  operator-created Deployments are diagnostic data, not desired GitOps state.
- Prefer automatic approval for the regular feature-forward demo path when
  product docs and environment constraints allow it. Use manual approval only
  when official docs require it or the demo deliberately needs a human gate.
- Do not apply `operator/base` directly when the channel is intentionally
  patched by overlays.
- Keep operator install resources separate from operand instance resources
  unless a temporary aggregate overlay is needed for a single Argo CD
  Application.
- For RHOAI, start with a minimal base DSC/DSCI deployment in the first demo
  platform stage. Later stages introduce capabilities by adding local Kustomize
  Components or patches that update the same platform-owned
  `DataScienceCluster`.
- Avoid duplicating the full `DataScienceCluster` in every demo stage. Duplicate
  full-resource ownership can cause Argo CD ownership conflicts and can remove
  previously enabled components.
- Prefer separate Argo CD Applications for operator install and instance
  resources when CRDs must exist before operand CRs render or dry-run cleanly.
- Use Argo CD sync waves, retries, and `SkipDryRunOnMissingResource=true` for
  operator/operand sequencing; use `project-gitops-authoring` for exact
  Application standards.
- Treat channel downgrades and generic Git rollback of Operator upgrades as
  product-specific recovery work, not a guaranteed downgrade mechanism. Check
  official docs and current CSV/operand health before rollback claims.
- Any cluster-scoped RBAC, console plugin enablement job, node labeler job, or
  privileged helper from a catalog pattern must be reviewed with the matching
  OCP skill before it is accepted into this repo.

## Workflow

1. Confirm the active platform baseline in `docs/PLATFORM_BASELINE.md`.
2. Identify the product owner skill:
   - RHOAI Operators and operands: `rhoai-*`
   - ODF Operator and operands: `odf-*`
   - OCP platform Operators, RBAC, routes, storage, images: `ocp-*`
3. Read `references/catalog-pattern.md`.
4. Read `references/operator-lifecycle.md` when adding or changing a
   Subscription, channel overlay, install-plan policy, product baseline, or
   Operator upgrade procedure.
5. Create or update a local curated operator layout with:
   - `operator/base`
   - `operator/overlays/<channel>`
   - `instance/base`
   - optional `instance/components`
   - optional `instance/overlays/<profile>`
   - optional `aggregate/overlays/<profile>`
6. For RHOAI, decide the progressive DSC owner path before adding stages:
   - base DSC/DSCI in the first RHOAI platform stage
   - later component patches under the same platform instance tree
   - one Argo CD Application owning the final rendered DSC/DSCI
7. For Argo CD, choose whether the operator and operand are separate
   Applications or a single aggregate Application. Prefer separate
   Applications when CRD ordering is material.
8. Verify Subscription channel, package name, catalog source, namespace,
   OperatorGroup shape, install-plan approval, and CR fields against official
   docs or live schema.
9. Before changing any image field, classify ownership:
   - repo-owned workload, hook, model, pipeline, or demo-app image
   - official CR field documented as a supported operand image override
   - operator-generated operand image or copied lifecycle state
10. For upgrades, plan the GitOps lifecycle sequence:
   - update `docs/PLATFORM_BASELINE.md` when the product baseline changes
   - update channel overlays or approval strategy in Git
   - sync the operator Application before operand CR changes
   - validate Subscription, InstallPlan, CSV, CRDs, and operand readiness
11. Validate the rendered manifests and review with
   `references/validation-checklist.md`.

## Related Skills

- Use `project-gitops-authoring` for repo-specific Argo CD Application,
  Kustomize, sync-wave, targetRevision, and label conventions.
- Use `project-manifest-review` for read-only manifest review.
- Use `project-red-hat-doc-alignment-review` before accepting product image,
  channel, CR, or configuration claims.
- Use `rhoai-self-managed-installation`, `rhoai-update-channels`,
  `rhoai-dsci-dsc-configuration`, and related RHOAI component skills for
  RHOAI Operator and operand details.
- Use `rhoai-nvidia-gpu-accelerators` and `ocp-machine-management` for NVIDIA
  GPU Operator, ClusterPolicy, AWS GPU MachineSet, MachineAutoscaler, and
  RHOAI hardware-profile handoff details.
- Use `ocp-node-feature-discovery` for NFD Operator, NodeFeatureDiscovery,
  feature-label, topology updater, and NVIDIA-only discovery overlay details.
- Use `ocp-grafana-operator` for GitOps-managed Grafana Operator, Grafana
  instance, datasource, dashboard, OAuth route, and monitoring-access details.
- Use `odf-storagecluster`, `odf-multicloud-gateway`, and
  `odf-object-bucket-claims` for ODF details.
- Use `ocp-security-rbac-scc`, `ocp-image-registry-and-mirroring`,
  `ocp-ingress-gateway-routes`, and `ocp-gitops-operator` for OCP platform
  concerns.

## References

- `references/source-capture.md`
- `references/catalog-pattern.md`
- `references/operator-lifecycle.md`
- `references/validation-checklist.md`
- `examples/operator-layout.md`
