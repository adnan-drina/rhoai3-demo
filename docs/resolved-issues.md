# RHOAI Demo -- Resolved Issues Knowledge Base

> This file is maintained by the deployment agent. Each entry documents
> a resolved issue. Consult this file FIRST when diagnosing failures.
> For detailed solutions, follow the cross-reference to the step README.
>
> **Format:** Symptom → Component → Root Cause → Fix → Details link
>
> **Adding entries:** After resolving a new issue, append it under the
> appropriate step section following the existing format.

---

## Step 01: GPU Infrastructure & Prerequisites

### CUDA 13.0 driver compatibility with RHOAI 3.3

- **Component:** GPU Operator / ClusterPolicy
- **Root Cause:** `cuda-compat` in vLLM container causes CUDA 12.8 runtime to conflict with CUDA 13.0 host driver
- **Fix:** Pin driver to 570.195.03 in ClusterPolicy; Subscription set to Manual
- **Details:** [Step 01 README — CUDA 13.0 Driver Compatibility](../steps/step-01-gpu-and-prereq/README.md#-cuda-130-driver-compatibility-issue-rhoai-30)

### "RHEL entitlement" error (DTK fallback)

- **Component:** NFD Operator
- **Root Cause:** NFD cannot schedule on GPU nodes due to taints, preventing kernel-version labeling
- **Fix:** Verify NFD instance has tolerations for GPU taints
- **Details:** [Step 01 README — RHEL Entitlement Error](../steps/step-01-gpu-and-prereq/README.md#rhel-entitlement-error-dtk-fallback)

### NFD not detecting GPUs

- **Component:** NFD Operator
- **Root Cause:** NFD worker pods not running or not scheduling on GPU nodes
- **Fix:** Check NFD worker logs: `oc logs -n openshift-nfd -l app.kubernetes.io/component=worker`
- **Details:** [Step 01 README — NFD Not Detecting GPUs](../steps/step-01-gpu-and-prereq/README.md#nfd-not-detecting-gpus)

### GPU Operator pods failing

- **Component:** GPU Operator
- **Root Cause:** Driver compilation or image pull issues
- **Fix:** Check operator logs: `oc logs -n nvidia-gpu-operator -l app=gpu-operator`
- **Details:** [Step 01 README — GPU Operator Pods Failing](../steps/step-01-gpu-and-prereq/README.md#gpu-operator-pods-failing)

### MachineSet not provisioning

- **Component:** AWS MachineSet
- **Root Cause:** AWS quota, AMI, or subnet misconfiguration
- **Fix:** Check machine status: `oc get machines -n openshift-machine-api -o wide`
- **Details:** [Step 01 README — MachineSet Not Provisioning](../steps/step-01-gpu-and-prereq/README.md#machineset-not-provisioning)

### Pods not scheduling on GPU nodes

- **Component:** Kubernetes Scheduler
- **Root Cause:** Missing toleration for `nvidia.com/gpu` taint
- **Fix:** Ensure workload has toleration: `nvidia.com/gpu Exists NoSchedule`
- **Details:** [Step 01 README — Pods Not Scheduling](../steps/step-01-gpu-and-prereq/README.md#pods-not-scheduling-on-gpu-nodes)

---

## Step 02: Red Hat OpenShift AI 3.0

### Operator not installing

- **Component:** RHOAI Operator Subscription
- **Root Cause:** Subscription or CatalogSource issue
- **Fix:** Check subscription: `oc get subscription rhods-operator -n redhat-ods-operator -o yaml`
- **Details:** [Step 02 README — Operator Not Installing](../steps/step-02-rhoai/README.md#operator-not-installing)

### DataScienceCluster not ready

- **Component:** DataScienceCluster
- **Root Cause:** Component dependency not met or operator issue
- **Fix:** Check DSC conditions: `oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions}' | jq .`
- **Details:** [Step 02 README — DataScienceCluster Not Ready](../steps/step-02-rhoai/README.md#datasciencecluster-not-ready)

### GenAI Studio not visible

- **Component:** OdhDashboardConfig
- **Root Cause:** `genAiStudio` not enabled or `llamastackoperator` not Managed in DSC
- **Fix:** Verify `genAiStudio: true` in OdhDashboardConfig and `llamastackoperator: Managed` in DSC
- **Details:** [Step 02 README — GenAI Studio Not Visible](../steps/step-02-rhoai/README.md#genai-studio-not-visible)

### Hardware profile not appearing

- **Component:** HardwareProfile CR
- **Root Cause:** Profile not applied or wrong namespace
- **Fix:** Verify: `oc get hardwareprofile -n redhat-ods-applications`
- **Details:** [Step 02 README — Hardware Profile Not Appearing](../steps/step-02-rhoai/README.md#hardware-profile-not-appearing)

---

## Step 03: Private AI — GPU as a Service

### MinIO not starting

- **Component:** MinIO Deployment
- **Root Cause:** PVC or image pull issue
- **Fix:** Check pods: `oc get pods -n minio-storage`
- **Details:** [Step 03 README — MinIO Not Starting](../steps/step-03-private-ai/README.md#minio-not-starting)

### Data connection not appearing in Dashboard

- **Component:** RHOAI Data Connection
- **Root Cause:** Secret missing required labels
- **Fix:** Verify labels: `opendatahub.io/dashboard`, `opendatahub.io/managed`, `opendatahub.io/connection-type: s3`
- **Details:** [Step 03 README — Data Connection Not Appearing](../steps/step-03-private-ai/README.md#data-connection-not-appearing-in-dashboard)

### Login fails

- **Component:** OpenShift Authentication
- **Root Cause:** HTPasswd identity provider not configured or OAuth pods restarting
- **Fix:** Check auth pods: `oc get pods -n openshift-authentication`
- **Details:** [Step 03 README — Login Fails](../steps/step-03-private-ai/README.md#login-fails)

### User can't access project

- **Component:** RBAC / RoleBindings
- **Root Cause:** Missing group membership or RoleBinding
- **Fix:** Check bindings: `oc get rolebinding -n private-ai`
- **Details:** [Step 03 README — User Can't Access Project](../steps/step-03-private-ai/README.md#user-cant-access-project)

### Workbench FailedScheduling (untolerated taint)

- **Component:** Workbench / Notebook
- **Root Cause:** GPU nodes have taints; workbenches need tolerations
- **Fix:** Add toleration `nvidia.com/gpu Equal "true" NoSchedule` to workbench spec
- **Details:** [Step 03 README — Workbench FailedScheduling](../steps/step-03-private-ai/README.md#workbench-failedscheduling-untolerated-taint)

### "Notebook image deprecated" warning

- **Component:** Workbench / Notebook
- **Root Cause:** Image version git commit annotation mismatch
- **Fix:** Patch workbench annotation: `oc patch notebook ... --type=merge -p '{"metadata":{"annotations":{"notebooks.opendatahub.io/last-image-version-git-commit-selection":"8e73cac"}}}'`
- **Details:** [Step 03 README — Notebook Image Deprecated](../steps/step-03-private-ai/README.md#notebook-image-deprecated-warning)

### Workbench route not working

- **Component:** Gateway API / HTTPRoute
- **Root Cause:** RHOAI 3.3 uses Gateway API instead of Routes for workbenches
- **Fix:** Check HTTPRoute: `oc get httproute -n redhat-ods-applications | grep demo-workbench`
- **Details:** [Step 03 README — Workbench Route Not Working](../steps/step-03-private-ai/README.md#workbench-route-not-working)

### ArgoCD sync error: "unable to resolve parseableType for Group"

- **Component:** Argo CD / OpenShift Groups
- **Root Cause:** ArgoCD cannot parse the `user.openshift.io/v1 Group` schema
- **Fix:** Groups excluded from ArgoCD; created by `deploy.sh` using `oc adm groups new`
- **Details:** [Step 03 README — ArgoCD Sync Error](../steps/step-03-private-ai/README.md#argocd-sync-error-unable-to-resolve-parseabletype-for-group)

---

## Step 04: Enterprise Model Governance

### ModelRegistry not ready

- **Component:** ModelRegistry CR
- **Root Cause:** RHOAI operator issue or missing prerequisite
- **Fix:** Check operator logs: `oc logs -n redhat-ods-operator -l app=rhods-operator --tail=50`
- **Details:** [Step 04 README — ModelRegistry Not Ready](../steps/step-04-model-registry/README.md#modelregistry-not-ready)

### Database connection failed

- **Component:** MariaDB
- **Root Cause:** Database pod not running or credentials mismatch
- **Fix:** Test connection: `oc exec -n rhoai-model-registries deployment/model-registry-db -- mysql -u mlmd -pmlmd-secret-123 -e "SELECT 1"`
- **Details:** [Step 04 README — Database Connection Failed](../steps/step-04-model-registry/README.md#database-connection-failed)

### Seed job failed

- **Component:** Kubernetes Job
- **Root Cause:** Registry API not ready or network issue
- **Fix:** Check logs: `oc logs job/model-registry-seed -n rhoai-model-registries`
- **Details:** [Step 04 README — Seed Job Failed](../steps/step-04-model-registry/README.md#seed-job-failed)

### Internal service not accessible

- **Component:** Kubernetes Service
- **Root Cause:** Service or endpoints not created
- **Fix:** Check service: `oc get svc private-ai-registry-internal -n rhoai-model-registries`
- **Details:** [Step 04 README — Internal Service Not Accessible](../steps/step-04-model-registry/README.md#internal-service-not-accessible)

---

## Step 05: LLM on vLLM

### Workload stuck in pending

- **Component:** Kueue Workload
- **Root Cause:** Insufficient GPU quota or no available nodes
- **Fix:** Describe workload: `oc describe workload -n private-ai <workload-name>`
- **Details:** [Step 05 README — Workload Stuck in Pending](../steps/step-05-llm-on-vllm/README.md#workload-stuck-in-pending)

### Kueue + rolling update deadlock (SchedulingGated pods)

- **Component:** Kueue / KServe
- **Root Cause:** Rolling update triggers new pod; Kueue gates it because GPU quota is full (old pod holds it)
- **Fix:** Use `deploymentStrategy.type: Recreate`; manual: `oc delete pod <gated-pod> -n private-ai --force --grace-period=0`
- **Details:** [Step 05 README — Kueue Rolling Update Deadlock](../steps/step-05-llm-on-vllm/README.md#kueue--rolling-update-deadlock-schedulinggated-pods)

### OCI image pull fails: "No space left"

- **Component:** CRI-O / Container Runtime
- **Root Cause:** OCI images > 20GB exceed CRI-O overlay limits
- **Fix:** Use S3 storage instead of OCI ModelCar for large models
- **Details:** [Step 05 README — OCI Image Pull Fails](../steps/step-05-llm-on-vllm/README.md#oci-image-pull-fails-no-space-left)

### CUDA driver error 803

- **Component:** NVIDIA Driver
- **Root Cause:** Driver version incompatibility
- **Fix:** See Red Hat KB 7134740 for driver downgrade instructions
- **Details:** [Step 05 README — CUDA Driver Error 803](../steps/step-05-llm-on-vllm/README.md#cuda-driver-error-803)

### Granite model: chat template or quantization errors

- **Component:** vLLM ServingRuntime
- **Root Cause:** vLLM doesn't have built-in `granite` template; Granite uses `compressed-tensors`, not generic `fp8`
- **Fix:** Remove `--chat-template=granite` and `--quantization=fp8`; vLLM auto-detects from model config
- **Details:** [Step 05 README — Granite Model Errors](../steps/step-05-llm-on-vllm/README.md#granite-model-chat-template-or-quantization-errors)

### Workbench: route access issues

- **Component:** Workbench / Notebook
- **Root Cause:** Wrong annotation for RHOAI 3.3 (inject-oauth vs inject-auth)
- **Fix:** Use `notebooks.opendatahub.io/inject-auth: "true"`
- **Details:** [Step 05 README — Workbench Route Access Issues](../steps/step-05-llm-on-vllm/README.md#workbench-route-access-issues)

---

## Step 05: GenAI Playground (merged into LLM on vLLM)

### Playground shows no models

- **Component:** GenAI Playground / InferenceService
- **Root Cause:** No models have the `opendatahub.io/genai-asset: "true"` label
- **Fix:** `oc label inferenceservice --all -n private-ai opendatahub.io/genai-asset=true`
- **Details:** [Step 05 README](../steps/step-05-llm-on-vllm/README.md)

### Playground returns errors for a model

- **Component:** InferenceService / KServe
- **Root Cause:** Model not running (minReplicas: 0) or still loading
- **Fix:** Check predictor pods: `oc get pods -n private-ai | grep predictor`
- **Details:** [Step 05 README](../steps/step-05-llm-on-vllm/README.md)

### LlamaStack pod CrashLoopBackOff

- **Component:** LlamaStackDistribution
- **Root Cause:** ConfigMap syntax error or invalid model URLs
- **Fix:** Check logs: `oc logs deployment/lsd-genai-playground -n private-ai --tail=100`
- **Details:** [Step 05 README](../steps/step-05-llm-on-vllm/README.md)

### Model works directly but not in Playground

- **Component:** LlamaStack / vLLM
- **Root Cause:** LlamaStack `VLLM_MAX_TOKENS` exceeds model's `--max-model-len`
- **Fix:** Ensure model has `--max-model-len > 4096 + input_tokens`; recommended `--max-model-len=16384`
- **Details:** [Step 05 README](../steps/step-05-llm-on-vllm/README.md)

---

## Step 05b: LiteMaaS (Experimental)

### OAuth "Authentication failed"

- **Component:** LiteMaaS / OpenShift OAuth
- **Root Cause:** OpenShift OAuth doesn't provide standard OIDC `sub` claim
- **Fix:** `ALTER TABLE users ALTER COLUMN oauth_id DROP NOT NULL;` via PostgreSQL
- **Details:** [Step 06b README — OAuth Authentication Failed](../steps/step-06b-private-ai-litemaas/README.md#oauth-authentication-failed)

### Subscription "Failed to subscribe"

- **Component:** LiteMaaS Backend
- **Root Cause:** Models not registered in backend database
- **Fix:** Run model registration SQL from Post-Deployment Setup
- **Details:** [Step 06b README — Subscription Failed](../steps/step-06b-private-ai-litemaas/README.md#subscription-failed-to-subscribe)

### Chatbot "Network Error"

- **Component:** LiteMaaS Frontend / LiteLLM
- **Root Cause:** Backend returning internal LiteLLM URL instead of public URL
- **Fix:** Set `LITELLM_API_URL` in backend-secret to the **public** route URL
- **Details:** [Step 06b README — Chatbot Network Error](../steps/step-06b-private-ai-litemaas/README.md#chatbot-network-error)

### LiteLLM "Database not connected"

- **Component:** LiteLLM
- **Root Cause:** Wrong image or missing DATABASE_URL
- **Fix:** Use `ghcr.io/berriai/litellm-non_root:main-v1.74.7-stable` with `DATABASE_URL` env var
- **Details:** [Step 06b README — LiteLLM Database Not Connected](../steps/step-06b-private-ai-litemaas/README.md#litellm-database-not-connected)

---

## Step 06: Model Performance Metrics

### GuideLLM job failing

- **Component:** GuideLLM CronJob
- **Root Cause:** Model not responding or benchmark rate too high
- **Fix:** Check logs: `oc logs job/<job-name> -n private-ai`
- **Details:** [Step 06 README — GuideLLM Job Failing](../steps/step-06-model-performance-metrics/README.md#guidellm-job-failing)

### No data in Grafana

- **Component:** Grafana / Prometheus
- **Root Cause:** Prometheus targets not scraping or ServiceMonitor misconfigured
- **Fix:** Verify targets: `oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -- curl -s 'localhost:9090/api/v1/targets'`
- **Details:** [Step 06 README — No Data in Grafana](../steps/step-06-model-performance-metrics/README.md#no-data-in-grafana)

---

## Distributed Inference (llm-d) — removed, see [llm-d workshop](https://rhpds.github.io/llm-d-showroom/)

### Pods not scheduling

- **Component:** LeaderWorkerSet / Kueue
- **Root Cause:** Insufficient GPU nodes, quota exceeded, or missing tolerations
- **Fix:** Check node capacity and Kueue workload status
- **Details:** [Step 08 README — Pods Not Scheduling](../steps/step-08-llm-d/README.md#pods-not-scheduling)

### Router not ready

- **Component:** llm-d Router
- **Root Cause:** Router pod not starting or misconfigured
- **Fix:** Check router pods: `oc get pods -n private-ai | grep router`
- **Details:** [Step 08 README — Router Not Ready](../steps/step-08-llm-d/README.md#router-not-ready)

### OpenShift Console / Routes unavailable after creating Gateway

- **Component:** Gateway API / DNSRecord
- **Root Cause:** Gateway listener hostname `*.apps.<domain>` overwrites default wildcard DNS record
- **Fix:** Remove stale gateway stack; patch default-wildcard DNSRecord
- **Details:** [Step 08 README — Routes Unavailable After Gateway](../steps/step-08-llm-d/README.md#openshift-console--routes-unavailable-after-creating-openshift-ai-inference-gateway)

### Gateway TLS origination issues (known limitation)

- **Component:** Gateway API / Envoy
- **Root Cause:** HTTPRoute TLS origination from Gateway Envoy to HTTPS backend fails
- **Fix:** Use OpenShift Route (passthrough TLS) instead of Gateway endpoint
- **Details:** [Step 08 README — Gateway TLS Issues](../steps/step-08-llm-d/README.md#gateway-tls-origination-issues-known-limitation)

### Gateway connection issues (general)

- **Component:** Gateway API
- **Root Cause:** Gateway or HTTPRoute misconfigured
- **Fix:** Check gateway: `oc get gateway -n openshift-ingress`
- **Details:** [Step 08 README — Gateway Connection Issues](../steps/step-08-llm-d/README.md#gateway-connection-issues-general)

### Missing Kueue label

- **Component:** Kueue Admission Webhook
- **Root Cause:** CR rejected for missing required label
- **Fix:** Add `kueue.x-k8s.io/queue-name: default` to metadata.labels
- **Details:** [Step 08 README — Missing Kueue Label](../steps/step-08-llm-d/README.md#missing-kueue-label)

---

## Step 07: RAG Pipeline

### Milvus pod not starting

- **Component:** Milvus Standalone
- **Root Cause:** PVC or resource issue
- **Fix:** Describe pod: `oc describe pod -l app=milvus -n private-ai`
- **Details:** [Step 07 README — Milvus Pod Not Starting](../steps/step-07-rag-pipeline/README.md#milvus-pod-not-starting)

### LlamaStack lsd-rag CrashLoopBackOff

- **Component:** LlamaStackDistribution
- **Root Cause:** ConfigMap syntax error or Milvus not reachable
- **Fix:** Check logs: `oc logs deploy/lsd-rag -n private-ai --tail=100`
- **Details:** [Step 07 README — lsd-rag CrashLoopBackOff](../steps/step-07-rag-pipeline/README.md#llamastack-lsd-rag-crashloopbackoff)

### DSPA not ready

- **Component:** DataSciencePipelinesApplication
- **Root Cause:** Pipeline server or database issue
- **Fix:** Check DSPA: `oc get dspa dspa-rag -n private-ai -o yaml`
- **Details:** [Step 07 README — DSPA Not Ready](../steps/step-07-rag-pipeline/README.md#dspa-not-ready)

### Pipeline run fails

- **Component:** Kubeflow Pipelines
- **Root Cause:** Compilation error, missing PVC, or component failure
- **Fix:** Check pipeline pods: `oc get pods -n private-ai -l pipeline/runid --sort-by=.metadata.creationTimestamp`
- **Details:** [Step 07 README — Pipeline Run Fails](../steps/step-07-rag-pipeline/README.md#pipeline-run-fails)

---

## Step 08: RAG Evaluation

### Pipeline run fails immediately

- **Component:** Kubeflow Pipelines
- **Root Cause:** Eval configs not copied to PVC or lsd-rag not reachable
- **Fix:** Check pod logs: `oc logs <pod-name> -n private-ai`
- **Details:** [Step 08 README — Pipeline Run Fails Immediately](../steps/step-08-rag-evaluation/README.md#pipeline-run-fails-immediately)

### LlamaStack scoring timeout

- **Component:** LlamaStack Scoring API
- **Root Cause:** granite-8b-agent InferenceService not running (minReplicas: 0)
- **Fix:** Scale up granite-8b-agent InferenceService
- **Details:** [Step 08 README — Scoring Timeout](../steps/step-08-rag-evaluation/README.md#llamastack-scoring-timeout)

### All scores are ERROR

- **Component:** LlamaStack Scoring
- **Root Cause:** Missing scoring providers in lsd-rag configuration
- **Fix:** Check scoring config: `oc get configmap llama-stack-rag-config -n private-ai -o yaml | grep -A5 scoring`
- **Details:** [Step 08 README — All Scores ERROR](../steps/step-08-rag-evaluation/README.md#all-scores-are-error)

### Empty Milvus collections

- **Component:** Milvus / RAG Pipeline
- **Root Cause:** Ingestion pipeline not run
- **Fix:** Run ingestion: `cd steps/step-07-rag-pipeline && ./run-batch-ingestion.sh acme`
- **Details:** [Step 08 README — Empty Milvus Collections](../steps/step-08-rag-evaluation/README.md#empty-milvus-collections)

---

## Step 09: AI Safety with Guardrails

### Orchestrator pod not starting

- **Component:** GuardrailsOrchestrator
- **Root Cause:** ConfigMap syntax error or detector service not reachable
- **Fix:** Check logs: `oc logs -l app=guardrails-orchestrator -n private-ai --all-containers`
- **Details:** [Step 09 README — Orchestrator Pod Not Starting](../steps/step-09-guardrails/README.md#orchestrator-pod-not-starting)

### Detector InferenceService not ready

- **Component:** TrustyAI Detectors
- **Root Cause:** GPU scheduling or model loading issue
- **Fix:** Describe ISVC: `oc describe isvc hap-detector -n private-ai`
- **Details:** [Step 09 README — Detector Not Ready](../steps/step-09-guardrails/README.md#detector-inferenceservice-not-ready)

### LlamaStack shields not registering

- **Component:** LlamaStack / TrustyAI
- **Root Cause:** `trustyai_fms` safety provider not available
- **Fix:** Check providers: `oc exec deploy/lsd-genai-playground -n private-ai -- llama stack list-providers safety`
- **Details:** [Step 09 README — Shields Not Registering](../steps/step-09-guardrails/README.md#llamastack-shields-not-registering)

### Gateway returns 502

- **Component:** Gateway / Orchestrator
- **Root Cause:** granite-8b-agent not running or orchestrator can't reach it
- **Fix:** Verify model: `oc get isvc granite-8b-agent -n private-ai`
- **Details:** [Step 09 README — Gateway Returns 502](../steps/step-09-guardrails/README.md#gateway-returns-502)

---

## Step 10: MCP Integration

### Build fails

- **Component:** BuildConfig / S2I
- **Root Cause:** Git URL not reachable or npm install failure
- **Fix:** Check build logs: `oc logs build/database-mcp-1 -n private-ai`
- **Details:** [Step 10 README — Build Fails](../steps/step-10-mcp-integration/README.md#build-fails)

### MCP server not starting

- **Component:** MCP Server Deployment
- **Root Cause:** PostgreSQL not ready or image not built yet
- **Fix:** Check logs: `oc logs deploy/database-mcp -n private-ai`
- **Details:** [Step 10 README — MCP Server Not Starting](../steps/step-10-mcp-integration/README.md#mcp-server-not-starting)

### MCP tools not visible in Playground

- **Component:** ConfigMap / GenAI Playground
- **Root Cause:** ConfigMap `gen-ai-aa-mcp-servers` missing or in wrong namespace
- **Fix:** Check: `oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o yaml`
- **Details:** [Step 10 README — MCP Tools Not Visible](../steps/step-10-mcp-integration/README.md#mcp-tools-not-visible-in-playground)

### Agent doesn't call MCP tools

- **Component:** granite-8b-agent / vLLM
- **Root Cause:** Tool-calling not enabled in model serving arguments
- **Fix:** Verify args: `oc get isvc granite-8b-agent -n private-ai -o jsonpath='{.spec.predictor.model.args}' | tr ',' '\n' | grep tool`
- **Details:** [Step 10 README — Agent Doesn't Call MCP Tools](../steps/step-10-mcp-integration/README.md#agent-doesnt-call-mcp-tools)

---

## Issues Discovered During Deployment (2026-03-09)

### Argo CD fails entire sync when CRD does not exist at sync time

- **Step:** 01 (affects all steps with operator CRs)
- **Component:** Argo CD / Operator CRDs
- **Date:** 2026-03-09
- **Root Cause:** Argo CD validates ALL API resources upfront before processing sync waves. If a CRD doesn't exist (e.g., `kueue.openshift.io/Kueue`), the entire sync fails — even wave 0 resources (namespaces, subscriptions) are never created.
- **Fix:** Add `SkipDryRunOnMissingResource=true` to syncOptions in all Argo CD Application YAMLs. Increase retry limit from 5 to 10. Applied in commit `e6bbc38`.
- **Ref:** [Argo CD Sync Options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)

### GPU Operator InstallPlan requires manual approval

- **Step:** 01
- **Component:** GPU Operator Subscription
- **Date:** 2026-03-09
- **Root Cause:** GPU Operator subscription has `installPlanApproval: Manual` (intentional, to prevent driver auto-upgrade). In automated deployment, the InstallPlan must be explicitly approved.
- **Fix:** `oc patch installplan <name> -n nvidia-gpu-operator --type merge -p '{"spec":{"approved":true}}'`. The deploy-and-evaluate skill should auto-approve after creating the subscription.
- **Ref:** [Step 01 README — CUDA 13.0 Driver Compatibility](../steps/step-01-gpu-and-prereq/README.md#-cuda-130-driver-compatibility-issue-rhoai-30)

### GPU MachineSet fails with "no subnet IDs were found"

- **Step:** 01
- **Component:** AWS MachineSet
- **Date:** 2026-03-09
- **Root Cause:** The deploy.sh script hardcodes AZ suffix `b` (e.g., `us-east-2b`), but the cluster may not have a subnet in that AZ. Sandbox clusters often use only AZs `a` and `c`.
- **Fix:** Before creating MachineSets, check which AZs have working subnets by examining existing worker MachineSets: `oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.placement.availabilityZone}'`. Use the first available AZ.
- **Ref:** AWS subnet configuration is cluster-specific

### LeaderWorkerSet CRD name differs from upstream

- **Step:** 01
- **Component:** LWS Operator
- **Date:** 2026-03-09
- **Root Cause:** Red Hat build of LWS uses CRD name `leaderworkersetoperators.operator.openshift.io`, not the upstream `leaderworkersets.leaderworkerset.x-k8s.io`. Validation scripts checking the upstream name fail.
- **Fix:** Updated `validate.sh` to check for `leaderworkersetoperators.operator.openshift.io`.
- **Ref:** RHOAI 3.3 specific

### OpenShift Pipelines InstallPlan requires manual approval

- **Step:** 06
- **Component:** Pipelines Operator Subscription
- **Date:** 2026-03-09
- **Root Cause:** When installed via `oc apply` (not via OLM automatic channel), the Pipelines operator InstallPlan may default to Manual approval.
- **Fix:** Auto-approve all pending InstallPlans: `oc get installplan -A -o json | ...filter unapproved... | oc patch`
- **Ref:** OLM InstallPlan approval

### Kueue ClusterQueue missing GPU resource groups

- **Step:** 03 / 05
- **Component:** Kueue ClusterQueue
- **Date:** 2026-03-09
- **Root Cause:** The RHOAI operator creates its own ResourceFlavors (`nvidia-gpu-flavor`) but the step-03 ClusterQueue references custom flavors (`nvidia-l4-1gpu`, `nvidia-l4-4gpu`). If the Argo CD sync for step-03 doesn't complete fully, the ClusterQueue ends up with only `default-flavor` (CPU/memory), and GPU workloads are never admitted.
- **Fix:** Manually ensure both ResourceFlavors exist and the ClusterQueue includes them: `oc apply -f gitops/step-03-private-ai/base/cluster-queue.yaml`.
- **Ref:** [RHOAI 3.3 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_on_data_science_projects/working-with-distributed-workloads_distributed-workloads)

### AWS GPU vCPU quota too low for full demo (64 vCPU default)

- **Step:** 01 (Phase 0 prerequisite)
- **Component:** AWS Service Quotas / GPU MachineSets
- **Date:** 2026-03-09
- **Root Cause:** AWS sandbox accounts default to 64 vCPU for "Running On-Demand G and VT instances". The full demo requires 2x g6.4xlarge (32 vCPU) + 1x g6.12xlarge (48 vCPU) = 80 vCPU, exceeding the limit. With only 64 vCPU, you can provision 1x g6.4xlarge + 1x g6.12xlarge (5 GPUs) but not the 2nd g6.4xlarge needed for running granite-8b-agent and mistral-3-int4 simultaneously.
- **Fix:** Request AWS quota increase to 96 via Service Quotas console: "Running On-Demand G and VT instances" → 96. Small increases are often auto-approved within minutes.
- **Important:** Verify the quota increase is for the SAME region as the cluster (e.g., us-east-2). AWS quotas are per-region.
- **Ref:** https://console.aws.amazon.com/servicequotas/ (search EC2, "Running On-Demand G and VT instances")

### Kueue defaultClusterQueueName mismatch between DSC and Kueue component

- **Step:** 02 / 03
- **Component:** Kueue component CR
- **Date:** 2026-03-09
- **Root Cause:** The Kueue component CR (`kueue-component.yaml`) had `defaultClusterQueueName: default` while the DSC and LocalQueue in step-03 both reference `rhoai-main-queue`. This caused Argo CD OutOfSync and workloads routed to the wrong ClusterQueue.
- **Fix:** Changed `kueue-component.yaml` to `defaultClusterQueueName: rhoai-main-queue`. Committed in git.
- **Ref:** Queue chain: Workloads (queue-name: default) → LocalQueue "default" → ClusterQueue "rhoai-main-queue"

### Kueue assigns GPU nodeSelector to CPU-only pods (LlamaStack)

- **Step:** 03 / 05
- **Component:** Kueue ClusterQueue / ResourceFlavors
- **Date:** 2026-03-09
- **Root Cause:** ClusterQueue `rhoai-main-queue` only had GPU flavors. CPU-only pods (LlamaStack, Grafana) got assigned `nvidia-l4-1gpu` flavor which pins them to g6.4xlarge GPU nodes. When GPU nodes are full, CPU-only pods can't schedule.
- **Fix:** Add `default-flavor` FIRST in the ClusterQueue resourceGroups (before GPU flavors). This ensures CPU-only workloads get the default-flavor which schedules on regular worker nodes. Committed in gitops.
- **Ref:** Kueue tries flavors in order; first matching flavor wins

### LlamaStack DSCI CA bundle empty blocks operator

- **Step:** 05
- **Component:** DSCInitialization / LlamaStack operator
- **Date:** 2026-03-09
- **Root Cause:** DSCI `trustedCABundle.customCABundle: ""` causes `odh-trusted-ca-bundle` ConfigMap to have empty `odh-ca-bundle.crt` key. LlamaStack operator loops on "failed to find valid certificates" and never creates deployment.
- **Fix:** Patch DSCI with cluster CA cert at deploy time. See deploy-and-evaluate skill Phase 0 for the exact command.
- **Ref:** RHOAI 3.3 DSCInitialization trustedCABundle configuration

### LlamaStack config.yaml vs run.yaml key mismatch

- **Step:** 05
- **Component:** LlamaStack operator / ConfigMap
- **Date:** 2026-03-09
- **Root Cause:** The LlamaStack operator sets `LLAMA_STACK_CONFIG=/etc/llama-stack/config.yaml` but the userConfig ConfigMap had key `run.yaml`. The file `/etc/llama-stack/config.yaml` didn't exist, causing "Could not resolve config or distribution" error.
- **Fix:** Changed ConfigMap key from `run.yaml` to `config.yaml`. Also set `image_name: starter` (not `rh`) since `rh` is not a built-in distribution in the RHOAI image.
- **Ref:** LlamaStack v0.4.2.1+rhai0 config resolution

### Step 09 guardrails detector ISVCs missing Kueue label

- **Step:** 09
- **Component:** InferenceService / Kueue webhook
- **Date:** 2026-03-09
- **Root Cause:** The `hap-detector` and `prompt-injection-detector` InferenceServices were missing the `kueue.x-k8s.io/queue-name: default` label. The RHOAI Kueue webhook rejects ISVCs without this label.
- **Fix:** Added `kueue.x-k8s.io/queue-name: default` to both detector ISVC manifests. Committed in git.
- **Ref:** RHOAI 3.3 Kueue integration requires queue-name label on all InferenceServices

### Step 01 deploy.sh hangs on LWS CSV check

- **Step:** 01
- **Component:** deploy.sh / OLM CSV propagation
- **Date:** 2026-03-10
- **Root Cause:** `oc get csv -n openshift-lws-operator | grep -q "Succeeded"` hangs because OLM copies ALL global CSVs to every namespace. The output is very large and the pipe/grep becomes unreliable, causing the `until` loop to never exit even though the LWS CSV is Succeeded.
- **Fix:** Changed deploy.sh to use jsonpath filter for the specific CSV: `oc get csv -n openshift-lws-operator -o jsonpath='{.items[?(@.spec.displayName=="Red Hat build of Leader Worker Set")].status.phase}' | grep -q "Succeeded"`. This targets only the LWS CSV instead of grepping all CSV output.
- **Ref:** OLM copies CSVs to all namespaces for visibility; use jsonpath to filter specific operators

### ArgoCD ComparisonError for InferenceService CRD

- **Step:** 05
- **Component:** ArgoCD / serving.kserve.io/v1beta1
- **Date:** 2026-03-10
- **Root Cause:** ArgoCD's structured merge diff fails to resolve the InferenceService CRD schema, causing `ComparisonError: unable to resolve parseableType`. Affects any app managing InferenceService, LlamaStackDistribution, or Notebook CRDs.
- **Fix:** Add `ServerSideDiff=true` to ArgoCD Application `syncOptions`. This delegates diff calculation to the API server instead of ArgoCD's local schema resolver.
- **Ref:** [ArgoCD Server-Side Diff](https://argo-cd.readthedocs.io/en/stable/user-guide/diff-strategies/#server-side-diff)

### Upload jobs hang on HuggingFace network call

- **Step:** 05
- **Component:** model-upload Jobs / huggingface_hub
- **Date:** 2026-03-10
- **Root Cause:** Upload job Python scripts import `huggingface_hub` which tries to validate tokens against `huggingface.co`. In restricted clusters or when HF is slow, the process hangs indefinitely on `futex_wait_queue`. Output is also invisible because Python buffers stdout.
- **Fix:** Add `export HF_HUB_OFFLINE=1` (prevents network calls) and `export PYTHONUNBUFFERED=1` (shows progress immediately). Also removed `argocd.argoproj.io/hook: Sync` so jobs don't block ArgoCD sync.
- **Ref:** [HuggingFace Hub Offline Mode](https://huggingface.co/docs/huggingface_hub/guides/manage-cache#offline-mode)

### LlamaStack v0.4.x config schema incompatibility

- **Step:** 05
- **Component:** LlamaStackDistribution / config.yaml
- **Date:** 2026-03-10
- **Root Cause:** LlamaStack v0.4.2.1+rhai0 (RHOAI 3.3) uses a completely different config schema (`StackConfig`) than earlier versions. Key changes: (1) `url` → `base_url` in VLLMInferenceAdapterConfig, (2) `persistence_store` → `persistence.agent_state`/`responses` with KV/SQL store references, (3) `metadata_store.db_path` → `table_name` + `backend` referencing named storage backends, (4) top-level `models`/`shields`/`tool_groups` → `registered_resources.*`, (5) `version` must be int not string.
- **Fix:** Complete config.yaml rewrite matching StackConfig schema. Verified each field against live image introspection using a debug pod.
- **Ref:** Schema classes in `llama_stack.core.server.server.StackConfig`, `llama_stack.core.storage.datatypes`

### LlamaStack rh-dev distribution template merge overrides custom config

- **Step:** 05
- **Component:** LlamaStackDistribution / image_name
- **Date:** 2026-03-10
- **Root Cause:** When `image_name: rh-dev`, LlamaStack merges the rh-dev distribution's built-in template OVER the custom config. The built-in template has old-format provider configs (e.g., `db_path` + `type: sqlite`) that fail validation against the v0.4.x schema.
- **Fix:** Set `image_name: custom` in config.yaml. This prevents template loading, using only the custom config. All providers must be explicitly defined.
- **Ref:** `StackConfig.image_name` controls distribution template resolution

### LlamaStack duplicate LLAMA_STACK_CONFIG env var

- **Step:** 05
- **Component:** LlamaStackDistribution CR / operator
- **Date:** 2026-03-10
- **Root Cause:** The LlamaStack operator (v0.4.0) automatically injects `LLAMA_STACK_CONFIG` into the Deployment. Adding it in the CR's `containerSpec.env` causes "duplicate entries for key" error, preventing Deployment creation.
- **Fix:** Remove `LLAMA_STACK_CONFIG` from `containerSpec.env` in the LSD CR. The operator manages this env var.
- **Ref:** LlamaStack operator injects: `LLAMA_STACK_CONFIG`, `LLAMA_STACK_CONFIG_DIR`, `HF_HOME`, `SSL_CERT_FILE`, `LLS_WORKERS`, `LLS_PORT`

### LlamaStack queued models cause DNS failure at startup

- **Step:** 05
- **Component:** LlamaStackDistribution / vLLM providers
- **Date:** 2026-03-10
- **Root Cause:** Models with `minReplicas: 0` have headless Services but no endpoints. DNS resolution for `<model>-predictor.private-ai.svc.cluster.local` fails with "Name or service not known". LlamaStack tries to connect to all registered vLLM providers during startup and crashes if any are unreachable.
- **Fix:** Only register active models (minReplicas: 1) in the LlamaStack config.yaml. Queued models can be added when activated.
- **Ref:** KServe RawDeployment mode creates headless Services; DNS fails without running pods

### Missing tool-calling args cause silent Playground failure

- **Step:** 05
- **Component:** InferenceService / vLLM runtime args
- **Date:** 2026-03-10
- **Root Cause:** Playground RAG (`knowledge_search`) and MCP tool invocations require `--enable-auto-tool-choice` and `--tool-call-parser=<parser>` on the vLLM runtime. Without these, the model never invokes tools — failures are completely silent (no error, model just ignores tool calls).
- **Fix:** Add `--enable-auto-tool-choice --tool-call-parser=mistral` (or `granite`, `llama3_json`, `hermes` per model family) to each InferenceService's `spec.predictor.model.args`.
- **Ref:** [RHOAI 3.3 Model and runtime requirements for the playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#model-and-runtime-requirements-for-the-playground_rhoai-user)

### Playground RAG file_search tool fails — custom config bypasses rh-dev template

- **Step:** 05
- **Component:** LlamaStackDistribution / Playground RAG
- **Date:** 2026-03-11
- **Root Cause:** Providing a custom `config.yaml` via `userConfig.configMapName` with `image_name: custom` bypasses the `rh-dev` distribution template that wires `file_search` → `vector_io` → `embedding` in the Responses API. Without the template wiring, the file_search tool executes but returns `status: "failed"` with null results, even though the direct `/v1/vector_stores/{id}/search` endpoint works.
- **Fix:** Remove `userConfig` entirely. Let the `rh-dev` distribution template handle ALL provider wiring. Configure everything via env vars only: `INFERENCE_MODEL`, `VLLM_URL`, `VLLM_API_TOKEN`, `VLLM_TLS_VERIFY`, `VLLM_MAX_TOKENS`, `ENABLE_SENTENCE_TRANSFORMERS=true`, `EMBEDDING_PROVIDER=sentence-transformers`, `POSTGRES_HOST/PORT/DB/USER/PASSWORD`.
- **Ref:** [RHOAI 3.3 Example A: LlamaStackDistribution with Inline Milvus](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/)

### Granite model leaks `<tool_call>` XML tags in Playground

- **Step:** 05
- **Component:** InferenceService / vLLM chat template
- **Date:** 2026-03-11
- **Root Cause:** vLLM needs `--chat-template=/opt/app-root/template/tool_chat_template_granite.jinja` for the granite model to properly format tool calls. Without it, tool invocations appear as raw `<tool_call>` XML in the response text.
- **Fix:** Add `--chat-template=/opt/app-root/template/tool_chat_template_granite.jinja` to the granite-8b-agent InferenceService args.
- **Ref:** [RHOAI 3.3 Troubleshooting — model fails to call MCP tools](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/troubleshooting-playground-issues_rhoai-user)

### Playground RAG answers from training data instead of uploaded documents

- **Step:** 05
- **Component:** GenAI Playground / System instructions
- **Date:** 2026-03-11
- **Root Cause:** Granite 3.1 8B doesn't automatically invoke the `knowledge_search` tool. Its tool-calling heuristic matches system instructions to registered tool function names. Generic phrases like "search the knowledge base" or "search your documents" are NOT sufficient — the model needs to see the exact tool name `knowledge_search` to trigger invocation.
- **Fix:** System instructions MUST include the exact tool name. Tested working prompt: `"You are a knowledgeable AI assistant. When documents are available, always use the knowledge_search tool before answering. Ground your response in the retrieved content. If no relevant information is found, say so and offer general knowledge as a fallback."`
- **Key insight:** The minimum trigger phrase is `use the knowledge_search tool`. Everything else in the prompt is cosmetic.
- **Ref:** [RHOAI 3.3 Troubleshooting — model does not use RAG data](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/troubleshooting-playground-issues_rhoai-user)

### Mistral RAG fails in Playground — vLLM ToolCall index validation error

- **Step:** 05
- **Component:** vLLM Mistral chat template / LlamaStack tool-calling
- **Date:** 2026-03-11
- **Root Cause:** When LlamaStack sends tool-call results back to Mistral (as part of the RAG multi-turn conversation), the `ToolCall` object includes an `index` field. vLLM v0.13.0's Mistral chat template (`apply_mistral_chat_template`) rejects this with: `ValueError: 1 validation error for ToolCall / index / Extra inputs are not permitted`. This causes a 400 Bad Request, and the Playground shows an empty response.
- **Affected models:** All Mistral-family models (`mistral-3-bf16`, `mistral-3-int4`, `devstral-2`) with `--tool-call-parser=mistral`.
- **Not affected:** Granite models (uses `--tool-call-parser=granite` which accepts the `index` field).
- **Workaround:** Use Granite for all RAG/tool-calling demos. Use Mistral for basic chat only (RAG toggle OFF).
- **Status:** Upstream vLLM bug. Monitor for fix in future vLLM releases.

### Dashboard "Create playground" blocked by existing LSD

- **Step:** 05
- **Component:** RHOAI Dashboard UI (not the operator)
- **Date:** 2026-03-11
- **Root Cause:** The Dashboard's "Create playground" UI checks if ANY LlamaStackDistribution exists in the namespace and blocks creation with "LlamaStackDistribution already exists". This is a **Dashboard UI check only** — the LlamaStack operator supports multiple LSDs per namespace.
- **Workaround:** Create the Playground via Dashboard FIRST (when no LSD exists), then deploy `lsd-rag` via GitOps/`oc apply`. Both LSDs coexist at runtime without conflict.
- **Design Decision:** Two LSDs in `private-ai`: `lsd-genai-playground` (Dashboard-created, inline Milvus, multi-model Playground) + `lsd-rag` (GitOps-created, remote Milvus, production RAG). Each serves a distinct purpose. The RAG workbench connects to `lsd-rag-service:8321`.

### Kueue gates ALL pods in private-ai namespace (builds, chatbot, pipelines)

- **Step:** 03 (Kueue configuration)
- **Component:** Red Hat Build of Kueue / ClusterQueue / Namespace labeling
- **Date:** 2026-03-11
- **Symptom:** OpenShift builds, Streamlit chatbot deployments, KFP pipeline executor pods, and workbenches all get `SchedulingGated` by Kueue. Only GPU-consuming InferenceServices should be queued.
- **Root Cause:** The `private-ai` namespace has `kueue.openshift.io/managed=true` label, which causes Kueue to create Workload objects for EVERY pod in the namespace. The `default-flavor` with `nvidia.com/gpu: 0` should handle CPU-only pods, but Kueue's topology-aware scheduling (`kueue.x-k8s.io/topology` gate) still blocks them while trying to assign a topology domain.
- **Current Workaround:** Manually remove scheduling gates: `oc patch pod <name> -n private-ai --type=json -p '[{"op":"remove","path":"/spec/schedulingGates"}]'`
- **Proper Fix (TODO):** Two options per RHOAI 3.3 + Kueue docs:
  1. **Option A — Explicit queue labeling:** Remove `kueue.openshift.io/managed=true` from namespace. Only workloads with `kueue.x-k8s.io/queue-name` label get managed. RHOAI auto-adds this to InferenceServices/Notebooks. Builds and chatbot skip Kueue.
  2. **Option B — Separate resourceGroup for CPU:** Add a second `resourceGroup` in the ClusterQueue that covers only `cpu` + `memory` (without `nvidia.com/gpu`). CPU-only pods match this group and skip GPU topology scheduling.
- **Ref:** [RHOAI 3.3 — Managing workloads with Kueue](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_openshift_ai/managing-workloads-with-kueue), [Kueue Documentation](https://kueue.sigs.k8s.io/docs/)
