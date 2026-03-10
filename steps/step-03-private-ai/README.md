# Step 03: Private AI - GPU as a Service (GPUaaS)

Transforms RHOAI from a "static" platform to a **GPU-as-a-Service** model using Kueue integration for dynamic GPU allocation, quota enforcement, S3 storage via MinIO, and proper access control.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       Private AI - GPU as a Service                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   ┌───────────────┐       ┌───────────────┐       ┌───────────────┐            │
│   │   ai-admin    │       │ ai-developer  │       │    MinIO      │            │
│   │   (Service    │       │   (Service    │       │   (S3 Data)   │            │
│   │    Governor)  │       │   Consumer)   │       │               │            │
│   └───────┬───────┘       └───────┬───────┘       └───────┬───────┘            │
│           │                       │                       │                    │
│           ▼                       ▼                       ▼                    │
│   ┌─────────────────────────────────────────────────────────────────────┐      │
│   │                    RHOAI Dashboard (3.0)                            │      │
│   │  • Hardware Profiles  • Distributed Workloads  • Data Connections   │      │
│   └─────────────────────────────────────────────────────────────────────┘      │
│                                   │                                            │
│                                   ▼                                            │
│   ┌─────────────────────────────────────────────────────────────────────┐      │
│   │                    Kueue (Queue Management)                         │      │
│   │  LocalQueue (default) ─────▶ ClusterQueue (rhoai-main-queue)       │      │
│   └─────────────────────────────────────────────────────────────────────┘      │
│                                   │                                            │
│                                   ▼                                            │
│   ┌─────────────────────────────────────────────────────────────────────┐      │
│   │                    GPU Nodes (g6.4xlarge / g6.12xlarge)             │      │
│   │  NVIDIA L4 GPUs  •  Automatic Admission  •  Fair Queuing            │      │
│   └─────────────────────────────────────────────────────────────────────┘      │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Demo Credentials

| Username | Password | Role | RHOAI Persona | Project Access |
|----------|----------|------|---------------|----------------|
| `ai-admin` | `redhat123` | Service Governor | RHOAI Admin | `admin` in `private-ai` |
| `ai-developer` | `redhat123` | Service Consumer | RHOAI User | `edit` in `private-ai` |

> **Note**: Passwords are pre-configured in the HTPasswd secret. For production, generate new hashes.

---

## The Three Service Layers

### Layer 1: S3 Storage (MinIO)

MinIO provides the **storage backbone** for all RHOAI workloads:

| Bucket | Purpose |
|--------|---------|
| `rhoai-storage` | Default bucket for workbench data |
| `models` | Model artifacts and checkpoints |
| `pipelines` | Pipeline data and outputs |

**Data Connection**: Appears automatically in Dashboard dropdowns for:
- Workbench data sources
- Model serving endpoints
- Pipeline artifacts

### Layer 2: GPU Quota (Kueue)

Kueue provides the **fair-share scheduling** mechanism:

| Component | Name | Purpose |
|-----------|------|---------|
| ResourceFlavor | `nvidia-l4-1gpu` | Targets g6.4xlarge (1x L4) |
| ResourceFlavor | `nvidia-l4-4gpu` | Targets g6.12xlarge (4x L4) |
| ClusterQueue | `rhoai-main-queue` | Custom GPU quota pool (5 GPUs) |
| LocalQueue | `default` | Standard name → maps to `rhoai-main-queue` |

### Layer 3: Platform Governance

Automatic cost control through `OdhDashboardConfig`:

| Setting | Value | Effect |
|---------|-------|--------|
| Idle Culling | 15 min (demo setting) | Auto-stops inactive notebooks quickly |
| Default PVC | 40Gi | Standardized storage allocation |
| Kueue UI | Enabled | Queue visibility in Dashboard |

> **Why Idle Culling Matters**: Prevents "zombie" notebooks from hoarding GPUs. For this demo, we use 15 minutes to quickly release resources when not in use.

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

