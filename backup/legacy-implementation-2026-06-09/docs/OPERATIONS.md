# Operations Guide

This guide keeps runbook content out of the step READMEs. Use it when you are deploying, validating, operating, or cleaning up the RHOAI 3.4 demo environment.

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| OpenShift Container Platform 4.20 | The manifests and scripts target OCP 4.20. Verify cluster APIs with `oc version` and `oc get clusterversion`. |
| Cluster-admin access | Bootstrap grants the OpenShift GitOps Argo CD application controller cluster-admin for this demo. |
| AWS GPU capacity | Step 01 creates `g6.4xlarge` and `g6.12xlarge` MachineSets for NVIDIA L4 GPUs. Confirm regional quota before deployment. |
| `oc` CLI | Required by every script. Login before running bootstrap or step scripts. |
| Optional project kubeconfig | Set `KUBECONFIG` in local `.env` to an absolute path under `tmp/` when this repo owns a cluster-specific kubeconfig. |
| Git remote | `scripts/bootstrap.sh` detects `origin` and rewrites Argo CD Application repo URLs for forks. |
| Optional credentials | `HF_TOKEN` speeds or authorizes Hugging Face downloads; `OPENAI_API_KEY` enables Step 05 external MaaS models; `SLACK_BOT_TOKEN` enables Slack MCP; Step 13b needs `EDGE_HOST`, `EDGE_USER`, and `EDGE_PASS`. |
| Pull access | Red Hat registry, Quay, and other image sources must be reachable unless you adapt the demo for disconnected mirroring. |

Self-signed or demo certificates are expected. The scripts and examples use `--insecure-skip-tls-verify=true` and `curl -k` where needed.

## Fresh Environment Checklist

When moving the demo to a new cluster, update local environment state before
running bootstrap or step scripts:

1. Save the new cluster kubeconfig as an ignored repo-local file, for example
   `tmp/current-cluster.kubeconfig`.
2. Update local `.env`:
   - `KUBECONFIG=/absolute/path/to/rhoai3-demo/tmp/current-cluster.kubeconfig`
   - `RHOAI_EXPECTED_API_SERVER=<unique substring or full API hostname>`
   - `GIT_REPO_URL=<repo URL Argo CD should sync from>`
   - `GIT_REPO_BRANCH=<branch Argo CD should sync from>`
3. Refresh local-only credentials as needed: `HF_TOKEN`, `OPENAI_API_KEY`,
   Slack values, and edge host values.
4. Confirm AWS GPU quota and region can create the required `g6.4xlarge` and
   `g6.12xlarge` MachineSets.
5. Run the prerequisite validation:

   ```bash
   ./.agents/skills/env-deploy-and-evaluate/scripts/validate-prerequisites.sh
   ```

6. Run `./scripts/bootstrap.sh`, then deploy and validate steps in order.

Do not encode a generated cluster name such as `cluster-abcde` in tracked
files. Use it only as a local `.env` guard value or local kubeconfig filename
when that helps identify the active environment.

## Deployment Order

Run bootstrap once, then deploy steps in order.

```bash
./scripts/bootstrap.sh
```

| Phase | Steps | Purpose |
|-------|-------|---------|
| Platform | 01-02 | GPU prerequisites, OpenShift Serverless, Red Hat build of Kueue Operator, RHCL/Kuadrant for MaaS, RHOAI operator, DataScienceCluster, hardware profiles. |
| Governance | 03-04 | Project boundary, users, RBAC, MinIO, data connections, model registry. |
| Generative AI | 05-10 | LLM serving, metrics, RAG, evaluation, guardrails, MCP tools. |
| Predictive AI | 11-12 | Face recognition serving, notebooks, training pipeline, TrustyAI monitoring. |
| Edge AI | 13-13b | Simulated edge namespace and optional MicroShift edge host. |

Use the same pattern for each step:

```bash
./steps/step-XX-name/deploy.sh
./steps/step-XX-name/validate.sh
```

## Bootstrap Behavior

`scripts/bootstrap.sh` performs cluster-wide setup for GitOps:

| Action | Why It Exists |
|--------|---------------|
| Installs OpenShift GitOps | Provides the Argo CD instance used by every step. |
| Pins OpenShift GitOps to `gitops-1.20` by default | Keeps the GitOps operator aligned with the OCP 4.20 demo baseline and avoids stale conversion webhooks from older channels. Override with `OPENSHIFT_GITOPS_CHANNEL` only for a documented compatibility test. |
| Detects Git remote | Makes forks work without manually editing all Application manifests. |
| Grants Argo CD cluster-admin | Simplifies a demo that installs operators and cluster-scoped resources. Do not copy this blindly into production. |
| Sets `resourceTrackingMethod: annotation` | Avoids label tracking collisions on resources managed by operators. |
| Ignores operator-owned status-only updates | Prevents RHOAI, OLM, KServe, Model Registry, and Llama Stack status heartbeats from forcing continuous Argo CD reconciliation. |
| Applies only out-of-sync resources | Step Applications set `ApplyOutOfSyncOnly=true` so Argo CD does not rewrite every managed object during recovery or refresh cycles. This reduces API and etcd write pressure while operators are already reconciling. |
| Aligns RHCL to the RHOAI recovery catalog | Step 01 uses `redhat-operators-rhoai` for `rhcl-operator` because the RHOAI 3.4 upgrade installed the live RHCL stack from that catalog in this lab. RHCL dependency subscriptions for Authorino, Limitador, and DNS Operator are left to OLM in `openshift-operators`; Step 01 does not install duplicate standalone subscriptions in component-specific namespaces. |
| Adds Argo CD health checks | Handles PVC `WaitForFirstConsumer`, KServe `InferenceService`, and `TrustyAIService` health more accurately. |
| Creates `rhoai-demo` AppProject | All step Applications use this project. |

## Deploy Script Model

Every `deploy.sh` applies its Argo CD Application as the first material deployment action. Do not deploy Argo CD managed resources directly with `oc apply -k`.

Some deploy scripts then perform runtime actions that cannot live cleanly in Git:

| Step | Runtime Work |
|------|--------------|
| 01 | Detects cluster ID, AMI, region, and availability zone; installs the RHOAI observability prerequisite operators; approves RHCL dependency install plans when OLM requires them; repairs MaaS AuthConfig schema drift before RHCL/Authorino upgrade validation; creates GPU MachineSets; applies documented Authorino TLS runtime configuration after Kuadrant creates generated services. |
| 02 | Approves pending Service Mesh 3 install plans when RHOAI creates them manually; patches DSCI CA bundle; configures `DSCI.spec.monitoring` metrics/traces; re-enables GenAI Studio if reconciled away. |
| 03 | Creates OpenShift groups; applies MinIO console Route excluded from Argo CD due to diff behavior. |
| 05 | Creates Hugging Face token secret if available; creates `maas/openai-provider-api-key` from `OPENAI_API_KEY` if available; uploads large Mistral model to MinIO; registers local and external MaaS models; reapplies the MaaS AuthConfig schema repair when MaaS route objects are regenerated. |
| 07 | Builds or deploys ingestion/chatbot resources and initializes RAG data. |
| 08 | Copies evaluation configs and can launch evaluation jobs. |
| 10 | Creates Slack secret from `.env`, patches route-specific MCP config, registers MCP tool groups in Llama Stack. |
| 11 | Creates Hugging Face token secret if available and uploads pre-trained face model. |
| 12 | Uploads training data when present, ensures YOLO base model, launches the KFP training pipeline, configures TrustyAI metrics. |
| 13 | Optionally builds/pushes edge camera image, then waits for the edge app and InferenceService. |
| 13b | SSHes to the edge host, installs/configures MicroShift, creates ModelCar image, and deploys edge workloads. |

## Operator Subscription Alignment

Use the alignment helper when an upgraded RHOAI 3.4 cluster shows stale OLM channels, copied CSV churn, or RHCL dependency drift:

```bash
./scripts/align-operator-subscriptions.sh --verify
./scripts/align-operator-subscriptions.sh --apply
```

