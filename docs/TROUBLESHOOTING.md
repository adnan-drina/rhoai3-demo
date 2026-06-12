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

## Stage 210: Model Serving Foundation

### Stage 210 deploy runs but KServe remains Removed

- **Likely causes:** the `stage-110-rhoai-base-platform` Argo CD Application is
  still pointed at an older Git revision, the branch with the Stage 210 patch
  was not pushed, or Argo CD has not refreshed the shared owner.
- **Checks:**

```bash
oc get application stage-110-rhoai-base-platform -n openshift-gitops \
  -o jsonpath='{.spec.source.targetRevision}{" "}{.status.sync.revision}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}'
oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.kserve.managementState}{" "}{.status.phase}{"\n"}'
```

The expected Stage 210 state is `kserve.managementState=Managed` and
`DataScienceCluster` phase `Ready`.

### Stage 110 Application is OutOfSync after enabling KServe

- **Likely causes:** a KServe-related CRD or webhook is still being installed,
  the RHOAI operator is reconciling component state, or Argo CD hit a dry-run
  race while CRDs appeared.
- **Checks:**

```bash
oc get application stage-110-rhoai-base-platform -n openshift-gitops \
  -o jsonpath='{.status.operationState.message}{"\n"}'
oc get pods -n redhat-ods-applications | grep -Ei 'kserve|model'
oc get crd inferenceservices.serving.kserve.io servingruntimes.serving.kserve.io
```

Wait for the RHOAI operator reconciliation before changing manifests. If Argo
CD reports a schema error, verify the field with:

```bash
oc explain datasciencecluster.spec.components.kserve \
  --api-version=datasciencecluster.opendatahub.io/v2
```

### vLLM runtime is not discoverable

- **Likely causes:** the serving platform is still reconciling, preinstalled
  runtime templates are disabled, or the dashboard/runtime configuration has
  not completed.
- **Checks:**

```bash
oc get servingruntime -A
oc get datasciencecluster default-dsc \
  -o jsonpath='{.status.installedComponents}{"\n"}'
```

Do not hard-code a runtime name in GitOps until the active runtime template has
been verified from the live cluster or official documentation.

### demo-registry is missing or not Available

- **Likely causes:** the Stage 110 Application has not reconciled the registry
  base, the model registry operator is still starting, or the generated default
  PostgreSQL deployment is not available.
- **Checks:**

```bash
oc get application stage-110-rhoai-base-platform -n openshift-gitops \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
oc get modelregistries.modelregistry.opendatahub.io demo-registry \
  -n rhoai-model-registries -o yaml
oc get pods,deploy,route -n rhoai-model-registries
```

The expected demo state is `Available=True` on
`modelregistries.modelregistry.opendatahub.io/demo-registry`.

### Nemotron registry metadata is missing

- **Likely causes:** `stage-210-model-serving-foundation/deploy.sh` has not run
  after the registry became available, the current user cannot access the model
  registry route, or the registry REST API returned an error.
- **Checks:**

```bash
./stage-210-model-serving-foundation/deploy.sh
./stage-210-model-serving-foundation/validate.sh
```

The deploy script is idempotent. It reuses existing registered model, version,
and artifact metadata when present, and creates missing metadata through the
Model Registry REST API when absent.

### Nemotron InferenceService is missing or not Ready

- **Likely causes:** the vLLM runtime template is missing, the modelcar pull
  secret is missing or invalid, GPU quota is unavailable, or the model pod is
  still loading the OCI modelcar.
- **Checks:**

```bash
oc get template vllm-cuda-runtime-template -n redhat-ods-applications
oc get secret nemotron-3-nano-30b -n demo-sandbox
oc get inferenceservice nvidia-nemotron-3-nano-30b-a3b -n demo-sandbox -o yaml
oc get pods -n demo-sandbox | grep -Ei 'nemotron|vllm|predictor'
```

The expected Stage 210 state is a ready
`demo-sandbox/nvidia-nemotron-3-nano-30b-a3b` `InferenceService` using the
Nemotron OCI modelcar source, the curated vLLM args, and the L40S-sized
resource profile.