### MinIO Storage Provider

| Resource | Name | Namespace | Purpose |
|----------|------|-----------|---------|
| **Namespace** | `minio-storage` | - | MinIO isolation |
| **Deployment** | `minio` | `minio-storage` | S3-compatible storage |
| **Service** | `minio` | `minio-storage` | API (9000) + Console (9001) |
| **Route** | `minio-console` | `minio-storage` | Admin console access |
| **Job** | `minio-init` | `minio-storage` | Creates buckets and users |
| **PVC** | `minio-storage` | `minio-storage` | 10Gi persistent storage |

### RHOAI Data Connection

| Resource | Name | Namespace | Purpose |
|----------|------|-----------|---------|
| **Secret** | `minio-connection` | `private-ai` | S3 credentials for workloads |

> **How It Works**: The secret has labels `opendatahub.io/connection-type: s3` and `opendatahub.io/managed: "true"`, which make it appear in Dashboard dropdowns automatically.

### Authentication & Authorization

| Resource | Name | Purpose | Managed By |
|----------|------|---------|------------|
| **Secret** | `htpass-secret` | HTPasswd file for demo users | ArgoCD |
| **OAuth** | `cluster` | HTPasswd identity provider | ArgoCD |
| **Group** | `rhoai-admins` | Admin group (ai-admin) | `deploy.sh`* |
| **Group** | `rhoai-users` | User group (ai-developer) | `deploy.sh`* |
| **RoleBinding** | `ai-admin-admin` | Project admin access | ArgoCD |
| **RoleBinding** | `ai-developer-edit` | Project edit access | ArgoCD |

> \* **Note**: OpenShift Groups are created via `deploy.sh` instead of ArgoCD because ArgoCD cannot parse the `user.openshift.io/v1 Group` schema for diff calculation.

### Kueue Resources

| Resource | Name | Purpose |
|----------|------|---------|
| **ResourceFlavor** | `nvidia-l4-1gpu` | Targets g6.4xlarge nodes (1x L4) |
| **ResourceFlavor** | `nvidia-l4-4gpu` | Targets g6.12xlarge nodes (4x L4) |
| **ClusterQueue** | `rhoai-main-queue` | Main GPU quota pool (5 GPUs) for vLLM |
| **ClusterQueue** | `rhoai-llmd-queue` | Reserved GPU quota (2 GPUs) for llm-d ⭐ |
| **LocalQueue** | `default` | Standard name → maps to `rhoai-main-queue` |
| **LocalQueue** | `llmd` | llm-d workloads → maps to `rhoai-llmd-queue` ⭐ |

> **Queue Separation Strategy**:
> - The `default` LocalQueue is the standard name that Hardware Profiles expect. It maps to `rhoai-main-queue`.
> - The `llmd` LocalQueue provides a **hard reservation** of 2 GPUs for llm-d distributed inference (Step 08).
> - This ensures llm-d can always start, even when vLLM workloads saturate the main queue.
> - Global profiles reference `localQueueName: default` - this queue must exist in each project.

### Namespace

| Resource | Name | Purpose |
|----------|------|---------|
| **Namespace** | `private-ai` | GPU-managed project with Kueue labels |

---

## Prerequisites

- [x] Step 01 completed (GPU infrastructure, MachineSets, Kueue Operator)
- [x] Step 02 completed (RHOAI 3.2 with Hardware Profiles)
- [x] GPU nodes available with labels

---

## Deploy

### A) One-shot (recommended)

```bash
./steps/step-03-private-ai/deploy.sh
```

The script will:
1. Deploy MinIO storage provider (namespace, deployment, init job)
2. Deploy authentication resources (HTPasswd, OAuth, Groups)
3. Create the `private-ai` namespace with Kueue labels
4. Create RHOAI Data Connection for MinIO
5. Deploy Kueue resources (ResourceFlavors, ClusterQueue, LocalQueue)
6. Configure RBAC for ai-admin and ai-developer

