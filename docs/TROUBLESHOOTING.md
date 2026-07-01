# Troubleshooting

Active troubleshooting guidance for the reimplementation.

## Operator-Generated Operand Images

If a generated operand appears to use the wrong image, first decide whether the
image is repo-owned or operator-owned. Repo-owned images include demo apps,
hook Jobs, modelcars, pipeline components, and utility containers authored by
this repository. Operator-owned images include CSV `relatedImages`, copied
CSVs, generated CR image fields, generated datasources, and
operator-created Deployments or StatefulSets.

For operator-owned images, diagnose but do not patch:

```bash
oc get subscription -n <operator-namespace> <subscription-name> \
  -o jsonpath='{.status.installedCSV}{"\n"}'
oc get csv -n <operator-namespace> <installed-csv> \
  -o jsonpath='{range .spec.relatedImages[*]}{.name}{"="}{.image}{"\n"}{end}'
oc get <generated-kind> <name> -n <namespace> -o yaml
```

Use the owning Subscription `status.installedCSV` as the authoritative
installed-version check. Copied CSVs created for all-namespace installs and
display-name matches can be misleading. Durable fixes should change
Subscription lifecycle policy, the product baseline, or documented CR fields;
generated image patches are expected to drift or be reconciled away.

If failed operator/controller pods remain after an API-server outage or leader
election loss, verify ClusterOperators and events first. Deleting only the
failed operator-managed pods so the owning controller recreates them is a live
recovery action, not a GitOps change.

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
- **Persistent OutOfSync on `DSCInitialization/default-dsci`** — check the
  storage version and fields before assuming Argo CD is stuck. Current RHOAI 3.4
  clusters serve `dscinitialization.opendatahub.io/v2`; fields such as
  `spec.monitoring.metrics.resources` are not in the v2 schema and are pruned or
  rejected by the API.
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

### Observability dashboard shows Service Unavailable

- **Symptom:** the RHOAI dashboard shows **Observe & monitor -> Dashboard**, but
  the page reports `Error loading components` or `Service Unavailable`.
- **Likely cause:** `OdhDashboardConfig.spec.dashboardConfig.observabilityDashboard`
  is enabled but the backing RHOAI observability stack in
  `redhat-ods-monitoring` did not deploy. On RHOAI 3.4, the documented
  prerequisites are Cluster Observability Operator, Red Hat build of
  OpenTelemetry, and Tempo Operator. `DSCInitialization.spec.monitoring` must
  also include metrics and traces configuration; `managementState=Managed` and
  `namespace=redhat-ods-monitoring` alone can leave the RHOAI `Monitoring`
  service reporting `MetricsNotConfigured` and `TracesNotConfigured`. In demo
  sandbox clusters, the product-generated monitoring stack can also expect
  `Secret/prometheus-web-tls-ca` while OpenShift service-ca injection creates
  the CA bundle as `ConfigMap/prometheus-web-tls-ca`; Stage 110 mirrors the
  ConfigMap into the expected Secret at sync time.
- **Checks:**

```bash
oc get subscription -n openshift-cluster-observability-operator cluster-observability-operator
oc get subscription -n openshift-opentelemetry-operator opentelemetry-product
oc get subscription -n openshift-tempo-operator tempo-product
oc get dscinitialization default-dsci \
  -o jsonpath='{.spec.monitoring.managementState}{" "}{.spec.monitoring.namespace}{" "}{.spec.monitoring.metrics.storage.size}{" "}{.spec.monitoring.traces.storage.backend}{" "}{.status.phase}{"\n"}'
oc get monitoring.services.platform.opendatahub.io default-monitoring \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{" "}{.reason}{"\n"}{end}'
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.observabilityDashboard}{"\n"}'
oc get secret prometheus-web-tls-ca -n redhat-ods-monitoring
oc get networkpolicy perses-backend-operator-access -n redhat-ods-monitoring
oc auth can-i list persesdashboards.perses.dev \
  --as=ai-admin --as-group=rhods-admins --all-namespaces
oc auth can-i create prometheuses/k8s --subresource=api \
  --as=ai-admin --as-group=rhods-admins -n openshift-monitoring
oc get pods,svc,route -n redhat-ods-monitoring
```

- **Fix:** reconcile Stage 110 from current Git. Stage 110 owns the three
  prerequisite operator Subscriptions, the complete
  `DSCInitialization.spec.monitoring` metrics/traces configuration, the
  `prometheus-web-tls-ca` sync hook, Perses backend access, dashboard RBAC, and
  the dashboard flag. Do not enable the dashboard flag by itself.

If `data-science-perses-0` is `CrashLoopBackOff`, inspect the pod logs and
compare the generated Perses image with the installed Cluster Observability
Operator related image:

```bash
oc logs pod/data-science-perses-0 -n redhat-ods-monitoring --previous
oc get subscription -A | grep -E 'cluster-observability|opentelemetry|tempo'
oc get perses data-science-perses -n redhat-ods-monitoring \
  -o jsonpath='{.spec.image}{"\n"}'
CSV=$(oc get subscription cluster-observability-operator \
  -n openshift-cluster-observability-operator \
  -o jsonpath='{.status.installedCSV}')
oc get csv "$CSV" -n openshift-cluster-observability-operator \
  -o jsonpath='{.spec.relatedImages[?(@.name=="perses")].image}{"\n"}'
```

If the generated Perses image differs from the installed Cluster Observability
Operator `perses` related image and the logs show unsupported Perses flags,
treat it as a product compatibility incident. Do not pin or patch the generated
`Perses` image: the RHOAI controller can reconcile it back, and operand image
selection should remain under the owning operator lifecycle. Stage 110 handles
the current RHOAI 3.4 compatibility posture by installing the Cluster
Observability Operator at `cluster-observability-operator.v1.4.0` through OLM
`startingCSV` plus manual InstallPlan approval automation.

