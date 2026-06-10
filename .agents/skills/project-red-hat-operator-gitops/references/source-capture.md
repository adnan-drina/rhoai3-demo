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
| Capture date | 2026-06-10 |

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

## Source Boundaries

The GitOps Catalog is a pattern source only. Do not treat it as official Red
Hat product configuration truth. For this repo:

- official product docs define supported channels and resource fields
- catalog examples suggest local GitOps organization and Kustomize layering
- live cluster schema verifies installed CRDs and field availability
- `docs/PLATFORM_BASELINE.md` controls product versions
