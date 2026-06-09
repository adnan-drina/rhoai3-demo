# Diagnostic Commands Reference

Quick-reference commands organized by component for troubleshooting the RHOAI
demo active baseline.

Before running live commands, use the repository safety guard from
`scripts/lib.sh`: load `.env`, verify the current API server matches
`RHOAI_EXPECTED_API_SERVER`, and prefer read-only inspection before mutation.

## Argo CD

```bash
# App status overview
oc get application <app-name> -n openshift-gitops

# Detailed sync status and health
oc get application <app-name> -n openshift-gitops -o yaml | grep -A 20 'status:'

# Sync errors
oc get application <app-name> -n openshift-gitops -o jsonpath='{.status.conditions[*].message}'

# Resource health breakdown
oc get application <app-name> -n openshift-gitops -o jsonpath='{range .status.resources[*]}{.kind}/{.name}: {.health.status} {.status}{"\n"}{end}'

# Force sync
oc patch application <app-name> -n openshift-gitops --type merge -p '{"operation":{"sync":{}}}'

# Argo CD server logs
oc logs deploy/openshift-gitops-server -n openshift-gitops --tail=50

# Verify AppProject usage (all apps should show rhoai-demo, not default)
oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,PROJECT:.spec.project

# Verify annotation tracking
oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.spec.resourceTrackingMethod}'

# Check manifest-generate-paths coverage
oc get applications -n openshift-gitops -o custom-columns='NAME:.metadata.name,PATHS:.metadata.annotations.argocd\.argoproj\.io/manifest-generate-paths'
```

## Operators (CSV, Subscription, InstallPlan)

```bash
# All CSVs across namespaces
oc get csv -A | grep -v Succeeded

# Subscription details
oc get sub -n <namespace> -o yaml

# InstallPlan status
oc get installplan -n <namespace>
oc describe installplan <name> -n <namespace>

# CatalogSource health
oc get catalogsource -n openshift-marketplace
oc get pods -n openshift-marketplace
```

## Pods

```bash
# Pod status with node placement
oc get pods -n <namespace> -o wide

# Describe pod (events, conditions, volumes)
oc describe pod <pod-name> -n <namespace>

# Current logs
oc logs <pod-name> -n <namespace> [-c <container>] --tail=100

# Previous container logs (after crash)
oc logs <pod-name> -n <namespace> [-c <container>] --previous

# Events in namespace (sorted by time)
oc get events -n <namespace> --sort-by=.lastTimestamp | tail -20

# Resource usage
oc adm top pods -n <namespace>
```

## GPU & Nodes

```bash
# GPU node status
oc get nodes -l node-role.kubernetes.io/gpu -o wide

# Node labels (GPU, NFD)
oc get nodes --show-labels | grep -E "gpu|nvidia|kernel-version"

# Node taints
oc get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key'

# MachineSet status
oc get machineset -n openshift-machine-api | grep gpu

# Machine status (provisioning)
oc get machines -n openshift-machine-api | grep gpu

# GPU allocatable resources
oc get nodes -l nvidia.com/gpu.present=true -o jsonpath='{range .items[*]}{.metadata.name}: {.status.allocatable.nvidia\.com/gpu} GPUs{"\n"}{end}'

# DCGM exporter metrics
oc exec -n nvidia-gpu-operator $(oc get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter -o name | head -1) -- curl -s localhost:9400/metrics | head -20
```

## KServe / InferenceService

```bash
# InferenceService status
oc get inferenceservice -n <namespace>

# Detailed conditions
oc get inferenceservice <name> -n <namespace> -o jsonpath='{range .status.conditions[*]}{.type}: {.status} ({.reason}){"\n"}{end}'

# Predictor pod
oc get pods -n <namespace> | grep <isvc-name>
oc describe pod <predictor-pod> -n <namespace>
oc logs <predictor-pod> -n <namespace> --tail=100

# ServingRuntime
oc get servingruntime -n <namespace> -o yaml

# Dashboard runtime recognition (check template annotations)
oc get servingruntime -n <namespace> -o custom-columns='NAME:.metadata.name,TEMPLATE:.metadata.annotations.opendatahub\.io/template-name,DISPLAY:.metadata.annotations.opendatahub\.io/template-display-name'

# KServe revision
oc get revision -n <namespace>
```