If `perses-operator` in `openshift-cluster-observability-operator` restarts
with `Last State: OOMKilled` while `Monitoring/default-monitoring` later
recovers, keep the fix in the COO `Subscription`, not in the generated
Deployment. Stage 110 sets `Subscription.spec.config.resources` for the Cluster
Observability Operator overlay so OLM reconciles higher resource limits for the
operator-managed pods. Validate with:

```bash
oc describe pod -n openshift-cluster-observability-operator \
  -l app.kubernetes.io/name=perses-operator
oc get subscription cluster-observability-operator \
  -n openshift-cluster-observability-operator -o yaml
```

If the Perses dashboards are available but `default-monitoring` remains
`Not Ready` with `tempo-datasource` and `spec.client.tls.caCert ... namespace is
required`, the remaining issue is the RHOAI-generated Tempo
`PersesDatasource` not satisfying the installed v1alpha2 PersesDatasource
schema. Do not patch the operator-owned generated datasource by hand; either
use a compatible Cluster Observability Operator version or wait for the RHOAI
monitoring controller to generate the v1alpha2-required namespace field. If the
cluster already installed a newer Cluster Observability Operator, do not assume
that a Git change can downgrade it in place; plan a controlled prerequisite
operator reinstall or redeploy Stage 110 into a fresh environment.

### Cluster events show generated ServiceMonitor rejection

- **Symptom:** warning events report that ServiceMonitors such as
  `openshift-kueue-operator/kueue-metrics`,
  `openshift-lws-operator/lws-controller-manager-metrics-monitor`,
  `openshift-nfd/nfd-controller-manager-metrics-monitor`, or
  `redhat-ods-applications/odh-model-controller-metrics-monitor` were rejected
  because `endpoints[0]` accesses a bearer token file.
- **Cause observed on cluster-xgg8t and cluster-qt67m:** these ServiceMonitors
  are generated by platform or product operators and use `bearerTokenFile`. The
  user-workload Prometheus Operator rejects that field because filesystem bearer-token access
  is prohibited by the Prometheus specification.
- **Action:** do not change endpoint auth fields, copy the generated resources,
  or patch generated operands. Exclude only the known invalid generated
  ServiceMonitor resources from user-workload monitoring with Red Hat's
  documented `openshift.io/user-monitoring=false` label:

  ```bash
  oc label servicemonitor -n openshift-kueue-operator kueue-metrics \
    openshift.io/user-monitoring=false --overwrite
  oc label servicemonitor -n openshift-nfd nfd-controller-manager-metrics-monitor \
    openshift.io/user-monitoring=false --overwrite
  oc label servicemonitor -n redhat-ods-applications odh-model-controller-metrics-monitor \
    openshift.io/user-monitoring=false --overwrite
  oc label servicemonitor -n openshift-lws-operator lws-controller-manager-metrics-monitor \
    openshift.io/user-monitoring=false --overwrite
  ```

  Stage 220 deployment automation applies these labels idempotently. Historical
  `InvalidConfiguration` events can remain visible for a few minutes after the
  alert clears.

### TargetDown for generated Istio PodMonitor

- **Symptom:** `TargetDown` fires for
  `openshift-ingress/istio-pod-monitor` even though the MaaS and data-science
  Gateway pods are `Running` and `Ready`.
- **Cause observed on cluster-xgg8t and cluster-qt67m:** the generated
  `PodMonitor` creates
  scrape targets for the gateway pods on `15020`, `15021`, and `15090`.
  `/stats/prometheus` succeeds on `15020` and `15090`, but returns `404` on
  the status port `15021`.
- **Action:** keep the generated monitor but constrain it to the actual Istio
  gateway metrics port. `PodMonitor.spec.podMetricsEndpoints.port` is a
  verified CRD field, and the gateway pods expose `15020` as named port
  `metrics`. Because the generated relabeling otherwise still discovers all
  container ports, also add an explicit keep relabeling for the metrics port:

  ```bash
  oc patch podmonitor -n openshift-ingress istio-pod-monitor --type=json \
    -p='[{"op":"add","path":"/spec/podMetricsEndpoints/0/port","value":"metrics"}]'
  oc patch podmonitor -n openshift-ingress istio-pod-monitor --type=json \
    -p='[{"op":"add","path":"/spec/podMetricsEndpoints/0/relabelings/0","value":{"action":"keep","regex":"metrics","sourceLabels":["__meta_kubernetes_pod_container_port_name"]}}]'
  ```

  Stage 220 deployment automation applies this correction idempotently. Verify
  with the Prometheus targets API that only `15020` targets remain and are `up`.

### AlertmanagerReceiversNotConfigured in openshift-monitoring

- **Symptom:** `AlertmanagerReceiversNotConfigured` fires in
  `openshift-monitoring`, and the console says receivers are not configured.
- **Cause:** OpenShift installs Alertmanager but does not configure external
  notification integrations by default. Receiver names such as `Default`,
  `Watchdog`, and `Critical` are not enough; each receiver needs a supported
  integration such as a webhook, email, Slack, PagerDuty, or Microsoft Teams.
- **Action:** configure Alertmanager through the documented
  `openshift-monitoring/alertmanager-main` Secret. Stage 210 uses a
  GitOps-managed in-cluster webhook receiver so sandbox clusters have a real
  notification sink without committing external notification credentials.
  Watchdog is routed to the same sink with a shorter repeat interval so it can
  act as a heartbeat check.
