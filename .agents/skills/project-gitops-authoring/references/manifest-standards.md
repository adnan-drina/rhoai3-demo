# Manifest Standards

Use these standards when creating or modifying Kubernetes, OpenShift, RHOAI, or
Argo CD YAML.

## YAML Formatting

- Use 2-space indentation; never tabs.
- Use `.yaml`, not `.yml`.
- Prefer one resource per file.
- Order top-level keys as `apiVersion`, `kind`, `metadata`, `spec`, then
  `data` or `stringData`.
- Use block style for multi-line strings.
- End files with a single newline.
- Use `true` and `false`, not `yes` or `no`.

## Schema And Version Alignment

- Use the active product versions in `docs/PLATFORM_BASELINE.md`.
- Do not invent custom resource fields, API versions, annotations, or operator
  configuration.
- If unsure, propose verification with `oc explain` or CRD inspection.
- If the target cluster exposes a different API version than expected, call out
  the mismatch explicitly.

## Image And Artifact Provenance

- Prefer Red Hat product images, Red Hat registry sources, Red Hat validated
  model artifacts, or internally built demo images.
- Pin image tags where reproducibility matters.
- Do not introduce community images or external model artifacts as if they were
  Red Hat-supported. If a non-Red Hat dependency is required for the demo,
  document the exception in the README and keep credentials out of Git.
- For model-serving, registry, pipeline, and workbench resources, check
  `project-red-hat-doc-alignment-review` before merge so the README, manifests,
  and source references agree.

## Validation

Use the narrowest deterministic validation available:

- `kustomize build <base-path>` for render validation.
- Server-side dry-run validation for CRD-aware schema checks when a live cluster
  is available and the OpenShift safety guard is satisfied.
- Optional local tools such as kube-linter and kubeconform when configured.

## Comment Hygiene

Comments should explain why, not what.

Avoid:

- title comments that restate `kind`
- decorative section headers
- blank spacer comments
- comments that narrate obvious fields

Prefer:

- design decisions
- official reference links
- warnings such as demo-value or version-specific caveats
- constraints that will break behavior if changed

## Cross-Resource Consistency

Linters validate individual resources but do not catch broken references between
resources. Check these manually:

- Service and NetworkPolicy selectors match Pod template labels exactly.
- ConfigMap and Secret references resolve to resources in the base or are
  documented as runtime-created dependencies.
- `serviceAccountName` resolves to a ServiceAccount.
- Route or Ingress backends point to existing Services.
- Service target ports match container ports by name or number.
- Route target ports match Service port names.
- Namespaced references stay in the same namespace unless the resource type is
  cluster-scoped.

Do not rationalize missing references. If a dependency is created by an
operator or runtime script, document that in the manifest or README.

## Orphan Prevention

When removing a resource from a `kustomization.yaml`, also delete or explicitly
document the unreferenced file. When adding a resource file, ensure it appears
in the intended kustomization.