The helper is intentionally scoped to subscriptions used by this demo. It aligns RHOAI to `stable-3.x`, OpenShift GitOps to `gitops-1.20`, RHCL to `rhcl-operator.v1.3.4` from `redhat-operators-rhoai`, keeps Authorino/Limitador/DNS as RHCL-generated dependencies in `openshift-operators`, approves pending RHCL and Service Mesh install plans, and removes the old standalone RHCL dependency namespaces.

## GitOps And Argo CD Operating Model

The GitOps source of truth is split intentionally:

| Path | Responsibility |
|------|----------------|
| `gitops/argocd/app-of-apps/step-*.yaml` | Per-step Argo CD Applications. |
| `gitops/step-*/base/` | Kustomize bases applied by Argo CD. |
| `gitops/edge-ai-microshift/` | Manifests consumed by the optional MicroShift edge GitOps flow. |
| `steps/step-*/deploy.sh` | Runtime orchestration around the GitOps source. |
| `steps/step-*/validate.sh` | Read-only checks for cluster state. |

Most Applications enable automated sync and pruning. Step 01, Step 02, and Step 05 intentionally set `selfHeal: false` for cases where platform operators or manual scaling can legitimately change live state during the demo. Step 02 still syncs desired RHOAI specs when the Application is applied, but it does not continuously reapply while the RHOAI operator reconciles generated resources.

Step 02 manages `DataScienceCluster/default-dsc`, whose status can update frequently while RHOAI components reconcile. Bootstrap configures Argo CD to ignore `/status`-only updates for this and other operator-owned resources; the Step 02 Application also ignores RHOAI CR status fields directly. This keeps the application managing desired specs while avoiding high-frequency reconciliation loops.

All step Applications include `ApplyOutOfSyncOnly=true`. During normal operation this is equivalent to standard auto-sync for changed resources, but during control-plane recovery it avoids full-application rewrites that amplify OLM, RHOAI, KServe, and Gateway controller lease churn.

When Argo CD reports drift, first check whether the Application contains an `ignoreDifferences` entry for an operator-managed field. If drift is not covered and the field matters, update the manifest and README together.

## Validation Strategy And Exit Codes

Most validation scripts source `scripts/validate-lib.sh`:

| Exit Code | Meaning |
|-----------|---------|
| 0 | All checks passed. |
| 1 | One or more critical checks failed. |
| 2 | Warnings only; the step may still be usable while asynchronous resources settle. |

Validation checks are deterministic cluster checks, not narrative demos. They normally verify Argo CD status, CRDs, CSVs, pods, Routes, key CR conditions, jobs, services, secrets, API-key metadata, and selected API calls.

The full ACME flow has a separate validator:

```bash
./scripts/validate-genai-playground-readiness.sh
./scripts/validate-demo-flow.sh
```

`validate-genai-playground-readiness.sh` checks the product-native Playground prerequisites: GenAI Studio flags, internal custom endpoint posture, model AI asset labels, MCP ConfigMap JSON, RAG project storage, vector-store availability, and MLflow workspace readiness. Step 08 `validate.sh` now checks the product-native EvalHub path: target cluster guard, RHOAI 3.4 readiness gates, EvalHub CR/route/health, tenant RBAC, provider discovery, latest smoke job, and MLflow experiment URL. `validate-demo-flow.sh` checks tool runtime, agentic behavior, and guardrail behavior across the custom RAG/MCP flow. Slack tests require a valid Slack token and expected channel configuration.

MaaS API key handling is part of deployment, not a manual post-step. Step 05 creates user-owned `60d` keys for `ai-admin` and `ai-developer`; Step 07 creates the system key used by Llama Stack and the Streamlit chatbot; Step 09 syncs the same key into NeMo Guardrails. The default lifetime can be overridden with `RHOAI_DEMO_MAAS_KEY_TTL`, and the validation scripts fail if the stored key metadata or model-discovery calls drift.

