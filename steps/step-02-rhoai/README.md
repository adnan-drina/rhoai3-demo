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
| **Resource Targeting** | Accelerator Profiles | **Hardware Profiles** |
| **GenAI Features** | N/A | **GenAI Studio** (Playground + Model Catalog) |
| **LLM Agents** | N/A | **`llamastackoperator`** |
| **Service Mesh** | SM 2.x | SM 3 (auto-installed by DSC) |

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
| **GenAI Studio** | Enabled | Agent Playground + Model Catalog UI |

### Model Serving

| Component | State | Purpose |
|-----------|-------|---------|
| KServe | Managed | Primary model serving (RawDeployment mode) |
| Model Registry | Managed | Model versioning and catalog |

### Distributed Workloads

| Component | State | Purpose |
|-----------|-------|---------|
| Training Operator | Managed | Kubernetes-native distributed training |
| Ray | Managed | Distributed computing framework |
| **Kueue** | **Unmanaged** | External standalone operator (step-01-gpu-and-prereq) |
| **Kueue Component** | Created | Dashboard integration for standalone Kueue |

### AI Governance & Feature Store

| Component | State | Purpose |
|-----------|-------|---------|
| TrustyAI | Managed | Model explainability, bias detection, drift monitoring |
| Feast Operator | Managed | Feature store for ML features |

---

## Hardware Profiles (Global, Queue-Based)

Hardware Profiles are **global** (in `redhat-ods-applications`) and use **Queue-based scheduling** for Kueue integration.

| Profile | Display Name | Scheduling | LocalQueue |
|---------|-------------|------------|------------|
| **cpu-small** | Small (CPU Only) | Queue | `default` |
| **default-profile** | NVIDIA L4 1GPU (Default) | Queue | `default` |
| nvidia-l4-1gpu | NVIDIA L4 1GPU | Queue | `default` |
| nvidia-l4-4gpu | NVIDIA L4 4GPUs | Queue | `default` |

### Queue-Based Scheduling Architecture

```yaml
spec:
  scheduling:
    type: Queue  # NOT Node
    kueue:
      localQueueName: default  # Must exist in user projects
```

**How It Works:**
1. **Profiles are global** - defined once in `redhat-ods-applications`
2. **Profiles reference `localQueueName: default`**
3. **Each user project** needs a `LocalQueue` named `default`
4. **Kueue handles node selection** via ClusterQueue/ResourceFlavor (step-03)

> **Note**: Profiles with `scheduling.type: Node` won't work in Kueue-managed projects.

---

## RHOAI 3.0 Resources

| Resource | Purpose |
|----------|---------|
| **Subscription** | Uses `fast-3.x` channel (required for 3.0) |
| **DSCInitialization** | Global operator configuration (Service Mesh: Managed) |
| **DataScienceCluster** | Core RHOAI components |
| **Auth** | User/Admin group management (`rhoai-admins`, `rhoai-users`) |
| **OdhDashboardConfig** | Feature toggles (GenAI Studio, Hardware Profiles) |
| **HardwareProfile** | GPU resource targeting for AWS G6 nodes |

---

## Kueue Integration (RHOAI 3.0 Architecture)

RHOAI 3.0 uses a **standalone Kueue operator** (installed in step-01-gpu-and-prereq) instead of an embedded version.

### Configuration

**DataScienceCluster (DSC):**
```yaml
spec:
  components:
    kueue:
      managementState: Unmanaged  # External standalone operator
```

**ODH Kueue Component (for Dashboard integration):**
```yaml
apiVersion: components.platform.opendatahub.io/v1alpha1
kind: Kueue
metadata:
  name: default-kueue
spec:
  managementState: Unmanaged
  defaultClusterQueueName: default
  defaultLocalQueueName: default
```

**OdhDashboardConfig:**
```yaml
spec:
  dashboardConfig:
    disableKueue: false  # Enable UI integration
    disableDistributedWorkloads: false  # Show queues in sidebar
```

### Auto-installed Dependencies

| Component | Purpose |
|-----------|---------|
| OpenShift Service Mesh 3 | Service mesh for KServe traffic management |

