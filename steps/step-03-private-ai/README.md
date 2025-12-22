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
│                                       │                                     │
│   4. MONITORING (ai-admin)            │                                     │
│   ──────────────────────────          │                                     │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                    NVIDIA DCGM Dashboard                             │  │
│   │   • GPU Utilization → Detect idle/hoarding                          │  │
│   │   • Power Usage     → Training vs. idle                              │  │
│   │   • VRAM Usage      → Model memory footprint                         │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
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

- [x] Step 01 completed (GPU infrastructure, MachineSets)
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
3. Select **Hardware Profile**: "NVIDIA L4 1GPU (Default)"
4. Click **Create**

**Behind the Scenes:**
- RHOAI creates a Notebook CR with GPU request
- Kueue intercepts via `private-ai-queue`
- ClusterQueue checks quota → Admits or Queues

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

**Setup:** The `rhoai-main-queue` has **1 GPU** quota (for g6.4xlarge flavor).

#### Option A: Apply via CLI (Recommended for Demo)

```bash
# Step 1: Apply all demo resources at once
oc apply -k gitops/step-03-private-ai/demo/

# Step 2: Watch the queuing behavior
oc get workloads -n private-ai -w

# Expected output:
# NAME                        QUEUE              ADMITTED   AGE
# pod-demo-workbench-1-xxx    private-ai-queue   True       5s   ← RUNNING
# pod-demo-workbench-2-xxx    private-ai-queue   False      3s   ← QUEUED!

# Step 3: Check pod status
oc get pods -n private-ai

# Expected output:
# NAME                  READY   STATUS            RESTARTS   AGE
# demo-workbench-1-0    1/1     Running           0          2m
# demo-workbench-2-0    0/1     SchedulingGated   0          2m   ← WAITING!

# Step 4: Release GPU by deleting workbench-1
oc delete notebook demo-workbench-1 -n private-ai

# Watch workbench-2 automatically start!
oc get pods -n private-ai -w
```

#### Option B: Apply Step-by-Step

```bash
# 1. Apply ConfigMap with demo notebooks
oc apply -f gitops/step-03-private-ai/demo/configmap-notebooks.yaml

# 2. Apply PVCs for storage
oc apply -f gitops/step-03-private-ai/demo/pvcs.yaml

# 3. Create first workbench (gets GPU)
oc apply -f gitops/step-03-private-ai/demo/workbench-1.yaml

# 4. Wait for it to start
oc wait --for=condition=ready pod/demo-workbench-1-0 -n private-ai --timeout=300s

# 5. Create second workbench (gets QUEUED!)
oc apply -f gitops/step-03-private-ai/demo/workbench-2.yaml

# 6. Observe the queuing
oc get workloads -n private-ai
```

#### Option C: Via RHOAI Dashboard

1. Login as `ai-developer` to RHOAI Dashboard
2. Go to **Data Science Projects** → **private-ai**
3. Create workbench: `demo-workbench-1` with **NVIDIA L4 1GPU** → ✅ **Running**
4. Create workbench: `demo-workbench-2` with **NVIDIA L4 1GPU** → ⏳ **Queued**

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

# Verify ai-developer has edit role
oc auth can-i --list -n private-ai --as=ai-developer | grep workloads
```

### 4. Kueue Resources

```bash
# Check all Kueue resources
oc get resourceflavors
oc get clusterqueue rhoai-main-queue
oc get localqueue -n private-ai
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
    └── workbench-2.yaml            # Second workbench (gets QUEUED)
```

> **Note**: The `demo/` folder is NOT included in ArgoCD sync.
> Apply manually with `oc apply -k gitops/step-03-private-ai/demo/` to demonstrate queuing.

> **Note**: Hardware Profiles are **global** (in step-02-rhoai).
> Each project only needs a LocalQueue named `default` to use them.

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

### Workload Stuck Pending

```bash
# Check ClusterQueue status
oc get clusterqueue rhoai-main-queue -o jsonpath='{.status}'

# Check LocalQueue events
oc describe localqueue private-ai-queue -n private-ai

# View pending workloads
oc get workloads -n private-ai
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

---

## RHOAI 3.0 Kueue Architecture

In RHOAI 3.0, Kueue has transitioned from an embedded component to a **standalone operator**.

### The Four-Part Handshake

For the Dashboard to recognize Kueue and enable Hardware Profiles:

1. **Kueue Operator**: Red Hat Build of Kueue (step-01-gpu) with `Kueue` resource named `cluster`
2. **DSC**: Set `kueue.managementState: Unmanaged` (recognizes external Kueue)
3. **ODH Kueue Component**: Created for Dashboard integration
4. **Dashboard**: Set `disableKueue: false` in `OdhDashboardConfig`

### Hardware Profile Integration

Global Hardware Profiles use Queue-based scheduling:

```yaml
# Hardware Profile (in redhat-ods-applications)
spec:
  scheduling:
    type: Queue
    kueue:
      localQueueName: default  # Must exist in user projects
```

**Each project needs a LocalQueue named `default`** to use global profiles!

### Configuration Summary

**DataScienceCluster (step-02):**
```yaml
spec:
  components:
    kueue:
      managementState: Unmanaged  # External standalone operator
```

**ODH Kueue Component (step-02):**
```yaml
apiVersion: components.platform.opendatahub.io/v1alpha1
kind: Kueue
metadata:
  name: default-kueue
spec:
  managementState: Unmanaged
  defaultLocalQueueName: default
```

**LocalQueue (this step):**
```yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: default  # MUST match localQueueName in profiles
  namespace: private-ai
spec:
  clusterQueue: default  # Or your custom ClusterQueue
```

### Verification Commands
```bash
# Check Kueue operator
oc get pods -n openshift-kueue-operator

# Check Kueue instance
oc get kueue cluster

# Check LocalQueues in project (must have 'default')
oc get localqueue -n private-ai

# Check global HardwareProfiles
oc get hardwareprofile -n redhat-ods-applications -o custom-columns=NAME:.metadata.name,TYPE:.spec.scheduling.type,QUEUE:.spec.scheduling.kueue.localQueueName

# Check workload admission
oc get workloads -n private-ai
```
