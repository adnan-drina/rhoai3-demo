# Step 03: Private AI - GPU as a Service (GPUaaS)

Transforms RHOAI from a "static" platform to a **GPU-as-a-Service** model using Kueue integration for dynamic GPU allocation, quota enforcement, and proper access control.

---

## Demo Credentials

| Username | Password | Role | RHOAI Persona | Project Access |
|----------|----------|------|---------------|----------------|
| `ai-admin` | `redhat123` | Service Admin | RHOAI Admin | `admin` in `private-ai` |
| `ai-developer` | `redhat123` | Service Consumer | RHOAI User | `edit` in `private-ai` |

> **Note**: Passwords are pre-configured in the HTPasswd secret. For production, generate new hashes.

---

## Access Control Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Access Control Layers                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Layer 1: Authentication (OpenShift)                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  HTPasswd Identity Provider → ai-admin, ai-developer                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  Layer 2: RHOAI Personas (Auth Resource)                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  rhoai-admins (ai-admin)     │  rhoai-users (ai-developer)          │   │
│  │  • Manage Hardware Profiles  │  • Create Workbenches                │   │
│  │  • View ClusterQueue quotas  │  • Use GenAI Playground              │   │
│  │  • Access Distributed WL     │  • Deploy Models                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  Layer 3: Project RBAC (private-ai)                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  ai-admin: admin role        │  ai-developer: edit role             │   │
│  │  • View all workloads        │  • Create own workloads              │   │
│  │  • Manage LocalQueue         │  • Cannot modify quotas              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## GPU-as-a-Service Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          GPU Request Flow                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   1. USER REQUEST              2. KUEUE ADMISSION           3. EXECUTION   │
│   ─────────────────────────────────────────────────────────────────────     │
│                                                                             │
│   ┌─────────────────┐         ┌─────────────────┐         ┌─────────────┐  │
│   │  ai-developer   │────────▶│  LocalQueue     │────────▶│  GPU Pod    │  │
│   │  selects L4     │         │  (private-ai)   │         │  Running    │  │
│   │  Hardware       │         │                 │         │             │  │
│   │  Profile        │         │  ┌───────────┐  │         │  ┌───────┐  │  │
│   │                 │         │  │ Check     │  │         │  │ L4    │  │  │
│   │  ┌───────────┐  │         │  │ Cluster   │  │         │  │ GPU   │  │  │
│   │  │ Workbench │  │         │  │ Queue     │  │         │  │       │  │  │
│   │  │ Create    │  │         │  │ Quota     │  │         │  └───────┘  │  │
│   │  └───────────┘  │         │  └───────────┘  │         │             │  │
│   └─────────────────┘         └─────────────────┘         └─────────────┘  │
│                                       │                                     │
│                                       ▼                                     │
│                               ┌─────────────────┐                          │
│                               │  QUOTA FULL?    │                          │
│                               │                 │                          │
│                               │  YES: Queue     │                          │
│                               │       (Pending) │                          │
│                               │                 │                          │
│                               │  NO: Admit      │                          │
│                               │      (Running)  │                          │
│                               └─────────────────┘                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## What Gets Installed

### Authentication & Authorization

| Resource | Name | Purpose |
|----------|------|---------|
| **Secret** | `htpass-secret` | HTPasswd file for demo users |
| **OAuth** | `cluster` | HTPasswd identity provider |
| **Group** | `rhoai-admins` | Admin group (ai-admin) |
| **Group** | `rhoai-users` | User group (ai-developer) |
| **RoleBinding** | `ai-admin-admin` | Project admin access |
| **RoleBinding** | `ai-developer-edit` | Project edit access |

### Kueue Resources

