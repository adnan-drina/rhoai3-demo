# Troubleshooting Guide

Use this guide for symptom-based recovery. Keep detailed failure handling here instead of expanding every step README into a runbook.

## Argo CD Application Is Missing

**Symptom:** `validate.sh` reports `NOT_FOUND` for a step Application.

**Likely root cause:** The step deploy script was not run, or bootstrap did not finish.

**Diagnose:**

```bash
oc get applications -n openshift-gitops
oc get appproject rhoai-demo -n openshift-gitops
```

**Recover:**

```bash
./scripts/bootstrap.sh
./steps/step-XX-name/deploy.sh
```

## Argo CD Application Is OutOfSync

**Symptom:** `oc get applications -n openshift-gitops` shows `OutOfSync`.

**Likely root cause:** Operator-managed fields, runtime patches, manual MachineSet scaling, or a real manifest drift.

**Diagnose:**

```bash
oc describe application step-XX-name -n openshift-gitops
oc get application step-XX-name -n openshift-gitops -o yaml
```

**Recover:** If the drift is expected, document or add an `ignoreDifferences` entry. If it is not expected, update the GitOps manifest and the matching step README together.

## Step 02 Reconciles Continuously

**Symptom:** `step-02-rhoai` is `Synced` and `Healthy`, but the Argo CD application controller logs show frequent `Reconciliation completed` entries for the application.

**Likely root cause:** `DataScienceCluster/default-dsc` status is changing frequently while the RHOAI operator reconciles. The spec is stable, but status-only updates can still create Argo CD watch events.

**Diagnose:**

```bash
oc logs -n openshift-gitops statefulset/openshift-gitops-application-controller --since=2m \
  | grep 'step-02-rhoai' | wc -l
oc get datasciencecluster default-dsc -o jsonpath='{.metadata.resourceVersion}{" "}{.metadata.generation}{" "}{.status.observedGeneration}{"\n"}'
```

**Recover:** Rerun bootstrap. It configures Argo CD to ignore `/status`-only updates for `DataScienceCluster` and other operator-owned resources while continuing to manage desired specs.

## OpenShift GitOps Operator Conversion Webhook Has No Endpoints

**Symptom:** The kube-apiserver logs repeatedly show `conversion webhook for argoproj.io ... no endpoints available for service "openshift-gitops-operator-controller-manager-service"` and normal `oc` commands intermittently hit TLS handshake or handler timeouts.

**Likely root cause:** The OpenShift GitOps operator is on a stale channel, its controller-manager pod is not fully available, and the CRD conversion webhook service has no ready endpoint. This creates repeated kube-apiserver list/watch failures for ArgoCD CRDs.

**Diagnose:**

```bash
oc get subscription openshift-gitops-operator -n openshift-operators -o yaml
oc get deploy,pods,endpoints -n openshift-operators | grep -i gitops
oc logs -n openshift-kube-apiserver -l app=openshift-kube-apiserver --tail=300 | grep -i argocd
```

**Recover:** Rerun bootstrap or patch the Subscription to the pinned OCP 4.20 demo channel:

```bash
oc patch subscription openshift-gitops-operator -n openshift-operators --type merge \
  -p '{"spec":{"channel":"gitops-1.20","installPlanApproval":"Automatic"}}'
oc get csv -n openshift-operators | grep openshift-gitops-operator
oc delete csv openshift-gitops-operator.v1.15.4 -n openshift-operators
oc delete pod -n openshift-operators -l control-plane=controller-manager
oc get endpoints openshift-gitops-operator-controller-manager-service -n openshift-operators
```

Only delete the stale CSV if `openshift-gitops-operator.v1.20.x` is present and the older `v1.15.x` CSV is stuck in `Replacing` while still owning Argo CD CRDs. Wait until the endpoint is populated before judging Argo CD health.

## Operator Subscriptions Drift After RHOAI 3.4 Upgrade

**Symptom:** Multiple operator subscriptions or CSVs show stale channels after a RHOAI 3.3 to 3.4 upgrade. Common examples are OpenShift GitOps still on `gitops-1.15`, RHCL sourced from `redhat-operators` instead of `redhat-operators-rhoai`, standalone Authorino/Limitador/DNS subscriptions in legacy namespaces, or pending Service Mesh 3 install plans.

**Recover:** Use the alignment helper first, then inspect any warnings it reports:

```bash
./scripts/align-operator-subscriptions.sh --verify
./scripts/align-operator-subscriptions.sh --apply
```

The helper patches the subscriptions used by this demo, removes the old standalone RHCL dependency namespaces, approves matching RHCL and Service Mesh install plans, and runs the MaaS `AuthConfig` schema repair when the generated MaaS route policy exists.

## RHCL Upgrade Blocked By MaaS AuthConfig Schema Validation

**Symptom:** `rhcl-operator` is `AtLatestKnown`, but its Subscription keeps a stale `InstallPlanFailed` condition similar to:

```text
error validating existing CRs against new CRD's schema for "authconfigs.authorino.kuadrant.io"
updated validation is too restrictive
spec.response.success.headers.X-MaaS-Group-OC.when[0]
spec.response.success.headers.X-MaaS-Username-OC.when[0]
spec.authentication.openshift-identities.when[0]
```

**Cause:** MaaS generated an `AuthConfig` with v1beta3 `predicate` conditions. During the RHCL/Authorino upgrade, OLM validates existing stored objects against the v1beta2 schema and rejects those `predicate` entries. This can block the install plan and leave RHCL/Authorino in a partial upgrade state.

**Diagnose:**

```bash
oc get subscription rhcl-operator -n openshift-operators -o yaml
oc get authconfig -n kuadrant-system -o yaml | grep -n "predicate:.*sk-oai" -B5 -A5
```

**Recover:** Patch the generated MaaS API `AuthConfig` so the OpenShift-token path uses v1beta2-compatible `operator/selector/value` conditions. Select the object by the `maas-api-route` annotation first:

```bash
AUTHCONFIG=$(
  oc get authconfig -n kuadrant-system -o jsonpath='{range .items[?(@.metadata.annotations.HTTPRouteRule\.gateway\.networking\.k8s\.io=="httproute.gateway.networking.k8s.io:redhat-ods-applications/maas-api-route#rule-2")]}{.metadata.name}{"\n"}{end}'
)

oc patch authconfig "${AUTHCONFIG}" -n kuadrant-system --type=json -p='[
  {"op":"replace","path":"/spec/authentication/openshift-identities/when/0","value":{"operator":"matches","selector":"request.headers.authorization","value":"^Bearer (sha256~|eyJ).*"}},
  {"op":"replace","path":"/spec/response/success/headers/X-MaaS-Group-OC/when/0","value":{"operator":"matches","selector":"request.headers.authorization","value":"^Bearer (sha256~|eyJ).*"}},
  {"op":"replace","path":"/spec/response/success/headers/X-MaaS-Username-OC/when/0","value":{"operator":"matches","selector":"request.headers.authorization","value":"^Bearer (sha256~|eyJ).*"}}
]'
```

Then verify the RHCL CSV and webhook endpoints:

```bash
oc get csv rhcl-operator.v1.3.4 -n openshift-operators
oc get endpoints rhods-operator-service -n redhat-ods-operator
oc get endpoints llmisvc-webhook-server-service -n redhat-ods-applications
```

Step 01 and Step 05 now call this repair path automatically through `scripts/lib.sh`, because the generated MaaS API `AuthConfig` can be recreated during MaaS route reconciliation.

## PVC Stays Pending

**Symptom:** Argo CD shows a PVC as progressing or pods wait for storage.

**Likely root cause:** The storage class uses `WaitForFirstConsumer`, so the PVC binds only after a consuming pod is scheduled.

**Diagnose:**

```bash
oc describe pvc <pvc-name> -n <namespace>
oc get storageclass
oc get pods -n <namespace>
```

**Recover:** Confirm the consuming pod exists and can schedule. Bootstrap adds an Argo CD health check that treats pending `WaitForFirstConsumer` PVCs as healthy for GitOps progress.

## GPU Nodes Do Not Appear

**Symptom:** Model pods remain pending, `validate.sh` warns about zero GPU nodes, or `oc get nodes -l nvidia.com/gpu.present=true` returns nothing.

**Likely root cause:** AWS GPU quota, MachineSet provisioning, subnet/AZ mismatch, or NVIDIA GPU Operator not ready.

**Diagnose:**

```bash
oc get machinesets -n openshift-machine-api | grep gpu
oc get machines -n openshift-machine-api | grep gpu
oc get nodes -l node-role.kubernetes.io/gpu
oc get csv -n nvidia-gpu-operator
oc get clusterpolicy -n nvidia-gpu-operator
```

