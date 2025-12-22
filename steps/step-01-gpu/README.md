# Step 01: GPU Infrastructure & RHOAI Prerequisites

Prepares an OpenShift 4.20 cluster on AWS for Red Hat OpenShift AI (RHOAI) 3.0 by installing required operators and creating GPU-enabled MachineSets.

## What Gets Installed

| Component | Version/Channel | Purpose | Status |
|-----------|-----------------|---------|--------|
| Node Feature Discovery (NFD) | stable (4.20) | Detects hardware features on nodes | ✅ Deployed |
| NVIDIA GPU Operator | v25.10 | Manages GPU drivers, device plugin, monitoring | ✅ Deployed |
| OpenShift Serverless | stable-1.37 | Provides Knative Serving for KServe model inference | 🔧 GitOps Ready |
| OpenShift Service Mesh 3 | stable (3.1) | Service mesh for KServe traffic management | ✅ Deployed |
| Red Hat Authorino | stable | Authentication/authorization for KServe endpoints | 🔧 GitOps Ready |
| GPU MachineSets | - | AWS g6.4xlarge, g6.12xlarge instances | ✅ Deployed |

---

## Prerequisites

Per [Red Hat OpenShift AI 3.0 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index):

- [ ] OpenShift 4.14+ cluster on AWS
- [ ] Cluster admin access
- [ ] `oc` CLI installed and logged in
- [ ] AWS account with permissions to create EC2 instances (g6 family)
- [ ] Bootstrap completed (`./scripts/bootstrap.sh`)
- [ ] **RHEL entitlements configured** (required for NVIDIA driver compilation)

### RHEL Entitlements for Driver Compilation

The NVIDIA GPU Operator compiles kernel modules on GPU nodes. This requires access to RHEL repositories for kernel-devel packages. If you see errors like:

```
FATAL: failed to install elfutils-libel-devel. RHEL entitlement may be improperly deployed.
```

