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

## Label Compliance

Check:

- `app.kubernetes.io/part-of`
- `app.kubernetes.io/name`
- `app.kubernetes.io/component`
- `app.kubernetes.io/instance` where useful
- `app.openshift.io/runtime` on visible resources
- `demo.rhoai.io/step` on Argo CD Applications

Use functional group names, not step numbers.

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

## Output Categories

Use stable categories:

- `[LABEL]`
- `[SELECTOR]`
- `[REFERENCE]`
- `[PORT]`
- `[SECURITY]`
- `[YAML]`
- `[ORPHAN]`
- `[DOCS]`
