# Source Capture

## Pattern Sources

| Field | Value |
|-------|-------|
| Pattern family | Red Hat Community of Practice GitOps Catalog |
| Repository | https://github.com/redhat-cop/gitops-catalog |
| Root README | https://github.com/redhat-cop/gitops-catalog/tree/main |
| OpenShift AI catalog item | https://github.com/redhat-cop/gitops-catalog/tree/main/openshift-ai |
| OpenShift AI instance pattern | https://github.com/redhat-cop/gitops-catalog/tree/main/openshift-ai/instance |
| OpenShift Data Foundation Operator catalog item | https://github.com/redhat-cop/gitops-catalog/tree/main/openshift-data-foundation-operator |
| Node Feature Discovery catalog item | https://github.com/redhat-cop/gitops-catalog/tree/main/nfd |
| NVIDIA GPU Operator catalog item | https://github.com/redhat-cop/gitops-catalog/tree/main/gpu-operator-certified |
| NVIDIA GPU Operator AWS MachineSet component | https://github.com/redhat-cop/gitops-catalog/tree/main/gpu-operator-certified/instance/components/aws-gpu-machineset |
| Grafana Operator catalog item | https://github.com/redhat-cop/gitops-catalog/tree/main/grafana-operator |
| Capture date | 2026-06-10 |

## Official Lifecycle Sources

| Source | URL | Use |
|--------|-----|-----|
| OCP 4.20 Operators - Understanding Operators | https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/operators/understanding-operators | OLM concepts, Subscription, InstallPlan, CSV, CatalogSource, OperatorGroup, channel, update graph |
| OCP 4.20 Operators - Administrator tasks | https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/operators/administrator-tasks | Operator install settings, CLI Subscription shape, changing update channel, manual approval, subscription status, uninstall and refresh behavior |
| RHOAI 3.4 - Understanding update channels | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/understanding-update-channels_install | RHOAI channel meanings, fast/stable/EUS/alpha posture, legacy channel warning |
| ODF 4.20 - Updating OpenShift Data Foundation | https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.20/html-single/updating_openshift_data_foundation/index | ODF update process, OCP/ODF compatibility, automatic/manual approval guidance, storage health checks |

## Official Lifecycle Extraction

- OLM controls installation, upgrade, and RBAC for application Operators on
  OpenShift.
- Operator installation requires deliberate choices for installation mode,
  update channel, and approval strategy.
- A Subscription tracks an Operator package channel. OLM uses that desired
  policy to create or update InstallPlans and CSVs.
- Automatic approval allows OLM to upgrade the running Operator when a newer
  version is available in the selected channel.
- Manual approval creates a pending update request that a cluster
  administrator must review and approve.
- Installed Operators cannot be moved to an older channel as a generic update
  operation.
- `startingCSV` is for specific-version installation and should be paired with
  manual approval when used to prevent automatic movement to a later available
  version.
- Default OpenShift cluster Operators are CVO-managed and do not use
  Subscription objects; this skill targets OLM-managed application Operators.
- ODF update docs recommend `Automatic` approval for same-channel automatic
  storage-system updates and require ODF/OCP compatibility checks.
- RHOAI 3.4 docs recommend `fast` or `fast-x.y` for production environments
  that want latest product features, while warning that `embedded` and `beta`
  are legacy channels for new installations.

## Captured Pattern

- Catalog root provides Kustomize bases and overlays for OpenShift Operators
  and applications.
- Root README warns that the catalog is not officially supported by Red Hat and
  discourages customers from referencing it directly as a remote Kustomize
  source. It recommends curating selected items into a maintained catalog.
- Most operator entries use `operator/base` plus `operator/overlays/<channel>`.
- Operator bases typically include Namespace, OperatorGroup, Subscription, and
  `kustomization.yaml`.
- Channel overlays patch `spec.channel` on the Subscription.
- Instance resources live separately under `instance/base`,
  `instance/components`, and `instance/overlays/<profile>`.
- Aggregate overlays combine operator and instance overlays for a deployable
  profile and commonly add the Argo CD sync option annotation
  `SkipDryRunOnMissingResource=true`.

## OpenShift AI Observations

- Root item: `openshift-ai`.
- Operator base includes `redhat-ods-operator` Namespace, OperatorGroup, and
  `rhods-operator` Subscription.
- Operator overlays patch channels such as `fast`, `fast-3.x`, `stable`, and
  EUS/stable minor variants.
- Instance base contains `DSCInitialization`, `DataScienceCluster`,
  `OdhDashboardConfig`, and the `redhat-ods-applications` namespace.
- Instance components are modeled as Kustomize `kind: Component` entries that
  patch `DataScienceCluster` and `DSCInitialization` or add related resources.
  Examples observed:
  - `components-serving` patches `kserve`, `modelmeshserving`, and DSCI
    `serviceMesh`.
  - `components-distributed-compute` patches `codeflare`, `kueue`, and `ray`.
  - `components-training` patches `datasciencepipelines` and `workbenches`.
  - `components-trustyai` patches `trustyai`.
  - `components-modelregistry` patches `modelregistry` and
    `registriesNamespace`.
  - `nvidia-gpu-accelerator-profile` adds an `AcceleratorProfile`.
