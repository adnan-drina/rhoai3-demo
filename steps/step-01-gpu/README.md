# Step 01: GPU Infrastructure & RHOAI Prerequisites

Prepares an OpenShift 4.20 cluster on AWS for Red Hat OpenShift AI (RHOAI) 3.0. This configuration focuses on enabling **Distributed Inference (llm-d)** and ensuring GPU nodes are correctly labeled and reachable by infrastructure operators.

## What Gets Installed

### Infrastructure & Acceleration

| Component | Version/Channel | Purpose |
|-----------|-----------------|---------|
| User Workload Monitoring | - | Enables Prometheus to scrape RHOAI metrics |
| Node Feature Discovery (NFD) | stable (4.20) | Hardware labeling (PCI, Kernel, CPU) |
| NVIDIA GPU Operator | v25.10 | Driver lifecycle via Driver Toolkit (DTK) |
| GPU MachineSets | AWS G6 (L4) | High-efficiency inference nodes |

### Model Serving & Distributed Inference (llm-d)

| Component | Version/Channel | Purpose |
|-----------|-----------------|---------|
| OpenShift Serverless | stable-1.37 | Knative infrastructure for KServe |
| KnativeServing Instance | v1.17 | Knative Serving control plane |
| LeaderWorkerSet (LWS) | stable-v1.0 | Multi-node GPU orchestration for sharded LLMs |
| Red Hat Authorino | stable | AuthZ for the llm-d Inference Gateway |
| Limitador Operator | stable | Rate limiting for LLM endpoints |
| DNS Operator | stable | Endpoint DNS management |

### GPU-as-a-Service (Kueue)

| Component | Version/Channel | Purpose |
|-----------|-----------------|---------|
| **Red Hat Build of Kueue** | stable-v1.2 | Workload queuing, quota management |
| Kueue Instance (`cluster`) | - | Singleton controller with framework integrations |

---

## Prerequisites

Per [Red Hat OpenShift AI 3.0 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index):

- [ ] OpenShift 4.20+ cluster on AWS
- [ ] Cluster admin access
- [ ] `oc` CLI installed and logged in
- [ ] AWS account with permissions to create EC2 instances (g6 family)
- [ ] Bootstrap completed (`./scripts/bootstrap.sh`)

---

## ⚠️ Important: Driver Toolkit (DTK) - No RHEL Entitlements Needed

In OpenShift 4.20, the NVIDIA GPU Operator uses the **Driver Toolkit (DTK)**. This eliminates the need for RHEL Entitlement secrets or Subscription Manager on the nodes.

### Understanding the Error

If you encounter this error:
```
FATAL: failed to install elfutils-libel-devel. RHEL entitlement may be improperly deployed.
```

**This is NOT an entitlements problem.** It indicates that the **NFD Operator cannot schedule on your GPU nodes**. When NFD is blocked by taints, it cannot label the kernel version (`feature.node.kubernetes.io/kernel-version.*`), forcing the GPU Operator to fallback to a standard `dnf install` (which fails without RHEL repos).

### The Solution: Tolerations

Ensure the NFD and GPU Operator have the **tolerations** defined in this GitOps folder. The manifests in `step-01-gpu` include:

**NFD Instance** (`gitops/step-01-gpu/base/nfd/instance.yaml`):
```yaml
spec:
  operand:
    workerTolerations:
      - operator: "Exists"  # Allows NFD to run on tainted GPU nodes
```

**GPU Operator ClusterPolicy** (`gitops/step-01-gpu/base/gpu-operator/clusterpolicy.yaml`):
```yaml
spec:
  daemonsets:
    tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
```

**Ref:** [OCP 4.20 - Understanding the Driver Toolkit](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/using-the-driver-toolkit)

---

## Component Details

### 0. User Workload Monitoring

**Purpose:** RHOAI 3.0 components (KServe, TrustyAI, Model Servers) export metrics to user namespaces. This configuration enables the cluster to scrape those endpoints.