**Recover:** Check AWS quota for G/VT instances, confirm the MachineSet AZ has a subnet, rerun Step 01 after fixing infrastructure, and inspect GPU Operator pods.

## Service Mesh 3 Gateway Or RHOAI Dashboard Is Not Ready

**Symptom:** Step 02 waits indefinitely, the dashboard is unreachable, or Gateway API resources do not appear.

**Likely root cause:** The RHOAI operator creates the Service Mesh 3 install plan with manual approval.

**Diagnose:**

```bash
oc get subscription servicemeshoperator3 -n openshift-operators -o yaml
oc get installplan -n openshift-operators | grep -i service
oc get csv -n openshift-operators | grep -i service
```

**Recover:** Rerun Step 02. The deploy script approves the pending install plan and waits for the CSV.

## DataScienceCluster Is Not Ready

**Symptom:** `oc get datasciencecluster default-dsc` does not show `Ready`.

**Likely root cause:** Operator install still progressing, Service Mesh dependency blocked, or component reconciliation failed.

**Diagnose:**

```bash
oc get datasciencecluster default-dsc -o yaml
oc get pods -n redhat-ods-applications
oc get pods -n redhat-ods-operator
oc get events -n redhat-ods-applications --sort-by=.lastTimestamp
```

**Recover:** Resolve failed component pods, approve Service Mesh if needed, and rerun Step 02 after the dependency is healthy.

## Observability Dashboard Or Alerts Are Not Healthy

**Symptom:** Observe & monitor shows `Service Unavailable`, dashboard cards stay empty after traffic, or enabling alerting makes the RHOAI operator unstable.

**Likely root cause:** The RHOAI observability prerequisite operators are not Ready, `Monitoring/default-monitoring` has not reconciled, the OpenTelemetry collector or Tempo backend is unavailable, workload pods do not carry the scrape opt-in label, or the known RHOAI 3.4 MLflow prometheus-rules packaging issue is triggered by `spec.monitoring.alerting`.

**Diagnose:**

```bash
oc get monitoring default-monitoring
oc get pods,pvc,monitoringstack,perses,persesdashboard,tempomonolithic,opentelemetrycollector -n redhat-ods-monitoring
oc get svc -n redhat-ods-monitoring | grep -E 'data-science-collector|tempo.*query|query.*tempo|alertmanager'
oc logs -n redhat-ods-operator -l name=rhods-operator --tail=200 | grep -Ei 'monitoring|alert|mlflow|prometheus'
oc get pods -n maas -l serving.kserve.io/inferenceservice=granite-8b-agent \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.monitoring\.opendatahub\.io/scrape}{"\n"}{end}'
```

**Recover:** Rerun Step 01 and Step 02 to restore the prerequisite operators and DSCI monitoring configuration. Keep `DSCInitialization.spec.monitoring.alerting` unset until the operator logs no longer show `failed to add prometheus rules for component mlflowoperator`. If workload metrics are missing, verify that the generated predictor Deployment and pods carry `monitoring.opendatahub.io/scrape=true`, then restart only the affected predictor rollout.

## Application Traces Are Missing

**Symptom:** Tempo is Ready but the RAG chatbot does not produce traces.

**Likely root cause:** The chatbot image was not rebuilt after OpenTelemetry dependencies were added, the collector service is unavailable, or no chatbot page request has occurred since the app started.

**Diagnose:**

```bash
oc get deploy rag-chatbot -n enterprise-rag \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="chatbot")].env[?(@.name=="OTEL_EXPORTER_OTLP_ENDPOINT")].value}{"\n"}'
oc get pods -n redhat-ods-monitoring | grep data-science-collector
oc get svc -n redhat-ods-monitoring | grep -E 'tempo.*query|query.*tempo'
oc logs deploy/rag-chatbot -n enterprise-rag --tail=100 | grep -Ei 'otel|opentelemetry|export'
```

**Recover:** Rerun Step 07 so the BuildConfig rebuilds the chatbot image, open the chatbot route, then port-forward the Tempo query service identified by `oc get svc -n redhat-ods-monitoring | grep -E 'tempo.*query|query.*tempo'`.

## MinIO Or Data Connections Are Missing

**Symptom:** Step 03 validation fails for MinIO, `minio-connection`, or `storage-config`.