Verify the active serving configuration:

```bash
oc get inferenceservice nvidia-nemotron-3-nano-30b-a3b -n demo-sandbox \
  -o json | jq '.spec.predictor.model | {args, resources}'
```

Expected resources are one `nvidia.com/gpu`, `2` CPU and `16Gi` memory
requested, and `4` CPU and `24Gi` memory limited. Expected args include
`--enable-prefix-caching`, `--max-model-len=131072`,
`--max-num-batched-tokens=8192`, `--enable-auto-tool-choice`,
`--tool-call-parser=qwen3_coder`, and `--reasoning-parser=nano_v3`. If the spec
drifts, rerun `./stage-210-model-serving-foundation/deploy.sh` and then
`./stage-210-model-serving-foundation/validate.sh`.

### Stage 210 observability Application is missing or unhealthy

- **Likely causes:** the branch with the Stage 210 observability GitOps path
  was not pushed, Argo CD is still installing Grafana Operator CRDs, or the
  Grafana community Operator catalog is temporarily unavailable.
- **Checks:**

```bash
oc get application stage-210-model-serving-foundation -n openshift-gitops \
  -o jsonpath='{.spec.source.targetRevision}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}'
oc get subscription,csv -n rhoai-demo-grafana
oc get crd grafanas.grafana.integreatly.org grafanadatasources.grafana.integreatly.org grafanadashboards.grafana.integreatly.org
```

If the Application reports a schema or dry-run error, wait for the Grafana
Operator CSV to reach `Succeeded`, then hard-refresh the Application:

```bash
oc annotate application stage-210-model-serving-foundation -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite
```

### vLLM metrics are exposed but not visible in Grafana

- **Likely causes:** user workload monitoring is not enabled yet, the
  generated ServiceMonitor is missing, Grafana datasource token substitution
  failed, or Prometheus has not scraped a fresh sample.
- **Checks:**

```bash
oc get configmap cluster-monitoring-config -n openshift-monitoring \
  -o jsonpath='{.data.config\.yaml}'
oc get pods -n openshift-user-workload-monitoring
oc get servicemonitor nvidia-nemotron-3-nano-30b-a3b-metrics -n demo-sandbox
oc get grafanadatasource prometheus -n rhoai-demo-grafana -o yaml
```

The endpoint itself should expose vLLM metrics:

```bash
MODEL_URL=$(oc get inferenceservice nvidia-nemotron-3-nano-30b-a3b \
  -n demo-sandbox -o jsonpath='{.status.url}')
curl -ks "${MODEL_URL}/metrics" | grep 'vllm:time_to_first_token_seconds_bucket'
```

If the endpoint has metrics but Prometheus does not, wait a few minutes after
enabling user workload monitoring and then re-run validation.

### Grafana route returns an authorization error

- **Likely causes:** the logged-in OpenShift user cannot satisfy the OAuth
  proxy SAR, the Grafana service account OAuth redirect annotation is not
  reconciled, or the route/service serving certificate has not settled.
- **Checks:**

```bash
oc get route grafana-route -n rhoai-demo-grafana -o yaml
oc get serviceaccount grafana-sa -n rhoai-demo-grafana -o yaml
oc auth can-i get services -n rhoai-demo-grafana \
  --as ai-admin --as-group rhods-admins
oc auth can-i get services -n rhoai-demo-grafana \
  --as ai-developer --as-group rhoai-developers
oc get rolebinding grafana-viewer-demo-users -n rhoai-demo-grafana -o yaml
oc get pod -n rhoai-demo-grafana -l app.kubernetes.io/name=grafana -o wide
```

The demo `ai-admin` and `ai-developer` users should return `yes` when their
OpenShift groups are included in the impersonation check. If they return `no`,
resync `stage-210-model-serving-foundation` and confirm the
`grafana-viewer-demo-users` RoleBinding contains the `rhods-admins` and
`rhoai-developers` groups.

