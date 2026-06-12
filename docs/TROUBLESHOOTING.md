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
  use `datasciencecluster.opendatahub.io/v2`; v1 lacks the 3.4 component fields.
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

## Stage 120: GPU-as-a-Service

### Stage 120 Application is OutOfSync

- **MachineSet replica drift after scale-down is expected.** The Application
  ignores `MachineSet.spec.replicas`, so intentional manual scale-down should
  not be self-healed. If other MachineSet fields drift, inspect the sync error
  before changing live resources.
- **CRD not found for Kueue or hardware profiles** usually means the operator
  has not finished installing. The Application has retry/backoff and
  `SkipDryRunOnMissingResource=true`; wait for CSVs before assuming the
  manifest is wrong.

```bash
oc get application stage-120-gpu-as-a-service -n openshift-gitops \
  -o jsonpath='{.status.operationState.message}{"\n"}'
```

### GPU MachineSet has no ready worker

- **Likely causes:** AWS quota for `g6e.2xlarge`, wrong availability zone,
  stale AMI/providerSpec from another cluster, or insufficient cloud capacity.
- **Checks:** inspect Machine and MachineSet events:

```bash
oc get machineset -n openshift-machine-api -l cluster-api/accelerator=nvidia-gpu
oc get machine -n openshift-machine-api -l cluster-api/accelerator=nvidia-gpu
oc describe machineset -n openshift-machine-api -l cluster-api/accelerator=nvidia-gpu
```

Do not reuse the committed `cluster-klvxt` MachineSet in a fresh environment
without regenerating provider fields from that environment.

### NVIDIA ClusterPolicy is not ready

- **Likely causes:** GPU node not ready, driver daemonset cannot tolerate the
  GPU taint, entitlement/pull-secret issue, or incompatible node/kernel state.
- **Checks:**

```bash
oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}{"\n"}'
oc get pods -n nvidia-gpu-operator -o wide
oc get nodes -l nvidia.com/gpu.present=true
```

The expected ready state is `ready`.

### GPU allocatable count is not four

- **Expected:** one L40S node advertises four `nvidia.com/gpu` units because
  Stage 120 configures NVIDIA device-plugin time-slicing.
- **Checks:**

```bash
oc get nodes -l nvidia.com/gpu.present=true \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'
oc get configmap time-slicing-config -n nvidia-gpu-operator -o yaml
```

If the node advertises one GPU, confirm the `ClusterPolicy` references the
`time-slicing-config` ConfigMap and wait for the device-plugin pods to roll.

### Kueue queues are not Active

- **Likely causes:** Kueue operator still installing, invalid ResourceFlavor
  reference, or namespace not labeled for Kueue-managed workloads.
- **Checks:**

```bash
oc get clusterqueue
oc get localqueue -n demo-sandbox
oc get namespace demo-sandbox -o jsonpath='{.metadata.labels.kueue\.openshift\.io/managed}{"\n"}'
```

ClusterQueues and LocalQueues should report condition `Active=True`.

### Hardware profiles are missing in the dashboard

- **Checks:** confirm the HardwareProfile objects exist in
  `redhat-ods-applications` and that the RHOAI dashboard is healthy:

```bash
oc get hardwareprofile -n redhat-ods-applications
oc get route rhods-dashboard -n redhat-ods-applications
```

If the objects exist but the UI is stale, refresh the dashboard session or log
out and back in.

---

Legacy troubleshooting content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/TROUBLESHOOTING.md`