- **Confirm:**

```bash
oc get deployment rhoai-demo-alert-webhook -n openshift-monitoring
oc get secret alertmanager-main -n openshift-monitoring \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
oc -n openshift-monitoring exec prometheus-k8s-0 -c prometheus -- \
  curl -s 'http://localhost:9090/api/v1/query?query=cluster%3Aalertmanager_integrations%3Amax' | jq
oc -n openshift-monitoring exec prometheus-k8s-0 -c prometheus -- \
  curl -s 'http://localhost:9090/api/v1/query?query=ALERTS%7Balertname%3D%22AlertmanagerReceiversNotConfigured%22%2Calertstate%3D%22firing%22%7D' | jq
```

- **Fix:** resync Stage 210 or apply the Stage 210 monitoring manifests. If a
  production receiver is required, replace the demo webhook with a supported
  receiver configuration and keep credentials in Kubernetes Secrets, not in
  Git.

### Control-plane pressure causes transient probe and catalog warnings

- **Symptom:** warnings arrive in bursts across multiple namespaces:
  `ConnectivityOutageDetected`, catalog source `connection refused`,
  webhook `no endpoints available`, readiness-probe timeouts, and temporary
  operator pod restarts. Red Hat build of OpenTelemetry can also temporarily
  enter `CrashLoopBackOff` during startup if it cannot read the cluster TLS
  profile from the Kubernetes API.
- **Cause observed on cluster-xgg8t:** control-plane nodes are `m6a.xlarge`;
  alerts report `HighOverallControlPlaneMemory`, and `oc adm top nodes` shows
  control-plane memory above 85-90% on busy nodes. This can make the API
  server, OLM, webhooks, and catalog pods briefly unresponsive even when all
  ClusterOperators recover to healthy.
- **Action:** first confirm that ClusterOperators are healthy, no pods remain
  failed, and stage validation passes. For a durable fix, resize the control
  plane through the OpenShift `ControlPlaneMachineSet` in a controlled
  maintenance window, for example from `m6a.xlarge` to a larger supported AWS
  type. Do not resize control-plane machines during a live demo unless the
  user accepts the rolling-control-plane risk. If OpenTelemetry failed only
  with an API timeout during this burst, wait for API recovery and recheck the
  CSV before changing operator configuration.

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
- **Stage boundary:** after Stage 220 has been deployed, a missing direct
  `demo-sandbox` `InferenceService` can be expected because Stage 220 migrates
  the shared Nemotron backend into `models-as-a-service` as an
  `LLMInferenceService`.
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
`--enable-prefix-caching`, `--max-model-len=8192`,
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

## Stage 220: Models-as-a-Service

### AI asset endpoints show "Models as a Service could not be loaded"

- **Symptom:** OpenShift AI dashboard → Gen AI Studio → AI asset endpoints
  shows `Some model sources could not be loaded` or
  `Models as a Service could not be loaded`. The MaaS CRs may still show
  `Ready=True`.
- **Cause observed on cluster-klvxt before the RHCL pin:** generated Kuadrant
  Gateway WASM configuration contained `allow_on_headers_stop_iteration`, but
  the OpenShift gateway Envoy rejected that WASM field. The Kuadrant filter
  did not load correctly, so Gateway requests reached `maas-api` without the
  required identity headers.
- **Confirm:**

```bash
./stage-220-models-as-a-service/validate.sh

oc logs -n openshift-ingress \
  -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
  --since=10m --tail=200 | grep allow_on_headers_stop_iteration

oc logs -n redhat-ods-applications deploy/maas-api --since=10m \
  | grep 'Missing or empty username header'

oc get authpolicy,tokenratelimitpolicy -n models-as-a-service
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
  `kuadrant-wasm-shim` plugin load failures. Do not patch generated Kuadrant
  `AuthPolicy` or EnvoyFilter resources in GitOps unless official Red Hat
  documentation or support guidance requires it.
- **Current action:** Stage 220 pins Red Hat Connectivity Link to
  `rhcl-operator.v1.3.4` with manual InstallPlan approval. If validation shows
  any other installed CSV, remediate RHCL through operator lifecycle first and
  then rerun `deploy.sh` and `validate.sh`. Do not claim the Stage 220
  dashboard experience is complete until generated model AuthPolicy and
  TokenRateLimitPolicy resources are enforced and the dashboard/API checks
  pass for real demo users.
- **Dependency-upgrade boundary observed on cluster-xgg8t:** approving the
  broader RHCL dependency InstallPlan moved RHCL to `1.3.4` and kept Stage 220
  functional, but the same plan failed for later dependency updates such as DNS
  Operator `1.3.1` and Service Mesh `3.3.5`. OLM reported
  `InstallComponentFailed` because generated MaaS Authorino `AuthConfig`
  resources did not validate against the stricter incoming
  `authconfigs.authorino.kuadrant.io` schema. Do not approve more dependency
  plans or patch generated `AuthConfig` resources as a workaround. Hold the
  validated operator set and require a Red Hat-supported replacement path plus
  full Stage 220 validation before moving beyond it.

### Gen AI Playground accepts prompts but models do not reply

- **Symptom:** `ai-developer` creates a Gen AI Playground in `demo-sandbox`,
  selects the MaaS Nemotron or external GPT model, submits a prompt, and the UI
  does not return a response.
- **Likely cause:** the dashboard-created `LlamaStackDistribution` was created
  with placeholder MaaS endpoint tokens such as `fake`. MaaS model discovery
  can still appear in the UI, but inference from the Llama Stack pod receives
  `401 Unauthorized` from the MaaS Gateway.
- **Confirm:**

```bash
oc get llamastackdistribution lsd-genai-playground -n demo-sandbox -o yaml
oc get deployment lsd-genai-playground -n demo-sandbox -o yaml
oc logs deployment/lsd-genai-playground -n demo-sandbox --since=10m \
  | grep -E '401|Unauthorized|fake'