Follow [Red Hat's entitlement documentation](https://docs.openshift.com/container-platform/4.20/cicd/builds/running-entitled-builds.html) to configure cluster entitlements.

---

## Component Details

### 1. Node Feature Discovery (NFD) Operator

**Purpose:** NFD detects and labels hardware features on nodes (CPUs, GPUs, PCI devices). This is a **prerequisite** for the NVIDIA GPU Operator, which relies on NFD labels like `feature.node.kubernetes.io/pci-10de.present=true` to identify GPU nodes.

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/nfd/
```

**Validation:**
```bash
# Check NFD operator status
oc get csv -n openshift-nfd | grep nfd

# Check NFD instance
oc get nodefeaturediscovery -n openshift-nfd

# Check NFD pods are running
oc get pods -n openshift-nfd

# Verify GPU detection label on GPU nodes
oc get nodes -l feature.node.kubernetes.io/pci-10de.present=true
```

**Tolerations:** The NFD instance includes tolerations for GPU-tainted nodes:
```yaml
spec:
  operand:
    workerTolerations:
      - operator: "Exists"
```

**Ref:** [OCP 4.20 - NVIDIA GPU Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)

---

### 2. NVIDIA GPU Operator

**Purpose:** Manages NVIDIA GPU drivers, container toolkit, device plugin, and DCGM monitoring components. Enables GPU workloads to run on Kubernetes without manual driver installation.

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/gpu-operator/
```

**Validation:**
```bash
# Check GPU operator status
oc get csv -n nvidia-gpu-operator | grep gpu

# Check ClusterPolicy
oc get clusterpolicy gpu-cluster-policy

# Check GPU operator pods
oc get pods -n nvidia-gpu-operator

# Verify GPU capacity on nodes
oc get nodes -l node-role.kubernetes.io/gpu \
  -o jsonpath='{range .items[*]}{.metadata.name}: {.status.allocatable.nvidia\.com/gpu} GPUs{"\n"}{end}'
```

**Tolerations:** The ClusterPolicy includes tolerations for GPU-tainted nodes:
```yaml
spec:
  daemonsets:
    tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
```

**Ref:** [NVIDIA GPU Operator on OpenShift](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.1/install-gpu-ocp.html)

---

### 3. OpenShift Serverless Operator

**Purpose:** Provides Knative Serving, which is **required for KServe** model serving in RHOAI 3.0. KServe uses Knative to autoscale inference endpoints from zero to many replicas.

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/serverless/
```

**Validation:**
```bash
# Check Serverless operator status
oc get csv -n openshift-serverless | grep serverless

# Check subscription
oc get subscription serverless-operator -n openshift-serverless
```

**Ref:** [RHOAI 3.0 - Installing the OpenShift Serverless Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-openshift-serverless-operator_install-kserve)

---

### 4. OpenShift Service Mesh 3 Operator

**Purpose:** Provides Istio-based service mesh capabilities for traffic management, security, and observability. **Required for KServe** when using the RawDeployment mode or advanced traffic routing.

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/servicemesh/
```

**Validation:**
```bash
# Check Service Mesh operator status
oc get csv -A | grep servicemesh | head -1

# Check subscription
oc get subscription servicemeshoperator3 -n openshift-operators
```

**Ref:** [RHOAI 3.0 - Installing the OpenShift Service Mesh Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-openshift-service-mesh-operator_install-kserve)

---

### 5. Red Hat Authorino Operator

**Purpose:** Provides authentication and authorization for API endpoints. **Required for KServe** to secure model inference endpoints with token-based authentication.

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/authorino/
```

**Validation:**
```bash
# Check Authorino operator status
oc get csv -n openshift-authorino | grep authorino

# Check subscription
oc get subscription authorino-operator -n openshift-authorino
```

**Ref:** [RHOAI 3.0 - Installing the Red Hat Authorino Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-authorino-operator_install-kserve)

---

## Deploy All Components

Deploy all operators and GPU infrastructure via Argo CD:

```bash
./steps/step-01-gpu/deploy.sh
```

The script will:
1. Template MachineSet manifests with your cluster ID and AMI
2. Validate Kustomize build
3. Create Argo CD Application pointing to `gitops/step-01-gpu/overlays/aws`

---

## GPU Node Configuration

### Scale GPU Nodes

MachineSets are created with `replicas: 1`. Adjust as needed:

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

### Node Taints and Labels

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

**Ref:** [OpenShift - Controlling Pod Placement](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/controlling-pod-placement-onto-nodes-scheduling)

---

## GPU Telemetry (DCGM)

GPU metrics are **automatically scrape-able by OpenShift Prometheus** after this step:

- Namespace `nvidia-gpu-operator` has label `openshift.io/cluster-monitoring=true`
- DCGM Exporter is enabled with ServiceMonitor
- Metrics available at `/metrics` endpoint on DCGM pods
- **NVIDIA DCGM Exporter Dashboard** is added to OpenShift Console

**Ref:** [NVIDIA GPU Operator - Cluster Monitoring](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.1/install-gpu-ocp.html)

### Accessing the GPU Dashboard

Navigate to: **Observe → Dashboards → NVIDIA DCGM Exporter Dashboard**

The dashboard displays:
- GPU Temperature / Average Temperature
- GPU Power Usage / Total Power
- GPU SM Clocks
- GPU Utilization
- GPU Framebuffer Memory Used
- Tensor Core Utilization

**Ref:** [NVIDIA - Enabling GPU Monitoring Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.1/enable-gpu-monitoring-dashboard.html)

---

## Verification Checklist

### All Operators

```bash
# Quick status check for all required operators
echo "=== NFD ===" && oc get csv -n openshift-nfd | grep nfd
echo "=== GPU Operator ===" && oc get csv -n nvidia-gpu-operator | grep gpu
echo "=== Serverless ===" && oc get csv -n openshift-serverless | grep serverless
echo "=== Service Mesh ===" && oc get csv -A | grep servicemesh | head -1
echo "=== Authorino ===" && oc get csv -n openshift-authorino | grep authorino
```

### GPU Nodes - Taints and Labels

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

### DCGM Telemetry Readiness

```bash
# Verify namespace has monitoring label
oc get namespace nvidia-gpu-operator -o jsonpath='{.metadata.labels.openshift\.io/cluster-monitoring}'
# Expected: true

# Check DCGM exporter pods
oc get pods -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter

# Check ServiceMonitor exists
oc get servicemonitor -n nvidia-gpu-operator
```

---

## Kustomize Structure

```
gitops/step-01-gpu/
├── base/
│   ├── kustomization.yaml
│   ├── nfd/                        # Node Feature Discovery
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   ├── subscription.yaml
│   │   └── instance.yaml           # NFD CR with tolerations
│   ├── gpu-operator/               # NVIDIA GPU Operator
│   │   ├── namespace.yaml          # Has openshift.io/cluster-monitoring=true
│   │   ├── operatorgroup.yaml
│   │   ├── subscription.yaml
│   │   ├── clusterpolicy.yaml      # DCGM + ServiceMonitor + tolerations
│   │   └── dcgm-dashboard-configmap.yaml
│   ├── serverless/                 # OpenShift Serverless (KServe prerequisite)
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   └── subscription.yaml
│   ├── servicemesh/                # OpenShift Service Mesh 3
│   │   └── subscription.yaml       # Uses global OperatorGroup
│   └── authorino/                  # Red Hat Authorino
│       ├── namespace.yaml
│       ├── operatorgroup.yaml
│       └── subscription.yaml
└── overlays/
    └── aws/
        ├── kustomization.yaml
        └── machinesets/
            ├── gpu-g6-4xlarge.yaml   # Taints + labels in template
            └── gpu-g6-12xlarge.yaml
```

---

## References

### RHOAI 3.0 Documentation
- [RHOAI 3.0 - Installing and Uninstalling](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [RHOAI 3.0 - Installing the OpenShift Serverless Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-openshift-serverless-operator_install-kserve)
- [RHOAI 3.0 - Installing the OpenShift Service Mesh Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-openshift-service-mesh-operator_install-kserve)
- [RHOAI 3.0 - Installing the Red Hat Authorino Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-authorino-operator_install-kserve)

### OpenShift Container Platform 4.20
- [OCP 4.20 - NVIDIA GPU Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)
- [OCP 4.20 - Controlling Pod Placement (Taints/Tolerations)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/controlling-pod-placement-onto-nodes-scheduling)
- [OCP 4.20 - Modifying MachineSets](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/machine_management/modifying-machineset)
- [OCP 4.20 - Manually Scaling MachineSets](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/machine_management/manually-scaling-machineset)

### GPU Monitoring
- [NVIDIA GPU Operator on OpenShift - Installation](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.1/install-gpu-ocp.html)
- [NVIDIA - Enabling GPU Monitoring Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/enable-gpu-monitoring-dashboard.html)

---

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