### B) Step-by-step (exact commands)

For manual deployment or debugging:

```bash
# 1. Validate manifests (dry-run)
kustomize build gitops/step-03-private-ai/base | oc apply --dry-run=server -f -

# 2. Apply Argo CD Application
oc apply -f gitops/argocd/app-of-apps/step-03-private-ai.yaml

# 3. Wait for MinIO namespace and deployment
until oc get namespace minio-storage &>/dev/null; do sleep 5; done
oc rollout status deployment/minio -n minio-storage --timeout=120s

# 4. Wait for MinIO init job
oc wait --for=condition=complete job/minio-init -n minio-storage --timeout=120s

# 5. Wait for authentication resources
until oc get secret htpass-secret -n openshift-config &>/dev/null; do sleep 5; done

# 6. Create OpenShift Groups (cannot be managed by ArgoCD)
oc adm groups new rhoai-admins ai-admin 2>/dev/null || oc adm groups add-users rhoai-admins ai-admin
oc adm groups new rhoai-users ai-developer 2>/dev/null || oc adm groups add-users rhoai-users ai-developer

# 7. Wait for private-ai namespace and resources
until oc get namespace private-ai &>/dev/null; do sleep 5; done
until oc get secret minio-connection -n private-ai &>/dev/null; do sleep 5; done

# 8. Verify Kueue resources
oc get clusterqueue rhoai-main-queue
oc get localqueue default -n private-ai
```

> **Note**: For self-signed clusters, add `--insecure-skip-tls-verify=true` to `oc` commands if needed.

---

## Validation Commands

### 1. Verify S3 Provider

```bash
# Check MinIO pods
oc get pods -n minio-storage

# Expected output:
# NAME                     READY   STATUS    RESTARTS   AGE
# minio-xxxx-xxxxx         1/1     Running   0          5m

# Check MinIO init job completed
oc get job minio-init -n minio-storage

# Get MinIO console URL
oc get route minio-console -n minio-storage -o jsonpath='{.spec.host}'
```

### 2. Verify RHOAI Data Connection

```bash
# Check S3 connection secret
oc get secret -n private-ai -l opendatahub.io/connection-type=s3

# Expected output:
# NAME               TYPE     DATA   AGE
# minio-connection   Opaque   5      2m
```

### 3. Verify Kueue Status

```bash
# Check LocalQueue
oc get localqueue default -n private-ai

# Expected output:
# NAME      CLUSTERQUEUE       PENDING   ADMITTED   ...
# default   rhoai-main-queue   0         True       ...

# Check ClusterQueue
oc get clusterqueue rhoai-main-queue -o yaml | grep -A5 "status:"
```

### 4. Verify Authentication

```bash
# Test login
oc login -u ai-admin -p redhat123
oc login -u ai-developer -p redhat123

# Verify groups
oc get groups | grep rhoai
```

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
4. Select **Data Connection**: "MinIO Storage" ← **Appears automatically!**
5. Click **Create**

### 2. Login as `ai-admin` (Service Governor)

```bash
# Login via CLI
oc login -u ai-admin -p redhat123
```

**In RHOAI Dashboard:**
1. Go to **Distributed Workloads** in sidebar
2. View `rhoai-main-queue` ClusterQueue status
3. See workloads: Admitted vs. Pending

**Monitor GPU Usage:**
1. OpenShift Console → **Observe** → **Dashboards**
2. Select **NVIDIA DCGM Exporter Dashboard**
3. Track: GPU Utilization, Power Usage, VRAM

**Access MinIO Console:**
```bash
MINIO_URL=$(oc get route minio-console -n minio-storage -o jsonpath='{.spec.host}')
echo "https://${MINIO_URL}"
# Login: minio-admin / minio-secret-123
```

### 3. Demo: GPU Queuing Behavior

This demonstrates what happens when demand exceeds GPU quota.

