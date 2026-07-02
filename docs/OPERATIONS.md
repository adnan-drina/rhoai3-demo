# Operations

Active operations guidance for the reimplementation.

## Current Demo Storyline

The active implementation follows this sequence:

1. `stage-110-rhoai-base-platform` - GitOps, ODF MCG, RHOAI base platform,
   RHOAI observability prerequisites, model registry, access personas, and
   shared DSC ownership.
2. `stage-120-gpu-as-a-service` - GPU worker capacity, NVIDIA GPU enablement,
   Kueue quotas, and RHOAI hardware profiles.
3. `stage-210-model-serving-foundation` - enable the standard KServe model
   serving platform, vLLM serving path, `demo-registry`, Nemotron metadata,
   Nemotron endpoint readiness, and lightweight GuideLLM/Grafana baseline.
4. `stage-220-models-as-a-service` - MaaS prerequisite enablement, local
   Nemotron `LLMInferenceService` publication in `models-as-a-service`,
   external OpenAI model publication, and governed access to both models.
5. `stage-230-private-data-rag` - metadata-aware enterprise RAG with RHOAI
   Llama Stack / OGX, PostgreSQL with pgvector, AG News validation, official
   RHOAI product-document Q&A, and Nemotron consumed through Stage 220 MaaS.

## Operator Lifecycle And Image Ownership

Before changing an image value in GitOps, classify who owns it:

- **Repo-owned images:** Argo CD hook Jobs, utility containers, demo apps,
  pipeline component images, modelcar images, workbench images, and other
  workloads authored by this repository. Avoid explicit image tags or digests
  unless Red Hat documentation, validated artifact guidance, or a documented
  non-operator demo-app exception requires them.
- **Operator-owned images:** OLM CSV `relatedImages`, copied CSVs, generated CR
  image fields, generated datasources, and operator-created Deployments or
  StatefulSets. These must remain owned by OLM or the product operator.

Do not patch operator-generated operand images as a compatibility shortcut.
Use those values only for diagnosis, for example by comparing a generated CR
with the owning Subscription `status.installedCSV` and CSV `relatedImages`.
Durable fixes belong in Git-managed Subscription lifecycle policy (`channel`,
`startingCSV`, `installPlanApproval`), `docs/PLATFORM_BASELINE.md`, or a
documented product CR field that official docs expose as a supported override.
For platform components, repeatability should come from Red Hat Operator
packages and product lifecycle management, not from manually pinning images.

Deleting a failed operator/controller pod can be appropriate after API-server
instability when logs show leader-election or API timeout failures and the
owning Deployment is otherwise healthy. Treat that as live recovery only. Do
not capture it as generated Deployment patches or operand image pins in Git.

## Stage 110: RHOAI Base Platform

### Bootstrap Sequence

1. Copy `env.example` to `.env` and set `RHOAI_EXPECTED_API_SERVER` and `KUBECONFIG`.
2. Run `stage-110-rhoai-base-platform/deploy.sh`. The script:
   - Verifies the target cluster against `RHOAI_EXPECTED_API_SERVER`.
   - Applies `gitops/bootstrap/overlays/operator` to install the OpenShift GitOps operator on the baseline-pinned channel (`gitops-1.20`). Do not apply `gitops/bootstrap/base` directly — its channel is a placeholder patched by the overlay.
   - Waits for the `openshift-gitops-operator` CSV to reach `Succeeded` and for the ArgoCD instance to become Available.
   - Applies `gitops/bootstrap/overlays/demo` (ArgoCD instance config for annotation resource tracking + the `rhoai-demo` AppProject), which depend on CRDs the operator installs.
   - Creates the `stage-110-rhoai-base-platform` Argo CD Application, which then reconciles ODF, OpenShift observability prerequisite operators, and RHOAI.
3. Run `stage-110-rhoai-base-platform/validate.sh` to confirm all components are healthy.
4. Run `stage-110-rhoai-base-platform/setup-access.sh` to configure platform access (htpasswd users, RHOAI admin, and the `demo-sandbox` S3 connection). This is a separate script because it modifies cluster authentication and depends on the GitOps-provisioned `ObjectBucketClaim`. See **Platform Access** below.

### Channel Verification

GitOps operator channel is pinned to `gitops-1.20` in `gitops/bootstrap/overlays/operator/patch-channel.yaml`. Verified 2026-06-11 against OCP 4.20.24 on cluster-klvxt — no change needed before deploy.

Stage 110 also installs the RHOAI observability prerequisite operators from
`redhat-operators`:

- `cluster-observability-operator` in `openshift-cluster-observability-operator`
  on the `stable` channel, held at
  `cluster-observability-operator.v1.4.0` with `installPlanApproval: Manual`
  and a GitOps hook that approves only that generated InstallPlan
- `opentelemetry-product` in `openshift-opentelemetry-operator`
- `tempo-product` in `openshift-tempo-operator`

The package/channel selection was verified from the active cluster catalog on
the OCP 4.20 / RHOAI 3.4 baseline. The Cluster Observability Operator hold is
an OLM lifecycle policy, not an operand image pin; Perses, Prometheus, and
related operand images remain operator-managed. Stage 110 sets
`Subscription.spec.config.resources` for the Cluster Observability Operator so
OLM gives the operator pods enough headroom; this prevents the
`perses-operator` pod from repeatedly hitting the default 512Mi limit during
dashboard reconciliation bursts. These operators must be available before the
RHOAI `DSCInitialization.spec.monitoring` stack can create the backing services
for **Observe & monitor -> Dashboard**.

Stage 110 also carries a narrow RHOAI 3.4 observability compatibility layer:

- `redhat-ods-monitoring` is GitOps-managed as the monitoring namespace.
- `job-sync-prometheus-web-tls-ca` mirrors the service-ca injected
  `ConfigMap/prometheus-web-tls-ca` into the
  `Secret/prometheus-web-tls-ca` expected by the product-generated
  `MonitoringStack`.
- `perses-backend-operator-access` allows the Perses operator to reach the
  RHOAI Perses backend when OLM installs the operator outside
  `redhat-ods-monitoring`.
- `rhods-admins` receives read-only Perses dashboard/datasource discovery plus
  the narrow `prometheuses/api/k8s` access required by the dashboard query
  path.

Remove these helpers only after validating that a later RHOAI/observability
operator build creates equivalent behavior natively.

### Accessing Argo CD

```bash
oc get route openshift-gitops-server -n openshift-gitops \
  -o jsonpath='{.spec.host}'
```

Log in with OpenShift OAuth (cluster-admin). The `rhoai-demo` AppProject scopes all demo Applications.

#### Argo CD cluster-admin grant (demo posture)

The default `openshift-gitops` ArgoCD instance ships with a scoped ClusterRole that cannot create the cluster-scoped resources, SCCs, and cross-namespace ServiceAccounts the ODF and RHOAI operators require. The bootstrap overlay (`gitops/bootstrap/overlays/demo/argocd-cluster-admin.yaml`) grants the `openshift-gitops-argocd-application-controller` service account `cluster-admin` via a ClusterRoleBinding.

This is accepted **for this demo only**, per AGENTS.md. A least-privilege replacement (scoped to the resource kinds the demo actually manages) is tracked in `docs/BACKLOG.md`. Verify the grant with:

```bash
oc auth can-i create serviceaccounts -n openshift-storage \
  --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
```

### ODF MCG — S3 Endpoint Discovery

After `NooBaa` phase reaches `Ready`:

```bash
oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}'
```

The NooBaa admin credentials are in the `noobaa-admin` secret in `openshift-storage`. Project-scoped S3 credentials are generated by `ObjectBucketClaim` resources — use those for RHOAI workloads, not the admin secret.

### RHOAI Dashboard