```

- **Fix:** first recreate or update the Playground from the dashboard so it
  regenerates product-owned resources from the current AI asset endpoint list,
  then validate the Llama Stack and dashboard BFF response paths:

```bash
./stage-220-models-as-a-service/validate.sh
```

If the product-generated backend still contains placeholder tokens after
recreation, `configure-genai-playground.sh` can be used as a diagnostic repair
tool. It is not the normal desired configuration path.

If checking or unchecking a model in the Playground settings triggers a
Playground update, treat that as a new generated-resource lifecycle event.
Wait for the dashboard-created `LlamaStackDistribution` to become `Ready`,
refresh the browser, and rerun validation. Otherwise the UI can show the model
as selected while the backend has reset to stale generated state.

Expected model IDs inside Llama Stack are provider-qualified:

```text
maas-vllm-inference-<n>/nemotron-3-nano-30b-a3b
maas-vllm-inference-<m>/gpt-4o-mini
```

Short model IDs can fail through the Llama Stack API even when they work at the
raw MaaS Gateway layer.

If logs show `Model 'maas-vllm-inference-*/gpt-4o-mini' not found`, the
browser or dashboard backend is using a stale provider-qualified model id.
Refresh the page or recreate the Playground after the model list shows
`gpt-4o-mini` as Ready in AI asset endpoints.

If the AI asset endpoints MaaS tab shows the model name as `gpt-4o-mini`,
that is expected. The MaaS resource id and upstream OpenAI provider model id
are intentionally the same.

If direct Llama Stack `/v1/responses` checks pass but the browser still does
not show a reply, validate both dashboard BFF paths. First check
`/gen-ai/api/v1/lsd/models?namespace=<project>` and confirm the GPT entry
includes `gpt-4o-mini`. Then validate
`/gen-ai/api/v1/lsd/responses` with that listed model id. Non-browser BFF
checks must include both `Authorization: Bearer <user-token>` and
`x-forwarded-access-token: <user-token>`. A `401 Unauthorized` from the
dashboard pod with only one of those headers does not prove the MaaS route is
broken.

### OpenShift MCP server is not visible in Gen AI Playground

- **Symptom:** the Playground MCP tab does not list `OpenShift-MCP`, or MCP
  tool calls fail before reaching the server.
- **Likely cause:** the platform MCP discovery ConfigMap is missing, malformed,
  or points to a Service without ready endpoints.
- **Confirm:**

```bash
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o yaml
oc get deployment,service,endpoints openshift-mcp -n rhoai-mcp
oc get configmap openshift-mcp-config -n rhoai-mcp -o yaml
```

- **Fix:** sync Stage 220 and rerun validation:

```bash
./stage-220-models-as-a-service/deploy.sh
./stage-220-models-as-a-service/validate.sh
```

Do not replace the read-only OpenShift MCP server with the older generic MCP
demo image. Stage 220 follows the newer OpenShift MCP server project and Red
Hat preview guidance. If the server starts but tools fail, first check that
the config still includes `read_only = true`, `toolsets = ["core", "config"]`,
and denied entries for `Secret`, `ConfigMap`, and RBAC resources. Then inspect
the pod logs:

```bash
oc logs deployment/openshift-mcp -n rhoai-mcp --since=10m
```

### OpenShift MCP appears in Playground but returns no model response

- **Symptom:** `OpenShift-MCP` is visible and selectable in the Playground,
  but a chat message with MCP enabled returns an empty response, no visible
  answer, or an upstream connection error.
- **Likely causes:**
  - Llama Stack can reach the MCP server, but the MCP tool schema plus prompt
    exceeds the selected model's effective context/output budget.
  - The OpenShift MCP tool catalog is too broad for the demo, causing the
    model to spend the response budget listing tools rather than calling one.
  - The MCP server returns YAML for broad list tools, which can produce large
    tool results that are then forwarded through Llama Stack.
  - The MCP pod hit its memory limit and was OOMKilled while serving tool-list
    requests.
  - For external `gpt-4o-mini`, the MCP request or tool output is too large
    for the external provider quota or token-per-minute limit even though
    direct function calling is enabled.
- **Confirm:**

```bash
oc logs deployment/lsd-genai-playground -n demo-sandbox --since=30m \
  | grep -E 'maximum context length|MCP|mcp|Provider SDK error|Request too large|rate_limit_exceeded|tokens per min'
oc describe pod -n rhoai-mcp -l app.kubernetes.io/name=openshift-mcp \
  | grep -E 'OOMKilled|Restart Count|Limits|Requests'
oc get configmap openshift-mcp-config -n rhoai-mcp \
  -o jsonpath='{.data.config\.toml}'
