# GitOps-Native Operator Lifecycle

Use this reference when installing, updating, or decommissioning Red Hat
Operators through Argo CD and OLM.

## Lifecycle Model

OLM manages application Operators through `Subscription`, `InstallPlan`,
`ClusterServiceVersion` (CSV), `CatalogSource`, and `OperatorGroup` resources.
GitOps should own the desired lifecycle policy:

- package name and catalog source
- installation namespace and OperatorGroup shape
- subscribed update channel
- install-plan approval strategy
- optional placement or environment configuration on the Subscription
- operand custom resources rendered after CRDs are available

OLM owns the generated lifecycle state:

- InstallPlans
- CSVs
- Operator deployments and related generated RBAC
- operator-managed operand deployments and images, unless official product
  docs expose a supported operand image override field
- Subscription status and conditions
- copied CSVs for all-namespace installs

Do not commit generated InstallPlans, CSVs, or copied CSVs as desired state.
Do not patch operator-generated operand images as the normal compatibility fix.
When a generated operand and its installed operator are incompatible, align the
Subscription channel, `startingCSV`, approval strategy, or product baseline
through GitOps and let OLM/operator reconciliation own images.

## Operand Image Ownership

Classify image ownership before changing an image value:

- **Repo-owned images**: Argo CD hook Jobs, utility containers, demo
  applications, pipeline component images, workbench images, modelcar images,
  and other workloads authored by this repository. Do not pin these solely for
  repeatability. Use the Red Hat-documented image reference, validated artifact
  reference, or project-approved non-operator demo-app exception.
- **Supported operand overrides**: explicit CR fields documented by the
  product as supported image overrides. Use only when the official docs and the
  matching product skill capture the field and support posture.
- **Operator-owned images**: CSV `relatedImages`, copied CSV content,
  generated CR image fields, and operator-created Deployments or StatefulSets.
  These are not project-owned desired state and should not be pinned or patched
  as a compatibility shortcut.

Use operator-owned image values only as diagnostic evidence:

```sh
oc get subscription -n <operator-namespace> <subscription-name> \
  -o jsonpath='{.status.installedCSV}{"\n"}'
oc get csv -n <operator-namespace> <installed-csv> \
  -o jsonpath='{range .spec.relatedImages[*]}{.name}{"="}{.image}{"\n"}{end}'
oc get <generated-kind> <name> -n <namespace> -o yaml
```

Durable fixes belong in one of these places:

- Subscription lifecycle policy: `channel`, `startingCSV`, or
  `installPlanApproval`
- product baseline changes in `docs/PLATFORM_BASELINE.md`
- documented product CR fields verified with official docs or `oc explain`
- waiting for or adopting a product-controller fix when the generated resource
  is invalid for the installed operand API

For platform components, repeatability should come from the Operator package,
Subscription lifecycle policy, and product baseline, not from pinning generated
operand images or copying generated lifecycle state into Git.

Deleting a failed operator/controller pod after API-server instability can be
valid live recovery, but it is not desired GitOps state. Do not convert that
recovery into generated Deployment patches or operand image pins.

## Installation

Install Operators from Git in this order:

1. Namespace and OperatorGroup.
2. Subscription from an `operator/overlays/<channel>` path.
3. Operand instance resources from a later sync wave or separate Application.
4. Validation of Subscription, InstallPlan, CSV, CRDs, and operands.

The Subscription channel must come from official product docs, installed package
metadata, or both. The community catalog pattern can show where to put the
channel patch, but it is not the authority for channel support.

## Regular Updates

For regular demo upgrades, prefer a tracked channel plus automatic approval
when the product docs and environment constraints allow it:

- RHOAI feature-forward demo posture normally uses the `fast-3.x` or current
  `fast-x.y` channel when available.
- ODF 4.20 docs recommend keeping update approval `Automatic` so the storage
  system updates when a new update is available in the same channel.
- Other Operators use the channel and approval policy from their official docs
  and installed package metadata.

With `installPlanApproval: Automatic`, Argo CD keeps the Subscription policy in
Git and OLM applies updates within the selected channel. Validation still
belongs in project automation and operations docs.

## Controlled Updates

Use a Git change for controlled lifecycle moves:

1. Update `docs/PLATFORM_BASELINE.md` when the intended product version changes.
2. Update or add `operator/overlays/<new-channel>/patch-channel.yaml`.
3. Update Argo CD Application paths only if the selected overlay path changes.
4. Sync the operator Application first.
5. Wait for Subscription, InstallPlan, and CSV readiness.
6. Update operand CR patches after the new CRDs and fields are available.
7. Validate product-specific health before merging further demo stages.

Do not use live `oc patch subscription` or console channel edits as the normal
path. If an emergency live change is needed, capture it back into Git or let
Argo CD self-heal it intentionally.

## Manual Approval

Manual approval is still compatible with GitOps when it is a documented control
gate, but it is not fully declarative because InstallPlan names are generated by
OLM.

Use manual approval only when:

- official docs require it for the environment or Operator
- the demo deliberately needs a human approval gate
- a specific starting CSV is required for a controlled installation

When manual approval is selected:

- keep `installPlanApproval: Manual` in Git
- document who approves pending InstallPlans and when
- review the generated InstallPlan before approval
- record approval as an operational action in `docs/OPERATIONS.md`
- avoid committing generated InstallPlan approval patches unless a specific
  automation design handles generated names safely

## RHOAI Component Lifecycle

For RHOAI, separate Operator lifecycle from platform capability lifecycle:

- operator overlay controls `rhods-operator` Subscription channel and approval
  strategy
- `instance/base` owns minimal `DSCInitialization` and `DataScienceCluster`
- later demo stages add Kustomize Components that patch the same
  platform-owned DSC/DSCI

During an RHOAI version upgrade, sync the Operator first, verify the CSV and
CRD schema, then adjust DSC component patches. Do not combine a channel jump
and broad DSC field changes in a single unvalidated edit unless official docs
require the changes to be atomic.

## ODF Lifecycle

ODF lifecycle must stay aligned with the OCP baseline. For this repo:

- OCP 4.20 pairs with ODF 4.20 unless `docs/PLATFORM_BASELINE.md` changes.
- ODF z-stream updates can flow through the selected 4.20 channel when the
  Subscription approval policy allows it.
- Minor ODF upgrades require the OCP and ODF compatibility check first.
- Storage health and data resilience checks are required before and after ODF
  upgrade work.

## Rollback And Recovery

A Git revert of a channel change does not guarantee an Operator downgrade.
OLM, CSV replacement graphs, CRDs, operand migrations, and product support
policy control what recovery is possible.

For rollback or failed upgrades:

- inspect Subscription conditions, InstallPlans, CSVs, catalog source health,
  and operand status
- use product-specific troubleshooting and uninstall/reinstall docs
- avoid deleting CRDs or namespaces with live data unless official docs and the
  user explicitly approve the recovery path
- document the actual recovery in `docs/TROUBLESHOOTING.md`

## Validation Commands

Run render checks before committing:

```sh
kustomize build gitops/<operator>/operator/overlays/<channel>
kustomize build gitops/<operator>/instance/overlays/<profile>
```

Run live checks only after the OpenShift safety guard confirms the target
cluster:

```sh
oc get packagemanifest -n openshift-marketplace <operator-package> -o yaml
oc get subscription -n <operator-namespace> <subscription-name> -o yaml
oc get installplan,csv -n <operator-namespace>
oc describe subscription -n <operator-namespace> <subscription-name>
oc get crd | rg '<operator-or-api-group>'
```

Product-specific checks come from the matching `rhoai-*`, `odf-*`, or `ocp-*`
skill.