- Instance overlays include `../../base` and compose selected components for
  profiles such as `fast`, `fast-nvidia-gpu`, serving-only, training-only, and
  modelregistry-only.
- Aggregate overlays combine an operator channel overlay and an instance
  profile overlay.

## OpenShift Data Foundation Observations

- Root item: `openshift-data-foundation-operator`.
- Operator base includes `openshift-storage` Namespace, OperatorGroup,
  `odf-operator` Subscription, and console-plugin helper resources.
- Operator overlays patch stable channels such as `stable-4.20`.
- Instance base includes `StorageSystem`.
- AWS and vSphere instance overlays add `OCSInitialization` and
  `StorageCluster` resources.
- The catalog's AWS aggregate overlay observed during capture referenced an
  older operator channel overlay even though newer channel overlays exist. This
  is a reminder to verify and curate locally instead of copying blindly.

## NVIDIA GPU Operator Observations

- Root item: `gpu-operator-certified`.
- Operator base includes `nvidia-gpu-operator` Namespace, OperatorGroup, and
  `gpu-operator-certified` Subscription from the `certified-operators`
  catalog source.
- Operator overlays patch channels such as `stable`, `v24.9`, and `v25.3`.
- Instance base includes NVIDIA `ClusterPolicy` and a device-plugin ConfigMap.
- Instance components include AWS GPU MachineSet generation, monitoring
  dashboard, time-slicing variants, and MIG variants.
- The AWS instance overlay composes `../../base` plus the
  `aws-gpu-machineset` component.
- The AWS GPU MachineSet component uses an Argo CD sync-hook Job to detect AWS,
  clone an existing worker MachineSet, change the instance type, add GPU labels
  and taints, and create MachineAutoscalers. For this repo, reuse this as a
  curation and generation pattern; prefer Git-tracked MachineSet resources for
  maintained environments.

## Node Feature Discovery Observations

- Root item: `nfd`.
- Operator base includes `openshift-nfd` Namespace, `nfd-group`
  OperatorGroup, and `nfd` Subscription from the `redhat-operators` catalog
  source.
- Operator overlay patches the Subscription channel to `stable`.
- Instance base contains a `NodeFeatureDiscovery` named `nfd-instance` in the
  `openshift-nfd` namespace.
- Instance overlays include profiles such as `default`, `kata`, and
  `only-nvidia`.
- Aggregate overlays combine the stable operator overlay with the selected
  instance overlay and add the Argo CD sync option annotation
  `SkipDryRunOnMissingResource=true`.
- The `only-nvidia` overlay narrows PCI feature publication to class whitelist
  values `0200`, `03`, and `12`, publishes the `vendor` field, keeps the
  worker `sleepInterval` at `60s`, and disables the topology updater.
- For this repo, reuse the catalog item as a local curation pattern for NFD
  operator and instance layering. Verify `NodeFeatureDiscovery` fields,
  `operand.image`, topology updater behavior, and generated labels against
  official docs or live schema before committing GitOps manifests.

## Grafana Operator Observations

- Root item: `grafana-operator`.
- The catalog uses an older layout than the newer operator/instance/aggregate
  pattern: `base/operator`, `base/instance`, and deployable overlays under
  `overlays/`.
- Operator base includes only a `Subscription`; the deployable example overlay
  adds Namespace and OperatorGroup.
- Subscription installs package `grafana-operator` from `community-operators`,
  uses channel `v5`, and sets `installPlanApproval: Automatic`.
- Instance base includes a `Grafana` custom resource, OAuth proxy RBAC,
  injected CA bundle ConfigMap, and a placeholder session secret.
- The `Grafana` resource uses API `grafana.integreatly.org/v1beta1`,
  configures an OpenShift OAuth redirect reference, creates a reencrypt Route,
  uses service serving certificates, and mounts an OAuth proxy sidecar.
- Aggregate overlay combines `base/operator` and `base/instance` with
  `SkipDryRunOnMissingResource=true`.
- The `user-app` overlay adds a `GrafanaDatasource` for OpenShift Thanos
  Querier, a service-account token Secret pattern, a
  `cluster-monitoring-view` ClusterRoleBinding, and patches the Grafana
  deployment to read `GRAFANA_TOKEN` from the Secret.
- For this repo, treat Grafana as a community Operator support-boundary
  decision. Curate the GitOps layout locally and verify channel, CRD fields,
  OAuth proxy image, route settings, RBAC, and token handling before
  implementation.

## Source Boundaries

The GitOps Catalog is a pattern source only. Do not treat it as official Red
Hat product configuration truth. For this repo:

- official product docs define supported channels and resource fields
- catalog examples suggest local GitOps organization and Kustomize layering
- live cluster schema verifies installed CRDs and field availability
- `docs/PLATFORM_BASELINE.md` controls product versions
- community-operator exceptions, such as Grafana, require explicit support
  boundary and upgrade-risk review
- operator lifecycle changes should be represented as Git changes to
  Subscription overlays, approval strategy, product baseline, and operand
  patches; direct live edits are exceptions that must be reconciled back to Git