```

- **Fix:** keep the Stage 220 OpenShift MCP server read-only and small-surface.
  The GitOps config must include `list_output = "table"`, an `enabled_tools`
  allowlist for the intended demo inspection tools, and enough memory for
  tool-list handling. Do not expose cluster-wide `namespaces_list`,
  `pods_list`, broad event listing, or log tools for the Stage 220 Playground
  demo. If the
  dashboard-created Llama Stack backend still uses a 4096-token vLLM output
  default for Nemotron, rerun:

```bash
./stage-220-models-as-a-service/configure-genai-playground.sh
./stage-220-models-as-a-service/validate.sh
```

The repair script should leave the vLLM provider at a smaller output default
such as 512 tokens. This is not a model-quality setting; it keeps MCP tool
context and answer generation bounded even though Stage 220 serves the
MaaS-published Nemotron backend with `--max-model-len=131072`.

For `gpt-4o-mini`, first distinguish direct tool-calling support from
Playground MCP behavior. A direct MaaS Chat Completions request with a simple
function schema can return `tool_calls`, while a Playground MCP request can
still fail if the MCP tool schema or tool result causes excessive provider
token pressure. In that case, use Nemotron as the primary OpenShift MCP demo
model. If you need to test GPT with MCP, start a new Playground chat, choose a
single bounded tool, and ask for a small result such as pod readiness in
`demo-sandbox` or one known pod. Do not use broad cluster-listing prompts for
the GPT MCP path.

### External OpenAI MaaS model stays Pending

- **Symptom:** `ExternalModel` exists, but `MaaSModelRef` is `Pending` and the
  combined `MaaSSubscription` reports a missing or unavailable external model.
- **Likely cause:** the `ExternalModel.metadata.name` is not a valid
  Kubernetes Service name, for example because the upstream provider model ID
  contains dots. The MaaS controller creates a Kubernetes `Service` from the
  `ExternalModel` name, and Services require DNS-1035 names. Prefer provider
  model IDs that are also DNS-safe, such as `gpt-4o-mini`; otherwise use a
  DNS-safe resource alias and keep the real provider model ID in
  `spec.targetModel`.
- **Confirm:**

```bash
oc logs deploy/maas-controller -n redhat-ods-applications --since=30m \
  | grep 'failed to create Service'
oc get externalmodel,maasmodelref,maassubscription -n models-as-a-service
```

- **Fix:** update GitOps so `ExternalModel`, `MaaSModelRef`,
  `MaaSSubscription.modelRefs`, and `MaaSAuthPolicy.modelRefs` use the same
  DNS-safe resource name. Then resync Stage 220 and rerun validation.

### External OpenAI MaaS inference fails after the model appears Ready

- **Symptom:** `ExternalModel` and `MaaSModelRef` are Ready, but inference
  through the MaaS Gateway returns `provider 'openai' credentials not found`.
- **Likely cause:** the provider Secret exists but lacks the official MaaS
  discovery label.
- **Fix:**

```bash
oc label secret openai-provider-api-key -n models-as-a-service --overwrite \
  inference.networking.k8s.io/bbr-managed=true
./stage-220-models-as-a-service/validate.sh
```

- **Symptom:** external OpenAI inference returns a provider-specific unsupported
  parameter error.
- **Fix:** verify the selected OpenAI model's current Chat Completions payload
  requirements. Stage 220 uses `gpt-4o-mini`, which accepts the standard
  `max_tokens` field used by the validator.

### Stage 220 sync fails on immutable Kueue queue label for maas-postgres

- **Symptom:** ArgoCD reports `metadata.labels[kueue.x-k8s.io/queue-name]:
  Invalid value: "default": field is immutable` while patching the
  `maas-postgres` StatefulSet.
- **Likely cause:** the PostgreSQL StatefulSet was created in
  `models-as-a-service` before that namespace became Kueue-managed. Kueue then
  tries to inject its default queue label during a later patch, and its webhook
  rejects the immutable label change.
- **Current design:** GitOps now creates demo-local PostgreSQL in
  `models-as-a-service-db`, which is not Kueue-managed. Keep MaaS/model
  resources in `models-as-a-service`; keep the database StatefulSet in the
  database namespace.
- **Cleanup for older clusters:** stop the stuck Stage 220 sync, temporarily
  remove both `kueue.openshift.io/managed` and legacy `kueue-managed`
  namespace labels from `models-as-a-service`, delete or finalize the old
  `maas-postgres` StatefulSet in that namespace, remove any orphaned
  `maas-postgres` Service/Pod/PVC/Secret, and let ArgoCD create the new
  database StatefulSet in `models-as-a-service-db`. Removing only
  `kueue.openshift.io/managed` is not enough if `kueue-managed=true` is still
  present, because the managed label can be recreated immediately.

### MaaS API key creation fails with old PostgreSQL hostname

- **Symptom:** Stage 220 model discovery works, MaaS CRs are Ready, but API key
  creation fails with `Failed to create API key` or `Failed to search API keys`.
  `maas-api` logs show a lookup for
  `maas-postgres.models-as-a-service.svc.cluster.local`.
- **Likely cause:** `maas-db-config` was corrected after MaaS was already
  running, but `deployment/maas-api` still has the old database configuration in
  memory. The official RHOAI MaaS guide requires restarting `maas-api` after
  changing `maas-db-config`.
- **Confirm:**

```bash
oc get secret maas-db-config -n redhat-ods-applications \
  -o jsonpath='{.data.DB_CONNECTION_URL}' | base64 -d
oc logs -n redhat-ods-applications deploy/maas-api --since=10m \
  | grep 'maas-postgres.models-as-a-service.svc.cluster.local'
