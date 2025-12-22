# Step 02: Red Hat OpenShift AI 3.0 Platform

Installs the **RHOAI 3.0 Platform Layer**, transitioning from the infrastructure layer (GPUs/Operators) to the AI Platform with GenAI Studio, Hardware Profiles, and full component stack.

> **⚠️ Important**: RHOAI 3.0 is for **new installations only**. You cannot upgrade from 2.x. See the [Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/release_notes/index) for details.

---

## What's New in RHOAI 3.0

### Key Changes from 2.x

| Change | 2.x | 3.0 |
|--------|-----|-----|
| **Component Naming** | `datasciencepipelines` | `aipipelines` |
| **User/Admin Groups** | `OdhDashboardConfig` | **`Auth` resource** |
| **Resource Targeting** | Accelerator Profiles | **Hardware Profiles** (Tech Preview) |
| **GenAI Features** | N/A | **GenAI Studio** (Playground + Model Catalog) |
| **Distributed Inference** | N/A | **`distributedinference`** (llm-d) |
| **LLM Agents** | N/A | **`llamastackoperator`** |

---

## What Gets Installed

### Core Platform Components

| Component | State | Purpose |
|-----------|-------|---------|
| Dashboard | Managed | RHOAI web console |
| Workbenches | Managed | Jupyter notebooks, VS Code, RStudio |
| AI Pipelines | Managed | ML Pipelines (formerly `datasciencepipelines`) |

### Generative AI Stack (New in 3.0)

| Component | State | Purpose |
|-----------|-------|---------|
| **LlamaStack Operator** | Managed | GenAI Playground, Agentic workflows |
| **Distributed Inference** | Managed | llm-d multi-node LLM serving |
| **GenAI Studio** | Enabled | Agent Playground + Model Catalog UI |

### Model Serving

| Component | State | Purpose |
|-----------|-------|---------|
| KServe | Managed | Primary model serving (RawDeployment mode) |
| ModelMesh | Managed | Multi-model serving for smaller models |
| Model Registry | Managed | Model versioning and catalog |

### Distributed Workloads

| Component | State | Purpose |
|-----------|-------|---------|
| Training Operator | Managed | Kubernetes-native distributed training |
| Ray | Managed | Distributed computing framework |
| Kueue | Managed | Workload queuing and scheduling |
| CodeFlare | Managed | Simplifies distributed computing on Ray |

### AI Governance

| Component | State | Purpose |
|-----------|-------|---------|
| TrustyAI | Managed | Model explainability, bias detection, drift monitoring |

---

## RHOAI 3.0 Resources

| Resource | Purpose |
|----------|---------|
| **Subscription** | Uses `fast-3.x` channel (required for 3.0) |
| **DSCInitialization** | Global operator configuration |
| **DataScienceCluster** | Core RHOAI components |
| **Auth** | **New in 3.0** - User/Admin group management |
| **OdhDashboardConfig** | Feature toggles (GenAI Studio, Hardware Profiles) |
| **HardwareProfile** | **New in 3.0** - GPU resource targeting (replaces Accelerator Profiles) |

---

## Key 3.0 Concepts Explained

### 1. Auth Resource (Replaces Dashboard Group Config)

In RHOAI 3.0, user and admin group management moved from `OdhDashboardConfig` to a dedicated **`Auth`** resource:

```yaml
apiVersion: services.platform.opendatahub.io/v1alpha1
kind: Auth
metadata:
  name: auth
  namespace: redhat-ods-applications
spec:
  adminGroups:
    - rhoai-admins
    - cluster-admins
  allowedGroups:
    - rhoai-users
    - system:authenticated
```

**Why the change?** Separates authentication/authorization concerns from dashboard configuration, enabling better RBAC integration.

### 2. GenAI Studio

GenAI Studio is the RHOAI 3.0 unified interface for generative AI capabilities:

- **Agent Playground** - Interactive LLM testing and prompt engineering
- **Model Catalog** - Browse and deploy pre-configured LLM models