| Setting | Purpose |
|---------|---------|
| `enableUserWorkload: true` | Enables Prometheus/Thanos for user namespaces |
| `enableUserAlertmanagerConfig: true` | Allows project owners to define their own alert routing |

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/monitoring/
```

**Validation:**
```bash
oc get pods -n openshift-user-workload-monitoring
# Expected: prometheus-user-workload-0, thanos-ruler-user-workload-0 in Running state
```

**Ref:** [OCP 4.20 - Configuring User Workload Monitoring](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/monitoring/configuring-the-monitoring-stack#enabling-monitoring-for-user-defined-projects_configuring-the-monitoring-stack)

---

### 1. Node Feature Discovery (NFD) Operator

**Purpose:** NFD detects and labels hardware features on nodes (CPUs, GPUs, PCI devices, **kernel version**). This is a **prerequisite** for the NVIDIA GPU Operator.

**Critical Labels for GPU Operator:**
- `feature.node.kubernetes.io/pci-10de.present=true` - NVIDIA PCI device detected
- `feature.node.kubernetes.io/kernel-version.*` - Kernel version for DTK image selection

**Crucial Config:** `enableTaints: false`
We disable NFD-managed taints to prevent the operator from marking nodes as unschedulable before GPU drivers are ready.

**Tolerations:** The NFD instance includes tolerations for GPU-tainted nodes:
```yaml
spec:
  operand:
    workerTolerations:
      - operator: "Exists"  # Allows NFD to run on ANY tainted node
```

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

# CRITICAL: Verify kernel-version labels (required for DTK)
oc get node --show-labels | grep kernel-version
```

**Ref:** [OCP 4.20 - Installing NFD](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)

---

### 2. NVIDIA GPU Operator

**Purpose:** Manages NVIDIA GPU drivers, container toolkit, device plugin, and DCGM monitoring. Uses the **Driver Toolkit (DTK)** for pre-compiled driver images.

**Configuration:** The ClusterPolicy is configured to use the Driver Toolkit.

**Tolerations:** The ClusterPolicy includes tolerations for GPU-tainted nodes:
```yaml
spec:
  daemonsets:
    tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
```

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/gpu-operator/
```

**Validation of GPU Readiness:**
```bash
# Check GPU operator status
oc get csv -n nvidia-gpu-operator | grep gpu

# Check ClusterPolicy
oc get clusterpolicy gpu-cluster-policy

# Verify the nodes show GPU capacity
oc get nodes -l feature.node.kubernetes.io/pci-10de.present=true \
  -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable."nvidia\.com/gpu"
```

**Ref:** [RHOAI 3.0 - Specialized Hardware Driver Enablement](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)

---

### 3. OpenShift Serverless & KnativeServing

**Purpose:** Provides Knative Serving infrastructure for KServe model serving.

> **Note:** While RHOAI 3.0 uses RawDeployment mode (deprecating Serverless mode), Knative Serving remains a **prerequisite** for the Inference Gateway networking logic.

This step installs:
1. **OpenShift Serverless Operator** - The operator itself
2. **KnativeServing Instance** - The Knative Serving control plane in `knative-serving` namespace

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/serverless/
```

**Validation:**
```bash
# Check Serverless operator status
oc get csv -n openshift-serverless | grep serverless

# Check KnativeServing instance is ready
oc get knativeserving knative-serving -n knative-serving
# Expected: READY=True
```

**Ref:** [RHOAI 3.0 - KServe Dependencies](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-openshift-serverless-operator_install-kserve)

---

### 4. LeaderWorkerSet (LWS) Operator

**Purpose:** Manages the lifecycle of multi-node GPU sets for large model sharding. **Required for llm-d distributed inference** - orchestrates leader-worker topology for models like Llama-3-70B that require sharding across multiple GPUs/nodes.

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/leaderworkerset/
```

**Validation:**
```bash
# Check LWS operator status
oc get csv -n openshift-lws-operator | grep leader