```

- **Fix:** ensure the secret points at
  `maas-postgres.models-as-a-service-db.svc.cluster.local`, then restart and
  validate:

```bash
oc rollout restart deployment/maas-api -n redhat-ods-applications
oc rollout status deployment/maas-api -n redhat-ods-applications
./stage-220-models-as-a-service/validate.sh
```

### Stage 220 validation reports missing CRDs or Gateway host, but resources exist

- **Symptom:** validation reports missing MaaS/LWS CRDs, missing
  `maas-default-gateway` hostname, missing Nemotron readiness, or cascading
  `status=000` MaaS API checks, but manual `oc get crd`, `oc get gateway`, and
  `oc get llminferenceservice` show healthy resources.
- **Likely cause:** transient OpenShift API reads returned empty output during
  validation. This can cascade: if `GATEWAY_HOST` is empty, the later
  subscription, API-key, inference, and unauthenticated checks build URLs with
  no host and fail with `no host given`.
- **Fix:** rerun the current Stage 220 validator, which retries critical CRD
  and JSONPath reads and falls back to the Ready `MaaSModelRef.status.endpoint`
  when deriving the Gateway host. Do not patch generated MaaS, Kuadrant,
  Gateway, or Llama Stack resources unless the retried checks and manual
  inspection still show a real platform defect.

Useful confirmation commands:

```bash
oc get crd tenants.maas.opendatahub.io leaderworkersets.leaderworkerset.x-k8s.io
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.spec.listeners[?(@.name=="https")].hostname}{"\n"}'
oc get llminferenceservice nemotron-3-nano-30b-a3b -n models-as-a-service \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
oc get maasmodelrefs -n models-as-a-service
```

### MaaS API key cleanup jobs fail every 15 minutes

- **Symptom:** `maas-api-key-cleanup-*` Jobs in `redhat-ods-applications` fail
  with backoff or active-deadline events. A manual probe to the generated
  command times out:

```bash
oc get cronjob maas-api-key-cleanup -n redhat-ods-applications -o yaml
oc get networkpolicy maas-api-cleanup-restrict -n redhat-ods-applications -o yaml
```

- **Cause observed on cluster-xgg8t:** the generated CronJob called
  `http://maas-api:8080/internal/v1/api-keys/cleanup`, but the generated
  `maas-api` Service and Deployment expose HTTPS on port `8443`. The generated
  cleanup NetworkPolicy also restricted cleanup pods to port `8080`.
- **Confirm the real endpoint:**

```bash
oc run maas-cleanup-https-check --rm -i --restart=Never \
  -n redhat-ods-applications \
  --image=registry.redhat.io/ubi9/ubi-minimal \
  --command -- /bin/sh -c \
  'curl -sk -i -X POST https://maas-api:8443/internal/v1/api-keys/cleanup'
```

- **Live demo recovery:** suspend the generated broken CronJob and create a
  clearly annotated replacement CronJob that calls the verified HTTPS endpoint.
  Treat this as live recovery for the active RHOAI 3.4 build, not as a product
  recommendation. Remove the replacement after Red Hat fixes the generated
  resources in a future operator update.

```bash
oc patch cronjob maas-api-key-cleanup -n redhat-ods-applications \
  --type=merge -p '{"spec":{"suspend":true}}'
```

### Nemotron still exists as a direct demo-sandbox deployment

- **Symptom:** after deploying Stage 220, `oc get inferenceservice
  nvidia-nemotron-3-nano-30b-a3b -n demo-sandbox` still returns a resource, or
  the MaaS namespace has no Nemotron `LLMInferenceService`.
- **Cause:** Stage 220 did not run the cleanup path, `RHOAI_STAGE220_CLEANUP_DEMO_SANDBOX_NEMOTRON`
  was set to `false`, or the old direct deployment was recreated outside
  GitOps.
- **Fix:** run the guarded Stage 220 deployment wrapper. It deletes stale
  direct Nemotron serving resources from `demo-sandbox` and lets Argo CD create
  the MaaS-owned backend in `models-as-a-service`:

```bash
./stage-220-models-as-a-service/deploy.sh
./stage-220-models-as-a-service/validate.sh
```

Expected MaaS-backed state:

```bash
oc get inferenceservice nvidia-nemotron-3-nano-30b-a3b -n demo-sandbox
oc get llminferenceservice nemotron-3-nano-30b-a3b -n models-as-a-service
oc get maasmodelref nemotron-3-nano-30b-a3b -n models-as-a-service
```

The direct `InferenceService` should be absent. The MaaS
`LLMInferenceService` and `MaaSModelRef` should exist, and the
`LLMInferenceService` should eventually report `Ready=True` after the model
pull and startup complete.

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

## Stage 230: Private Data RAG

Stage 230 is being reimplemented. The previous whoami/Docling/DSPA/pgvector
troubleshooting entries no longer describe the intended target design and
should not be used as active recovery guidance for the new RAG stage.

### Old Stage 230 resources exist in a live cluster

- **Symptom:** `enterprise-rag` contains resources such as
  `private-rag-chatbot`, `private-rag-docling`, `private-rag-pipelines`,
  `private-rag-postgres`, `whoami` vector-store references, or pgvector-related
  Secrets.
- **Likely cause:** the previous Stage 230 implementation was deployed before
  the AG News/Milvus reset.
- **Fix:** do not patch those resources into the new design. Remove or replace
  them as part of the Stage 230 reset implementation, then let Argo CD recreate
  only the new desired resources.

### Old Stage 230 scripts are about to be run

- **Symptom:** a command path references `run-whoami-ingestion-pipeline.sh`,
  Docling, DSPA, pgvector, or `private-rag-chatbot`.
- **Fix:** stop and use `stage-230-private-data-rag/PLAN.md` instead. The old
  scripts are stale until they are rewritten for the new metadata-aware AG News
  RAG flow and the later Docling/KFP Dutch publication phase.

### New Stage 230 implementation fails during development

Use `rhoai-enterprise-rag` and `rhoai-llama-stack` first, then add concrete
symptoms here after live validation creates repeatable failure modes. The first
new troubleshooting entries should cover:

- Llama Stack provider registration failures
- PostgreSQL metadata connection failures
- Milvus gRPC or token failures
- PVCs stuck in `Pending` with `WaitForFirstConsumer`
- embedding model and vector dimension mismatches
- Files API upload or vector-store attachment errors
- metadata filter extraction failures
- hybrid search returning empty results
- reranker endpoint failures
- Enterprise RAG Workbench startup failures
- MaaS-backed Nemotron authorization failures
- Docling conversion output missing or malformed after the Dutch corpus is
  introduced
- KFP run failures after Docling automation is introduced

Do not carry forward old pgvector, DSPA, Docling, or whoami-specific recovery
steps unless those components are intentionally reintroduced.

### Stage 230 Argo CD sync waits on the Milvus PVC

- **Symptom:** the Stage 230 Application remains `OutOfSync` or `Progressing`,
  `private-rag-milvus-data` is `Pending`, and the PVC event says
  `waiting for first consumer to be created before binding`.
- **Likely cause:** the active storage class uses `WaitForFirstConsumer`.
  If the PVC is placed in an earlier Argo CD sync wave than the Deployment that
  consumes it, Argo CD waits for a volume bind that cannot happen yet.
- **Fix:** keep the Milvus PVC and Milvus Deployment in the same sync wave so
  the scheduler can create the first consumer and trigger dynamic provisioning.
  Do not manually bind the PVC or change the cluster storage class for this
  demo stage.

### Stage 230 deploy cannot create the Llama Stack MaaS token

- **Symptom:** `deploy.sh` fails with a message asking for
  `RHOAI_STAGE230_MAAS_API_KEY` or `AI_DEVELOPER_PASSWORD`.
- **Likely cause:** the script could not create a MaaS API key for the
  Stage 220 subscription. Llama Stack needs a MaaS API key because the RAG
  runtime calls the governed Nemotron endpoint through MaaS.
- **Fix:** either set `AI_DEVELOPER_PASSWORD` in `.env` so the script can log
  in as `ai-developer` and create the key, or create a MaaS API key manually
  for the configured subscription and store it locally as
  `RHOAI_STAGE230_MAAS_API_KEY`. Do not commit the key.

### Llama Stack starts but does not list Nemotron

- **Symptom:** `validate.sh` reports that `/v1/models` does not include
  `nemotron-3-nano-30b-a3b`.
- **Likely cause:** the `private-rag-llama-stack-secret` contains a MaaS
  endpoint without the OpenAI-compatible `/v1` suffix, a stale endpoint, invalid
  API key, or mismatched `INFERENCE_MODEL`.
- **Fix:** confirm Stage 220 passes, then rerun
  `stage-230-private-data-rag/deploy.sh` so it refreshes the Llama Stack Secret
  from the current `MaaSModelRef.status.endpoint`, normalizes it to `/v1`, and
  uses the current API-key flow.

### Llama Stack is Ready but no OpenShift Route exists

- **Symptom:** `LlamaStackDistribution.status.phase` is `Ready`, but no Route
  is created and the namespace has an operator-owned Ingress with a wildcard or
  missing host.
- **Likely cause:** the installed Llama Stack operator exposes
  `network.exposeRoute` as an Ingress toggle. On OpenShift, a hostless Ingress
  is not converted to a Route by the ingress-to-route controller.
- **Fix:** keep `LlamaStackDistribution.spec.network.exposeRoute: false` and
  manage an explicit OpenShift `Route` in GitOps that points to the
  operator-managed `lsd-enterprise-rag-service` Service. Do not patch the
  generated Ingress.

### Llama Stack Responses API says the Nemotron model is not found

- **Symptom:** `/v1/models` shows Nemotron, but `/v1/responses` with
  `model: nemotron-3-nano-30b-a3b` returns `Model ... not found`.
- **Likely cause:** Llama Stack registers the model with a provider-qualified
  identifier.
- **Fix:** use the exact identifier returned by `/v1/models`, currently
  `vllm-inference/nemotron-3-nano-30b-a3b`.

### Stage 230 hybrid search ignores metadata filters

- **Symptom:** `vector_stores.search` with `search_mode: hybrid` and an
  OpenAI-style filter such as
  `{"type":"eq","key":"category","value":"business"}` returns chunks from
  other categories, while `search_mode: vector` or `keyword` returns the
  expected category.
- **Likely cause:** in the observed RHOAI 3.4 Llama Stack remote Milvus path,
  native hybrid search does not enforce the translated filter expression,
  although the same expression works directly against Milvus.
- **Fix:** use filtered `vector` search for the current deterministic smoke
  validation. Do not claim hybrid metadata filtering until this behavior is
  resolved through a supported Llama Stack/RHOAI path.

### Stage 230 Qwen3 reranker does not become Ready

- **Symptom:** `validate.sh` reports that `InferenceService/qwen3-reranker`
  is missing or not Ready, or the `qwen3-reranker` Route has no backend.
- **Likely cause:** the CPU vLLM runtime image, modelcar pull, Kueue queue
  label, or resource request is not accepted by the current cluster. The
  Qwen3 reranker modelcar is a demo exception adapted from the Red Hat
  article-linked implementation, not an operator-managed product operand. The
  article-linked `8` CPU request may not fit a fresh demo cluster if no worker
  has enough unallocated requested CPU, so the active GitOps manifest uses a
  smaller `4` CPU / `10Gi` request and reduced batching.
- **Fix:** inspect the KServe predictor pod, init container, and events:

  ```bash
  oc get inferenceservice qwen3-reranker -n enterprise-rag
  oc get pods -n enterprise-rag | grep qwen3-reranker
  oc describe inferenceservice qwen3-reranker -n enterprise-rag
  oc describe pod -n enterprise-rag -l serving.kserve.io/inferenceservice=qwen3-reranker
  oc get localqueue lq-cpu-default -n enterprise-rag
  oc logs -n enterprise-rag deploy/qwen3-reranker-predictor --all-containers --tail=100
  ```

  Do not patch generated KServe operand images. If the runtime image or
  modelcar no longer works, update the GitOps-managed `ServingRuntime` or
  `InferenceService` only after recording the artifact decision in
  `stage-230-private-data-rag/PLAN.md`.