**Likely root cause:** MinIO pod not ready, init job failed, or Argo CD/operator interaction around generated secrets.

**Diagnose:**

```bash
oc get pods,jobs,svc,route -n minio-storage
oc logs job/minio-init -n minio-storage
oc get secret minio-connection storage-config -n private-ai
```

**Recover:** Rerun Step 03. Do not add `opendatahub.io/managed: "true"` to `storage-config`; the ODH controller can delete secrets it does not own.

## ModelRegistry Pods Or Seed Job Fail

**Symptom:** Step 04 validation fails for MariaDB, registry pods, or seed job.

**Likely root cause:** Database pod not scheduled, PVC not bound, ModelRegistry CR reconciliation issue, or seed job cannot reach the internal registry service.

**Diagnose:**

```bash
oc get pods,pvc,svc,job -n rhoai-model-registries
oc describe modelregistry enterprise-ai-registry -n rhoai-model-registries
oc logs job/model-registry-seed -n rhoai-model-registries
```

**Recover:** Wait for PVC/pod scheduling if storage is delayed. If the seed job failed, delete and let Argo CD recreate it or rerun the step after the registry pod is healthy.

## LLM InferenceService Is Not Ready

**Symptom:** Step 05 validation warns that `granite-8b-agent` or `mistral-3-bf16` exists but is not Ready.

**Likely root cause:** GPU capacity unavailable, model image pull blocked, large Mistral S3 upload incomplete, or storage credentials missing.

**Diagnose:**

```bash
oc get inferenceservice -n private-ai
oc describe inferenceservice granite-8b-agent -n private-ai
oc describe inferenceservice mistral-3-bf16 -n private-ai
oc get pods -n private-ai | grep predictor
oc describe pod <predictor-pod> -n private-ai
```

**Recover:** Confirm GPU nodes and pull credentials. For Mistral, check the upload job and MinIO object path. For OCI ModelCar models, confirm registry access to `registry.redhat.io`.

## RAG Ingestion Or Chatbot Does Not Work

**Symptom:** Step 07 validation fails for PostgreSQL, Docling, Llama Stack, ingestion, or chatbot readiness.

**Likely root cause:** BuildConfig not complete, database/vector store not ready, model endpoint not reachable, or Llama Stack config provider mismatch.

**Diagnose:**

```bash
oc get pods,builds,jobs,svc,route -n private-ai
oc logs job/rag-ingestion -n private-ai
oc get llamastackdistribution -n private-ai
oc logs deploy/lsd-rag -n private-ai
```

**Recover:** Rerun Step 07 after Step 05 models are ready. Check `gitops/step-07-rag/base/llamastack-rag/lsd-rag-config.yaml` before enabling external providers.

## Gen AI Playground Assets Are Missing Or Fail

**Symptom:** GenAI Studio opens, but model endpoints, custom endpoints, knowledge sources, saved prompts, or MCP servers are missing from the product-native Playground.

**Likely root cause:** Dashboard feature flags are not reconciled, the InferenceServices are missing AI asset labels, the MCP ConfigMap JSON is invalid, the RAG project does not have a Dashboard-visible data connection, or the MLflow workspace is not present for prompt/evidence features.

**Diagnose:**

```bash
./scripts/validate-genai-playground-readiness.sh

oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o yaml
oc get inferenceservice -n maas \
  -o custom-columns=NAME:.metadata.name,DASHBOARD:.metadata.labels.opendatahub\\.io/dashboard,GENAI:.metadata.labels.opendatahub\\.io/genai-asset
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o yaml
oc get secret minio-connection -n enterprise-rag -o yaml
oc get mlflowconfig mlflow -n enterprise-rag
```

**Recover:** Rerun Steps 02, 05, 07, and 10 in order. Step 02 enables GenAI Studio and internal custom endpoints; Step 05 publishes model assets; Step 07 creates the RAG project storage/vector backend; Step 10 registers MCP servers for Dashboard discovery.

### Custom endpoint external providers are visible unexpectedly

**Symptom:** The Dashboard allows third-party external providers when the demo should remain private-first.

**Recover:** Keep `externalProviders: false` in `gitops/step-02-rhoai/base/rhoai-operator/dashboard-config.yaml`, then rerun Step 02. Only enable third-party providers after a customer-specific security review.

### Playground keeps thinking or does not use RAG

