# Documentation Alignment Evidence Ledger

**Generated:** 2026-05-15T22:20:23Z
**Command:** `./scripts/audit-doc-alignment.sh --component step-01-gpu-and-prereq`
**Base ref:** `origin/main`
**Docs baseline:** RHOAI 3.4 / OCP 4.20
**rh-brain source:** `/Users/adrina/Sandbox/rh-brain/Red Hat Brain`

This ledger is produced by `scripts/audit-doc-alignment.sh`. Official product documentation is the source of truth for supported configuration. `rh-brain` is read-only research input for narrative and Red Hat article alignment.

## Baseline References

- [Red Hat OpenShift AI Self-Managed 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/)
- [RHOAI 3.4 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/release_notes/index)
- [OpenShift Container Platform 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/)

## Component Evidence

### step-01-gpu-and-prereq

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-01-gpu-and-prereq/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-01-gpu-and-prereq.yaml` |
| README | `steps/step-01-gpu-and-prereq/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-01-gpu-and-prereq/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [PASS] No unpinned `:latest` image references found in GitOps path.

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-01-gpu-and-prereq/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain NodeFeatureDiscovery --api-version=nfd.openshift.io/v1`.
- [DEFERRED] Verify with `oc explain ClusterPolicy --api-version=nvidia.com/v1`.
- [DEFERRED] Verify with `oc explain KnativeServing --api-version=operator.knative.dev/v1beta1`.
- [DEFERRED] Verify with `oc explain Subscription --api-version=operators.coreos.com/v1alpha1`.
- [DEFERRED] Verify with `oc explain OperatorGroup --api-version=operators.coreos.com/v1`.
- [DEFERRED] Verify with `oc explain ClusterRoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain ConfigMap --api-version=v1`.
- [DEFERRED] Verify with `oc explain Namespace --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Autoscaling vLLM with OpenShift AI model serving Performance validation.md`
- `rh-brain: raw/Customize Models for Gen AI and Agentic AI Applications  Red Hat OpenShift AI Self-Managed  3.4.md`

## Summary

| Result | Count |
|--------|-------|
| Blocking findings | 0 |
| Notes / deferred checks | 1 |

**Decision:** aligned. Notes and deferred checks may be handled as follow-up work.
