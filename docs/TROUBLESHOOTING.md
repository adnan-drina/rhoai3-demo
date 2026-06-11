# Troubleshooting

Active troubleshooting guidance for the reimplementation.

## Stage 110: RHOAI Base Platform

Failure modes observed during the stage-110 bring-up, with the operationally
relevant fixes. Most authoring-time bugs are already fixed in the scripts and
manifests; the items below are the ones a fresh deploy or day-2 operator can
still hit.

### deploy.sh / setup-access.sh refuses to run

- **Symptom:** `ERROR: Active cluster (...) does not match RHOAI_EXPECTED_API_SERVER`.
- **Cause:** the active kubeconfig points at a different cluster than `.env`
  declares. This is the safety guard working as intended.
- **Fix:** confirm `KUBECONFIG` and `RHOAI_EXPECTED_API_SERVER` in `.env` match
  the target cluster. The scripts source `.env` with `set -a` so values reach
  `oc`; if you run `oc` by hand, the session `KUBECONFIG` from
  `.claude/settings.local.json` (or an inline `KUBECONFIG=...`) must point at the
  same cluster.

### Argo CD Application stuck OutOfSync / not progressing

- **`one or more objects failed to apply ... cannot patch ... in namespace`** —
  the Argo CD application-controller lacks permissions. The bootstrap grants it
  `cluster-admin` (`gitops/bootstrap/overlays/demo/argocd-cluster-admin.yaml`);
  verify with `oc auth can-i create serviceaccounts -n openshift-storage
  --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller`.
- **`no matches for kind "StorageSystem"`** — ODF 4.20 removed the
  `odf.openshift.io` StorageSystem API. The MCG-only path is a `StorageCluster`
  with `multiCloudGateway.reconcileStrategy: standalone`.
- **`field not declared in schema` on DataScienceCluster** — the manifest must
  use `datasciencecluster.opendatahub.io/v2`; v1 lacks the 3.4 component fields
  and fails under ServerSideApply.
- **A single resource is permanently OutOfSync (e.g. `OCSInitialization`)** — it
  is operator-owned. Do not manage it in GitOps. If it was previously committed,
  clear the orphaned tracking once:
  `oc annotate ocsinitialization ocsinit -n openshift-storage argocd.argoproj.io/tracking-id-`.

Inspect the live sync error directly — it is more specific than the dashboard:

```bash
oc get application stage-110-rhoai-base-platform -n openshift-gitops \
  -o jsonpath='{.status.operationState.message}{"\n"}'
```

### NooBaa / S3 not Ready

- **Symptom:** `validate.sh` fails on NooBaa phase, or S3 endpoint unreachable.
- **Checks:** `oc get noobaa noobaa -n openshift-storage -o jsonpath='{.status.phase}'`
  (want `Ready`); backing store and bucket class
  (`oc get backingstore,bucketclass -n openshift-storage`). A `403` from the S3
  route root is normal (anonymous S3 access denied), not a failure.

### Cannot log in as ai-admin / ai-developer

- **Cause:** htpasswd identities are created on first login and the OAuth pods
  need to roll out after `setup-access.sh`.
- **Fix:** wait for the authentication operator to settle, then retry:
  `oc get co authentication` (want `Available=True Progressing=False`).
- Forgotten passwords are in the gitignored `.env`
  (`grep -E '^AI_(ADMIN|DEVELOPER)_PASSWORD=' .env`).

### RHOAI admin (ai-admin) does not see a project

- **Cause:** the RHOAI dashboard-admin role does not grant access to a project
  namespace. This is expected RHOAI behavior.
- **Fix:** bind `rhods-admins` to `admin` on the project (see
  `gitops/stage-110-rhoai-base-platform/access/base/rolebinding-admins-admin.yaml`
  for `demo-sandbox`). Each new project needs its own binding.

### Workbench shows ready=0 with no pod

- **Not a failure.** A stopped workbench carries
  `metadata.annotations.kubeflow-resource-stopped` with a timestamp; its RWO PVC
  persists. Start it again from the dashboard.

---

Legacy troubleshooting content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/TROUBLESHOOTING.md`