```bash
oc get route rhods-dashboard -n redhat-ods-applications \
  -o jsonpath='{.spec.host}'
```

### RHOAI Observability Dashboard

RHOAI 3.4 treats the Observability dashboard as Technology Preview. Stage 110
enables the documented sequence:

1. Install Cluster Observability Operator, Red Hat build of OpenTelemetry, and
   Tempo Operator.
2. Configure `DSCInitialization.spec.monitoring.managementState=Managed`,
   `spec.monitoring.namespace=redhat-ods-monitoring`, metrics storage, and
   PV-backed traces.
3. Set
   `OdhDashboardConfig.spec.dashboardConfig.observabilityDashboard=true`.

Validate the backing stack before relying on the UI:

```bash
oc get subscription -n openshift-cluster-observability-operator cluster-observability-operator
oc get subscription -n openshift-opentelemetry-operator opentelemetry-product
oc get subscription -n openshift-tempo-operator tempo-product
oc get subscription cluster-observability-operator \
  -n openshift-cluster-observability-operator \
  -o jsonpath='{.spec.installPlanApproval}{" "}{.spec.startingCSV}{" "}{.status.installedCSV}{"\n"}'
oc get pods -n redhat-ods-monitoring
oc get secret prometheus-web-tls-ca -n redhat-ods-monitoring
oc get networkpolicy perses-backend-operator-access -n redhat-ods-monitoring
oc get dscinitialization default-dsci \
  -o jsonpath='{.spec.monitoring.managementState}{" "}{.spec.monitoring.namespace}{" "}{.spec.monitoring.metrics.storage.size}{" "}{.spec.monitoring.traces.storage.backend}{"\n"}'
oc get monitoring.services.platform.opendatahub.io default-monitoring \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{" "}{.reason}{"\n"}{end}'
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.observabilityDashboard}{"\n"}'
oc auth can-i list persesdashboards.perses.dev \
  --as=ai-admin --as-group=rhods-admins --all-namespaces
oc auth can-i create prometheuses/k8s --subresource=api \
  --as=ai-admin --as-group=rhods-admins -n openshift-monitoring
```

### Model Registry

The `modelregistry` DSC component provisions the operator and the
`rhoai-model-registries` namespace. The demo registry instance is now
GitOps-managed as `demo-registry` in the Stage 110 RHOAI registry base.

Verify the registry stack:

```bash
oc get deployment model-registry-operator-controller-manager \
  -n redhat-ods-applications
oc get modelregistries.modelregistry.opendatahub.io demo-registry \
  -n rhoai-model-registries
```

The registry uses the default generated PostgreSQL database. This is sufficient
for the demo and for fresh-environment reproducibility, but it is not the
production registry posture. For production, use an external PostgreSQL 16.x or
MySQL 9.x database and configure host, port, credentials, and CA certificate
settings.

Dashboard day-2 creation remains a useful manual workflow reference:

1. Open the RHOAI Dashboard → **Settings → Model resources and operations → Model registry settings**.
2. Click **Create model registry**.
3. Set a name (for the current demo environment, `demo-registry`). The resource
   name cannot be changed after creation.
4. For **database**, select **Default database** (PostgreSQL provisioned automatically by RHOAI — non-production only, sufficient for this demo).
5. Save. RHOAI creates the registry service and generates a `<name>-users` group and RBAC role in `rhoai-model-registries`.

To grant access, go to **Settings → AI registry settings**, select the registry, and add the relevant OpenShift group or user.

Current cluster-klvxt validation state originally created manually from the
dashboard and now handled by Stage 210 scripts when absent:

- Model registry resource: `demo-registry` in `rhoai-model-registries`.
- Nemotron 3 was manually registered in `demo-registry`.
- The registry entry was used to manually deploy the first Nemotron endpoint in
  `demo-sandbox`.

For fresh environments, run `stage-210-model-serving-foundation/deploy.sh` after
Stages 110 and 120 are healthy. It reuses this state when present and creates
missing registry metadata and the endpoint when absent.

Stage 220 migrates the shared Nemotron serving path into MaaS. Its deploy
wrapper removes a stale direct Nemotron deployment from `demo-sandbox` before
the MaaS-owned `LLMInferenceService` is reconciled in `models-as-a-service`.

Stage 230 consumes the MaaS-owned Nemotron endpoint. It does not deploy another
model or bypass MaaS governance.

### Platform Access (Users, Project, Connection)

`setup-access.sh` makes the platform ready for a user to log in and work. It is idempotent and re-runnable.

What it creates:

- **htpasswd identity provider** `demo-htpasswd` on the cluster `OAuth`, backed by `htpasswd-secret` in `openshift-config`. `kubeadmin` is retained as the cluster-admin recovery path.
- **`ai-admin`** — added to the `rhods-admins` group, which the RHOAI `auth` CR lists under `adminGroups`, granting RHOAI administrator access.
- **`ai-developer`** — a regular user; the GitOps-managed `rhoai-developers` group has Contributor (`edit`) access to `demo-sandbox`.
- **`demo-sandbox-s3`** — an S3 connection secret built from the `demo-sandbox-bucket` ObjectBucketClaim, labeled `opendatahub.io/dashboard: "true"` and referencing the `s3` connection type.

Credentials: passwords are generated and written to the gitignored `.env` (`AI_ADMIN_PASSWORD`, `AI_DEVELOPER_PASSWORD`). Set them in `.env` before running to use fixed values instead. Retrieve later with:

```bash
grep -E '^AI_(ADMIN|DEVELOPER)_PASSWORD=' .env
```

Login:

```bash
oc whoami --show-console   # console URL
# Log in via the demo-htpasswd identity provider as ai-admin or ai-developer.
```

htpasswd identities are created on first login; allow ~1 minute for the OAuth pods to roll out after running the script. After a permission change, users must log out of active OpenShift AI/Jupyter sessions.

Using `demo-sandbox`: log in as `ai-developer`, open the project in the RHOAI dashboard, create a workbench, and select the `demo-sandbox object storage` connection to mount `AWS_*` environment variables. The S3 endpoint is the in-cluster `https://s3.openshift-storage.svc:443` (self-signed; use `verify=False` in Boto3 for the demo).

### Adding RHOAI Components (Later Stages)

The `DataScienceCluster` at `gitops/stage-110-rhoai-base-platform/rhoai/instance/base/datasciencecluster.yaml` is the base shared copy. Later stages must not render a second `DataScienceCluster`; they enable only their component deltas through GitOps hook jobs that patch the shared DSC. The Stage 110 Argo CD Application ignores those component fields so it does not self-heal later-stage state back to the base. See `project-gitops-authoring` and `rhoai-dsci-dsc-configuration`.

## Stage 120: GPU-as-a-Service

### Deploy And Validate

Stage 120 depends on Stage 110. Run Stage 110 validation first.

```bash
./stage-110-rhoai-base-platform/validate.sh
./stage-120-gpu-as-a-service/deploy.sh
./stage-120-gpu-as-a-service/validate.sh
```

The deploy script applies the Argo CD Application only. Argo CD owns the stage
resources under `gitops/stage-120-gpu-as-a-service`.

### GPU Cost Control

The default desired state is one `g6e.2xlarge` GPU worker. To stop GPU spend
between demo sessions:

```bash
oc scale machineset -n openshift-machine-api \
  -l cluster-api/accelerator=nvidia-gpu \
  --replicas=0
```

To resume:

```bash
oc scale machineset -n openshift-machine-api \
  -l cluster-api/accelerator=nvidia-gpu \
  --replicas=1
```

The Stage 120 Argo CD Application ignores `MachineSet.spec.replicas` for managed
MachineSets. This keeps the Git default at one GPU worker for new deployments
while allowing intentional manual scale-down in the live demo environment.

After scaling up, wait for the node and NVIDIA stack:

```bash
oc get machineset -n openshift-machine-api -l cluster-api/accelerator=nvidia-gpu
oc get nodes -l nvidia.com/gpu.present=true
oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}{"\n"}'
```

### Fresh AWS Demo Environment

The committed GPU MachineSet is specific to the current AWS demo environment.
A fresh OpenShift environment has different cluster IDs, AMI IDs, subnet tags,
security groups, IAM profile names, regions, and availability zones.

Before deploying Stage 120 to a fresh environment:

1. Confirm the cluster is AWS-backed and has quota for `g6e.2xlarge`.
2. Export or identify a current non-GPU worker MachineSet from
   `openshift-machine-api`.
3. Preview a generated GPU MachineSet:

```bash
./stage-120-gpu-as-a-service/generate-gpu-machineset.sh \
  --source <worker-machineset>
```

4. Review the generated providerSpec, especially AMI, subnet, security group,
   IAM/profile, region, zone, tags, and userDataSecret values.
5. Replace the committed Stage 120 GPU MachineSet only after review:

```bash
./stage-120-gpu-as-a-service/generate-gpu-machineset.sh \
  --source <worker-machineset> \
  --write
kustomize build gitops/stage-120-gpu-as-a-service >/tmp/stage120.rendered.yaml
```

6. Commit the regenerated
   `gitops/stage-120-gpu-as-a-service/machineset/base/machineset-gpu.yaml`
   before syncing the Stage 120 Application.

Do not reuse the `cluster-klvxt` providerSpec in a different AWS cluster.

The generator keeps the demo defaults unless overridden:

- `RHOAI_GPU_INSTANCE_TYPE=g6e.2xlarge`
- `RHOAI_GPU_MACHINESET_REPLICAS=1`
- GPU labels: `cluster-api/accelerator=nvidia-gpu` and
  `node-role.kubernetes.io/gpu`
- GPU taint: `nvidia-gpu-only:NoSchedule`

## Stage 210: Model Serving Foundation

### Deploy And Validate

Stage 210 depends on Stage 110 and Stage 120. Run the earlier validations first
so model serving is enabled only after the base platform and GPU layer are
healthy.

```bash
./stage-110-rhoai-base-platform/validate.sh
./stage-120-gpu-as-a-service/validate.sh
./stage-210-model-serving-foundation/deploy.sh
./stage-210-model-serving-foundation/validate.sh
```

Stage 210 has two GitOps ownership surfaces:

- `stage-110-rhoai-base-platform` owns the base RHOAI `DataScienceCluster` and
  the GitOps-managed `demo-registry`.
- `stage-210-model-serving-foundation` patches the shared `DataScienceCluster`
  KServe component through a GitOps hook.
- `stage-210-model-serving-foundation` owns observability resources:
  OpenShift user workload monitoring configuration, Alertmanager notification
  receiver configuration, Grafana Operator, Grafana instance, Prometheus
  datasource, and the vLLM model-serving dashboard.

Do not create a second `DataScienceCluster` for Stage 210. In Argo CD, inspect
the Stage 210 Application hook for KServe enablement and the Stage 110
Application for base DSC ownership.

### Idempotent Nemotron Deployment

`stage-210-model-serving-foundation/deploy.sh` is safe to run after manual
dashboard validation or in a fresh environment. It follows this order:

1. Apply and refresh the Stage 210 Application.
2. Wait for its DSC KServe hook, KServe, and `demo-registry`.
3. Reuse existing Nemotron registry metadata when present.
4. Create missing Nemotron registered model, version, and OCI artifact metadata
   through the Model Registry REST API.
5. Reuse an existing Nemotron `InferenceService` when present.
6. Reconcile the endpoint to the curated Nemotron vLLM argument and resource
   profile.
7. Create the vLLM runtime from the active RHOAI template and deploy Nemotron
   when the endpoint is absent.

The script may copy the cluster pull-secret into `demo-sandbox` as a runtime
Kubernetes Secret named `nemotron-3-nano-30b` when the modelcar pull secret is
missing. The secret value is never printed or committed.

The curated Stage 210 Nemotron profile is adapted from the Red Hat AI MaaS code
assistant quickstart tested on AWS `g6e.2xlarge`/L40S GPU infrastructure:

- resources: request `2` CPU, `16Gi` memory, and one `nvidia.com/gpu`; limit
  `4` CPU, `24Gi` memory, and one `nvidia.com/gpu`
- vLLM args: `--enable-force-include-usage`,
  `--disable-uvicorn-access-log`, `--enable-prefix-caching`,
  `--max-model-len=8192`, `--max-num-batched-tokens=8192`,
  `--enable-auto-tool-choice`, `--tool-call-parser=qwen3_coder`,
  `--trust-remote-code`,
  `--reasoning-parser-plugin=/mnt/models/nano_v3_reasoning_parser.py`, and
  `--reasoning-parser=nano_v3`
- model source: keep the Red Hat registry modelcar
  `oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0`
  unless a newer official Red Hat artifact is intentionally selected

Stage 210 intentionally uses an `8192` token serving context for the current
single-GPU chat/RAG baseline. The earlier `131072` token setting remains a
model capability reference, but it is not the default operating envelope for
the governed MaaS path because one long request can consume too much of the
single-GPU serving budget.

### User-Led Dashboard Path

The dashboard path remains useful for the live demo and day-2 operations:

1. Log in to the RHOAI Dashboard as a demo user with access to `demo-sandbox`.
2. Open `demo-sandbox` and use **Deploy model**.
3. Select a generative model deployment using the vLLM NVIDIA GPU runtime.
4. Use a Stage 120 GPU hardware profile such as `GPU Reserved - Demo Team`.
5. Use the Nemotron model source:
   `oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0`.
6. Add the curated vLLM configuration parameters listed above when the
   dashboard exposes runtime parameter customization.
7. Use token authentication for external/shared endpoint access unless running
   the controlled Stage 210 baseline endpoint.
8. Test with the vLLM `/v1/chat/completions` path.

Current cluster-klvxt manual validation state:

- Registry: `demo-registry` in `rhoai-model-registries`.
- ServingRuntime: `nvidia-nemotron-3-nano-30b-a3b` in `demo-sandbox`.
- InferenceService: `nvidia-nemotron-3-nano-30b-a3b` in `demo-sandbox`,
  `Ready=True`.
- API: `serving.kserve.io/v1beta1` `InferenceService`.
- Model format: `vLLM`.
- Model source:
  `oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0`.

This confirms that the dashboard path works in the active environment. The
deploy and validation scripts now treat that state as reusable input rather
than requiring the same manual actions in every fresh environment.

### Grafana And Metrics

Stage 210 enables OpenShift user workload monitoring so the RHOAI/KServe
generated `ServiceMonitor` for the Nemotron endpoint can be scraped. It also
configures Alertmanager receivers through the documented
`openshift-monitoring/alertmanager-main` Secret, using a demo-local webhook
receiver in place of external Slack, email, PagerDuty, or Microsoft Teams
credentials. The receiver is intentionally simple: it acknowledges alert
notifications and logs the alert count so the cluster no longer runs with an
unconfigured notification path. It also installs a demo Grafana instance
through the community Grafana Operator.

Verify the monitoring path:

```bash
oc get configmap cluster-monitoring-config -n openshift-monitoring \
  -o jsonpath='{.data.config\.yaml}'
oc get deployment rhoai-demo-alert-webhook -n openshift-monitoring
oc get secret alertmanager-main -n openshift-monitoring \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
oc get servicemonitor nvidia-nemotron-3-nano-30b-a3b-metrics -n demo-sandbox
oc get grafana,grafanadatasource,grafanadashboard -n rhoai-demo-grafana
oc get grafanadatasource prometheus -n rhoai-demo-grafana \
  -o jsonpath='{.spec.uid}{" "}{.spec.valuesFrom[0].targetPath}{"\n"}'
```

