# Manifest Review Checklist

Use this checklist for readonly review of GitOps manifests.

## Cross-Resource Consistency

Check every reference that links one resource to another:

- Service selectors match Pod template labels exactly.
- NetworkPolicy selectors match intended Pod labels.
- ConfigMap names in volumes and environment references exist.
- Secret names in volumes and environment references exist.
- ServiceAccount names exist when referenced by workloads.
- RoleBinding subjects and roleRefs resolve.
- Route and Ingress backends point to existing Services.
- Service target ports match container ports by name or number.
- Route target ports match Service port names.

Flag runtime-created dependencies unless the manifest or README clearly says
which operator or script creates them.

## Admission And Namespace Mutation

Check whether the target namespace is managed by admission controllers that
mutate workloads or enforce queueing/security policy. Examples include Kueue,
service mesh injection, and operator-managed labels.

Flag a `[REFERENCE]` or `[SECURITY]` finding when:

- a long-lived infrastructure workload such as a database is placed in a
  Kueue-managed model namespace without an explicit reason
- a workload sets or inherits immutable labels that an admission webhook might
  later try to change
- old or legacy namespace labels can re-enable admission behavior after GitOps
  removes the newer label
- validation only checks source manifests and not the mutated live resource
  shape for workloads affected by admission

For the RHOAI MaaS demo, keep the model namespace Kueue-managed and keep the
demo-local PostgreSQL database in a separate non-Kueue-managed namespace.

## Label Compliance

Check:

- `app.kubernetes.io/part-of`
- `app.kubernetes.io/name`
- `app.kubernetes.io/component`
- `app.kubernetes.io/instance` where useful
- `app.openshift.io/runtime` on visible resources
- `demo.rhoai.io/stage` on Argo CD Applications

Use functional group names, not stage identifiers.

## YAML Standards

Check:

- 2-space indentation
- `.yaml` extension
- top-level key order
- one resource per file where practical
- comments explain why, not what
- no decorative section comments
- no title comments that restate resource kind
- no orphaned files after kustomization changes

## Security

Check:

- no real credentials
- demo secrets have a demo-value warning
- no privileged workload containers
- no hostPath mounts
- no container runtime socket mounts
- no wildcard RBAC outside documented Argo CD demo posture
- no unsupported ODH managed labels on GitOps-owned secrets

## Source Grounding Handoff

Manifest review does not decide whether a Red Hat API field, operator channel,
container image, or model artifact is officially supported. It should identify
where source grounding is required and route that evidence check to
`project-red-hat-doc-alignment-review`.

Flag a `[SOURCE]` finding when:

- a RHOAI or OpenShift custom resource uses a new or changed API version
- a manifest introduces or changes top-level CR spec fields
- an Operator `Subscription` channel, package, catalog source, or install
  posture changes
- a manifest introduces or changes a container image reference
- a model-serving, registry, pipeline, or workbench manifest introduces an
  external model artifact or runtime dependency
- the companion README claims Red Hat-supported behavior that is not clearly
  reflected in the GitOps artifacts

## Output Categories

Use stable categories:

- `[LABEL]`
- `[SELECTOR]`
- `[REFERENCE]`
- `[PORT]`
- `[SECURITY]`
- `[SOURCE]`
- `[YAML]`
- `[ORPHAN]`
- `[DOCS]`