| Resource | Name | Purpose |
|----------|------|---------|
| **ResourceFlavor** | `nvidia-l4-1gpu` | Targets g6.4xlarge nodes (1x L4) |
| **ResourceFlavor** | `nvidia-l4-4gpu` | Targets g6.12xlarge nodes (4x L4) |
| **ClusterQueue** | `rhoai-main-queue` | Cluster-wide GPU quota pool |
| **LocalQueue** | `default` | **Standard name** - matches global HardwareProfiles |
| **LocalQueue** | `private-ai-queue` | Alternative queue pointing to rhoai-main-queue |

> **Important**: The `default` LocalQueue is **required** for global Hardware Profiles to work.
> Global profiles reference `localQueueName: default` - this queue must exist in each project.

### Namespace

| Resource | Name | Purpose |
|----------|------|---------|
| **Namespace** | `private-ai` | GPU-managed project with Kueue labels |

---

## Prerequisites

- [x] Step 01 completed (GPU infrastructure, MachineSets, Kueue Operator)
- [x] Step 02 completed (RHOAI 3.0 with Hardware Profiles)
- [x] GPU nodes available with labels

---

## Deploy

```bash
./steps/step-03-private-ai/deploy.sh
```

The script will:
1. Deploy authentication resources (HTPasswd, OAuth, Groups)
2. Create the `private-ai` namespace with Kueue labels
3. Deploy Kueue resources (ResourceFlavors, ClusterQueue, LocalQueue)
4. Configure RBAC for ai-admin and ai-developer

---

## Demo Walkthrough

### 1. Login as `ai-developer` (Service Consumer)

```bash
# Login via CLI
oc login -u ai-developer -p redhat123

# Or use the OpenShift Console
# Navigate to: https://<console-url>
```

**In RHOAI Dashboard:**
1. Go to **Data Science Projects** → **private-ai**
2. Create a new **Workbench**
3. Select **Hardware Profile**: "NVIDIA L4 1GPU"
4. Click **Create**

### 2. Login as `ai-admin` (Service Administrator)

```bash
# Login via CLI
oc login -u ai-admin -p redhat123
```

**In RHOAI Dashboard:**
1. Go to **Distributed Workloads** in sidebar
2. View `rhoai-main-queue` status
3. See workloads: Admitted vs. Pending

**Monitor GPU Usage:**
1. OpenShift Console → **Observe** → **Dashboards**
2. Select **NVIDIA DCGM Exporter Dashboard**
3. Track: GPU Utilization, Power Usage, VRAM

### 3. Demo: GPU Queuing Behavior

This demonstrates what happens when demand exceeds GPU quota.

**Setup:** Two workbenches compete for 1 GPU on the g6.4xlarge node.

#### Option A: Apply via CLI (Recommended for Demo)

```bash
# Step 1: Apply all demo resources at once
oc apply -k gitops/step-03-private-ai/demo/

# Step 2: Watch the queuing behavior
oc get workloads -n private-ai -w

# Expected output:
# NAME                        QUEUE     ADMITTED   AGE
# pod-demo-workbench-1-xxx    default   True       5s   ← RUNNING
# pod-demo-workbench-2-xxx    default   True       3s   ← QUEUED (scheduler)

# Step 3: Check pod status
oc get pods -n private-ai

# Expected output:
# NAME                  READY   STATUS            RESTARTS   AGE
# demo-workbench-1-0    2/2     Running           0          2m   ← Got GPU!
# demo-workbench-2-0    0/2     Pending           0          2m   ← Waiting!

# Step 4: Access the workbench
GATEWAY=$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')
echo "https://${GATEWAY}/notebook/private-ai/demo-workbench-1/"

# Step 5: Release GPU by deleting workbench-1
oc delete notebook demo-workbench-1 -n private-ai

# Watch workbench-2 automatically start!
oc get pods -n private-ai -w
```

#### Option B: Via RHOAI Dashboard

1. Login as `ai-developer` to RHOAI Dashboard
2. Go to **Data Science Projects** → **private-ai**
3. Create workbench: `demo-workbench-1` with **NVIDIA L4 1GPU** → ✅ **Running**
4. Create workbench: `demo-workbench-2` with **NVIDIA L4 1GPU** → ⏳ **Pending**

