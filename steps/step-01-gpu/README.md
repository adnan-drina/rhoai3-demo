# Step 01: GPU Infrastructure

Prepares an OpenShift 4.x cluster on AWS for GPU workloads by installing required operators and creating GPU-enabled MachineSets.

## What Gets Installed

| Component | Version | Purpose |
|-----------|---------|---------|
| Node Feature Discovery (NFD) | 4.14+ (stable) | Detects hardware features on nodes |
| NVIDIA GPU Operator | 24.3+ (v25.10) | Manages GPU drivers, device plugin, monitoring |
| GPU MachineSets | - | AWS g6.4xlarge, g6.12xlarge instances |

## Prerequisites

Per [Red Hat AI documentation](https://docs.redhat.com/en/documentation/red_hat_ai/3/html/supported_product_and_hardware_configurations/rhaiis-software-prerequisites-for-gpu-deployments_supported-configurations):

- [ ] OpenShift 4.14+ cluster on AWS
- [ ] Cluster admin access
- [ ] `oc` CLI installed and logged in
- [ ] AWS account with permissions to create EC2 instances (g6 family)
- [ ] Bootstrap completed (`./scripts/bootstrap.sh`)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     OpenShift Cluster                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   NFD Operator  │  │  GPU Operator   │  │   Machine API   │  │
│  │  (openshift-nfd)│  │(nvidia-gpu-op.) │  │                 │  │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
│           │                    │                    │           │
│           ▼                    ▼                    ▼           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    GPU Worker Nodes                          ││
│  │  Labels:                                                     ││
│  │    - node-role.kubernetes.io/gpu=""                          ││
│  │  Taints:                                                     ││
│  │    - nvidia.com/gpu=true:NoSchedule                          ││
│  │  Instance types:                                             ││
│  │    - g6.4xlarge (1x L4) or g6.12xlarge (4x L4)              ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Deploy

```bash
./steps/step-01-gpu/deploy.sh
```

The script will:
1. Template MachineSet manifests with your cluster ID and AMI
2. Validate Kustomize build
3. Create Argo CD Application pointing to `gitops/step-01-gpu/overlays/aws`

## Scale GPU Nodes

MachineSets are created with `replicas: 0`. Scale when ready:

```bash
# Get cluster ID
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')

# Scale g6.4xlarge (1x NVIDIA L4)
oc scale machineset $CLUSTER_ID-gpu-g6-4xlarge-us-east-2b \
  -n openshift-machine-api --replicas=1

# Scale g6.12xlarge (4x NVIDIA L4)
oc scale machineset $CLUSTER_ID-gpu-g6-12xlarge-us-east-2b \
  -n openshift-machine-api --replicas=1
```

## Node Taints and Labels

**GPU nodes are tainted and reserved for GPU workloads only.** Non-GPU pods will not schedule on GPU nodes unless they explicitly tolerate the taint.

| Type | Key | Value | Effect |
|------|-----|-------|--------|
| **Taint** | `nvidia.com/gpu` | `true` | `NoSchedule` |
| **Label** | `node-role.kubernetes.io/gpu` | `""` | Node selector |

### Scheduling GPU Workloads

Workloads that need GPU must include a toleration:

```yaml
spec:
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  nodeSelector:
    node-role.kubernetes.io/gpu: ""
  containers:
    - name: gpu-workload
      resources:
        limits:
          nvidia.com/gpu: 1
```

Ref: [OpenShift Taints and Tolerations](https://docs.redhat.com/en/documentation/openshift_container_platform/4.11/html/nodes/controlling-pod-placement-onto-nodes-scheduling)

## GPU Telemetry (DCGM)

GPU metrics are **automatically scrape-able by OpenShift Prometheus** after this step:

- Namespace `nvidia-gpu-operator` has label `openshift.io/cluster-monitoring=true`
- DCGM Exporter is enabled with ServiceMonitor
- Metrics available at `/metrics` endpoint on DCGM pods
- **NVIDIA DCGM Exporter Dashboard** is added to OpenShift Console

Ref: [NVIDIA GPU Operator - Cluster Monitoring](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.1/install-gpu-ocp.html)

### Accessing the GPU Dashboard

Navigate to: **Observe → Dashboards → NVIDIA DCGM Exporter Dashboard**

The dashboard displays:
- GPU Temperature / Average Temperature
- GPU Power Usage / Total Power
- GPU SM Clocks
- GPU Utilization
- GPU Framebuffer Memory Used
- Tensor Core Utilization

Ref: [NVIDIA - Enabling GPU Monitoring Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.1/enable-gpu-monitoring-dashboard.html)

### Available Metrics

| Metric | Description |
|--------|-------------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU utilization % |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | Memory copy utilization % |
| `DCGM_FI_DEV_FB_USED` | Framebuffer memory used (bytes) |
| `DCGM_FI_DEV_FB_FREE` | Framebuffer memory free (bytes) |
| `DCGM_FI_DEV_POWER_USAGE` | Power consumption (W) |
| `DCGM_FI_DEV_GPU_TEMP` | GPU temperature (°C) |

Query in OpenShift Console: **Observe → Metrics → Custom Query**

## Verification Checklist

### 1. NFD Operator

```bash
# Check operator
oc get csv -n openshift-nfd | grep nfd

# Check NFD instance
oc get nodefeaturediscovery -n openshift-nfd

# Check NFD pods
oc get pods -n openshift-nfd
```

### 2. GPU Operator

```bash
# Check operator
oc get csv -n nvidia-gpu-operator | grep gpu

# Check ClusterPolicy
oc get clusterpolicy

# Check GPU operator pods
oc get pods -n nvidia-gpu-operator
```

### 3. GPU Nodes - Taints and Labels

```bash
# Check MachineSets
oc get machineset -n openshift-machine-api | grep gpu

# Verify nodes have GPU label
oc get nodes -l node-role.kubernetes.io/gpu

# Verify nodes have taint
oc get nodes -l node-role.kubernetes.io/gpu -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.taints}{"\n"}{end}'

# Verify GPU capacity
oc get nodes -l node-role.kubernetes.io/gpu \
  -o jsonpath='{range .items[*]}{.metadata.name}: {.status.allocatable.nvidia\.com/gpu} GPUs{"\n"}{end}'
```

### 4. DCGM Telemetry Readiness

```bash
# Verify namespace has monitoring label
oc get namespace nvidia-gpu-operator -o jsonpath='{.metadata.labels.openshift\.io/cluster-monitoring}'
# Expected: true

# Check DCGM exporter pods
oc get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter

# Check ServiceMonitor exists
oc get servicemonitor -n nvidia-gpu-operator

# Test metrics endpoint (from within cluster)
oc exec -n nvidia-gpu-operator $(oc get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter -o name | head -1) -- curl -s localhost:9400/metrics | head -20
```

### 5. GPU Dashboard

```bash
# Verify dashboard ConfigMap exists
oc get configmap nvidia-dcgm-exporter-dashboard -n openshift-config-managed

# Verify dashboard labels
oc get configmap nvidia-dcgm-exporter-dashboard -n openshift-config-managed --show-labels
# Expected: console.openshift.io/dashboard=true
```

Then navigate to **Observe → Dashboards → NVIDIA DCGM Exporter Dashboard** in OpenShift Console.

### 6. GPU Driver Status

```bash
# Check driver pods
oc get pods -n nvidia-gpu-operator -l app=nvidia-driver-daemonset

# Run nvidia-smi on GPU node
oc debug node/<gpu-node-name> -- chroot /host nvidia-smi
```

## Kustomize Structure

```
gitops/step-01-gpu/
├── base/
│   ├── kustomization.yaml
│   ├── nfd/
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   ├── subscription.yaml
│   │   └── instance.yaml
│   └── gpu-operator/
│       ├── namespace.yaml              # Has openshift.io/cluster-monitoring=true
│       ├── operatorgroup.yaml
│       ├── subscription.yaml
│       ├── clusterpolicy.yaml          # DCGM + ServiceMonitor enabled
│       └── dcgm-dashboard-configmap.yaml  # OpenShift Console dashboard
└── overlays/
    └── aws/
        ├── kustomization.yaml
        └── machinesets/
            ├── gpu-g6-4xlarge.yaml   # Taints + labels in template
            └── gpu-g6-12xlarge.yaml
```

## References

### Core Documentation
- [Red Hat AI - Software Prerequisites for GPU Deployments](https://docs.redhat.com/en/documentation/red_hat_ai/3/html/supported_product_and_hardware_configurations/rhaiis-software-prerequisites-for-gpu-deployments_supported-configurations)
- [OCP 4.20 - NVIDIA GPU Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)

### Taints and Scheduling
- [OCP - Controlling Pod Placement (Taints/Tolerations)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.11/html/nodes/controlling-pod-placement-onto-nodes-scheduling)

### Machine Management
- [OCP 4.20 - Modifying MachineSets](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/machine_management/modifying-machineset)
- [OCP 4.20 - Manually Scaling MachineSets](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/machine_management/manually-scaling-machineset)

### GPU Monitoring
- [NVIDIA GPU Operator on OpenShift - Installation](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.1/install-gpu-ocp.html)
- [NVIDIA - Enabling GPU Monitoring Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/enable-gpu-monitoring-dashboard.html)
- [OCP - NVIDIA GPU Administration Dashboard](https://docs.redhat.com/en/documentation/openshift_container_platform/4.11/html/monitoring/nvidia-gpu-admin-dashboard)

### GitOps Catalog
- [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog) (vendored components)

## Troubleshooting

### NFD not detecting GPUs

```bash
# Check NFD worker logs
oc logs -n openshift-nfd -l app.kubernetes.io/component=worker

# Verify PCI device detection
oc get nodes -o json | jq '.items[].metadata.labels | with_entries(select(.key | startswith("feature.node.kubernetes.io")))'
```

### GPU Operator pods failing

```bash
# Check operator logs
oc logs -n nvidia-gpu-operator -l app=gpu-operator

# Check driver container logs
oc logs -n nvidia-gpu-operator -l app=nvidia-driver-daemonset
```

### MachineSet not provisioning

```bash
# Check machine status
oc get machines -n openshift-machine-api -o wide

# Check machine events
oc describe machine <machine-name> -n openshift-machine-api
```

### Pods not scheduling on GPU nodes

Ensure your workload has the required toleration:

```yaml
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```