# Verify CRD is installed
oc get crd leaderworkersets.leaderworkerset.x-k8s.io
```

**Ref:** [RHOAI 3.0 - Installing Distributed Inference Dependencies](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-distributed-inference-dependencies)

---

## Red Hat Connectivity Link (RHCL) Stack

The RHCL operators provide the secure **Inference Gateway** for llm-d. These components work together to provide authorization, rate limiting, and DNS management for LLM endpoints.

### 5. Red Hat Authorino Operator (RHCL)

**Purpose:** Provides token-level authentication and authorization for API endpoints. **Required for the llm-d Inference Gateway** to secure model inference endpoints.

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/authorino/
```

**Validation:**
```bash
# Check Authorino operator status
oc get csv -n openshift-authorino | grep authorino

# Verify CRD is installed
oc get crd authorinos.operator.authorino.kuadrant.io
```

**Ref:** [RHOAI 3.0 - Installing the Red Hat Authorino Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-authorino-operator_install-kserve)

---

### 6. Limitador Operator (RHCL)

**Purpose:** Provides rate limiting capabilities for the Inference Gateway. **Required for llm-d** to control request rates to LLM endpoints and prevent overload.

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/limitador/
```

**Validation:**
```bash
# Check Limitador operator status
oc get csv -n openshift-limitador-operator | grep limitador

# Verify CRD is installed
oc get crd limitadors.limitador.kuadrant.io
```

**Ref:** [Red Hat Connectivity Link Documentation](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/)

---

### 7. DNS Operator (RHCL)

**Purpose:** Manages DNS registration for model serving endpoints. **Required for llm-d** Inference Gateway to provide discoverable endpoints for LLM services.

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/dns-operator/
```

**Validation:**
```bash
# Check DNS operator status
oc get csv -n openshift-dns-operator | grep dns

# Verify CRD is installed
oc get crd dnsrecords.dns.kuadrant.io
```

**Ref:** [Red Hat Connectivity Link Documentation](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/)

---

### 8. Red Hat Build of Kueue Operator

**Purpose:** Provides workload queuing, quota management, and GPU-as-a-Service capabilities. **Required for RHOAI 3.0** to enable Hardware Profiles with Queue-based scheduling.

**Key Configuration:** The Kueue instance (`cluster`) is configured with framework integrations:
```yaml
spec:
  controllerManager:
    config:
      integrations:
        frameworks:
          - BatchJob           # Standard Kubernetes Jobs
          - RayJob             # Ray distributed jobs
          - RayCluster         # Ray clusters
          - PyTorchJob         # PyTorch Training Operator
          - Pod                # Standalone pods (Workbenches)
          - LeaderWorkerSet    # llm-d distributed inference
```

**Deployment Command:**
```bash
oc apply -k gitops/step-01-gpu/base/kueue-operator/
```

**Validation:**
```bash
# Check Kueue operator status
oc get csv -n openshift-kueue-operator | grep kueue

# Check Kueue instance is ready
oc get kueue cluster

# Verify controller pods
oc get pods -n openshift-kueue-operator
```

**Ref:** [RHOAI 3.0 - Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/working_on_data_science_projects/working-with-distributed-workloads_distributed-workloads)

---

## Deploy All Components

Deploy all operators and GPU infrastructure via Argo CD:

```bash
./steps/step-01-gpu/deploy.sh
```

The script will:
1. Create Argo CD Application pointing to `gitops/step-01-gpu/base`
2. Wait for critical operators to be ready
3. Create GPU MachineSets dynamically (templated with your cluster ID)

---

## GPU Node Configuration (AWS G6)

We use the **G6 family (NVIDIA L4 GPUs)** for high-efficiency inference.

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

### Taints Applied

All GPU nodes are created with the following taint to **prevent standard workloads from consuming expensive GPU resources**:

| Type | Key | Value | Effect |
|------|-----|-------|--------|
| **Taint** | `nvidia.com/gpu` | `true` | `NoSchedule` |
| **Label** | `node-role.kubernetes.io/gpu` | `""` | Node selector |