#### Access the Workbenches

RHOAI 3.0 uses **Gateway API with path-based routing**. HTTPRoutes are auto-created by RHOAI.

```bash
# Get the Gateway hostname
GATEWAY=$(oc get gateway data-science-gateway -n openshift-ingress \
  -o jsonpath='{.spec.listeners[0].hostname}')

# Workbench URLs follow this pattern:
# https://<gateway>/notebook/<namespace>/<workbench-name>/

echo "Workbench 1: https://${GATEWAY}/notebook/private-ai/demo-workbench-1/"
echo "Workbench 2: https://${GATEWAY}/notebook/private-ai/demo-workbench-2/"

# Open workbench-1 in browser
open "https://${GATEWAY}/notebook/private-ai/demo-workbench-1/"
```

#### Demo Cleanup

```bash
# Remove demo workbenches
oc delete -k gitops/step-03-private-ai/demo/
```

**Why This Matters:**
- 🚫 No GPU hoarding - unused GPUs return to the pool
- ⏳ Fair queuing - first-come-first-served
- 📊 Quota enforcement - team/project limits respected
- 🔄 Automatic admission - queued workloads start when resources free up

---

## Workbench Configuration (RHOAI 3.0)

When creating workbenches via GitOps (not Dashboard), the following configurations are **required**:

### Key Annotations

| Annotation | Value | Purpose |
|------------|-------|---------|
| `notebooks.opendatahub.io/inject-auth` | `"true"` | Injects kube-rbac-proxy sidecar for authentication |
| `opendatahub.io/hardware-profile-name` | `"nvidia-l4-1gpu"` | References Hardware Profile |
| `opendatahub.io/hardware-profile-namespace` | `"redhat-ods-applications"` | Hardware Profile location |
| `notebooks.opendatahub.io/last-image-selection` | `"pytorch:2025.2"` | Image selection |
| `notebooks.opendatahub.io/last-image-version-git-commit-selection` | `"8e73cac"` | **Prevents "deprecated" warning** |
| `opendatahub.io/image-display-name` | `"Jupyter \| PyTorch \| CUDA \| Python 3.12"` | Display name in Dashboard |
| `opendatahub.io/workbench-image-namespace` | `""` | Image namespace tracking |

> **Important**: The `last-image-version-git-commit-selection` must match the ImageStream's `notebook-build-commit` annotation to avoid "Notebook image deprecated" warning.

### Required Labels

| Label | Value | Purpose |
|-------|-------|---------|
| `opendatahub.io/dashboard` | `"true"` | Shows in Dashboard |
| `opendatahub.io/odh-managed` | `"true"` | RHOAI manages lifecycle |
| `kueue.x-k8s.io/queue-name` | `"default"` | Kueue queue assignment |

### Tolerations for GPU Nodes

GPU nodes have taints that must be tolerated:

```yaml
tolerations:
  - key: nvidia.com/gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
```

### Node Selector

Target specific GPU instance types:

```yaml
nodeSelector:
  node.kubernetes.io/instance-type: g6.4xlarge  # Single L4 GPU
```

### Path-Based Routing (Gateway API)

RHOAI 3.0 uses Gateway API instead of individual Routes:

```yaml
env:
  - name: NOTEBOOK_ARGS
    value: |-
      --ServerApp.port=8888
      --ServerApp.token=''
      --ServerApp.password=''
      --ServerApp.base_url=/notebook/private-ai/demo-workbench-1
      --ServerApp.quit_button=False
```

Probes must use the base_url path:

```yaml
livenessProbe:
  httpGet:
    path: /notebook/private-ai/demo-workbench-1/api
    port: notebook-port
readinessProbe:
  httpGet:
    path: /notebook/private-ai/demo-workbench-1/api
    port: notebook-port
```

### Authentication Sidecar