## Networking (Routes, Services)

```bash
# Routes in namespace
oc get route -n <namespace>

# Test route externally
curl -sk https://<route-host>/

# Services and endpoints
oc get svc -n <namespace>
oc get endpoints -n <namespace>

# Gateway API (for llm-d)
oc get gateway -A
oc get httproute -A
```

## Storage (PVC, MinIO)

```bash
# PVC status
oc get pvc -n <namespace>

# StorageClass
oc get storageclass

# MinIO bucket listing (via mc pod)
oc exec deploy/minio -n minio-storage -- mc ls --recursive myminio/
```

## LlamaStack

```bash
# Distribution status
oc get llamastackdistribution -n <namespace>

# Pod logs
oc logs deploy/<lsd-name> -n <namespace> --tail=100

# Health check
oc exec deploy/<lsd-name> -n <namespace> -- curl -s http://localhost:8321/v1/models

# Registered tool groups
oc exec deploy/<lsd-name> -n <namespace> -- curl -s http://localhost:8321/v1/tool-groups

# Shields (guardrails)
oc exec deploy/<lsd-name> -n <namespace> -- curl -s http://localhost:8321/v1/shields

# Vector stores (OpenAI-compatible API)
oc exec deploy/<lsd-name> -n <namespace> -- curl -s http://localhost:8321/v1/vector_stores
oc exec deploy/<lsd-name> -n <namespace> -- curl -s -X POST \
    http://localhost:8321/v1/vector_stores/<VS_ID>/search \
    -H "Content-Type: application/json" \
    -d '{"query":"test","max_num_results":3}'
```

## Guardrails

```bash
# Orchestrator status
oc get guardrailsorchestrator -n <namespace>
oc get pods -l app=guardrails-orchestrator -n <namespace>

# Orchestrator health
oc exec deploy/guardrails-orchestrator -n <namespace> -c guardrails-orchestrator -- curl -s http://localhost:8034/health

# Detector InferenceServices
oc get isvc hap-detector prompt-injection-detector -n <namespace>
```

## MCP Servers

```bash
# MCP server deployments
oc get deploy database-mcp openshift-mcp slack-mcp -n <namespace>

# MCP server logs
oc logs deploy/<server-name> -n <namespace> --tail=50

# PostgreSQL (database-mcp backend)
oc exec deploy/postgresql -n <namespace> -- psql -U acme_equipment -d acme_equipment -c "SELECT count(*) FROM equipment;"

# MCP ConfigMap for Playground (check transport field and URLs)
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o yaml

# Dashboard MCP status check (server-side validation)
# The gen-ai backend validates MCP endpoints — not the browser.
TOKEN=$(oc whoami -t)
GATEWAY=$(oc get route data-science-gateway -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null)
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://${GATEWAY}/gen-ai/api/v1/mcp/status?namespace=<project>&server_url=<url-encoded-mcp-url>"

# List MCP servers as seen by Dashboard (shows transport type)
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://${GATEWAY}/gen-ai/api/v1/aaa/mcps?namespace=<project>"

# LlamaStack tool_group registration (uses SSE transport internally, separate from Dashboard)
oc exec deploy/lsd-rag -n <namespace> -- curl -s http://localhost:8321/v1/toolgroups/mcp::<name>
```

## Model Registry

```bash
# Registry status
oc get modelregistry -n rhoai-model-registries

# Database health
oc exec deploy/model-registry-db -n rhoai-model-registries -- mysql -u mlmd -p'<password-from-secret>' -e "SHOW DATABASES;"

# API query
oc run test-api --rm -i --restart=Never --image=curlimages/curl -n rhoai-model-registries -- \
    curl -sf http://enterprise-ai-registry-internal:8080/api/model_registry/v1alpha3/registered_models
```

## Data Science Pipelines

```bash
# DSPA status
oc get dspa -n <namespace>

# Pipeline pods
oc get pods -n <namespace> -l pipeline/runid --sort-by=.metadata.creationTimestamp | tail -10

# Pipeline server
oc get pods -n <namespace> | grep ds-pipeline
```
