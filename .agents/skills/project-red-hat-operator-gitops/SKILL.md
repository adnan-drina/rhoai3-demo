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
  overlays, Argo CD Application ordering, sync options, and operator readiness
  handoff. Use when deploying RHOAI, ODF, NFD, NVIDIA GPU Operator, OpenShift
  GitOps, cert-manager, Kueue, OpenTelemetry, Tempo, or other Red Hat
  Operators through GitOps. Do NOT use as product authority for Subscription
  channels, CR fields, API versions, or support posture; use official Red Hat
  docs and the matching rhoai-*, ocp-*, or odf-* skill. Do NOT reference the
  Community of Practice catalog directly as a remote base in committed GitOps;
  curate the pattern locally.
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
posture.

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

## Demo Rules

- Curate catalog-inspired manifests into this repo; do not commit remote
  Kustomize bases that point directly to `redhat-cop/gitops-catalog`.
- Keep `base/` reusable and environment-neutral. Put operator channel,
  provider, platform, or profile choices in overlays.
- For the current demo posture, RHOAI Operator channel selection belongs to
  `rhoai-update-channels`; ODF channel selection belongs to the ODF baseline
  and `odf-storagecluster`.
- Do not apply `operator/base` directly when the channel is intentionally
  patched by overlays.
- Keep operator install resources separate from operand instance resources
  unless a temporary aggregate overlay is needed for a single Argo CD
  Application.
- Prefer separate Argo CD Applications for operator install and instance
  resources when CRDs must exist before operand CRs render or dry-run cleanly.
- Use Argo CD sync waves, retries, and `SkipDryRunOnMissingResource=true` for
  operator/operand sequencing; use `project-gitops-authoring` for exact
  Application standards.
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
4. Create or update a local curated operator layout with:
   - `operator/base`
   - `operator/overlays/<channel>`
   - `instance/base`
   - optional `instance/components`
   - optional `instance/overlays/<profile>`
   - optional `aggregate/overlays/<profile>`
5. For Argo CD, choose whether the operator and operand are separate
   Applications or a single aggregate Application. Prefer separate
   Applications when CRD ordering is material.
6. Verify Subscription channel, package name, catalog source, namespace,
   OperatorGroup shape, install-plan approval, and CR fields against official
   docs or live schema.
7. Validate the rendered manifests and review with
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
- Use `odf-storagecluster`, `odf-multicloud-gateway`, and
  `odf-object-bucket-claims` for ODF details.
- Use `ocp-security-rbac-scc`, `ocp-image-registry-and-mirroring`,
  `ocp-ingress-gateway-routes`, and `ocp-gitops-operator` for OCP platform
  concerns.

## References

- `references/source-capture.md`
- `references/catalog-pattern.md`
- `references/validation-checklist.md`
- `examples/operator-layout.md`