**Requirements:**
1. `llamastackoperator: Managed` in DataScienceCluster
2. `distributedinference: Managed` in DataScienceCluster
3. `genAiStudio: true` in OdhDashboardConfig

### 3. Hardware Profiles (Replaces Accelerator Profiles)

Hardware Profiles are the 3.0 successor to Accelerator Profiles, providing:
- Better node targeting via `nodeSelector`
- Proper GPU taint tolerations
- Resource limits (min/max GPU counts)

```yaml
apiVersion: dashboard.opendatahub.io/v1alpha1
kind: HardwareProfile
metadata:
  name: aws-g6-gpu
spec:
  displayName: "AWS G6 - NVIDIA L4 GPU"
  nodeSelector:
    node-role.kubernetes.io/gpu: ""
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  identifiers:
    - displayName: "NVIDIA L4 GPU"
      identifier: nvidia.com/gpu
      minCount: 1
      maxCount: 4
```

**Dashboard Settings:**
```yaml
disableHardwareProfiles: false   # Enable new 3.0 UI
disableAcceleratorProfiles: true  # Disable legacy UI
```

### 4. aipipelines (Renamed from datasciencepipelines)

The ML Pipelines component was renamed in 3.0:
- **2.x**: `datasciencepipelines`
- **3.0**: `aipipelines`

This aligns with the broader AI Platform branding.

---

## Auto-installed Dependencies

The following operators are **automatically installed** by the DataScienceCluster CR:

| Component | Purpose |
|-----------|---------|
| OpenShift Service Mesh 3 | Service mesh for KServe traffic management |
| Kueue | Workload queuing for distributed training |

> **Note**: Service Mesh is managed by the DSC when `kserve.managementState: Managed`.

---

## Prerequisites

