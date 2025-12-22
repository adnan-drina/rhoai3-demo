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
| **LocalQueue** | `private-ai-queue` | Entry point for private-ai namespace |

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

### 3. Test Quota Enforcement

```bash
# As ai-developer, try to exceed quota
# Create multiple workbenches requesting GPUs

# As ai-admin, watch the queue
oc get workloads -n private-ai -w

# Expected output when quota exceeded:
# NAME                    QUEUE               ADMITTED   AGE
# notebook-jupyter-abc    private-ai-queue    True       2m
# notebook-jupyter-xyz    private-ai-queue    False      30s  # QUEUED
```

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
└── base/
    ├── kustomization.yaml
    │
    ├── auth/
    │   ├── htpasswd-secret.yaml    # Demo user credentials
    │   ├── oauth.yaml              # HTPasswd identity provider
    │   └── groups.yaml             # rhoai-admins, rhoai-users
    │
    ├── rbac/
    │   ├── project-admin.yaml      # ai-admin → admin role
    │   └── project-editor.yaml     # ai-developer → edit role
    │
    ├── namespace.yaml              # private-ai namespace
    ├── resource-flavors.yaml       # GPU node flavors
    ├── cluster-queue.yaml          # Cluster-wide quota
    └── local-queue.yaml            # Project entry point
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

## Known Limitation: Dashboard "Kueue Disabled" Warning

### The Issue
The RHOAI 3.0 Dashboard may display:
> "Kueue is disabled in this cluster"

This occurs even when Kueue is fully functional.

### Why It Happens
- RHOAI 3.0 DSC only supports `kueue.managementState: Unmanaged` or `Removed`
- The Dashboard UI expects `Managed` but this value is **not valid** in RHOAI 3.0
- The backend correctly shows `KueueReady: True` but the UI doesn't recognize `Unmanaged`

### Verification (Kueue IS Working)
```bash
# Check DSC condition - should show True
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="KueueReady")].status}'

# Check LocalQueue - should show 0 pending
oc get localqueue -n private-ai

# Test workload admission
oc get workloads -n private-ai
```

### Workaround
**Ignore the warning** - Kueue functions correctly. Create workbenches and deploy models normally.

Alternatively, change the project's "Workload allocation strategy" to "None" in project settings (loses quota management).