**Setup:** Two workbenches compete for 1 GPU on the g6.4xlarge node.

#### Option A: Apply via CLI (Recommended for Demo)

```bash
# Step 1: Apply all demo resources at once
oc apply -k gitops/step-03-private-ai/gpu-as-a-service-demo/

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

RHOAI 3.2 uses **Gateway API with path-based routing**. HTTPRoutes are auto-created by RHOAI.

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
oc delete -k gitops/step-03-private-ai/gpu-as-a-service-demo/
```

**Why This Matters:**
- 🚫 No GPU hoarding - unused GPUs return to the pool
- ⏳ Fair queuing - first-come-first-served
- 📊 Quota enforcement - team/project limits respected
- 🔄 Automatic admission - queued workloads start when resources free up
- 💤 Idle culling - inactive notebooks auto-stop after 15 minutes (demo setting)

---

## Understanding Workbenches in RHOAI 3.2

A **Workbench** is RHOAI's term for a containerized development environment that provides data scientists with familiar tools like JupyterLab, VS Code, or RStudio. In RHOAI 3.2, workbenches are implemented as **Kubeflow Notebook CRs** managed by the ODH Notebook Controller.

### Workbench Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Workbench Lifecycle                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. User Creates Workbench (Dashboard or GitOps)                            │
│     ↓                                                                       │
│  2. Notebook CR Created with Hardware Profile Reference                     │
│     ↓                                                                       │
│  3. Kueue Intercepts → Evaluates Quota → Admits or Queues                  │
│     ↓                                                                       │
│  4. Pod Scheduled → kube-rbac-proxy Sidecar Injected                       │
│     ↓                                                                       │
│  5. HTTPRoute Created → Workbench Accessible via Gateway                   │
│     ↓                                                                       │
│  6. User Works → Last Activity Tracked                                      │
│     ↓                                                                       │
│  7. Idle Timeout → Notebook Controller Stops Workbench                      │
│     ↓                                                                       │
│  8. Resources Released → User Can Restart Instantly                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Workbench Concepts

| Concept | Description |
|---------|-------------|
| **Notebook CR** | Kubernetes Custom Resource (`kubeflow.org/v1/Notebook`) that defines the workbench |
| **Hardware Profile** | RHOAI resource that specifies CPU, memory, GPU, and tolerations |
| **Kueue Integration** | Workbenches are queued/admitted based on cluster quota availability |
| **kube-rbac-proxy** | Sidecar container injected for authentication (replaces OAuth proxy) |
| **Gateway API** | Path-based routing via HTTPRoute (replaces individual Routes) |
| **Idle Culling** | Automatic stopping of inactive workbenches to release resources |
| **PVC Storage** | Persistent storage for notebooks and data survives restarts |

### Idle Culling (Resource Management)

RHOAI 3.2 includes an **Idle Notebook Culler** that automatically stops workbenches after a period of inactivity. This is critical for GPU cost optimization.

| Setting | Value | Impact |
|---------|-------|--------|
| **Idle Timeout** | 15 min (demo setting) | Workbench stopped after 15 min of no kernel activity |
| **Detection Method** | Jupyter kernel activity | Last execution timestamp tracked |
| **Restart Behavior** | Instant | User clicks "Start" in Dashboard, pod recreated |
| **Data Persistence** | ✅ Preserved | PVC data survives stop/start cycles |
| **GPU Release** | ✅ Immediate | GPU returned to pool when stopped |

> **How Idle Detection Works**: The ODH Notebook Controller periodically checks the `notebooks.kubeflow.org/last-activity` annotation. When the time since last activity exceeds the platform timeout, the controller sets `kubeflow-resource-stopped: "odh-notebook-controller-lock"` and scales the pod to 0.

**Best Practices for Workbench Management:**

1. **Stop when done** - Manually stop workbenches when not actively using them
2. **Save frequently** - Ensure notebooks are saved; unsaved work persists in PVC
3. **Right-size resources** - Use CPU-only Hardware Profiles for non-GPU work
4. **Monitor queue status** - Check Kueue queues before creating GPU workbenches