**Likely root cause:** The model does not have enough remaining context after tool/knowledge results, no knowledge source is selected, or the selected file was uploaded with chunk settings that produce poor retrieval.

**Recover:** Select the intended knowledge source, reduce generated token count, and use conservative upload settings such as chunk length `1024`, overlap `128`, and delimiter `\n\n`. For production-style RAG, use the Step 07 KFP ingestion pipeline instead of one-off Playground uploads.

## Evaluation Jobs Do Not Complete

**Symptom:** Step 08 validation warns or evaluation reports are missing.

**Likely root cause:** RAG pipeline server not ready, EvalHub not Ready, model endpoint unavailable, Step 12 MLflow unavailable, tenant RBAC missing, or evaluation configs were not copied to the expected location.

**Diagnose:**

```bash
oc whoami --show-server
oc get subscription rhods-operator -n redhat-ods-operator -o jsonpath='{.status.installedCSV}'
oc get evalhub evalhub -n redhat-ods-applications -o yaml
oc get serviceaccount,rolebinding,configmap -n enterprise-rag | grep evalhub
oc get lmevaljob -n enterprise-rag
oc get jobs,pods -n enterprise-rag | grep -i eval
oc logs <eval-pod> -n enterprise-rag
```

**Recover:** Confirm Steps 05, 07, and 12 are healthy, then rerun Step 08 or the specific evaluation helper script in `steps/step-08-model-evaluation/`. Step 08 uses the project `RHOAI_EXPECTED_API_SERVER` guard and does not patch the RHOAI Subscription automatically.

### EvalHub providers are missing

**Symptom:** `run-evalhub-smoke.sh` cannot find `lm_evaluation_harness`, or Step 08 validation fails the EvalHub providers API check.

**Recover:** Confirm the TrustyAI operator installed the built-in provider ConfigMaps and that the EvalHub CR provider names match the ConfigMap labels:

```bash
oc get configmaps -n redhat-ods-applications --show-labels | grep evalhub-provider
oc get evalhub evalhub -n redhat-ods-applications -o jsonpath='{.spec.providers}'
```

On the target RHOAI 3.4 cluster, the CR uses the provider ConfigMap label `lm-evaluation-harness`, while the API provider ID returned by EvalHub is `lm_evaluation_harness`.

### Dashboard Evaluations page says admin configuration required

**Symptom:** RHOAI Dashboard → Develop & train → Evaluations shows `Admin configuration required` even though `OdhDashboardConfig.spec.dashboardConfig.disableLMEval=false`.

**Recover:** Confirm the dashboard EvalHub UI can find `EvalHub/evalhub` in the RHOAI applications namespace:

```bash
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.disableLMEval}'
oc get evalhub evalhub -n redhat-ods-applications -o jsonpath='{.status.phase} {.status.ready}'
oc logs -n redhat-ods-applications -l app=rhods-dashboard -c eval-hub-ui --since=15m
```

Step 08 keeps the EvalHub CR and route in `redhat-ods-applications` for dashboard discovery, while PostgreSQL remains in `evalhub-system`.

### EvalHub smoke has no MLflow experiment URL

**Symptom:** EvalHub job reaches `completed`, but `results.mlflow_experiment_url` is empty.

**Recover:** Confirm Step 12 MLflow is Available and the EvalHub CR has the MLflow environment expected by RHOAI 3.4:

```bash
oc get mlflow mlflow -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
oc get evalhub evalhub -n redhat-ods-applications -o jsonpath='{.spec.env}'
oc auth can-i get experiments.mlflow.kubeflow.org -n enterprise-rag --as=ai-developer
```

## Guardrails Detectors Are Not Ready

**Symptom:** HAP or prompt injection detector InferenceServices are not Ready, or the orchestrator is unavailable.

**Likely root cause:** Detector model image pull blocked, TrustyAI CRD unavailable, or orchestrator configuration is invalid.

**Diagnose:**

```bash
oc get inferenceservice hap-detector prompt-injection-detector -n private-ai
oc describe guardrailsorchestrator guardrails-orchestrator -n private-ai
oc get pods -n private-ai | grep -E 'guardrails|detector'
```

**Recover:** Confirm Step 02 installed TrustyAI components, check image pull access to Quay, and rerun Step 09.

## MCP Tools Are Registered But Calls Fail

**Symptom:** Step 10 validation finds MCP pods but tool invocation fails.

