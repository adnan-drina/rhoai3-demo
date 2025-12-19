# Step 02: Red Hat OpenShift AI 3.0 (RHOAI)

Installs Red Hat OpenShift AI 3.0 operator and creates a DataScienceCluster with core components enabled.

> **Note**: RHOAI 3.0 is for **new installations only**. If you have 2.x, do not attempt to "upgrade" via the subscription channel.

## What Gets Installed

Per [RHOAI 3.0 documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index):

| Component | State | Purpose |
|-----------|-------|---------|
| Dashboard | Managed | RHOAI web console |
| Workbenches | Managed | Jupyter notebooks, VS Code |
| **LlamaStack Operator** | Managed | **GenAI Playground / Agentic workflows** |
| **Model Registry** | Managed | **Model Catalog registration** |
| KServe | Managed | Model serving (RawDeployment mode) |
| Training Operator | Managed | Distributed training jobs |
| Ray | Removed | Requires distributed workloads prereqs (Ch. 5) |
| Kueue | Removed | Requires distributed workloads prereqs (Ch. 5) |
| AI Pipelines | Removed | Requires Argo Workflows config (Ch. 4) |
| TrustyAI | Removed | Model explainability (optional) |
| Feast Operator | Removed | Feature store (optional) |

> **Note**: RHOAI 3.0 is a new installation only (no upgrade from 2.x). See [Chapter 5](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-distributed-workloads-components_component-install) for distributed workloads prerequisites.

## RHOAI 3.0 Specific Resources

| Resource | Purpose |
|----------|---------|
| Subscription | Uses `fast-3.x` channel (required for 3.0) |
| DSCInitialization | **New in 3.0** - Global operator configuration |
| DataScienceCluster | Core RHOAI configuration |
| OdhDashboardConfig | **Enables GenAI Studio** (Playground + Model Catalog UI) |

## Prerequisites

- [ ] Step 01 completed (GPU infrastructure)
- [ ] Cluster admin access
- [ ] `oc` CLI installed and logged in

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     OpenShift Cluster                            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              RHOAI Operator (redhat-ods-operator)           ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              DataScienceCluster (default-dsc)               ││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐││
│  │  │  Dashboard  │ │ Workbenches │ │    Model Serving        │││
│  │  │             │ │  (Jupyter)  │ │  (KServe, ModelMesh)    │││
│  │  └─────────────┘ └─────────────┘ └─────────────────────────┘││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐││
│  │  │  Pipelines  │ │   Registry  │ │  Distributed Workloads  │││
│  │  │  (Kubeflow) │ │   (Models)  │ │   (Ray, Kueue, Codefl.) │││
│  │  └─────────────┘ └─────────────┘ └─────────────────────────┘││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Deploy

```bash
./steps/step-02-rhoai/deploy.sh
```

## Verification Checklist

### Operator Installation
```bash
# Check operator is installed
oc get csv -n redhat-ods-operator | grep rhods

# Check operator pod is running
oc get pods -n redhat-ods-operator
```

### DataScienceCluster Status
```bash
# Check DSC status
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'

# Should show: Ready
```

### Component Pods
```bash
# Check RHOAI application pods
oc get pods -n redhat-ods-applications

# Check monitoring pods
oc get pods -n redhat-ods-monitoring
```

### Dashboard Access
```bash
# Get dashboard route
oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}'
```

## Troubleshooting

### Operator not installing
```bash
# Check subscription status
oc get subscription rhods-operator -n redhat-ods-operator -o yaml

# Check install plan
oc get installplan -n redhat-ods-operator
```

### DataScienceCluster not ready
```bash
# Check DSC conditions
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions}' | jq .

# Check operator logs
oc logs -n redhat-ods-operator -l name=rhods-operator --tail=100
```

## Documentation Links

- [RHOAI 3.0 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [Red Hat CoP GitOps Catalog - OpenShift AI](https://github.com/redhat-cop/gitops-catalog/tree/main/openshift-ai)

## Important Notes

> **Warning**: You cannot upgrade from OpenShift AI 2.25 or any earlier version to 3.0. OpenShift AI 3.0 introduces significant technology and component changes and is intended for **new installations only**.
>
> To use OpenShift AI 3.0, install the Red Hat OpenShift AI Operator on a cluster running OpenShift Container Platform 4.19 or later and select the `fast-3.x` channel.
>
> — [Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