---

## Workbench GitOps Configuration (RHOAI 3.2)

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

RHOAI 3.2 uses Gateway API instead of individual Routes:

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

RHOAI 3.2 uses `kube-rbac-proxy` instead of OAuth proxy:

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
│   ├── minio/                      # S3 Storage Provider
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml          # minio-storage namespace
│   │   ├── credentials-secret.yaml # MinIO root + RHOAI credentials
│   │   ├── pvc.yaml                # 10Gi persistent storage
│   │   ├── deployment.yaml         # MinIO server pod
│   │   ├── service.yaml            # API (9000) + Console (9001)
│   │   └── init-job.yaml           # Creates buckets and users
│   │
│   ├── auth/
│   │   ├── htpasswd-secret.yaml    # Demo user credentials
│   │   ├── oauth.yaml              # HTPasswd identity provider
│   │   └── groups.yaml             # NOT in ArgoCD (created by deploy.sh)
│   │
│   ├── rbac/
│   │   ├── project-admin.yaml      # ai-admin → admin role
│   │   ├── project-editor.yaml     # ai-developer → edit role
│   │   └── kueue-admin-access.yaml # Kueue ClusterRole binding
│   │
│   ├── namespace.yaml              # private-ai namespace with Kueue labels
│   ├── data-connection.yaml        # MinIO S3 connection for RHOAI
│   ├── resource-flavors.yaml       # GPU node flavors
│   ├── cluster-queue.yaml          # Cluster-wide GPU quota pool
│   └── local-queue.yaml            # LocalQueue named 'default'
│
└── demo/                           # Manual apply for demo (NOT in ArgoCD)
    ├── kustomization.yaml
    ├── configmap-notebooks.yaml    # Sample notebooks
    ├── pvcs.yaml                   # Storage for workbenches
    ├── workbench-1.yaml            # First workbench (gets GPU)
    └── workbench-2.yaml            # Second workbench (Pending)
```

> **Note**: The `demo/` folder is NOT included in ArgoCD sync.
> Apply manually with `oc apply -k gitops/step-03-private-ai/gpu-as-a-service-demo/` to demonstrate queuing.

---

## Troubleshooting

### MinIO Not Starting

```bash
# Check MinIO pod status
oc get pods -n minio-storage
oc describe pod -n minio-storage -l app=minio

# Check PVC is bound
oc get pvc -n minio-storage

# Check init job logs
oc logs job/minio-init -n minio-storage
```

### Data Connection Not Appearing in Dashboard

```bash
# Verify secret has correct labels
oc get secret minio-connection -n private-ai -o yaml | grep -A5 labels

# Required labels:
# opendatahub.io/dashboard: "true"
# opendatahub.io/managed: "true"
# Required annotation:
# opendatahub.io/connection-type: s3
```

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

RHOAI 3.2 uses Gateway API, not Routes:

```bash
# Check HTTPRoute exists
oc get httproute -n redhat-ods-applications | grep demo-workbench

# Check Gateway
oc get gateway data-science-gateway -n openshift-ingress

# Correct URL format
# https://<gateway-hostname>/notebook/<namespace>/<workbench-name>/
```

### ArgoCD Sync Error: "unable to resolve parseableType for Group"

ArgoCD cannot parse the `user.openshift.io/v1 Group` schema:

```
Failed to compare desired state to live state: failed to calculate diff:
error calculating structured merge diff: unable to resolve parseableType
for GroupVersionKind: user.openshift.io/v1, Kind=Group
```

**Solution**: Groups are excluded from ArgoCD and created by `deploy.sh`:

```bash
# deploy.sh creates groups via CLI
oc adm groups new rhoai-admins ai-admin
oc adm groups new rhoai-users ai-developer
```

This is a known ArgoCD limitation with OpenShift's `user.openshift.io` API.

---

## RHOAI 3.2 Architecture Notes

### Gateway API (Path-Based Routing)

RHOAI 3.2 replaced individual Routes with Gateway API:

| Component | Location | Purpose |
|-----------|----------|---------|
| **Gateway** | `data-science-gateway` in `openshift-ingress` | Shared ingress point |
| **HTTPRoute** | `nb-<namespace>-<name>` in `redhat-ods-applications` | Path-based routing |
| **URL Format** | `https://<gateway>/notebook/<ns>/<name>/` | Standardized access |

