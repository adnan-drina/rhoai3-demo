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

For NFD, the instance layer usually starts with a `NodeFeatureDiscovery`
resource in `openshift-nfd`. Treat CoP profiles such as `default` and
`only-nvidia` as examples of how to keep product instance posture separate from
the OLM Subscription.

For Grafana, the CoP `grafana-operator` item uses an older shape:
`base/operator`, `base/instance`, and deployable overlays. When implementing it
in this repo, normalize that split into the project layout while preserving the
same separation between OLM install, Grafana instance, datasource, dashboard,
and aggregate overlays.

## RHOAI Progressive DSC Patching

The CoP `openshift-ai/instance` pattern is especially important for this demo.
It does not create unrelated full `DataScienceCluster` resources for every
feature. It starts from an `instance/base` that owns the baseline
`DSCInitialization` and `DataScienceCluster`, then adds optional RHOAI
capabilities through Kustomize Components that patch those same resources.

Use this pattern for the demo:

```text
gitops/rhoai-platform/
  instance/
    base/
      dsc-init.yaml
      datasciencecluster.yaml
      odhdashboardconfig.yaml
      namespace.yaml
      kustomization.yaml
    components/
      serving/
        kustomization.yaml
        patch-datasciencecluster.yaml
        patch-dsc-init.yaml
      distributed-workloads/
        kustomization.yaml
        patch-datasciencecluster.yaml
      workbenches-pipelines/
        kustomization.yaml
        patch-datasciencecluster.yaml
      model-registry/
        kustomization.yaml
        patch-datasciencecluster.yaml
      trustyai/
        kustomization.yaml
        patch-datasciencecluster.yaml
    overlays/
      demo/
        kustomization.yaml
```

The first platform stage should introduce the operator and a minimal base
DSC/DSCI. Later demo stages should add component directories and append those
components to the platform overlay that is already owned by the RHOAI platform
Argo CD Application.

This avoids several failure modes:

- two Argo CD Applications fighting over the same `DataScienceCluster`
- a later stage rendering a full DSC that accidentally removes a previously
  enabled component
- unclear ownership of shared RHOAI namespaces, DSCI service mesh, monitoring,
  dashboard, or CA bundle settings
- stage-specific manifests encoding global platform state without updating the
  platform source of truth

Component patches should be minimal and additive. A component patch should only
touch the component subtree it owns unless the official RHOAI docs require a
shared DSCI setting.

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

The CoP NFD aggregate overlays are a useful compact example: they compose the
stable operator overlay with an instance overlay and add
`SkipDryRunOnMissingResource=true` so Argo CD can reconcile the operand after
the Operator provides the CRD.

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

## Lifecycle Management

The same `operator/base` and `operator/overlays/<channel>` split is the
upgrade mechanism:

- keep the Subscription channel and `installPlanApproval` policy in Git
- add a new channel overlay when moving to a different supported stream
- update aggregate overlays or Argo CD Application paths only when the selected
  overlay path changes
- let Argo CD reconcile the Subscription and let OLM create generated
  InstallPlans and CSVs
- validate the new CSV and CRD schema before changing operand CRs

Avoid live Subscription patches, web console channel edits, or hand-managed
CSV changes as the normal lifecycle path. If an emergency cluster-side change
is made, reconcile it into Git or let Argo CD intentionally revert it.

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

## Generator Hook Boundary

Some catalog components, such as the GPU Operator AWS MachineSet component, use
an Argo CD hook Job to inspect the live cluster and create resources
imperatively. Treat this as a bootstrap pattern, not the default desired-state
model for this repo.

Prefer to:

- reuse the generator's transformation logic
- capture the resulting MachineSet and MachineAutoscaler as reviewed manifests
  in Git
- apply them through normal Argo CD resource tracking

Use a hook Job only when the environment is intentionally disposable or the
live provider shape cannot be known until first sync. Review hook RBAC with
`ocp-security-rbac-scc` and document any generated resources that Argo CD does
not own directly.