**Likely root cause:** Route URLs were not patched into the MCP ConfigMap, Llama Stack tool groups were not registered, OpenShift MCP permissions are insufficient, database data is not initialized, or Slack token/channel configuration is missing.

**Diagnose:**

```bash
oc get pods,svc,route -n private-ai | grep mcp
oc get configmap gen-ai-aa-mcp-servers -n private-ai -o yaml
oc logs deploy/database-mcp -n private-ai
oc logs deploy/openshift-mcp -n private-ai
oc logs deploy/slack-mcp -n private-ai
oc get clusterrolebinding openshift-mcp-view -o yaml
```

**Recover:** Rerun Step 10 to recreate the Slack secret, patch route-specific config, and register tool groups. If Slack is not required, treat Slack-specific failures as a disabled external integration rather than a private platform failure.

## Face Recognition Model Is Not Ready

**Symptom:** Step 11 or Step 13 InferenceService exists but is not Ready.

**Likely root cause:** The ONNX model was not uploaded to MinIO, the OpenVINO runtime cannot pull, or storage credentials are missing in the target namespace.

**Diagnose:**

```bash
oc get job upload-face-model -n minio-storage
oc logs job/upload-face-model -n minio-storage
oc describe inferenceservice face-recognition -n private-ai
oc describe inferenceservice face-recognition-edge -n edge-ai-demo
```

**Recover:** Rerun Step 11 to upload the model. For Step 13, verify `storage-config` exists in `edge-ai-demo` and points to the same MinIO model path.

## Training Pipeline Does Not Launch Or Finish

**Symptom:** Step 12 deploy warns about pipeline launch, no KFP pods complete, or quality gate fails.

**Likely root cause:** DSPA from Step 07 is missing, face recognition endpoint from Step 11 is missing, training data is absent, packages cannot be installed, or model metrics fail threshold checks.

**Diagnose:**

```bash
oc get dspa dspa-rag -n private-ai
oc get pods -n private-ai -l pipeline/runid
oc logs <pipeline-pod> -n private-ai
oc get pvc face-pipeline-workspace -n private-ai
```

**Recover:** Deploy Steps 07 and 11 first. Add training photos if you expect custom training. If the quality gate fails, inspect evaluation metrics before forcing deployment.

## MicroShift Edge Deployment Fails

**Symptom:** Step 13b cannot connect to the host, MicroShift is not active, or the edge model is not Ready.

**Likely root cause:** SSH credentials missing, pull secret missing, MicroShift repositories unavailable, NVIDIA runtime not configured, or ModelCar image not accessible.

**Diagnose:**

```bash
EDGE_HOST=<host> EDGE_USER=<user> EDGE_PASS=<pass> ./steps/step-13b-edge-ai-microshift/validate.sh
ssh <user>@<host> 'systemctl status microshift --no-pager'
ssh <user>@<host> 'oc get pods -A'
ssh <user>@<host> 'nvidia-smi'
```

**Recover:** Install the required RHEL/MicroShift repos, place the pull secret at `/etc/crio/openshift-pull-secret`, configure the NVIDIA runtime, and rerun Step 13b.

## Stale Privacy Or Capability Claims In Docs

**Symptom:** Documentation says all AI is private, no external services are used, or a future feature is implemented.

**Likely root cause:** README text drifted from manifests and scripts.

**Diagnose:**

```bash
rg -n "no external|all models are private|fully private|sovereign|air-gapped|disconnected" README.md steps docs
rg -n "OPENAI|AZURE|BEDROCK|WATSONX|SLACK|HF_TOKEN|HuggingFace|quay.io|registry.redhat.io" gitops steps scripts
```

**Recover:** Keep Private AI as the platform theme, but name the exception clearly. Say that local serving, RAG data, registry metadata, pipelines, and platform controls run inside OpenShift. When external providers, public registries, Hugging Face downloads, Slack, or Quay-based ModelCar promotion are involved, describe them as explicit demo exceptions or trust boundaries. Label planned capabilities as future/deferred and reference [BACKLOG.md](BACKLOG.md).

## References

- [Red Hat OpenShift AI Self-Managed 3.4 documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/)
- [OpenShift Container Platform 4.20 documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/)
- [OpenShift GitOps documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/latest/)
- [Using AI models on Red Hat build of MicroShift 4.20](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html-single/using_ai_models/index)
- [KServe debugging guide](https://kserve.github.io/website/docs/developer-guide/debugging)