### OpenShift ConsoleLink does not open Grafana

- **Likely causes:** the Grafana route was not ready when the sync hook ran,
  the `patch-grafana-consolelink` hook failed, or Argo CD has not reconciled
  the latest Stage 210 manifests.
- **Checks:**

```bash
oc get consolelink rhoai-demo-grafana -o jsonpath='{.spec.href}{"\n"}'
oc get route grafana-route -n rhoai-demo-grafana -o jsonpath='{.spec.host}{"\n"}'
oc get application stage-210-model-serving-foundation -n openshift-gitops \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

The `href` should point to
`/d/llm-performance/llm-inference-performance`. If it still contains the
placeholder host or old dashboard slug, hard-refresh or resync the Stage 210
Application.

### Grafana dashboards show datasource errors

- **Likely causes:** imported dashboard JSON still contains an unresolved
  datasource variable such as `${DS_PROMETHEUS}`, the dashboard references a
  datasource UID that does not exist, or the Prometheus datasource bearer token
  was not substituted into `secureJsonData`.
- **Checks:**

```bash
oc get grafanadatasource prometheus -n rhoai-demo-grafana \
  -o jsonpath='{.spec.uid}{" "}{.spec.valuesFrom[0].targetPath}{"\n"}'
oc get grafanadashboard -n rhoai-demo-grafana
./stage-210-model-serving-foundation/validate.sh
```

The datasource UID should be `Prometheus`, the datasource should use
`valuesFrom` for `secureJsonData.httpHeaderValue1`, and validation should pass
the live Grafana datasource query. If the browser still shows an old
datasource variable after GitOps sync, hard-refresh the Grafana tab. If
Grafana recently rolled out, allow the operator resync period to repopulate
datasources and dashboards, then rerun validation.

For the `LLM Inference Performance` dashboard specifically, vLLM panels should
use the live `namespace` label, the `vllm:inter_token_latency_seconds_bucket`
metric, and the active `:8080` scrape target labels. The llm-d EPP panels are
expected to show no data in Stage 210 because llm-d/EPP is not deployed yet.

### Stage 210 Application waits on benchmark-data PVC

- **Likely cause:** the storage class uses `WaitForFirstConsumer`, so
  `benchmark-data` remains `Pending` until a pod mounts it. Stage 210 solves
  this with the normal `seed-stage210-benchmark-data` Job in the same sync wave
  as the PVC.
- **Checks:**

```bash
oc get pvc benchmark-data -n demo-sandbox
oc get job seed-stage210-benchmark-data -n demo-sandbox
oc get application stage-210-model-serving-foundation -n openshift-gitops \
  -o jsonpath='{.status.operationState.message}{"\n"}'
```

If an older sync operation is stuck waiting for PVC health before the seed Job
exists, confirm the Application has no finalizers, delete only the Stage 210
Application, and rerun `./stage-210-model-serving-foundation/deploy.sh`. The
Application is recreated and re-adopts the existing resources.

### GuideLLM benchmark job fails

- **Likely causes:** the upstream GuideLLM image cannot be pulled, the
  endpoint is not reachable from inside the cluster, the selected rate profile
  overwhelms the one-GPU endpoint, the processor cannot be resolved, the
  `benchmark-data` PVC is missing, or the PVC cannot bind.
- **Checks:**

```bash
oc get pvc benchmark-data -n demo-sandbox
oc get configmap stage210-guidellm-prompts -n demo-sandbox \
  -o jsonpath='{.data.prompts\.csv}' | head -1
oc get job,pod,pvc -n demo-sandbox | grep guidellm
oc logs -n demo-sandbox job/<guidellm-job-name>
oc describe job -n demo-sandbox <guidellm-job-name>
```

Use a smaller smoke-test profile first:

```bash
RHOAI_GUIDELLM_RATE=1 RHOAI_GUIDELLM_MAX_SECONDS=30 RHOAI_GUIDELLM_OUTPUTS=benchmark-results.json \
  ./stage-210-model-serving-foundation/benchmark-guidellm.sh
