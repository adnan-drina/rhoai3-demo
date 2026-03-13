# Step 02: Red Hat OpenShift AI 3.3 Platform

Installs the full RHOAI 3.3 AI Platform — GenAI Studio, Hardware Profiles, model serving, distributed training, and governance — on top of the GPU infrastructure from step-01.

## The Business Story

RHOAI 3.3 is a **new-installation-only** release (no upgrade path from 2.x). It replaces Accelerator Profiles with **Hardware Profiles**, introduces **GenAI Studio** (Agent Playground + Model Catalog), renames `datasciencepipelines` to `aipipelines`, and moves user/admin group management from `OdhDashboardConfig` to a dedicated **Auth** resource. Service Mesh 3 is auto-installed by the DSC.

> **Warning**: You cannot upgrade from OpenShift AI 2.x to 3.x. Install fresh on OCP 4.19+ using the `stable-3.x` channel. See the [Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/release_notes/index).

## What Gets Deployed

| Component | State | Purpose |
|-----------|-------|---------|
| Dashboard | Managed | RHOAI web console |
| Workbenches | Managed | Jupyter notebooks, VS Code, RStudio |
| AI Pipelines | Managed | ML Pipelines (formerly `datasciencepipelines`) |
| LlamaStack Operator | Managed | GenAI Playground, agentic workflows |
| GenAI Studio | Enabled | Agent Playground + Model Catalog UI |
| KServe | Managed | Primary model serving (RawDeployment mode) |
| Model Registry | Managed | Model versioning and catalog |
| Training Operator | Managed | Kubernetes-native distributed training |
| Ray | Managed | Distributed computing framework |
| Kueue | **Unmanaged** | Standalone operator from step-01 |
| Kueue Component | Created | Dashboard integration for standalone Kueue |
| TrustyAI | Managed | Explainability, bias detection, drift monitoring |
| Feast Operator | Managed | Feature store for ML features |

## Hardware Profiles

Profiles are **global** (in `redhat-ods-applications`) and use **Queue-based scheduling** so Kueue controls node placement.

| Profile | Display Name | LocalQueue |
|---------|-------------|------------|
| cpu-small | Small (CPU Only) | `default` |
| default-profile | NVIDIA L4 1GPU (Default) | `default` |
| nvidia-l4-1gpu | NVIDIA L4 1GPU | `default` |
| nvidia-l4-4gpu | NVIDIA L4 4GPUs | `default` |

All profiles set `scheduling.type: Queue` with `localQueueName: default`. Each user project needs a matching `LocalQueue` named `default` (created in step-03). Kueue handles node selection via ClusterQueue/ResourceFlavor.

## Prerequisites

- [x] Step 01 completed (GPU infrastructure, Serverless, LWS, RHCL)
- [x] Cluster admin access
- [x] `oc` CLI installed and logged in
- [x] OpenShift 4.19+ (4.20 recommended)

## Deployment

### A) One-shot (recommended)

```bash
./steps/step-02-rhoai/deploy.sh
```

The script verifies step-01 prerequisites, creates the Argo CD Application, waits for the operator, and confirms the DataScienceCluster is Ready.

### B) Step-by-step

```bash
# Validate manifests
kustomize build gitops/step-02-rhoai/base | oc apply --dry-run=server -f -

# Apply Argo CD Application
oc apply -f gitops/argocd/app-of-apps/step-02-rhoai.yaml

# Wait for operator CSV to succeed (2-5 min)
until oc get namespace redhat-ods-operator &>/dev/null; do sleep 5; done
oc get csv -n redhat-ods-operator -w

# Wait for DSCInitialization CRD
until oc get crd dscinitializations.dscinitialization.opendatahub.io &>/dev/null; do sleep 5; done

# Wait for DataScienceCluster to become Ready (5-10 min)
until oc get datasciencecluster default-dsc &>/dev/null; do sleep 10; done
oc get datasciencecluster default-dsc -w

# Verify Hardware Profiles
oc get hardwareprofiles -n redhat-ods-applications
```