Open Grafana:

```bash
oc get route grafana-route -n rhoai-demo-grafana -o jsonpath='{.spec.host}'
```

Use OpenShift OAuth. The demo `ai-admin` and `ai-developer` users are allowed
through the OAuth proxy by a namespace-scoped `grafana-viewer-demo-users`
RoleBinding in `rhoai-demo-grafana`. The proxy checks only `get services` in
that namespace; the Grafana service account remains responsible for reading
OpenShift monitoring data.

Validate demo-user access:

```bash
oc auth can-i get services -n rhoai-demo-grafana \
  --as ai-admin --as-group rhods-admins
oc auth can-i get services -n rhoai-demo-grafana \
  --as ai-developer --as-group rhoai-developers
```

Stage 210 includes two dashboards with functional names:

- `vLLM Model Serving Baseline` for the demo-specific Nemotron/vLLM view.
  The pressure panels use peak-over-selected-range queries for KV cache and
  GPU signals so short GuideLLM bursts remain visible after the request load
  drains.
- `LLM Inference Performance` at
  `/d/llm-performance/llm-inference-performance`, adapted from the Red Hat AI
  services llm-d reference. It is the primary dashboard for the GuideLLM
  showroom-style benchmark and includes vLLM latency, request queue, token
  throughput, KV cache, prefix cache, and later llm-d EPP panels. The vLLM
  panels are aligned with the same metric names and label model as
  `vLLM Model Serving Baseline`; the llm-d EPP panels are expected to remain
  empty until a later stage deploys llm-d/EPP.

The OpenShift Console application menu has a `RHOAI Demo Grafana` link that is
patched at sync time to the cluster-specific `llm-performance` dashboard URL.
`stage-210-model-serving-foundation/validate.sh` also runs a live Grafana
datasource query against the `Prometheus` datasource so dashboard-ready status
includes Prometheus authentication, not only synchronized custom resources.
The Stage 210 Grafana datasource and dashboards use a short operator
`resyncPeriod` so they are repopulated quickly after Grafana pod replacement
during demo updates.

The Grafana Operator is installed from `community-operators` as a demo
observability UI. It is not a Red Hat product dependency for RHOAI.

### GuideLLM Baseline

Run a short benchmark after the endpoint is ready:

```bash
./stage-210-model-serving-foundation/benchmark-guidellm.sh
```

Defaults:

- Image: `ghcr.io/vllm-project/guidellm:v0.5.0`
- Target: the internal KServe URL from
  `InferenceService.status.address.url`, with `/v1` appended
- Model: `nvidia-nemotron-3-nano-30b-a3b`
- Processor: `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-FP8`
- Data: `/data/prompts.csv` mounted from the GitOps-managed `benchmark-data`
  PVC in `demo-sandbox`
- Rate profile: concurrent rates `32,64`, 30 seconds per rate
- Results: JSON and CSV under `runs/stage-210-guidellm/<timestamp>/`

For a quick smoke test:

```bash
RHOAI_GUIDELLM_RATE=1 RHOAI_GUIDELLM_MAX_SECONDS=30 RHOAI_GUIDELLM_OUTPUTS=benchmark-results.json \
  ./stage-210-model-serving-foundation/benchmark-guidellm.sh
```

Set `RHOAI_GUIDELLM_KEEP_RESOURCES=true` to keep the temporary Job, PVC, and
copy Job for debugging.

For a longer saturation search, use the background-agent prompt at
`stage-210-model-serving-foundation/prompts/guidellm-saturation-benchmark-agent.md`.
It tells a cost-efficient sub-agent how to run one GuideLLM concurrency level
per invocation, collect TTFT/latency/throughput/GPU evidence, stop at the first
clear saturation point, and report a recommended operating envelope.

Validated 2026-06-12 on cluster-klvxt with:

```bash
RHOAI_GUIDELLM_RATE=1 RHOAI_GUIDELLM_MAX_SECONDS=10 RHOAI_GUIDELLM_OUTPUTS=benchmark-results.json \
  ./stage-210-model-serving-foundation/benchmark-guidellm.sh
```

After the showroom-style prompt dataset was added, the smoke run completed 5
requests with no errors using `/data/prompts.csv`. Observed values were
approximately p95 TTFT 1.63 seconds, p95 ITL 6.1 ms, p95 end-to-end request
latency 3.0 seconds, and mean output throughput 126.7 output tokens/second.
Treat these as harness and endpoint proof only; run chat/RAG policy profiles
before using benchmark results for capacity, quota, or MaaS limit decisions.

For a policy-oriented benchmark that feeds Stage 220 MaaS limits, seed the
chat/RAG prompt data first:

```bash
./stage-210-model-serving-foundation/prepare-policy-benchmark-data.sh
```

Then run the chat profile:

```bash
RHOAI_GUIDELLM_DATA=/data/policy-chat.csv \
RHOAI_GUIDELLM_RATE=1,2,4,8,12,16 \
RHOAI_GUIDELLM_MAX_SECONDS=120 \
RHOAI_GUIDELLM_TIMEOUT=35m \
  ./stage-210-model-serving-foundation/benchmark-guidellm.sh
```

Run the longer-context RAG profile separately:

```bash
RHOAI_GUIDELLM_DATA=/data/policy-rag-4k.csv \
RHOAI_GUIDELLM_RATE=1,2,4,8 \
RHOAI_GUIDELLM_MAX_SECONDS=120 \
RHOAI_GUIDELLM_TIMEOUT=30m \
  ./stage-210-model-serving-foundation/benchmark-guidellm.sh
```

Validated 2026-06-12 on cluster-klvxt after reconciling the live model to
`--max-model-len=8192`:

| Profile | Concurrent users | Successful requests | p95 TTFT | p95 ITL | p95 end-to-end | Output tokens/sec |
|---------|------------------|---------------------|----------|---------|----------------|-------------------|
| Chat, about 148 input / 256 output tokens | 1 | 63/63 | 1.8s | 4.9ms | 1.9s | 134 |
| Chat, about 148 input / 256 output tokens | 2 | 95/96 | 2.5s | 6.2ms | 2.6s | 203 |
| Chat, about 148 input / 256 output tokens | 4 | 141/144 | 3.0s | 8.9ms | 3.4s | 301 |
| Chat, about 148 input / 256 output tokens | 8 | 160/160 | 4.6s | 12.6ms | 6.0s | 423 |
| Chat, about 148 input / 256 output tokens | 12 | 160/160 | 6.4s | 18.3ms | 6.7s | 459 |
| Chat, about 148 input / 256 output tokens | 16 | 160/160 | 6.3s | 18.8ms | 6.9s | 586 |
| RAG, about 3.6k input / 512 output tokens | 1 | 31/31 | 3.1s | 5.6ms | 3.9s | 132 |
| RAG, about 3.6k input / 512 output tokens | 2 | 47/48 | 4.6s | 7.2ms | 5.2s | 201 |
| RAG, about 3.6k input / 512 output tokens | 4 | 57/60 | 19.3s | 10.2ms | 22.6s | 243 |
| RAG, about 3.6k input / 512 output tokens | 8 | 80/80 | 9.9s | 15.0ms | 11.3s | 381 |

Initial policy interpretation for one `g6e.2xlarge` GPU worker:

- Chat assistant lane: start MaaS limits at `8` active concurrent requests per
  Nemotron replica, with 256 output-token defaults and conservative prompt
  sizes even when the Stage 220 MaaS backend is served with a larger context
  window for Playground MCP headroom.
- Chat burst lane: allow `12` concurrent requests only for trusted/internal
  users or during demos where p95 TTFT around 6 seconds is acceptable.