### Authentication (kube-rbac-proxy)

RHOAI 3.2 replaced OAuth proxy with kube-rbac-proxy:

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

### Platform Governance (OdhDashboardConfig)

```yaml
# Key settings in step-02-rhoai
spec:
  notebookController:
    pvcSize: 40Gi           # Default storage allocation
  notebookSizes:            # CPU/memory tiers
    - name: Small
    - name: Medium
    - name: Large
  dashboardConfig:
    disableKueue: false     # Enable queue UI
    disableDistributedWorkloads: false
```

---

## Rollback / Cleanup

### Remove GPU-as-a-Service Infrastructure

> **⚠️ Warning**: This will remove the private-ai project, all workbenches, MinIO storage, and user authentication. Back up any critical data before proceeding.

```bash
# 1. Delete Argo CD Application (cascades to managed resources)
oc delete application step-03-private-ai -n openshift-gitops

# 2. Delete OpenShift Groups (created by deploy.sh, not ArgoCD)
oc delete group rhoai-admins
oc delete group rhoai-users

# 3. Remove HTPasswd from OAuth (if no other users depend on it)
# Edit oauth/cluster and remove the htpasswd identity provider

# 4. Optional: Delete namespaces manually if not cleaned up
oc delete namespace private-ai
oc delete namespace minio-storage
```

### GitOps Revert (alternative)

```bash
# Remove from Git and let Argo CD prune
git revert <commit-with-step-03>
git push

# Or delete Argo CD Application with cascade
oc delete application step-03-private-ai -n openshift-gitops --cascade=foreground
```

---

## Documentation Links

### Official Red Hat Documentation
- [RHOAI 3.2 - Managing Resources](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.2/html-single/managing_resources/index)
- [RHOAI 3.2 - Using Connections](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.2/html-single/managing_resources/index#using-connections)
- [RHOAI 3.2 - Dashboard Configuration](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.2/html-single/managing_resources/index#dashboard-configuration-options_dashboard-config)
- [RHOAI 3.2 - User Management](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.2/html/managing_users/index)
- [RHOAI 3.2 - Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.2/html/working_on_data_science_projects/working-with-distributed-workloads_distributed-workloads)
- [OpenShift - Configuring HTPasswd](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/configuring-identity-providers#configuring-htpasswd-identity-provider)

### GPU Monitoring
- [NVIDIA DCGM Exporter Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/enable-gpu-monitoring-dashboard.html)

### Reference Implementation
- [rhoai-genaiops/deploy-lab](https://github.com/rhoai-genaiops/deploy-lab) - MinIO patterns

---

## Summary

| Role | User | Manages | Consumes |
|------|------|---------|----------|
| **Service Governor** | `ai-admin` | Quotas, Hardware Profiles, Monitoring | - |
| **Service Consumer** | `ai-developer` | - | Workbenches, Models, GPU Resources, S3 Storage |

**The GPU-as-a-Service Model:**
1. **Admin provisions** → MinIO storage, ClusterQueue quotas, Hardware Profiles
2. **Admin configures** → Idle culling, storage limits, queue policies
3. **Users request** → Select Hardware Profile + Data Connection in Dashboard
4. **Kueue enforces** → Admits or queues based on quota
5. **Platform governs** → Auto-stops idle notebooks, releases GPUs
6. **Admin monitors** → DCGM Dashboard for utilization, MinIO for storage