### Stage 230 Enterprise RAG Workbench does not start

- **Symptom:** the `Enterprise RAG Workbench` remains Starting, the Notebook
  does not report Ready, or the user cannot open JupyterLab from the
  `enterprise-rag` project.
- **Likely cause:** missing project access, an unavailable workbench image,
  missing `lq-cpu-default` LocalQueue for the `cpu-default` hardware profile,
  PVC binding delay, failed repository clone, or package install failure in the
  bootstrap init container. The RHOAI notebook image can run inside a virtual
  environment, so the bootstrap must not use `pip install --user`.
  Reused PVCs can also contain a shallow Git checkout that diverges from the
  branch head; the bootstrap should reset the repo copy to the fetched branch
  rather than relying on `git pull --ff-only`.
  The RHOAI 3.4 Python package index might not publish every upstream patch
  version; pin notebook dependencies to versions available from that index and
  compatible with the active server.
  RHOAI also injects workbench trusted-CA and pipeline runtime mounts; keep the
  GitOps Notebook manifest aligned with those controller-managed defaults to
  avoid persistent Argo CD drift.
  In RHOAI 3.x, workbench access uses Gateway API path-based routing. A
  GitOps-created Notebook must use
  `notebooks.opendatahub.io/inject-auth: "true"` so the notebook controller
  injects the `kube-rbac-proxy` sidecar,
  creates the `*-kube-rbac-proxy` Service, and points the HTTPRoute backend to
  that service. The older `notebooks.opendatahub.io/inject-oauth` annotation
  leaves the dashboard in migration-required mode and the Open link falls back
  to legacy Route lookup. The dashboard also uses
  `notebooks.opendatahub.io/last-image-version-git-commit-selection` to decide
  whether a selected workbench image is current for the selected ImageStream
  tag.
- **GitOps note:** the Notebook and its PVC must be in the same Argo CD sync
  wave when the storage class uses `WaitForFirstConsumer`; otherwise Argo can
  wait on the PVC before creating the consumer pod.
- **Fix:** inspect the Notebook, PVC, pod events, and bootstrap logs:

  ```bash
  oc get notebook enterprise-rag-workbench -n enterprise-rag
  oc get localqueue lq-cpu-default -n enterprise-rag
  oc get pvc enterprise-rag-workbench -n enterprise-rag
  oc get pods -n enterprise-rag | grep enterprise-rag-workbench
  oc describe notebook enterprise-rag-workbench -n enterprise-rag
  oc get svc enterprise-rag-workbench-kube-rbac-proxy -n enterprise-rag
  oc get endpointslice -n enterprise-rag \
    -l kubernetes.io/service-name=enterprise-rag-workbench-kube-rbac-proxy
  oc get httproute nb-enterprise-rag-enterprise-rag-workbench -n redhat-ods-applications -o yaml
  oc logs -n enterprise-rag <workbench-pod> -c bootstrap-stage-230 --tail=100
  ```

  Keep the workbench image, Notebook fields, and PVC in GitOps. Do not commit
  Git credentials or package tokens into the notebook, `requirements.txt`, or
  manifests.

### Stage 230 Workbench opens to `no healthy upstream`

- **Symptom:** the OpenShift AI dashboard Open link resolves to the Gateway URL,
  but the browser shows `no healthy upstream`.
- **Likely cause:** the generated `HTTPRoute` points to
  `enterprise-rag-workbench-kube-rbac-proxy:8443`, but the generated
  `StatefulSet` or running pod does not include the `kube-rbac-proxy` sidecar,
  so the proxy Service has no ready endpoint. This can happen when an existing
  GitOps-created Notebook is migrated from legacy `inject-oauth` to
  `notebooks.opendatahub.io/inject-auth: "true"` after the StatefulSet already
  exists. The notebook controller can update the Notebook template, but the
  Kubernetes StatefulSet pod template container list is immutable.
- **Checks:**

  ```bash
  oc get notebook enterprise-rag-workbench -n enterprise-rag \
    -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'
  oc get statefulset enterprise-rag-workbench -n enterprise-rag \
    -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'
  oc get pods -n enterprise-rag -l statefulset=enterprise-rag-workbench \
    -o jsonpath='{.items[0].spec.containers[*].name}{" "}{.items[0].status.containerStatuses[*].ready}{"\n"}'
  oc get endpointslice -n enterprise-rag \
    -l kubernetes.io/service-name=enterprise-rag-workbench-kube-rbac-proxy \
    -o jsonpath='{range .items[*]}{range .endpoints[*]}{.addresses[0]}{" ready="}{.conditions.ready}{" "}{end}{range .ports[*]}{.port}{" "}{end}{"\n"}{end}'
  ```

- **Fix:** keep the Notebook and PVC. Delete only the generated StatefulSet so
  the RHOAI notebook controller recreates it from the corrected Notebook spec:

  ```bash
  oc delete statefulset enterprise-rag-workbench -n enterprise-rag \
    --wait=true --timeout=90s
  ./stage-230-private-data-rag/validate.sh
  ```

  Do not copy the generated proxy container image, generated volumes, generated
  Service, or generated HTTPRoute into GitOps. GitOps owns the supported
  Notebook annotations and workbench template; the notebook controller owns the
  generated access operands.

---

Legacy troubleshooting content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/TROUBLESHOOTING.md`