- RAG lane: start at `2` active concurrent requests per Nemotron replica for
  about 4k-token prompts and 512 output-token responses.
- RAG burst lane: treat `4` concurrent requests as a breakpoint candidate until
  more RAG profiles prove the 19-second p95 TTFT spike was not repeatable.
- Do not treat the Stage 220 `131072` served context as a shared-service usage
  target. Keep larger-context RAG and high-output experiments separate from the
  governed shared-service policy until they have their own benchmark evidence.

## Stage 220: Models-as-a-Service

Stage 220 turns the Stage 210 model-serving foundation into a governed model
service. The implementation is phase-gated because RHOAI creates MaaS CRDs only
after prerequisites and DSC feature flags are healthy.

### Phase-One Deploy

1. Ensure `.env` has the correct `RHOAI_EXPECTED_API_SERVER`,
   `GIT_REPO_URL`, and `GIT_REPO_BRANCH`.
2. Run:

   ```bash
   ./stage-220-models-as-a-service/deploy.sh
   ```

3. The script:
   - Verifies the active OpenShift cluster through the guard.
   - Creates or updates local-only `maas-postgres-credentials` in
     `models-as-a-service-db`. The demo-local PostgreSQL database is kept
     outside the Kueue-managed `models-as-a-service` namespace so Kueue
     admission does not mutate or block the database StatefulSet.
   - Creates or updates `maas-db-config` in `redhat-ods-applications` with the
     PostgreSQL connection URL required by RHOAI MaaS. The URL must point at
     `maas-postgres.models-as-a-service-db.svc.cluster.local` in this demo.
   - Creates or updates local-only `openai-provider-api-key` in
     `models-as-a-service` from `OPENAI_API_KEY` or `RHOAI_OPENAI_API_KEY`, or
     reuses the Secret if it already exists. The Secret must contain data key
     `api-key` and label `inference.networking.k8s.io/bbr-managed=true` so the
     MaaS external-model route can discover provider credentials.
   - Deletes a stale direct Nemotron `InferenceService` or
     `LLMInferenceService` from `demo-sandbox` when present. The MaaS-owned
     backend is recreated by GitOps in `models-as-a-service`.
   - Applies the Stage 220 Application so its GitOps hook enables
     `kserve.modelsAsService` and `llamastackoperator` on the shared
     `DataScienceCluster`.
   - Verifies cert-manager is already installed and configured as a platform
     prerequisite.
   - Pins Red Hat Connectivity Link to `rhcl-operator.v1.3.4` with manual
     InstallPlan approval and GitOps-manages the RHCL dependency
     Subscriptions for Authorino, DNS, and Limitador at their validated 1.3.x
     CSVs. The bootstrap ArgoCD instance includes a conservative Subscription
     health customization: a manual pinned Subscription is healthy only when
     `status.installedCSV == spec.startingCSV`. This allows the RHCL hold to
     coexist with OLM `UpgradePending` while RHCL 1.4.x plans remain
     intentionally unapproved. The deployment fails visibly if a different RHCL
     or dependency CSV is already installed.
   - Applies the Stage 220 Application for LeaderWorkerSet, RHCL, Kuadrant,
     Authorino, the MaaS Gateway, PostgreSQL, the local Nemotron
     `LLMInferenceService`, external OpenAI, model policy, and the default MaaS
     tenant.
   - Waits for the MaaS-local Nemotron `LLMInferenceService` to reach
     `Ready=True`. On a fresh cluster this can take several minutes because the
     generated llm-d router/scheduler pulls the modelcar, inference scheduler,
     and tokenizer images on a non-GPU worker.
   - Restarts `deployment/maas-api` after the database Secret and MaaS component
     are present so the API-key service reads the current `maas-db-config`.

The Stage 220 Application prepares `maas-gateway-tls` in `openshift-ingress`
from the active OpenShift ingress certificate before applying
`maas-default-gateway`. The deploy wrapper also patches the Argo CD
Application source so the rendered Gateway uses `maas.<apps-domain>` and the
stable `maas-gateway-tls` certificate reference. This keeps the Gateway from
starting with a cluster-specific or missing certificate reference.

Secrets are generated in the cluster and are not committed. The demo uses an
in-cluster PostgreSQL 16 database backed by the Red Hat RHEL 9 PostgreSQL image.
This is a demo database posture; production MaaS should use a managed and
operationally backed PostgreSQL 14+ database.

Stage 220 external-provider rollout is intentionally credential-gated. If
neither `OPENAI_API_KEY` nor `RHOAI_OPENAI_API_KEY` is set locally and the
`openai-provider-api-key` Secret is absent, `deploy.sh` exits before Argo CD
sync so the demo does not publish a broken or placeholder external model.

### Phase-One Validation

Run:

```bash
./stage-220-models-as-a-service/validate.sh
```

The validator checks Argo CD app state, DSC fields, dashboard flags,
cert-manager, RHCL, Gateway API, `maas-gateway-tls`, Kuadrant, Authorino,
PostgreSQL, `maas-db-config`, Llama Stack CRDs, MaaS CRDs, and Tenant
readiness. It also checks the OpenAI provider Secret shape, `rhods-admins`
MaaS namespace administration, absence of direct `ai-developer` namespace
access, removal of stale direct Nemotron serving resources from
`demo-sandbox`, the demo-local PostgreSQL StatefulSet in
`models-as-a-service-db`, the local Nemotron `LLMInferenceService` and
`MaaSModelRef`,
the external OpenAI `ExternalModel` and `MaaSModelRef`, and the combined
`MaaSSubscription` and `MaaSAuthPolicy`.

The validator now also checks the user-facing MaaS discovery path. When
`AI_DEVELOPER_PASSWORD` and `AI_ADMIN_PASSWORD` are available in `.env`, it
logs in as the demo users, calls the RHOAI dashboard Gen AI MaaS models API,
and calls the external MaaS API subscription endpoint through the Gateway. A
deployment is not accepted as complete unless the dashboard/API path can load
the published model, not just the underlying CRs.

The validator also creates a temporary MaaS API key as `ai-developer`, calls
the Nemotron and external OpenAI OpenAI-compatible `/v1/chat/completions`
endpoints through the MaaS Gateway, verifies structured tool-call output and
token usage for both Nemotron and external GPT, verifies unauthenticated
inference is rejected, and revokes the temporary key. Do not treat raw
OpenShift OAuth tokens as the inference credential; the generated MaaS policy
requires `Authorization: Bearer <maas-api-key>` for chat/completions. External
OpenAI `gpt-4o-mini` requests use the standard Chat Completions `max_tokens`
field. This direct Chat Completions function-calling check is separate from
Playground MCP behavior.

MaaS quota or external-provider throttling is reported as a validation warning,
not as a configuration failure, when the model assets, subscriptions, auth
policies, API-key path, and discovery paths are otherwise healthy. A `429 Too
Many Requests` response proves the governed request path is active but the
current demo quota or upstream provider window is exhausted; wait for the
window to reset or adjust the demo subscription limit before repeating
interactive tests.

If a Gen AI Playground already exists in `demo-sandbox`, the validator also
checks that the generated `LlamaStackDistribution` and deployment use a
Secret-backed MaaS API key instead of the dashboard-created placeholder token.
It validates the Llama Stack model list and `/v1/responses` path for both
Nemotron and external GPT through MaaS. For MCP, the durable validation gate is
an actual `mcp_call` through the Llama Stack Responses API. Stage 220 validates
that path with Nemotron because it is the local, private, tool-calling model
for the MCP demo.