**Ref:** [OCP 4.20 - Creating a MachineSet on AWS](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/machine_management/modifying-machineset)

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

**Ref:** [OCP 4.20 - Controlling Pod Placement](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/controlling-pod-placement-onto-nodes-scheduling)

---

## GPU Telemetry (DCGM)

GPU metrics are **automatically scrape-able by OpenShift Prometheus** after this step:

- Namespace `nvidia-gpu-operator` has label `openshift.io/cluster-monitoring=true`
- DCGM Exporter is enabled with ServiceMonitor
- **NVIDIA DCGM Exporter Dashboard** is added to OpenShift Console

### Accessing the GPU Dashboard

Navigate to: **Observe → Dashboards → NVIDIA DCGM Exporter Dashboard**

The dashboard displays:
- GPU Temperature / Average Temperature
- GPU Power Usage / Total Power
- GPU SM Clocks
- GPU Utilization
- GPU Framebuffer Memory Used
- Tensor Core Utilization

**Ref:** [NVIDIA - Enabling GPU Monitoring Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/enable-gpu-monitoring-dashboard.html)

---

## Final Verification Checklist

Run these commands to verify all components are correctly installed:

```bash
# 1. NFD pods running
oc get pods -n openshift-nfd
# Expected: nfd-controller-manager, nfd-master, nfd-worker pods Running

# 2. GPU Operator pods running (including dcgm-exporter)
oc get pods -n nvidia-gpu-operator
# Expected: gpu-operator, nvidia-driver-daemonset, nvidia-dcgm-exporter Running

# 3. KnativeServing ready
oc get knativeserving knative-serving -n knative-serving
# Expected: READY=True

# 4. Kernel-version labels present (indicates NFD success - CRITICAL for DTK)
oc get node --show-labels | grep kernel-version

# 5. llm-d CRDs installed
oc get crd | grep -E "leaderworkerset|authorino|limitador"

# 6. All operators healthy
oc get csv -A | grep Succeeded
```

### Quick Status Check

```bash
echo "=== NFD ===" && oc get csv -n openshift-nfd | grep nfd
echo "=== GPU Operator ===" && oc get csv -n nvidia-gpu-operator | grep gpu
echo "=== Serverless ===" && oc get csv -n openshift-serverless | grep serverless
echo "=== KnativeServing ===" && oc get knativeserving -n knative-serving
echo "=== LeaderWorkerSet ===" && oc get csv -n openshift-lws-operator | grep leader
echo "=== Authorino ===" && oc get csv -n openshift-authorino | grep authorino
echo "=== Limitador ===" && oc get csv -n openshift-limitador-operator | grep limitador
echo "=== DNS Operator ===" && oc get csv -n openshift-dns-operator | grep dns
echo "=== Kueue Operator ===" && oc get csv -n openshift-kueue-operator | grep kueue
echo "=== Kueue Instance ===" && oc get kueue cluster
```

---

## Kustomize Structure

```
gitops/step-01-gpu/
├── base/
│   ├── kustomization.yaml
│   ├── monitoring/                 # User Workload Monitoring
│   │   └── cluster-monitoring-config.yaml
│   ├── nfd/                        # Node Feature Discovery
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   ├── subscription.yaml
│   │   └── instance.yaml           # NFD CR with tolerations
│   ├── gpu-operator/               # NVIDIA GPU Operator
│   │   ├── namespace.yaml          # Has openshift.io/cluster-monitoring=true
│   │   ├── operatorgroup.yaml
│   │   ├── subscription.yaml
│   │   ├── clusterpolicy.yaml      # DTK + tolerations
│   │   └── dcgm-dashboard-configmap.yaml
│   ├── serverless/                 # OpenShift Serverless (KServe prerequisite)
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   ├── subscription.yaml
│   │   ├── knative-serving-namespace.yaml
│   │   └── knative-serving.yaml    # KnativeServing instance
│   ├── leaderworkerset/            # LeaderWorkerSet (llm-d)
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   └── subscription.yaml
│   ├── authorino/                  # Red Hat Authorino (RHCL)
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   └── subscription.yaml
│   ├── limitador/                  # Limitador (RHCL)
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   └── subscription.yaml
│   ├── dns-operator/               # DNS Operator (RHCL)
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   └── subscription.yaml
│   └── kueue-operator/             # Red Hat Build of Kueue
│       ├── namespace.yaml
│       ├── operatorgroup.yaml
│       ├── subscription.yaml
│       └── kueue-instance.yaml     # Singleton with framework integrations
└── overlays/
    └── aws/
        ├── kustomization.yaml
        └── machinesets/
            ├── gpu-g6-4xlarge.yaml
            └── gpu-g6-12xlarge.yaml
```

