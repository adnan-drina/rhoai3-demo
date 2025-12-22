# Step 03: Private AI - GPU as a Service (GPUaaS)

Transforms RHOAI from a "static" platform to a **GPU-as-a-Service** model using Kueue integration for dynamic GPU allocation and quota enforcement.

---

## The Service Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          GPU-as-a-Service Flow                              │
│                                                                             │
│   User Request         Kueue Admission         RHOAI Execution              │
│   ───────────────────────────────────────────────────────────────────────   │
│                                                                             │
│   ┌─────────────┐     ┌─────────────────┐     ┌─────────────────────┐      │
│   │  User picks │────▶│  Kueue checks   │────▶│  Workload starts    │      │
│   │  Hardware   │     │  ClusterQueue   │     │  on GPU node        │      │
│   │  Profile    │     │  quota          │     │                     │      │
│   └─────────────┘     └─────────────────┘     └─────────────────────┘      │
│         │                     │                        │                    │
│         │                     ▼                        │                    │
│         │              ┌─────────────────┐             │                    │
│         │              │  If quota full: │             │                    │
│         │              │  Queue workload │             │                    │
│         │              │  (Pending)      │             │                    │
│         │              └─────────────────┘             │                    │
│         │                     │                        │                    │
│         │                     ▼                        │                    │
│         │              ┌─────────────────┐             │                    │
│         │              │  When GPU freed:│             │                    │
│         │              │  Auto-admit     │◀────────────┘                    │
│         │              │  next workload  │                                  │
│         │              └─────────────────┘                                  │
│         │                                                                   │
│         ▼                                                                   │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                    NVIDIA DCGM Dashboard                             │  │
│   │   • GPU Utilization (detect idle/hoarding)                          │  │
│   │   • Power Usage (training vs. idle)                                  │  │
│   │   • VRAM Usage (model memory footprint)                              │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

**The Flow:**
1. **Users Request** → Select Hardware Profile in RHOAI Dashboard
2. **Kueue Admits** → Checks quota, queues if full, admits when available
3. **RHOAI Executes** → Workload runs on GPU node

---

## What Gets Installed

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

## Architecture

### Layer 1: ResourceFlavors (Infrastructure)

Defines the "flavors" of GPUs available, mapping to physical node types.

```yaml
# nvidia-l4-1gpu → g6.4xlarge
nodeLabels:
  node.kubernetes.io/instance-type: g6.4xlarge
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```

### Layer 2: ClusterQueue (Quota)

Cluster-wide resource pool governing total GPU/CPU/Memory allocation.

```yaml
# rhoai-main-queue
resourceGroups:
  - flavors:
      - name: nvidia-l4-1gpu
        resources:
          - name: "nvidia.com/gpu"
            nominalQuota: 1      # 1 GPU from g6.4xlarge
      - name: nvidia-l4-4gpu
        resources:
          - name: "nvidia.com/gpu"
            nominalQuota: 4      # 4 GPUs from g6.12xlarge
```

### Layer 3: LocalQueue (Project Access)

Entry point for the `private-ai` project - what users "see" in the UI.

```yaml
# private-ai-queue → points to rhoai-main-queue
spec:
  clusterQueue: rhoai-main-queue
```

---

## Prerequisites

- [x] Step 01 completed (GPU infrastructure, MachineSets)
- [x] Step 02 completed (RHOAI 3.0 with Hardware Profiles)
- [x] GPU nodes available with labels:
  - `node-role.kubernetes.io/gpu: ""`
  - `node.kubernetes.io/instance-type: g6.4xlarge` or `g6.12xlarge`

---

## Deploy

```bash
./steps/step-03-private-ai/deploy.sh
```

The script will:
1. Create Argo CD Application for private-ai
2. Deploy Kueue ResourceFlavors, ClusterQueue, LocalQueue
3. Create the `private-ai` namespace with proper labels

---

## Verification Checklist

### 1. Namespace Status

```bash
# Verify namespace exists with Kueue labels
oc get namespace private-ai --show-labels
```

### 2. ResourceFlavors

```bash
# List GPU flavors
oc get resourceflavors

# Verify flavor details
oc get resourceflavor nvidia-l4-1gpu -o yaml
```

### 3. ClusterQueue Status

```bash
# Check queue status and quota usage
oc get clusterqueue rhoai-main-queue -o yaml

# View pending/admitted workloads
oc get clusterqueue rhoai-main-queue -o jsonpath='{.status}'
```

### 4. LocalQueue Status

```bash
# Check local queue in private-ai namespace
oc get localqueue -n private-ai

# View queue details
oc get localqueue private-ai-queue -n private-ai -o yaml
```