Stage 220 also registers a read-only OpenShift MCP server for the Gen AI
Playground MCP tab. The server runs in `rhoai-mcp`, uses the newer
OpenShift-specific MCP server project, and is discovered through
`redhat-ods-applications/gen-ai-aa-mcp-servers`. Validation checks that the
server deployment is available, the Service has endpoints, the ServiceAccount
is bound to the `view` ClusterRole, and the MCP `config.toml` sets
`read_only = true`, enables only `core` and `config` toolsets, allowlists the
small demo inspection tool set, and denies `Secret`, `ConfigMap`, and RBAC
resources. Treat this as preview/demo tool context, not production automation.

If validation fails on the RHCL or dependency pin, or on MaaS Gateway generated
policy
filters, inspect the installed RHCL CSV, generated Kuadrant AuthPolicy and
TokenRateLimitPolicy status, and gateway logs before retrying the dashboard.
On the current `cluster-klvxt` environment, RHCL 1.4.0 generated a Gateway
WASM EnvoyFilter with `allow_on_headers_stop_iteration`; the OpenShift gateway
Envoy rejected that field, so Gateway requests did not reliably inject the
identity headers required by `maas-api`. Stage 220 now expects
`rhcl-operator.v1.3.4`, Authorino/DNS/Limitador on the validated 1.3.x CSVs,
current model policies with `Enforced=True`, and
functional dashboard/Gateway discovery for the published MaaS models.

Do not patch generated Kuadrant `AuthPolicy` or EnvoyFilter resources as the
Stage 220 fix. Treat RHCL version remediation as operator lifecycle work and
keep the validation failure visible until the documented product path works end
to end.

The external model resources use the installed
`maas.opendatahub.io/v1alpha1` schemas confirmed with `oc explain`. External
OpenAI `gpt-4o-mini` is represented by the same MaaS resource name and
provider model ID: `ExternalModel.metadata.name: gpt-4o-mini` and
`spec.targetModel: gpt-4o-mini`. This avoids the previous alias split between
Kubernetes resource names and provider model names.

The AI asset endpoints MaaS tab is expected to show `gpt-4o-mini`. After
adding the model to a Playground, validate that the product-generated Llama
Stack and dashboard BFF model lists expose a provider-qualified id ending in
`/gpt-4o-mini` and that `/gen-ai/api/v1/lsd/responses` returns a response.

Re-run the schema checks after RHOAI or RHCL upgrades
before changing `MaaSModelRef`, `ExternalModel`, `MaaSSubscription`, or
`MaaSAuthPolicy` manifests because the RHOAI 3.4 documentation examples and
CRD verification section use different
API groups for some MaaS resources.

### Gen AI Playground Configuration

The RHOAI dashboard creates the project `LlamaStackDistribution` when
`ai-developer` creates a Gen AI Playground in `demo-sandbox`. The normal
workflow is to let the dashboard generate the Playground resources from the
selected AI asset endpoints, then validate the generated Llama Stack model
list and response path:

```bash
./stage-220-models-as-a-service/validate.sh
```

If you later update the Playground model selection, for example by checking or
unchecking the GPT model, the dashboard can recreate the
`LlamaStackDistribution`, ConfigMap, and generated deployment. Finish model
selection first, wait for the Playground to become ready, refresh the browser,
then rerun validation.

`configure-genai-playground.sh` is a diagnostic repair tool, not the normal
configuration path. Use it only when validation shows the dashboard-generated
Llama Stack backend has placeholder tokens or stale model mappings and you
need to recover the demo without recreating the Playground from the dashboard.

Use the model IDs reported by the Llama Stack `/v1/models` API. They are
provider-qualified, and the generated provider number can change when the
dashboard recreates a playground:

```text
maas-vllm-inference-<n>/nemotron-3-nano-30b-a3b
maas-vllm-inference-<m>/gpt-4o-mini
```

The external GPT route should use the provider mapping selected by the
product-generated Playground as long as the actual response path works. With
`gpt-4o-mini`, the MaaS resource name and provider target match and the
standard `max_tokens` field is accepted, so the normal dashboard-generated
provider mapping should be validated before using any repair helper.

For non-browser validation of the dashboard BFF path, use both
`Authorization: Bearer <user-token>` and `x-forwarded-access-token:
<user-token>`. A direct Llama Stack `/v1/responses` call is necessary but not
sufficient evidence that the Gen AI Playground browser workflow is healthy;
the dashboard BFF model list and response path must both validate.

### OpenShift MCP In Gen AI Playground

Stage 220 registers one platform MCP server:

```text
OpenShift-MCP -> http://openshift-mcp.rhoai-mcp.svc:8080/mcp
```

Use it from the Gen AI Playground MCP tab after selecting a tool-calling model
such as the MaaS-published Nemotron model. The intended demo prompt shape is
bounded cluster inspection, for example asking for pod status in a specific
namespace, one known pod, or node usage status. Do not use this path for broad
namespace, pod, event, or log listing, and do not use it for write actions. The
MCP server is configured read-only, formats list results as `table` output,
and denies Secrets, ConfigMaps, and RBAC objects even though the ServiceAccount
has broad cluster `view` access.

External `gpt-4o-mini` can emit standard function/tool calls through the MaaS
OpenAI-compatible Chat Completions endpoint and can complete bounded MCP calls
through the Playground Llama Stack Responses API. It is not the preferred
OpenShift MCP demo model, because MCP tool schemas and tool outputs are sent
to the external provider and can trigger provider token-per-minute limits. In
one validated failure mode, a broad GPT+MCP request was rejected by OpenAI as
`Request too large ... Requested 1411226` tokens. For external GPT+MCP tests,
start a new chat, use only one bounded tool such as `pods_list_in_namespace`
for `demo-sandbox` or `pods_get` for a known pod, and inspect Llama Stack logs
before assuming tool calling is disabled.

Keep the MCP tool surface intentionally small. Stage 220 allowlists only
namespace-scoped pod inspection, known-pod, and node status tools because the
MCP tool schema and tool results are inserted into the Llama Stack Responses
API context. Broad list tools such as `namespaces_list`, `pods_list`,
`events_list`, and log tools can create excessive tool output and provider
token pressure. The MaaS-published Nemotron backend is served with
`--max-model-len=131072` for MCP headroom, and the diagnostic Playground repair
script keeps the vLLM provider output default at 512 tokens so MCP requests
leave room for tool context and a short answer.

Useful checks:

```bash
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o yaml
oc get deployment,service,endpoints openshift-mcp -n rhoai-mcp
oc get configmap openshift-mcp-config -n rhoai-mcp -o yaml
oc get clusterrolebinding rhoai-demo-openshift-mcp-view -o yaml
oc logs deployment/openshift-mcp -n rhoai-mcp --since=10m
```

### Access Posture

- `ai-admin` administers MaaS and can manage the `models-as-a-service`
  namespace. The namespace is labeled `opendatahub.io/dashboard: "true"` so it
  can appear as an OpenShift AI project for users with access.
- `ai-developer` should not have direct namespace access to
  `models-as-a-service`; the intended path is OpenShift AI dashboard assets,
  Gen AI Playground, and MaaS-issued API keys.
- External OpenAI `gpt-4o-mini` access must go through MaaS and must be
  documented as an external-provider data path where prompts leave the cluster.
  Provider credentials stay local and are never committed.

## Stage 230: Private Data RAG

Stage 230 is the metadata-aware enterprise RAG stage. Do not treat the old
whoami/Docling/DSPA/chatbot deploy and validation flow as the active operating
model.

### Current Intent

The rebuilt Stage 230 demonstrates metadata-aware enterprise RAG based on
the Red Hat Developer OGX/Llama Stack article and its linked AG News reference
implementation. The current active slice:

- creates the `enterprise-rag` OpenShift AI project
- labels `enterprise-rag` for Kueue management and creates `lq-cpu-default`
  for the Stage 120 `CPU Default` hardware profile and CPU reranker scheduling