RHOAI 3.0 uses `kube-rbac-proxy` instead of OAuth proxy:

```
┌─────────────────────────────────────────────────────────────────┐
│  Pod: demo-workbench-1-0                                        │
├─────────────────────────────────────────────────────────────────┤
│  Container 1: demo-workbench-1 (Jupyter on port 8888)          │
│  Container 2: kube-rbac-proxy (Auth on port 8443)              │
└─────────────────────────────────────────────────────────────────┘
                              ↑
                    HTTPRoute points here
                    (port 8443 via Gateway API)
```

---

## Kustomize Structure

```
gitops/step-03-private-ai/
├── base/                           # Auto-deployed by ArgoCD
│   ├── kustomization.yaml
│   │
│   ├── auth/
│   │   ├── htpasswd-secret.yaml    # Demo user credentials
│   │   ├── oauth.yaml              # HTPasswd identity provider
│   │   └── groups.yaml             # rhoai-admins, rhoai-users
│   │
│   ├── rbac/
│   │   ├── project-admin.yaml      # ai-admin → admin role
│   │   ├── project-editor.yaml     # ai-developer → edit role
│   │   └── kueue-admin-access.yaml # Kueue ClusterRole binding
│   │
│   ├── namespace.yaml              # private-ai namespace with Kueue labels
│   ├── resource-flavors.yaml       # GPU node flavors (g6.4xlarge, g6.12xlarge)
│   ├── cluster-queue.yaml          # Cluster-wide GPU quota pool
│   └── local-queue.yaml            # LocalQueue named 'default' (required!)
│
└── demo/                           # Manual apply for demo (NOT in ArgoCD)
    ├── kustomization.yaml
    ├── configmap-notebooks.yaml    # Sample notebooks (gpu-test.py, gpu-demo.ipynb)
    ├── pvcs.yaml                   # Storage for workbenches
    ├── workbench-1.yaml            # First workbench (gets GPU)
    └── workbench-2.yaml            # Second workbench (Pending - waiting for GPU)
```

> **Note**: The `demo/` folder is NOT included in ArgoCD sync.
> Apply manually with `oc apply -k gitops/step-03-private-ai/demo/` to demonstrate queuing.

---

## Verification Checklist

### 1. Authentication

```bash
# Verify OAuth configuration
oc get oauth cluster -o yaml

# Test login
oc login -u ai-admin -p redhat123
oc login -u ai-developer -p redhat123
```

### 2. Groups

```bash
# List groups
oc get groups

# Verify group membership
oc get group rhoai-admins -o jsonpath='{.users}'
oc get group rhoai-users -o jsonpath='{.users}'
```

### 3. Project RBAC

```bash
# Check rolebindings in private-ai
oc get rolebindings -n private-ai

# Verify ai-admin has admin role
oc auth can-i --list -n private-ai --as=ai-admin | grep -E "create|delete"
```

### 4. Kueue Resources

```bash
# Check all Kueue resources
oc get resourceflavors
oc get clusterqueue rhoai-main-queue
oc get localqueue -n private-ai
```

### 5. Demo Workbenches

```bash
# Apply demo
oc apply -k gitops/step-03-private-ai/demo/

# Check pods (one Running, one Pending)
oc get pods -n private-ai

# Check workloads
oc get workloads -n private-ai

# Get workbench URL
GATEWAY=$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')
echo "https://${GATEWAY}/notebook/private-ai/demo-workbench-1/"
```

---

## Troubleshooting

### Login Fails

```bash
# Check OAuth pods
oc get pods -n openshift-authentication

# Verify HTPasswd secret
oc get secret htpass-secret -n openshift-config

# Check OAuth configuration
oc describe oauth cluster
```

### User Can't Access Project

```bash
# Verify rolebinding exists
oc get rolebinding -n private-ai

# Check user's effective permissions
oc auth can-i --list -n private-ai --as=ai-developer
```