RHOAI creates a product-managed `models-as-a-service` namespace for MaaS governance (`Tenant`, `MaaSSubscription`, and `MaaSAuthPolicy`). Do not delete it during cleanup. The demo serving namespace is `maas`, displayed as `MaaS Runtime`, and that is where KServe models, Grafana, GuideLLM jobs, and model-serving routes live.

MaaS usage monitoring is enabled across the foundation steps. Step 01 installs Cluster Observability Operator, Tempo, and Red Hat build of OpenTelemetry, enables Kuadrant observability, and patches the generated `Limitador` CR to `telemetry: exhaustive`; Step 02 configures the RHOAI monitoring service for metrics and traces, enables the RHOAI observability dashboard, and enables MaaS Tenant telemetry with user capture for the demo; Step 05 generates model-route MaaS traffic with `X-Gateway-Model-Name` and verifies Prometheus can see dashboard-facing `authorized_calls` and `authorized_hits`.

The product MaaS Usage dashboard is a recent-window view, so it can legitimately return to zero after idle periods. Step 05 includes the GitOps-managed `maas-usage-heartbeat` CronJob to keep a low-rate stream of MaaS-gateway traffic alive for the demo. GuideLLM jobs in Step 06 call predictor services directly for performance benchmarking and do not populate MaaS Usage data.

`DSCInitialization.spec.monitoring.alerting` is intentionally not set for this demo baseline. On the target RHOAI 3.4 cluster, enabling the optional alerting branch caused the RHOAI operator to repeatedly log `failed to add prometheus rules for component mlflowoperator: prometheus rules file for component mlflowoperator not found`. Keep metrics/traces enabled for the dashboard and revisit alerting after a product fix or documented MLflow alerting posture is available.

To retest built-in alerting after the MLflow prometheus-rules issue is resolved:

```bash
RHOAI_OBSERVABILITY_ENABLE_ALERTING=true ./steps/step-02-rhoai/deploy.sh
oc get pods -n redhat-ods-monitoring | grep alertmanager
oc get svc -n redhat-ods-monitoring | grep alertmanager
oc port-forward svc/data-science-monitoringstack-alertmanager 9093:9093 -n redhat-ods-monitoring
```

The product-native **Observe & monitor** dashboard depends on `Monitoring/default-monitoring` being `Ready` and on the generated `redhat-ods-monitoring` stack. If the dashboard shows `Error loading components` or `Service Unavailable`, verify:

```bash
oc get csv -n openshift-cluster-observability-operator
oc get csv -n openshift-tempo-operator
oc get csv -n openshift-opentelemetry-operator
oc get networkpolicy tempo-operator-egress-to-kubernetes-service -n openshift-tempo-operator
oc get endpoints tempo-operator-controller-service -n openshift-tempo-operator
oc get monitoring default-monitoring
oc get pods,pvc,monitoringstack,perses,persesdashboard,tempomonolithic,opentelemetrycollector -n redhat-ods-monitoring
oc get svc -n redhat-ods-monitoring | grep -E 'data-science-collector|tempo.*query|query.*tempo'
oc rollout restart deployment/rhods-dashboard -n redhat-ods-applications
```

Workload metrics scraping is opt-in. Only workloads that expose `/metrics` should carry `monitoring.opendatahub.io/scrape=true` on generated pods. In this demo that currently means vLLM predictor pods in `maas` and OVMS predictor pods in `enterprise-mlops` and `edge-ai-demo`:

```bash
oc get pods -n maas -l serving.kserve.io/inferenceservice=granite-8b-agent \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.monitoring\.opendatahub\.io/scrape}{"\n"}{end}'
oc get pods -n enterprise-mlops -l serving.kserve.io/inferenceservice=face-recognition \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.monitoring\.opendatahub\.io/scrape}{"\n"}{end}'
```

External observability exporters are optional. Do not configure placeholder endpoints; use a real OTLP or Prometheus remote-write receiver. Step 02 can patch the documented DSCI exporter lists from environment variables:

```bash
RHOAI_OBSERVABILITY_METRICS_EXPORTER_ENDPOINT=https://otel.example.com:4318 \
RHOAI_OBSERVABILITY_METRICS_EXPORTER_NAME=enterprise-metrics \
RHOAI_OBSERVABILITY_METRICS_EXPORTER_TYPE=otlp \
RHOAI_OBSERVABILITY_TRACES_EXPORTER_ENDPOINT=https://tempo.example.com:4318 \
RHOAI_OBSERVABILITY_TRACES_EXPORTER_NAME=enterprise-traces \
RHOAI_OBSERVABILITY_TRACES_EXPORTER_TYPE=otlp \
./steps/step-02-rhoai/deploy.sh
```

Equivalent manual patch:

```bash
oc patch dscinitialization default-dsci --type merge -p '{
  "spec": {
    "monitoring": {
      "metrics": {
        "exporters": [
          {"name": "enterprise-metrics", "type": "otlp", "endpoint": "https://otel.example.com:4318"}
        ]
      },
      "traces": {
        "exporters": [
          {"name": "enterprise-traces", "type": "otlp", "endpoint": "https://tempo.example.com:4318"}
        ]
      }
    }
  }
}'
oc get pods -n redhat-ods-monitoring | grep data-science-collector
```

The Step 07 chatbot is wired to the in-cluster collector for minimal app traces:

```bash
oc get deploy rag-chatbot -n enterprise-rag \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="chatbot")].env[?(@.name=="OTEL_EXPORTER_OTLP_ENDPOINT")].value}{"\n"}'
oc port-forward svc/tempo-query-frontend 3200:3200 -n redhat-ods-monitoring
```

If the Tempo query service name differs, use `oc get svc -n redhat-ods-monitoring | grep -E 'tempo.*query|query.*tempo'` and port-forward that service instead.

The Streamlit chatbot also has a browser-level validator:

```bash
./scripts/validate-chatbot-ui.sh
```

It checks route health, Chat page load, every configured example prompt, MCP tool use, prompt-injection guardrails, and the Inspect page. Use `--skip-mcp` or `--skip-guardrails` only when those dependencies are intentionally not deployed.

## RHOAI 3.4 Chatbot Alignment Notes

The Step 07 chatbot is aligned for an RHOAI 3.4 demo with explicit preview/developer-preview posture:

| Component | Alignment |
|-----------|-----------|
| Llama Stack runtime | RHOAI 3.4 documents Llama Stack as Technology Preview. The chatbot uses the 0.7 client line and isolates live REST endpoints behind `llama_stack_compat.py`. |
| RAG vector stores | Uses the RHOAI 3.4 Llama Stack vector store and file search path with pgvector-backed storage and source metadata. |
| Responses API | Agent-based mode uses Responses API `file_search` and constrained output tokens to avoid vLLM context overflow. |
| MCP connectors | Release notes describe Llama Stack connector and MCP HTTP streaming compatibility. Product docs are still lighter than the live `/v1beta/connectors` API, so keep this path clearly labeled as demo/preview. |
| Guardrails | The chatbot calls the Step 09 NeMo Guardrails service for input and output policy checks. Prompt-injection blocking is validated in the UI test. |
| RHOAI Gen AI Playground | Steps 05, 07, and 10 now include product-native scenes for model comparison, inline knowledge upload, MCP server selection, prompt saving, and code export. These scenes complement the custom chatbot rather than replacing it. |

Product-aligned next improvements:

| Candidate | Why It Helps |
|-----------|--------------|
| Guardrails AutoConfig | Reduces hand-maintained detector/generator wiring once detector labels and model names are stable. |
| Guardrails OpenTelemetry | Adds traces and metrics for safety decisions, detector latency, and blocked prompts. |
| Guardrails Gateway | Provides a governed guarded endpoint demo in addition to the chatbot's direct detector-control path. |
| Product-native guardrail asset registration | The custom chatbot validates NeMo guardrails today. Add a Dashboard-native guardrail asset scene once the supported registration path is schema-verified on the target RHOAI 3.4 cluster. |
| EvalHub MCP integration | Exposes product-native EvalHub operations to agentic clients once the supported MCP surface is documented for RHOAI 3.4. |
| EvalHub observability | Adds OTEL/Prometheus dashboards for EvalHub server latency, job states, provider runtime failures, and MLflow logging outcomes. |

