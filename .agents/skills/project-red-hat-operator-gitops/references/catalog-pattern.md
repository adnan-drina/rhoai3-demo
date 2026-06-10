# Catalog Pattern Extraction

Use this extraction when creating local GitOps for Red Hat Operator
installations.

## Base And Overlay Split

The reusable operator base should contain OLM primitives:

- Namespace
- OperatorGroup
- Subscription
- optional catalog-supported helper resources such as a console plugin
  enablement job, only when the helper is still needed and reviewed

The base can use a placeholder channel only if every deployable path goes
through a channel overlay. Do not deploy a placeholder-channel base directly.

The channel overlay should:

- include `../../base`
- patch only the Subscription channel unless the official docs require more
  differences
- use a name that matches the selected channel, such as `fast-3.x` or
  `stable-4.20`

## Instance Split

Operator operands should live outside `operator/`:

- `instance/base` for common custom resources
- `instance/components/<feature>` for optional Kustomize Components
- `instance/overlays/<profile>` for complete feature selections

For RHOAI, the instance layer usually starts with `DSCInitialization` and
`DataScienceCluster`. For ODF, the instance layer can include `StorageSystem`,
`OCSInitialization`, `StorageCluster`, standalone Multicloud Object Gateway, or
ObjectBucketClaim resources depending on the chosen storage posture.

## Aggregate Overlays

An aggregate overlay combines an operator overlay and an instance overlay:

```text
aggregate/overlays/<profile>/
  kustomization.yaml
```

Use aggregate overlays when a single Argo CD Application should represent the
operator plus its default instance. Prefer separate Applications when:

- CRDs must exist before operands can dry-run
- the operator install and instance lifecycle have different owners
- the instance includes high-risk cluster-scoped resources
- a failed operand should not block operator installation

When using one aggregate Application, include Argo CD sync handling for missing
CRDs and give the Application enough retry budget.

## Channel And Version Selection

Do not infer channels from the catalog alone.

For this repo:

- RHOAI channel selection comes from `rhoai-update-channels` and the active
  demo posture.
- ODF channel selection comes from `docs/PLATFORM_BASELINE.md` and ODF skills.
- OCP add-on Operator channels come from their official product docs or
  installed package metadata.

If the selected overlay does not exist in a catalog example, create it locally
as a small channel patch.

## Local Curation Rules

- Copy only the pattern and minimal manifest shape needed for this demo.
- Preserve useful upstream comments only when they explain behavior.
- Add local references to official docs and this skill.
- Remove catalog resources that are not needed for the demo profile.
- Verify old aggregate overlays do not select obsolete channels.
- Keep helper jobs idempotent and review their RBAC with `ocp-security-rbac-scc`.

## Argo CD Handoff

Operator Applications need enough ordering support for OLM and CRDs:

- earlier sync wave for operator installation
- later sync wave for operands
- `SkipDryRunOnMissingResource=true` where CRDs are created by an earlier wave
- retry/backoff budget for Operator and CRD readiness
- project-standard resource tracking and labels from `project-gitops-authoring`

Avoid direct `oc apply -k` as the normal deployment path. It is acceptable as a
temporary local render or schema check only when clearly documented.