### Workbench FailedScheduling (Untolerated Taint)

GPU nodes have taints. Workbenches need tolerations:

```bash
# Check GPU node taints
oc get nodes -l nvidia.com/gpu.present=true -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# Verify workbench has tolerations
oc get notebook demo-workbench-1 -n private-ai -o jsonpath='{.spec.template.spec.tolerations}'
```

**Fix:** Add tolerations to workbench spec:
```yaml
tolerations:
  - key: nvidia.com/gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
```

### "Notebook image deprecated" Warning

The Dashboard checks `last-image-version-git-commit-selection` annotation:

```bash
# Get ImageStream git commit
oc get imagestream pytorch -n redhat-ods-applications -o json | \
  jq '.spec.tags[] | select(.name == "2025.2") | .annotations["opendatahub.io/notebook-build-commit"]'

# Patch workbench with correct commit
oc patch notebook demo-workbench-1 -n private-ai --type=merge -p \
  '{"metadata":{"annotations":{"notebooks.opendatahub.io/last-image-version-git-commit-selection":"8e73cac"}}}'
```

### Workbench Route Not Working

RHOAI 3.0 uses Gateway API, not Routes:

```bash
# Check HTTPRoute exists
oc get httproute -n redhat-ods-applications | grep demo-workbench

# Check Gateway
oc get gateway data-science-gateway -n openshift-ingress

# Correct URL format
# https://<gateway-hostname>/notebook/<namespace>/<workbench-name>/
```

---

## RHOAI 3.0 Architecture Notes

### Gateway API (Path-Based Routing)

RHOAI 3.0 replaced individual Routes with Gateway API:

| Component | Location | Purpose |
|-----------|----------|---------|
| **Gateway** | `data-science-gateway` in `openshift-ingress` | Shared ingress point |
| **HTTPRoute** | `nb-<namespace>-<name>` in `redhat-ods-applications` | Path-based routing |
| **URL Format** | `https://<gateway>/notebook/<ns>/<name>/` | Standardized access |

### Authentication (kube-rbac-proxy)

RHOAI 3.0 replaced OAuth proxy with kube-rbac-proxy:

| Annotation | Old (2.x) | New (3.0) |
|------------|-----------|-----------|
| Auth trigger | `inject-oauth: "true"` | `inject-auth: "true"` |
| Sidecar | oauth-proxy | kube-rbac-proxy |
| HTTPRoute target | port 8888 | port 8443 |

### Hardware Profile Integration

```yaml
# Hardware Profile (in redhat-ods-applications)
spec:
  scheduling:
    type: Queue
    kueue:
      localQueueName: default  # Must exist in user projects

# Workbench references profile via annotations
annotations:
  opendatahub.io/hardware-profile-name: "nvidia-l4-1gpu"
  opendatahub.io/hardware-profile-namespace: "redhat-ods-applications"
```

---

## Documentation Links

### Official Red Hat Documentation
- [RHOAI 3.0 - User Management](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/managing_users/index)
- [RHOAI 3.0 - Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/working_on_data_science_projects/working-with-distributed-workloads_distributed-workloads)
- [OpenShift - Configuring HTPasswd](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/configuring-identity-providers#configuring-htpasswd-identity-provider)

### GPU Monitoring
- [NVIDIA DCGM Exporter Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/enable-gpu-monitoring-dashboard.html)

---

## Summary

| Role | User | Manages | Consumes |
|------|------|---------|----------|
| **Service Admin** | `ai-admin` | Quotas, Hardware Profiles, Monitoring | - |
| **Service Consumer** | `ai-developer` | - | Workbenches, Models, GPU Resources |

**The Service Model:**
1. **Admin defines** → ClusterQueue quotas, Hardware Profiles
2. **Users request** → Select Hardware Profile in Dashboard
3. **Kueue enforces** → Admits or queues based on quota
4. **Admin monitors** → DCGM Dashboard for utilization