---

## References

### RHOAI 3.0 Documentation
- [RHOAI 3.0 - Installing and Uninstalling](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [RHOAI 3.0 - Installing Distributed Inference Dependencies](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-distributed-inference-dependencies)
- [RHOAI 3.0 - Installing the OpenShift Serverless Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-openshift-serverless-operator_install-kserve)
- [RHOAI 3.0 - Installing the Red Hat Authorino Operator](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-the-authorino-operator_install-kserve)

### OpenShift Container Platform 4.20
- [OCP 4.20 - Understanding the Driver Toolkit](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/using-the-driver-toolkit)
- [OCP 4.20 - NVIDIA GPU Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)
- [OCP 4.20 - Configuring User Workload Monitoring](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/monitoring/configuring-the-monitoring-stack#enabling-monitoring-for-user-defined-projects_configuring-the-monitoring-stack)
- [OCP 4.20 - Controlling Pod Placement (Taints/Tolerations)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/controlling-pod-placement-onto-nodes-scheduling)
- [OCP 4.20 - Modifying MachineSets](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/machine_management/modifying-machineset)

### Red Hat Connectivity Link
- [Red Hat Connectivity Link Documentation](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/)

### GPU Monitoring
- [NVIDIA GPU Operator on OpenShift](https://docs.nvidia.com/datacenter/cloud-native/openshift/24.9.1/install-gpu-ocp.html)
- [NVIDIA - Enabling GPU Monitoring Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/enable-gpu-monitoring-dashboard.html)

---

## Troubleshooting

### "RHEL entitlement" Error (DTK Fallback)

If you see:
```
FATAL: failed to install elfutils-libel-devel. RHEL entitlement may be improperly deployed.
```

**Root Cause:** NFD cannot schedule on GPU nodes due to taints, preventing kernel-version labeling.

**Solution:**
1. Verify NFD instance has tolerations:
   ```bash
   oc get nodefeaturediscovery -n openshift-nfd -o yaml | grep -A5 workerTolerations
   ```
2. Check NFD workers are running on GPU nodes:
   ```bash
   oc get pods -n openshift-nfd -l app.kubernetes.io/component=worker -o wide
   ```
3. Verify kernel-version labels exist:
   ```bash
   oc get node --show-labels | grep kernel-version
   ```

### NFD Not Detecting GPUs

```bash
# Check NFD worker logs
oc logs -n openshift-nfd -l app.kubernetes.io/component=worker

# Verify PCI device detection
oc get nodes -o json | jq '.items[].metadata.labels | with_entries(select(.key | startswith("feature.node.kubernetes.io")))'
```

### GPU Operator Pods Failing

```bash
# Check operator logs
oc logs -n nvidia-gpu-operator -l app=gpu-operator

# Check driver container logs
oc logs -n nvidia-gpu-operator -l app=nvidia-driver-daemonset
```

### MachineSet Not Provisioning

```bash
# Check machine status
oc get machines -n openshift-machine-api -o wide

# Check machine events
oc describe machine <machine-name> -n openshift-machine-api
```

### Pods Not Scheduling on GPU Nodes

Ensure your workload has the required toleration:

```yaml
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```