## Validation

```bash
# DSC phase
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'
# Expected: Ready

# Enabled components
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components}' | \
  jq -r 'to_entries | .[] | "\(.key): \(.value.managementState)"'

# Key pods running
oc get pods -n redhat-ods-applications | grep -E "dashboard|kserve|llama"

# Dashboard URL
oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='https://{.spec.host}'

# Hardware Profiles
oc get hardwareprofiles -n redhat-ods-applications

# GenAI Studio enabled
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.genAiStudio}'
# Expected: true
```

## Troubleshooting

### Operator Not Installing

```bash
oc get subscription rhods-operator -n redhat-ods-operator -o yaml
oc get installplan -n redhat-ods-operator
oc get packagemanifest rhods-operator -o jsonpath='{.status.channels[*].name}'
```

### DataScienceCluster Not Ready

```bash
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions}' | jq .
oc logs -n redhat-ods-operator -l name=rhods-operator --tail=100
```

### GenAI Studio Not Visible

Verify `genAiStudio: true` in `OdhDashboardConfig`, confirm `llamastackoperator` is `Managed` in DSC, and restart the dashboard pod if needed:

```bash
oc delete pod -n redhat-ods-applications -l app=rhods-dashboard
```

### Hardware Profile Not Appearing

```bash
oc get hardwareprofile -n redhat-ods-applications
oc get nodes -l node-role.kubernetes.io/gpu -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels."node\.kubernetes\.io/instance-type"
```

## GitOps Structure

```
gitops/step-02-rhoai/
└── base/
    ├── kustomization.yaml
    └── rhoai-operator/
        ├── namespace.yaml
        ├── operatorgroup.yaml
        ├── subscription.yaml               # stable-3.x channel
        ├── dsci.yaml                       # DSCInitialization (Service Mesh: Managed)
        ├── datasciencecluster.yaml         # Full component stack (kueue: Unmanaged)
        ├── kueue-component.yaml            # ODH Kueue for Dashboard integration
        ├── auth.yaml                       # User/Admin groups
        ├── dashboard-config.yaml           # GenAI Studio + disableKueue: false
        ├── hardware-profile-cpu-small.yaml
        ├── hardware-profile-default.yaml
        ├── hardware-profile-l4-1gpu.yaml
        └── hardware-profile-l4-4gpu.yaml
```

## Design Decisions

> **Kueue as standalone operator**: RHOAI 3.3 sets `kueue.managementState: Unmanaged` in the DSC because Kueue is installed as a standalone operator in step-01. The `Kueue` component CR and `disableKueue: false` in `OdhDashboardConfig` provide Dashboard integration without RHOAI managing the operator lifecycle.

> **GenAI Studio enabled by default**: `genAiStudio: true` in `OdhDashboardConfig` plus `llamastackoperator: Managed` in the DSC activate the Agent Playground and Model Catalog UI for all users.

> **Queue-based Hardware Profiles**: All profiles use `scheduling.type: Queue` instead of `Node` so Kueue governs GPU allocation. Profiles with `type: Node` will not work in Kueue-managed projects.

> **Service Mesh auto-managed**: `DSCInitialization` sets `serviceMesh.managementState: Managed`, so Service Mesh 3 is installed automatically by the DSC for KServe traffic management.

## References

- [RHOAI 3.3 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/release_notes/index)
- [RHOAI 3.3 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [Installing RHOAI Components](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-rhoai-components)
- [Configuring Hardware Profiles](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/working_with_accelerators/index#working-with-hardware-profiles)
- [RHOAI 3.3 Showroom](https://rhpds.github.io/redhat-openshift-ai-3-showroom/)
- [Red Hat CoP GitOps Catalog](https://github.com/redhat-cop/gitops-catalog/tree/main/openshift-ai)

## Next Steps

Continue to [Step 03 — Private AI Infrastructure](../step-03-private-ai/README.md) to configure Kueue queues, resource flavors, and per-project LocalQueues.