## Day-2 Operational Notes

| Task | Command Or Guidance |
|------|---------------------|
| Check all Applications | `oc get applications -n openshift-gitops` |
| Inspect one Application | `oc describe application step-07-rag -n openshift-gitops` |
| Watch pods for a step | `oc get pods -n maas -w` or the step-specific namespace. |
| Verify RHOAI health | `oc get datasciencecluster default-dsc -o yaml` |
| Verify KServe models | `oc get inferenceservice -A` |
| Verify MaaS API keys | `oc get secret ai-admin-maas-api-key ai-developer-maas-api-key -n maas` and `oc get secret rag-maas-api-key -n enterprise-rag` |
| Verify external MaaS models | `oc get externalmodel gpt-5 -n maas -o yaml`, `oc get maasmodelref gpt-5 -n maas`, and confirm `maas/openai-provider-api-key` has an `api-key` data key. |
| Verify external provider auth | If a GPT-5 chat request reaches OpenAI but returns `You didn't provide an API key`, inspect `oc get authpolicy maas-auth-gpt-5 -n maas -o yaml`; the current RHOAI 3.4 TP controller might clear upstream `Authorization` instead of injecting the provider Secret. Keep the provider key in `maas/openai-provider-api-key`; do not patch it into GitOps manifests. |
| Verify MaaS usage metrics | Query `up{job="kuadrant-system/kuadrant-limitador-monitor"}`, confirm `oc get cronjob maas-usage-heartbeat -n maas`, then generate or wait for model-route traffic with `X-Gateway-Model-Name: granite-8b-agent` and query `authorized_calls{user!="",subscription!=""}` plus `authorized_hits{user!="",model!=""}`. The RHOAI Usage dashboard uses these Limitador metrics. |
| Verify RHOAI observability dashboard | Check `oc get monitoring default-monitoring` and confirm **Observe & monitor** → **Dashboard** shows Cluster, Models, and Usage tabs. |
| Verify model registry | `oc get modelregistry -n rhoai-model-registries` |
| Verify GPU nodes | `oc get nodes -l nvidia.com/gpu.present=true` and `oc describe node <gpu-node>` |
| Scale GPU MachineSets | Use `oc scale machineset ... -n openshift-machine-api`; Step 01 self-heal is disabled to allow this. |
| Review external boundaries | Check `.env`, Llama Stack provider config, Slack secret, Hugging Face token secret, and image references. |
| Validate docs alignment | Keep step README, deploy script, validation script, and GitOps manifests aligned in the same change. |

## Pre-Merge Documentation Alignment Gate

Before merging a branch that changes GitOps-managed components, run the documentation alignment audit:

```bash
./scripts/audit-doc-alignment.sh --base origin/main
```

For a focused check while developing a single step:

```bash
./scripts/audit-doc-alignment.sh --component step-05-maas-model-serving
```

The gate is pinned to RHOAI 3.4 and OCP 4.20 until the demo baseline changes. It blocks only high-risk drift, including invalid Kustomize output, stale pre-3.4 product references in touched components, and unsupported API/schema evidence when strict live-cluster checks are enabled.

The audit prints a transient report and exits nonzero when it finds blocking drift. It can cite `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` as read-only research input for Red Hat article alignment, but official product documentation remains the source of truth.

## Cleanup

This repository does not provide a single destructive cleanup script. For individual resources, prefer Argo CD Application deletion only when you understand dependencies between steps:

```bash
oc delete application step-10-mcp-integration -n openshift-gitops
```

Avoid deleting shared namespaces such as `maas`, `minio-storage`, or RHOAI operator namespaces unless you are rebuilding the demo from scratch.

## References

- [OpenShift Container Platform 4.20 documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/)
- [Red Hat OpenShift AI Self-Managed 3.4 documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/)
- [OpenShift GitOps documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/latest/)
- [Using AI models on Red Hat build of MicroShift 4.20](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html-single/using_ai_models/index)