- deploys PostgreSQL for Llama Stack metadata and pgvector-backed retrieval
- enables the PostgreSQL `vector` extension and configures the documented
  `remote::pgvector` Llama Stack provider
- deploys a `LlamaStackDistribution` configured for RAG with a GitOps-managed
  `userConfig` ConfigMap adapted from the Red Hat article-linked AG News
  reference implementation
- consumes Nemotron through the Stage 220 MaaS gateway
- deploys a CPU Qwen3 reranker adapted from the Red Hat article-linked
  reference implementation, exposes it through Llama Stack as
  `vllm-reranker/qwen3-reranker`, and sizes it for the current demo CPU worker
  pool
- uses `sentence-transformers/nomic-ai/nomic-embed-text-v1.5` for
  indexing
- provides an Enterprise RAG Workbench, deterministic AG News sample, full AG
  News acceptance helper, and a focused official RHOAI 3.4 product-document
  explainer corpus for
  demo-audience Q&A about Llama Stack RAG, AutoRAG, RAGAS, EvalHub,
  guardrails, AI Pipelines, and Docling. The selected official PDFs and
  deterministic prepared chunks are committed under
  `stage-230-private-data-rag/data/rhoai-product-docs/` so fresh demo
  environments use the same reviewed corpus.
- runs a Docling KFP pipeline through the GitOps-managed DSPA server to process
  the same RHOAI product PDFs from S3 and write reviewed JSONL chunks plus
  converted Markdown/Docling JSON artifacts back to S3.

The validation gate is to ingest deterministic corpus records through Files
and Vector Stores APIs, validate metadata-filtered hybrid retrieval, rerank
candidates, and then generate a Nemotron answer from retrieved context. The
primary audience-facing corpus is the committed RHOAI product-document set.

### Operational Status

Current status:

- `stage-230-private-data-rag/PLAN.md` is the authoritative Stage 230 design
  document.
- `stage-230-private-data-rag/deploy.sh` applies the Argo CD Application,
  waits for the namespace and Stage 230 ObjectBucketClaim, creates
  non-committed runtime Secrets, creates the `enterprise-rag-s3` dashboard
  connection and `data-processing-docling-pipeline` S3 Secret from
  OBC-generated credentials, and uploads repo-stored source PDFs to the
  project bucket under `raw/rhoai-product-docs/` from an in-cluster Job. The
  dashboard connection uses the OBC-advertised HTTPS endpoint. The pipeline
  Secret uses the in-cluster NooBaa HTTP service endpoint that matches the
  DSPA artifact store configuration.
- `stage-230-private-data-rag/validate.sh` checks the Stage 230 Application,
  runtime resources, Llama Stack readiness, model listing, Qwen3 reranker
  readiness, workbench resources, helper syntax, and DSPA readiness.
- `stage-230-private-data-rag/scripts/agnews_rag_smoke.py` is the first
  deterministic ingestion/search helper and requires `llama-stack-client` in
  the execution environment.
- `stage-230-private-data-rag/scripts/agnews_rag_acceptance.py` is the full
  AG News acceptance helper. Run it from the Enterprise RAG Workbench, or set
  `RHOAI_STAGE230_RUN_ACCEPTANCE=true` before `validate.sh` to run the same
  helper inside the Enterprise RAG Workbench container.
- `stage-230-private-data-rag/scripts/rhoai_product_docs_prepare.py`
  prepares focused product-doc chunks with source metadata from the selected
  official RHOAI 3.4 PDFs stored in the stage folder. Use `--force-download`
  only when intentionally refreshing the corpus from `docs.redhat.com`.
- `stage-230-private-data-rag/scripts/rhoai_product_docs_rag_smoke.py` indexes
  those chunks into the `stage230-rhoai-34-product-docs` vector store and
  validates metadata-filtered hybrid retrieval, reranking, and a final
  Nemotron answer.
- `stage-230-private-data-rag/run-rhoai-docs-pipeline.sh` compiles the RHOAI
  product-document Docling KFP source, creates a Pipeline/PipelineVersion in
  the DSPA namespace, submits a run, reviews S3 output, checks converted
  Markdown and Docling JSON artifacts, and stores evidence in
  `enterprise-rag/stage230-rhoai-docs-pipeline-evidence`.
- `private-rag-chatbot` is the Stage 230 Streamlit chatbot. It is built from
  `stage-230-private-data-rag/chatbot/` by the deploy script through a binary
  OpenShift BuildConfig in `enterprise-rag-build`; the runtime Deployment and
  Route run in `enterprise-rag`. Keeping build pods outside the Kueue-managed
  RAG project avoids admitting OpenShift build infrastructure as queued AI
  workloads. The app uses the Stage 230 Llama Stack service, the
  product-document vector store, hybrid search, reranking, and governed
  Nemotron access. The app includes a RAG on/off toggle so the same question
  can be compared against model-only behavior.
- Old `run-whoami-*`, prior chatbot, prior non-product-document corpus, and
  prior Docling/KFP artifacts are removed from the active stage.

### Deployment Contract

`deploy.sh`:

- load `.env` and enforce the OpenShift safety guard
- apply the Stage 230 Argo CD Application first
- create non-committed runtime Secrets for PostgreSQL, MaaS access, and
  project-scoped S3 access
- create the `enterprise-rag-s3` dashboard S3 connection Secret and
  `data-processing-docling-pipeline` Secret from OBC-generated credentials
- upload repo-stored source PDFs to the project bucket under
  `raw/rhoai-product-docs/` using an in-cluster Job that clones the same Git
  branch as Argo CD
- start the `private-rag-chatbot` binary build in `enterprise-rag-build` from
  the local checked-out chatbot source and restart the `enterprise-rag`
  Deployment after the image is available
- refresh the Application after Secret creation
- leave ingestion to validation or an explicit user-triggered smoke run
- do not run removed corpus-specific pipelines

If the DSPA object-storage endpoint, scheme, bucket, or credentials are wrong,
do not live patch the generated workflow-controller ConfigMap. Red Hat
OpenShift AI documents pipeline server object-storage settings as requiring
pipeline server deletion and recreation when incorrect. For this demo, update
`gitops/stage-230-private-data-rag/pipelines/base/dspa.yaml`, recreate
`enterprise-rag/dspa-enterprise-rag`, and then rerun `deploy.sh` so generated
pipeline S3 secrets and source uploads match the recreated server.

`validate.sh` currently proves the runtime foundation and prepares the next
gate:

- Llama Stack model list includes the configured Nemotron provider, Nomic
  embedding model, and Qwen3 reranker model
- PostgreSQL, pgvector extension, and the `LlamaStackDistribution` are ready
- Qwen3 reranker `InferenceService` and Route exist and are ready
- the Enterprise RAG Workbench `Notebook`, PVC, and ServiceAccount exist
- the Enterprise RAG Workbench exposes the curated AG News notebooks and RHOAI
  product-doc explainer notebook, and does not expose the full `rhoai3-demo`
  repository checkout
- the Stage 230 ObjectBucketClaim is `Bound`
- the `enterprise-rag-s3` dashboard S3 connection and
  `data-processing-docling-pipeline` Secret exist
- the shared `default-dsc` has AI Pipelines enabled by the Stage 230 DSC patch
  job
- the `dspa-enterprise-rag` DSPA exists, reports Ready, and exposes the
  pipeline-server route
- the repo contains the selected RHOAI product source PDFs and deterministic
  prepared chunks
- the Enterprise RAG Workbench receives the S3 connection environment
- the `enterprise-rag` namespace is Kueue-managed and has the
  `lq-cpu-default` LocalQueue
- the AG News smoke and acceptance helpers compile
- the RHOAI product-document preparation and smoke helpers compile
- the RHOAI product-document Docling KFP source compiles
- optional KFP validation can run the DSPA pipeline and check
  `stage230-rhoai-docs-pipeline-evidence`