- [ ] Step 01 completed (GPU infrastructure, Serverless, LWS, RHCL)
- [ ] Cluster admin access
- [ ] `oc` CLI installed and logged in
- [ ] OpenShift 4.19+ (4.20 recommended)

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         OpenShift Cluster                                  │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                 RHOAI Operator (redhat-ods-operator)                 │ │
│  │                    Subscription: fast-3.x                             │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                    │                                       │
│           ┌────────────────────────┼────────────────────────┐             │
│           ▼                        ▼                        ▼             │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐       │
│  │ DSCInitialization│    │ DataScienceCluster│    │      Auth       │       │
│  │  (default-dsci)  │    │   (default-dsc)   │    │  (User Groups)  │       │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘       │
│                                    │                                       │
│  ┌─────────────────────────────────┼─────────────────────────────────────┐│
│  │                    redhat-ods-applications                            ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────────┐ ││
│  │  │   Dashboard   │  │  Workbenches  │  │      GenAI Studio         │ ││
│  │  │               │  │   (Jupyter)   │  │  (Playground + Catalog)   │ ││
│  │  └───────────────┘  └───────────────┘  └───────────────────────────┘ ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────────┐ ││
│  │  │    KServe     │  │   ModelMesh   │  │      Model Registry       │ ││
│  │  │ (RawDeployment│  │ (Multi-model) │  │   (Versioning/Catalog)    │ ││
│  │  └───────────────┘  └───────────────┘  └───────────────────────────┘ ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────────┐ ││
│  │  │  AI Pipelines │  │     Ray +     │  │  Distributed Inference    │ ││
│  │  │   (Kubeflow)  │  │   CodeFlare   │  │       (llm-d)             │ ││
│  │  └───────────────┘  └───────────────┘  └───────────────────────────┘ ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Deploy

```bash
./steps/step-02-rhoai/deploy.sh
```

The script will:
1. Verify step-01-gpu prerequisites
2. Create Argo CD Application for RHOAI
3. Wait for operator installation
4. Verify DataScienceCluster is ready

---

## Verification Checklist

### 1. DataScienceCluster Status

```bash
# Check DSC is Ready
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'
# Expected: Ready

# Check all component conditions
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions}' | jq .
```

### 2. Application Pods

```bash
# Check RHOAI application pods
oc get pods -n redhat-ods-applications

# Expected: dashboard, workbenches, kserve-controller, model-controller, etc.
```

### 3. Dashboard Access

```bash
# Get RHOAI Dashboard URL
oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='https://{.spec.host}'
```

### 4. Auth Configuration

```bash
# Check Auth resource
oc get auth -n redhat-ods-applications

# Verify admin groups
oc get auth auth -n redhat-ods-applications -o jsonpath='{.spec.adminGroups}'
```

### 5. Hardware Profiles

```bash
# List available Hardware Profiles
oc get hardwareprofiles -n redhat-ods-applications

# Verify AWS G6 profile
oc get hardwareprofile aws-g6-gpu -n redhat-ods-applications -o yaml
```

### 6. GenAI Studio

```bash
# Verify OdhDashboardConfig has GenAI enabled
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.genAiStudio}'
# Expected: true

# Check LlamaStack Operator pods
oc get pods -n redhat-ods-applications -l app=llama-stack-operator
```

---

## Kustomize Structure

```
gitops/step-02-rhoai/
└── base/
    ├── kustomization.yaml
    └── rhoai-operator/
        ├── namespace.yaml              # redhat-ods-operator namespace
        ├── operatorgroup.yaml          # Operator group
        ├── subscription.yaml           # fast-3.x channel
        ├── dsci.yaml                   # DSCInitialization
        ├── datasciencecluster.yaml     # Full 3.0 component stack
        ├── auth.yaml                   # NEW: User/Admin groups
        ├── dashboard-config.yaml       # GenAI Studio + Hardware Profiles
        └── hardware-profile-g6.yaml    # NEW: AWS G6 GPU profile
```

---

## Troubleshooting

### Operator Not Installing

```bash
# Check subscription status
oc get subscription rhods-operator -n redhat-ods-operator -o yaml

# Check install plan
oc get installplan -n redhat-ods-operator

# Verify fast-3.x channel is available
oc get packagemanifest rhods-operator -o jsonpath='{.status.channels[*].name}'
```

### DataScienceCluster Not Ready

```bash
# Check DSC conditions
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions}' | jq .

# Check operator logs
oc logs -n redhat-ods-operator -l name=rhods-operator --tail=100

# Check for missing CRDs
oc get crd | grep -E "datasciencecluster|dscinitialization|auth"
```

### GenAI Studio Not Visible

1. Verify `genAiStudio: true` in `OdhDashboardConfig`
2. Check `llamastackoperator` is `Managed` in DSC
3. Restart dashboard pod if needed:
   ```bash
   oc delete pod -n redhat-ods-applications -l app=odh-dashboard
   ```

### Hardware Profile Not Working

1. Verify profile is enabled: `disableHardwareProfiles: false`
2. Check profile exists: `oc get hardwareprofile -n redhat-ods-applications`
3. Ensure GPU nodes have matching labels: `node-role.kubernetes.io/gpu=""`

---

## Documentation Links

### Official Red Hat Documentation
- [RHOAI 3.0 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/release_notes/index)
- [RHOAI 3.0 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [Installing RHOAI Components](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-rhoai-components)
- [Configuring Hardware Profiles](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/working_with_accelerators/index#working-with-hardware-profiles)

### Community Resources
- [AI on OpenShift - RHOAI Configuration](https://ai-on-openshift.io/tools/rhoai-configuration/)
- [Red Hat CoP GitOps Catalog](https://github.com/redhat-cop/gitops-catalog/tree/main/openshift-ai)

---

## Important Notes

> **⚠️ Warning**: You cannot upgrade from OpenShift AI 2.25 or any earlier version to 3.0. OpenShift AI 3.0 introduces significant technology and component changes and is intended for **new installations only**.
>
> To use OpenShift AI 3.0, install the Red Hat OpenShift AI Operator on a cluster running OpenShift Container Platform 4.19 or later and select the `fast-3.x` channel.
>
> — [Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
