# Step 02: Red Hat OpenShift AI 3.0 (RHOAI)

Installs Red Hat OpenShift AI 3.0 operator and creates a DataScienceCluster with core components enabled.

> **Note**: RHOAI 3.0 is for **new installations only**. If you have 2.x, do not attempt to "upgrade" via the subscription channel.

## What Gets Installed

| Component | State | Purpose |
|-----------|-------|---------|
| Dashboard | Managed | RHOAI web console |
| Workbenches | Managed | Jupyter notebooks, VS Code |
| **LlamaStack Operator** | Managed | **GenAI Playground / Agentic workflows** |
| **Model Registry** | Managed | **Model Catalog registration** |
| KServe | Managed | Single-model serving (required for playground) |
| ModelMesh | Managed | Multi-model serving |
| AI Pipelines | Managed | ML pipelines (renamed from datasciencepipelines in 3.0) |
| Ray | Managed | Distributed computing |
| Kueue | Managed | Job scheduling/queuing |
| Training Operator | Managed | Distributed training jobs |
| CodeFlare | Managed | Distributed training orchestration |
| TrustyAI | Removed | Model explainability (optional) |

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

- [RHOAI Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2/html/installing_and_uninstalling_openshift_ai_self-managed/index)
- [DataScienceCluster Configuration](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2/html/installing_and_uninstalling_openshift_ai_self-managed/configuring-the-operator-and-datasciencecluster)
