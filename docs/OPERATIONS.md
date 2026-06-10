# Operations

Active operations guidance for the reimplementation.

No active bootstrap, deploy, validate, or demo-flow scripts exist yet. Legacy
operations content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/OPERATIONS.md`

Before adding live cluster automation, align it with `../AGENTS.md`,
`PLATFORM_BASELINE.md`, and the OpenShift safety guard.

## Operator Lifecycle And Upgrades

Operator lifecycle management is GitOps state for this project. Red Hat
Operator installation and upgrade intent must be represented in Git through the
operator Kustomize tree and Argo CD Applications, not maintained as live
Subscription drift.

Git-owned lifecycle fields include:

- Operator `Subscription` package name, catalog source, source namespace, and
  subscribed channel
- `installPlanApproval` policy
- selected channel overlay or aggregate overlay path
- product baseline changes in `PLATFORM_BASELINE.md`
- operand custom resource patches that depend on the upgraded Operator schema

Regular demo upgrades should use tracked channels with automatic approval when
the relevant Red Hat product documentation and the active environment allow it.
For example, the RHOAI demo posture favors feature-forward `fast-3.x` or the
current `fast-x.y` channel when available, while ODF stays pinned to the ODF
minor version compatible with the active OCP baseline.

Controlled upgrades should follow this sequence:

1. Update `PLATFORM_BASELINE.md` when the intended product version changes.
2. Update the Operator channel overlay or approval strategy in Git.
3. Sync the Operator Argo CD Application before changing operand CR fields.
4. Validate `Subscription`, `InstallPlan`, `ClusterServiceVersion`, CRDs, and
   product-specific health.
5. Update operand patches only after the new schema is available.
6. Record recovery notes in `TROUBLESHOOTING.md` if anything fails.

Manual InstallPlan approval is an operational gate, not a fully declarative
resource, because OLM generates InstallPlan names. Use manual approval only
when official docs require it or when the demo deliberately needs a human gate.
Document who approves the pending InstallPlan and why.

A Git revert of an Operator channel change does not guarantee a downgrade.
Rollback and recovery are product-specific and must follow the relevant Red Hat
documentation and live cluster health checks.
