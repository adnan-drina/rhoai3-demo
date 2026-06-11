# Operator Layout Example

Use this shape when curating a Red Hat Operator into this repo:

```text
gitops/operators/<operator-name>/
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
      kustomization.yaml
    overlays/
      <profile>/
        kustomization.yaml
  aggregate/
    overlays/
      <profile>/
        kustomization.yaml
```

Operator base:

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: <operator-subscription>
  namespace: <operator-namespace>
spec:
  channel: patch-me-use-overlay
  installPlanApproval: Automatic
  name: <operator-package>
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

Channel overlay patch:

```yaml
- op: replace
  path: /spec/channel
  value: <verified-channel>
```

Approval-strategy patch, only when the overlay intentionally changes lifecycle
policy:

```yaml
- op: replace
  path: /spec/installPlanApproval
  value: Manual
```

Aggregate overlay:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
commonAnnotations:
  argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
resources:
  - ../../../operator/overlays/<verified-channel>
  - ../../../instance/overlays/<profile>
```

Before committing this pattern:

- replace placeholders with product-verified values
- render each overlay with `kustomize build`
- create Argo CD Applications using `project-gitops-authoring`
- run `scripts/validate-agent-guidance.rb` if skills or rules changed

## Operator Upgrade Example

For a controlled channel move, add a new overlay or update the selected overlay:

```text
gitops/operators/<operator-name>/operator/overlays/<new-channel>/
  patch-channel.yaml
  kustomization.yaml
```

```yaml
- op: replace
  path: /spec/channel
  value: <new-verified-channel>
```

Then update the aggregate overlay or Argo CD Application path to select the new
overlay, sync the operator Application, and validate:

```sh
oc get subscription -n <operator-namespace> <subscription-name> -o yaml
oc get installplan,csv -n <operator-namespace>
oc describe subscription -n <operator-namespace> <subscription-name>
```

Do not commit generated InstallPlans or CSVs. Do not rely on a Git revert as a
generic Operator downgrade.

## RHOAI Progressive Component Example

Base overlay owns the RHOAI platform CRs:

```text
gitops/rhoai-platform/instance/base/
  dsc-init.yaml
  datasciencecluster.yaml
  kustomization.yaml
```

Serving component patches only serving-related fields:

```text
gitops/rhoai-platform/instance/components/serving/
  kustomization.yaml
  patch-datasciencecluster.yaml
  patch-dsc-init.yaml
```

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
patches:
  - path: patch-datasciencecluster.yaml
    target:
      kind: DataScienceCluster
      name: default
  - path: patch-dsc-init.yaml
    target:
      kind: DSCInitialization
      name: default-dsci
```

Demo overlay composes the base plus enabled features:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
components:
  - ../../components/serving
  - ../../components/model-registry
```

When a later demo stage introduces a new platform capability, add a focused
component and append it to this same overlay. Do not create another Argo CD
Application that owns a second full copy of `DataScienceCluster/default`.
