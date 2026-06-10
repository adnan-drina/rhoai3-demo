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