### 5. End-to-End Test

```bash
# Create a test workbench in private-ai namespace via RHOAI Dashboard
# Select "NVIDIA L4 1GPU" Hardware Profile
# Watch the queue admission:
oc get workloads -n private-ai -w
```

---

## GPU Utilization Monitoring (DCGM Dashboard)

Track GPU usage to detect idle resources and "GPU hoarding."

### Accessing the Dashboard

1. Navigate to **Observe → Dashboards** in OpenShift Console
2. Select **NVIDIA DCGM Exporter Dashboard**

### Key Metrics to Monitor

| Metric | What It Shows | Demo Use Case |
|--------|---------------|---------------|
| **GPU Utilization** | % of GPU compute used | 0% = idle/hoarding |
| **GPU Power Usage** | Watts consumed | High = training, Low = idle |
| **Framebuffer Memory** | VRAM usage | Track LLM memory footprint |
| **SM Occupancy** | Streaming multiprocessor usage | Model inference load |

### Identifying GPU Hoarding

```bash
# Find pods using GPUs but with low utilization
# Check DCGM dashboard for:
# - GPU Utilization = 0% for extended periods
# - Power Usage = Base power (not training)
# - Workbench idle but GPU allocated
```

---

## Kustomize Structure

```
gitops/step-03-private-ai/
└── base/
    ├── kustomization.yaml      # Resource list
    ├── namespace.yaml          # private-ai namespace
    ├── resource-flavors.yaml   # GPU node flavors (L4 1GPU, L4 4GPU)
    ├── cluster-queue.yaml      # Cluster-wide quota pool
    └── local-queue.yaml        # Project entry point
```

---

## How It Works in the RHOAI Dashboard

### Creating a GPU Workbench

1. Go to **Data Science Projects** → **private-ai**
2. Create a new **Workbench**
3. Select **Hardware Profile**: "NVIDIA L4 1GPU (Default)"
4. Click **Create**

### What Happens Behind the Scenes

1. **RHOAI Dashboard** creates a Notebook CR with GPU request
2. **Kueue** intercepts the workload via the LocalQueue
3. **ClusterQueue** checks if quota is available:
   - ✅ **Quota available**: Workload admitted, pod starts
   - ❌ **Quota full**: Workload queued (Status: `Pending`)
4. **When GPU freed**: Next queued workload auto-admitted

### Viewing Queue Status

```bash
# Watch workload admission in real-time
oc get workloads -n private-ai -w

# Example output:
# NAME                    QUEUE               ADMITTED   AGE
# notebook-jupyter-abc    private-ai-queue    True       2m
# notebook-jupyter-xyz    private-ai-queue    False      30s  # Queued
```

---

## Troubleshooting

### Workload Stuck in Pending

```bash
# Check ClusterQueue status
oc get clusterqueue rhoai-main-queue -o jsonpath='{.status.flavorsReservation}'

# Check if quota is exhausted
oc describe clusterqueue rhoai-main-queue | grep -A 10 "Status"

# Check LocalQueue events
oc describe localqueue private-ai-queue -n private-ai
```

### ResourceFlavor Not Matching Nodes

```bash
# Verify node labels match flavor
oc get nodes -l node.kubernetes.io/instance-type=g6.4xlarge

# Check if nodes have expected labels
oc get nodes -l node-role.kubernetes.io/gpu --show-labels
```

### Kueue CRDs Missing

```bash
# Verify Kueue is installed (managed by RHOAI DSC)
oc get crd | grep kueue

# Check Kueue controller pods
oc get pods -n redhat-ods-applications | grep kueue
```

---

## Documentation Links

### Official Red Hat Documentation
- [RHOAI 3.0 - Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/working_on_data_science_projects/working-with-distributed-workloads_distributed-workloads)
- [RHOAI 3.0 - Configuring Kueue](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/working_on_data_science_projects/configuring-distributed-workloads_distributed-workloads)
- [Kueue Documentation](https://kueue.sigs.k8s.io/docs/)

### GPU Monitoring
- [NVIDIA DCGM Exporter Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/enable-gpu-monitoring-dashboard.html)
- [OCP GPU Monitoring](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/monitoring/nvidia-gpu-admin-dashboard)

---

## Summary

| Concept | Implementation | Benefit |
|---------|----------------|---------|
| **Automation** | Hardware Profiles + Kueue | Users select, system allocates |
| **Enforcement** | ClusterQueue quotas | Prevent over-provisioning |
| **Fairness** | LocalQueue admission | First-come, first-served |
| **Visibility** | DCGM Dashboard | Detect idle/hoarding |