- the Stage 230 chatbot source compiles, the build namespace exists, image is
  built, Deployment is available, route health responds, and configuration
  points at the Enterprise RAG Llama Stack service plus the RHOAI
  product-document vector store
- the Stage 230 OpenShift AI dashboard application tile exists in
  `redhat-ods-applications` and points at the `private-rag-chatbot` Route in
  `enterprise-rag`

Optional validation gates prove the user-visible RAG outcome:

- vector store is created with expected metadata
- files are uploaded and attached with document metadata
- metadata-filtered hybrid search returns expected AG News candidates
- Qwen3 reranker scores are returned through Llama Stack
  `/v1alpha/inference/rerank`
- final answer is generated by Nemotron using retrieved context
- the RHOAI product-document explainer corpus can be prepared from the
  repo-stored PDFs and indexed through the same RAG path when
  `RHOAI_STAGE230_RUN_RHOAI_DOCS_SMOKE=true`
- the RHOAI product-document Docling pipeline runs through DSPA when
  `RHOAI_STAGE230_RUN_RHOAI_DOCS_PIPELINE=true`
- when both RHOAI product-document gates are enabled, validation downloads the
  pipeline-generated JSONL output and uses it for the RAG smoke vector store

Run the workbench-equivalent validated flow:

```bash
cd /opt/app-root/src/workspace
python .stage230/scripts/agnews_rag_acceptance.py \
  --vector-store stage230-agnews-demo \
  --search-mode hybrid
```

Run the official RHOAI product-document explainer corpus from the staged PDFs:

```bash
cd /opt/app-root/src/workspace
python .stage230/scripts/rhoai_product_docs_prepare.py \
  --manifest .stage230/data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json \
  --source-dir .stage230/data/rhoai-product-docs/source \
  --output .stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl
python .stage230/scripts/rhoai_product_docs_rag_smoke.py \
  --reset \
  --manifest .stage230/data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json \
  --sample .stage230/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl \
  --vector-store stage230-rhoai-34-product-docs \
  --search-mode hybrid
```

This flow is useful for explaining the setup to a demo audience from official
RHOAI 3.4 docs. It does not implement AutoRAG, EvalHub, guardrails, or RAGAS;
those remain separate product capabilities and future demo scope.

By default, the product-document RAG smoke reads the full JSONL file and
indexes a bounded per-topic subset for the selected smoke questions. This is
the normal redeploy gate because it proves Files API upload, Vector Stores
metadata, hybrid search, reranking, and Nemotron generation without indexing
hundreds of chunks on every validation run. Use `--full-corpus` only when you
intentionally want to index the entire generated corpus.

Run the official RHOAI product-document Docling pipeline through AI Pipelines:

```bash
./stage-230-private-data-rag/run-rhoai-docs-pipeline.sh
```

For a one-document pipeline smoke run:

```bash
./stage-230-private-data-rag/run-rhoai-docs-pipeline.sh \
  --max-documents=1 \
  --output-s3-key=processed/rhoai-product-docs/rhoai-3.4-product-docs-docling-kfp-smoke.jsonl
```

Run the full product-document pipeline and RAG smoke gate from validation:

```bash
RHOAI_STAGE230_RUN_RHOAI_DOCS_PIPELINE=true \
RHOAI_STAGE230_RUN_RHOAI_DOCS_SMOKE=true \
./stage-230-private-data-rag/validate.sh
```

After the pipeline has already passed and
`ConfigMap/stage230-rhoai-docs-pipeline-evidence` records a passing artifact
review, validation can reuse that evidence and run only the bounded RAG smoke
over the generated S3 output:

```bash
RHOAI_STAGE230_RUN_RHOAI_DOCS_SMOKE=true \
RHOAI_STAGE230_RHOAI_DOCS_USE_PIPELINE_OUTPUT=true \
./stage-230-private-data-rag/validate.sh
```

The KFP implementation uses the modular `docling-standard` path for
text-native PDFs, with OCR disabled by default and accurate table mode enabled.
Pipeline runs should show separate tasks for source selection, `import-pdfs`,
`create-pdf-splits`, `download-docling-models`,
`docling-convert-standard`, `docling-chunk`,
`publish-docling-split-outputs`, and
`normalize-rhoai-product-doc-chunks`. The split publisher uploads converted
Markdown, Docling JSON, and HybridChunker JSONL artifacts under
`processed/rhoai-product-docs/`; the final normalizer writes the JSONL RAG
handoff to the configured output key. The selected Docling component image is
a repo-owned KFP runtime dependency and is recorded as a demo exception until
replaced with a reviewed Red Hat or custom image.

Dashboard visibility: in OpenShift AI, select project `Enterprise RAG` and
open `Pipelines`, then choose `RHOAI Product Docs Docling Pipeline`. The
Docling conversion and chunking work is visible in the run graph; some tasks
are nested inside the `ParallelFor` split loop. Docling is not expected in the
project `Deployments` tab for this stage. `Deployments` shows KServe-served
endpoints such as `qwen3-reranker`; Docling follows the Red Hat-documented
data-preparation pattern as a KFP component.

To intentionally refresh the committed prepared JSONL from the official PDFs,
run the preparation helper locally and review the diff before committing:

```bash
python stage-230-private-data-rag/scripts/rhoai_product_docs_prepare.py \
  --source-dir stage-230-private-data-rag/data/rhoai-product-docs/source \
  --output stage-230-private-data-rag/data/rhoai-product-docs/processed/rhoai-3.4-product-docs-chunks.jsonl
```

Use `--force-download` only when the active product baseline changes or the
source manifest is intentionally updated.

The command must fail if metadata extraction, hybrid metadata filtering,
reranking, or final grounded answer generation is broken. Use `--reset` after
a provider migration or fresh redeploy when the vector store should be
recreated with the active pgvector provider.

Legacy Stage 230 operations content remains available in Git history and in the
pre-reset commits. The old backup tree under
`backup/legacy-implementation-2026-06-09/` is for historical reference only.

## Operator Lifecycle And Upgrades

Operator lifecycle management is GitOps state for this project. Red Hat
Operator installation and upgrade intent must be represented in Git through the
operator Kustomize tree and Argo CD Applications, not maintained as live
Subscription drift.

Git-owned lifecycle fields include:

- Operator `Subscription` package name, catalog source, source namespace, and
  subscribed channel
- `installPlanApproval` policy
- selected channel overlay or aggregate overlay path
- product baseline changes in `PLATFORM_BASELINE.md`
- operand custom resource patches that depend on the upgraded Operator schema

Regular demo upgrades should use tracked channels with automatic approval when
the relevant Red Hat product documentation and the active environment allow it.
For example, the RHOAI demo posture favors feature-forward `fast-3.x` or the
current `fast-x.y` channel when available, while ODF stays pinned to the ODF
minor version compatible with the active OCP baseline.

Controlled upgrades should follow this sequence:

1. Update `PLATFORM_BASELINE.md` when the intended product version changes.
2. Update the Operator channel overlay or approval strategy in Git.
3. Sync the Operator Argo CD Application before changing operand CR fields.
4. Validate `Subscription`, `InstallPlan`, `ClusterServiceVersion`, CRDs, and
   product-specific health.
5. Update operand patches only after the new schema is available.
6. Record recovery notes in `TROUBLESHOOTING.md` if anything fails.

Manual InstallPlan approval is an operational gate, not a fully declarative
resource, because OLM generates InstallPlan names. Use manual approval only
when official docs require it or when the demo deliberately needs a human gate.
Document who approves the pending InstallPlan and why.

A Git revert of an Operator channel change does not guarantee a downgrade.
Rollback and recovery are product-specific and must follow the relevant Red Hat
documentation and live cluster health checks.