> **Note**: Service Mesh is configured in DSCInitialization with `serviceMesh.managementState: Managed`.

---

## Prerequisites

- [x] Step 01 completed (GPU infrastructure, Serverless, LWS, RHCL)
- [x] Cluster admin access
- [x] `oc` CLI installed and logged in
- [x] OpenShift 4.19+ (4.20 recommended)

---

## Deploy

```bash
./steps/step-02-rhoai/deploy.sh
```

The script will:
1. Verify step-01-gpu-and-prereq prerequisites (KnativeServing, etc.)
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

# List enabled components
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components}' | \
  jq -r 'to_entries | .[] | "\(.key): \(.value.managementState)"'
```

### 2. Application Pods

```bash
# Check RHOAI application pods
oc get pods -n redhat-ods-applications

# Check for key pods
oc get pods -n redhat-ods-applications | grep -E "dashboard|kserve|llama"
```

### 3. Dashboard Access

```bash
# Get RHOAI Dashboard URL
oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='https://{.spec.host}'
```

### 4. Hardware Profiles

```bash
# List available Hardware Profiles
oc get hardwareprofiles -n redhat-ods-applications

# Check profile order
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.hardwareProfileOrder}'
```

### 5. GenAI Studio

```bash
# Verify GenAI Studio is enabled
oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  -o jsonpath='{.spec.dashboardConfig.genAiStudio}'
# Expected: true
```

---

## Kustomize Structure

```
gitops/step-02-rhoai/
└── base/
    ├── kustomization.yaml
    └── rhoai-operator/
        ├── namespace.yaml                  # redhat-ods-operator namespace
        ├── operatorgroup.yaml              # Operator group
        ├── subscription.yaml               # fast-3.x channel
        ├── dsci.yaml                       # DSCInitialization (Service Mesh: Managed)
        ├── datasciencecluster.yaml         # Full 3.0 component stack (kueue: Unmanaged)
        ├── kueue-component.yaml            # ODH Kueue for Dashboard integration
        ├── auth.yaml                       # User/Admin groups
        ├── dashboard-config.yaml           # GenAI Studio + disableKueue: false
        ├── hardware-profile-cpu-small.yaml # CPU only (Queue-based)
        ├── hardware-profile-default.yaml   # Default L4 1GPU (Queue-based)
        ├── hardware-profile-l4-1gpu.yaml   # NVIDIA L4 1GPU (Queue-based)
        └── hardware-profile-l4-4gpu.yaml   # NVIDIA L4 4GPUs (Queue-based)
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
```

### GenAI Studio Not Visible

1. Verify `genAiStudio: true` in `OdhDashboardConfig`
2. Check `llamastackoperator` is `Managed` in DSC
3. Restart dashboard pod if needed:
   ```bash
   oc delete pod -n redhat-ods-applications -l app=rhods-dashboard
   ```

### Hardware Profile Not Appearing

1. Verify profiles exist: `oc get hardwareprofile -n redhat-ods-applications`
2. Check profile order in dashboard config
3. Ensure GPU nodes have matching labels:
   ```bash
   oc get nodes -l node-role.kubernetes.io/gpu -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels."node\.kubernetes\.io/instance-type"
   ```

---

## Documentation Links

### Official Red Hat Documentation
- [RHOAI 3.0 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/release_notes/index)
- [RHOAI 3.0 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [Installing RHOAI Components](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-rhoai-components)
- [Configuring Hardware Profiles](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/working_with_accelerators/index#working-with-hardware-profiles)

### Community Resources
- [RHOAI 3.0 Showroom](https://rhpds.github.io/redhat-openshift-ai-3-showroom/)
- [Red Hat CoP GitOps Catalog](https://github.com/redhat-cop/gitops-catalog/tree/main/openshift-ai)

---

## Important Notes

> **⚠️ Warning**: You cannot upgrade from OpenShift AI 2.25 or any earlier version to 3.0. OpenShift AI 3.0 introduces significant technology and component changes and is intended for **new installations only**.
>
> To use OpenShift AI 3.0, install the Red Hat OpenShift AI Operator on a cluster running OpenShift Container Platform 4.19 or later and select the `fast-3.x` channel.
>
> — [Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