```

Set `RHOAI_GUIDELLM_KEEP_RESOURCES=true` when you need the temporary Job, PVC,
or copy Job to remain for inspection.

If GuideLLM fails while reading `/data/prompts.csv`, confirm the Stage 210
Application synced the `benchmark-data` PVC and prompt ConfigMap, then resync
the Application so the seed hook copies the CSV into the PVC.

If GuideLLM fails while tokenizing the prompt file, confirm the script is
passing an explicit processor. Stage 210 defaults to:

```bash
RHOAI_NEMOTRON_GUIDELLM_PROCESSOR=nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8
```

If GuideLLM completes the benchmark but fails while writing
`benchmark-results.html` with an HTTP 301 from the old report-template URL,
avoid HTML output. Stage 210 defaults to JSON and CSV; use JSON-only when you
want the smallest smoke output:

```bash
RHOAI_GUIDELLM_OUTPUTS=benchmark-results.json \
  ./stage-210-model-serving-foundation/benchmark-guidellm.sh
```

## Stage 230: Models-as-a-Service

### AI asset endpoints show "Models as a Service could not be loaded"

- **Symptom:** OpenShift AI dashboard → Gen AI Studio → AI asset endpoints
  shows `Some model sources could not be loaded` or
  `Models as a Service could not be loaded`. The MaaS CRs may still show
  `Ready=True`.
- **Cause observed on cluster-klvxt:** the generated
  `kuadrant-maas-default-gateway` EnvoyFilter contains
  `allow_on_headers_stop_iteration`, but the OpenShift gateway Envoy rejects
  that WASM field. The Kuadrant WASM filter does not load, so Gateway requests
  reach `maas-api` without the required `X-MaaS-Username` and `X-MaaS-Group`
  headers.
- **Confirm:**

```bash
./stage-230-models-as-a-service/validate.sh

oc logs -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
  --since=10m --tail=200 | grep allow_on_headers_stop_iteration

oc logs -n redhat-ods-applications deploy/maas-api --since=10m \
  | grep 'Missing or empty username header'
```

The dashboard backend failure presents as:

```text
GET /gen-ai/api/v1/maas/models?namespace=<project> -> 503
GET /maas/api/v1/models -> 500
GET /maas/api/v1/subscriptions -> 500
```

Direct `maas-api` calls with explicit `X-MaaS-Username` and `X-MaaS-Group`
headers can still return subscriptions. That proves the MaaS subscription data
exists and isolates the defect to the Gateway/AuthPolicy header-injection path.

- **Do not use these as durable fixes:** scaling the RHCL/Kuadrant operator to
  zero breaks the `kuadrant-operator-wasm` service that serves the WASM plugin;
  adding a second compatibility EnvoyFilter can cause duplicate
  `kuadrant-wasm-shim` plugin load failures.
- **Current action:** treat this as an RHCL/OpenShift Service Mesh compatibility
  blocker for Stage 230. Keep the validation failure visible, check Red Hat
  errata or supported RHCL/OSSM version guidance, and do not claim the Stage
  230 dashboard experience is complete until the Gateway can inject MaaS
  identity headers.

### models-as-a-service project is not visible in the OpenShift AI dashboard

- **Likely cause:** the namespace lacks `opendatahub.io/dashboard: "true"` or
  the user does not have project RBAC.
- **Checks:**

```bash
oc get namespace models-as-a-service \
  -o jsonpath='{.metadata.labels.opendatahub\.io/dashboard}{"\n"}'
oc auth can-i get pods -n models-as-a-service \
  --as ai-admin --as-group rhods-admins
oc auth can-i get pods -n models-as-a-service \
  --as ai-developer --as-group rhoai-developers
```

Expected demo posture: `ai-admin` can administer the namespace;
`ai-developer` cannot. Developers consume MaaS models through AI asset
endpoints and API keys, not direct namespace access.

---

Legacy troubleshooting content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/TROUBLESHOOTING.md`
