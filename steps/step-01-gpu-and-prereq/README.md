# Step 01: GPU Infrastructure & Prerequisites

Provisions GPU nodes and installs every operator that RHOAI 3.3 needs before the platform itself is deployed.

## The Business Story

ACME Corp is adopting open-source LLMs on private infrastructure. Before any model can be served, the OpenShift cluster needs GPU-accelerated compute, hardware discovery, workload queuing, and the networking stack that powers distributed inference. This step transforms a vanilla OpenShift 4.20 cluster into an AI-ready platform by installing the operator prerequisites defined in the RHOAI 3.3 installation guide, provisioning NVIDIA L4 GPU nodes on AWS, and enabling the monitoring pipeline that captures GPU telemetry.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  OpenShift 4.20 Cluster                                         │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ NFD Operator  │→│ GPU Operator  │→│ GPU Nodes (AWS G6)     │ │
│  │ (hw labels)   │  │ (drivers+DTK)│  │ g6.4xl (1×L4)         │ │
│  └──────────────┘  └──────────────┘  │ g6.12xl (4×L4)        │ │
│                                       └────────────────────────┘ │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ Serverless   │→│ KnativeServing│  │ Kueue (GPU-as-a-Svc)  │ │
│  └──────────────┘  └──────────────┘  └────────────────────────┘ │
│                                                                 │
│  ┌─ RHCL Stack (Inference Gateway) ──────────────────────────┐  │
│  │ Authorino · Limitador · DNS Operator · RHCL Operator      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                             │
│  │ LWS Operator │  │ User Workload│                             │
│  │ (llm-d)      │  │ Monitoring   │                             │
│  └──────────────┘  └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

## What Gets Deployed

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| User Workload Monitoring | Prometheus scraping for RHOAI metrics | `openshift-monitoring` |
| Node Feature Discovery (NFD) | Hardware labels (PCI, kernel version) for GPU Operator | `openshift-nfd` |
| NVIDIA GPU Operator v25.10 | Driver lifecycle via Driver Toolkit (DTK) | `nvidia-gpu-operator` |
| GPU MachineSets (AWS G6) | g6.4xlarge (1×L4) + g6.12xlarge (4×L4) = 5 GPUs | `openshift-machine-api` |
| OpenShift Serverless | Knative infrastructure for KServe networking | `openshift-serverless` |
| KnativeServing Instance | Knative Serving control plane | `knative-serving` |
| LeaderWorkerSet (LWS) | Multi-node GPU orchestration for llm-d | `openshift-lws-operator` |
| Red Hat Authorino | AuthZ for llm-d Inference Gateway | `openshift-authorino` |
| Limitador Operator | Rate limiting for LLM endpoints | `openshift-limitador-operator` |
| DNS Operator | Endpoint DNS for llm-d Gateway | `openshift-dns-operator` |
| Red Hat Connectivity Link | AuthPolicy CRD for llm-d Gateway integration | `rhcl-operator` |
| Red Hat Build of Kueue | Workload queuing and GPU quota management | `openshift-kueue-operator` |

> **AWS Quota:** The GPU config requires "Running On-Demand G and VT instances" >= 64 vCPU (1×g6.4xl=16 + 1×g6.12xl=48). Sandbox accounts default to 64.

## Prerequisites

- [ ] OpenShift 4.20+ cluster on AWS with cluster-admin access
- [ ] `oc` CLI installed and logged in
- [ ] AWS account with permissions to create EC2 instances (G6 family)
- [ ] Bootstrap completed (`./scripts/bootstrap.sh`)

**Ref:** [RHOAI 3.3 - Installing and Uninstalling](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)

## Deployment

### A) One-shot (via Argo CD)

```bash
./steps/step-01-gpu-and-prereq/deploy.sh
```

The script creates an Argo CD Application pointing to `gitops/step-01-gpu-and-prereq/base`, waits for critical operators, and creates GPU MachineSets templated with your cluster ID.

### B) Step-by-step

```bash
# Monitoring
oc apply -k gitops/step-01-gpu-and-prereq/base/monitoring/

# NFD + GPU Operator
oc apply -k gitops/step-01-gpu-and-prereq/base/nfd/
oc apply -k gitops/step-01-gpu-and-prereq/base/gpu-operator/

# Serverless + KnativeServing
oc apply -k gitops/step-01-gpu-and-prereq/base/serverless/

# llm-d dependencies
oc apply -k gitops/step-01-gpu-and-prereq/base/leaderworkerset/
oc apply -k gitops/step-01-gpu-and-prereq/base/authorino/
oc apply -k gitops/step-01-gpu-and-prereq/base/limitador/
oc apply -k gitops/step-01-gpu-and-prereq/base/dns-operator/
oc apply -k gitops/step-01-gpu-and-prereq/base/rhcl-operator/

# Kueue
oc apply -k gitops/step-01-gpu-and-prereq/base/kueue-operator/
```

GPU MachineSets are provisioned separately (the deploy script templates cluster ID and AZ):

```bash
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
AZ=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.placement.availabilityZone}')

oc scale machineset $CLUSTER_ID-gpu-g6-4xlarge-$AZ -n openshift-machine-api --replicas=1
oc scale machineset $CLUSTER_ID-gpu-g6-12xlarge-$AZ -n openshift-machine-api --replicas=1
```

## Validation

```bash
# All operators healthy
oc get csv -A | grep Succeeded

# GPU nodes have allocatable GPUs
oc get nodes -l feature.node.kubernetes.io/pci-10de.present=true \
  -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable."nvidia\.com/gpu"

# KnativeServing ready
oc get knativeserving knative-serving -n knative-serving

# Kernel-version labels present (critical for DTK)
oc get node --show-labels | grep kernel-version

# llm-d CRDs installed
oc get crd | grep -E "leaderworkerset|authorino|limitador|authpolicies.kuadrant"

# Kueue instance ready
oc get kueue cluster
```

Quick operator status sweep:

```bash
for ns_grep in \
  "openshift-nfd nfd" \
  "nvidia-gpu-operator gpu" \
  "openshift-serverless serverless" \
  "openshift-lws-operator leader" \
  "openshift-authorino authorino" \
  "openshift-limitador-operator limitador" \
  "openshift-dns-operator dns" \
  "rhcl-operator rhcl" \
  "openshift-kueue-operator kueue"; do
  ns=${ns_grep%% *}; pat=${ns_grep##* }
  echo "=== $ns ===" && oc get csv -n "$ns" 2>/dev/null | grep "$pat"
done
```

## Troubleshooting

### CUDA 13.0 Driver Compatibility Issue (RHOAI 3.3)

**KB:** [NVIDIA GPU driver 580.105.08 compatibility issue](https://access.redhat.com/solutions/7134740)

**Symptom:** vLLM pods fail with:
```
RuntimeError: system has unsupported display driver / cuda driver combination
```

**Root Cause:** GPU Operator 25.10.1 ships driver 580.105.08 (CUDA 13.0). The RHOAI 3.3 vLLM image uses CUDA 12.8, and the `cuda-compat` package creates a fatal conflict.

**Resolution (applied in this demo):**

1. Subscription set to `installPlanApproval: Manual` to prevent auto-upgrade.
2. Driver pinned to `570.195.03` (CUDA 12.4) in `clusterpolicy.yaml`:
   ```yaml
   spec:
     driver:
       repository: nvcr.io/nvidia
       image: driver
       version: "570.195.03"
   ```

**Verify:**
```bash
for pod in $(oc get pods -n nvidia-gpu-operator -o name | grep nvidia-driver-daemonset); do
  node=$(oc get $pod -n nvidia-gpu-operator -o jsonpath='{.spec.nodeName}')
  version=$(oc exec -n nvidia-gpu-operator $pod -c nvidia-driver-ctr -- nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
  echo "$node: Driver $version"
done
```

### "RHEL entitlement" Error (DTK Fallback)

**Symptom:** `FATAL: failed to install elfutils-libel-devel. RHEL entitlement may be improperly deployed.`

**This is NOT an entitlements problem.** NFD cannot schedule on GPU nodes due to taints, so kernel-version labels are missing and the GPU Operator falls back to `dnf install`.

**Fix:** Ensure NFD instance has `workerTolerations: [{operator: "Exists"}]` and GPU Operator ClusterPolicy has the `nvidia.com/gpu` toleration. Both are configured in the GitOps manifests.

```bash
oc get nodefeaturediscovery -n openshift-nfd -o yaml | grep -A5 workerTolerations
oc get pods -n openshift-nfd -l app.kubernetes.io/component=worker -o wide
oc get node --show-labels | grep kernel-version
```

### MachineSet Not Provisioning

```bash
oc get machines -n openshift-machine-api -o wide
oc describe machine <machine-name> -n openshift-machine-api
```

Check AWS quota limits, availability zone capacity, and that the instance type is available in your region.

### Pods Not Scheduling on GPU Nodes

GPU nodes carry the taint `nvidia.com/gpu=true:NoSchedule`. Workloads must include:

```yaml
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
nodeSelector:
  node-role.kubernetes.io/gpu: ""
resources:
  limits:
    nvidia.com/gpu: 1
```

## GitOps Structure

```
gitops/step-01-gpu-and-prereq/
├── base/
│   ├── kustomization.yaml
│   ├── monitoring/
│   │   └── cluster-monitoring-config.yaml
│   ├── nfd/
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   ├── subscription.yaml
│   │   └── instance.yaml
│   ├── gpu-operator/
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   ├── subscription.yaml
│   │   ├── clusterpolicy.yaml
│   │   └── dcgm-dashboard-configmap.yaml
│   ├── serverless/
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   ├── subscription.yaml
│   │   ├── knative-serving-namespace.yaml
│   │   └── knative-serving.yaml
│   ├── leaderworkerset/
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   └── subscription.yaml
│   ├── authorino/
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   └── subscription.yaml
│   ├── limitador/
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   └── subscription.yaml
│   ├── dns-operator/
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   └── subscription.yaml
│   ├── rhcl-operator/
│   │   ├── namespace.yaml
│   │   ├── operatorgroup.yaml
│   │   └── subscription.yaml
│   └── kueue-operator/
│       ├── namespace.yaml
│       ├── operatorgroup.yaml
│       ├── subscription.yaml
│       └── kueue-instance.yaml
└── overlays/
    └── aws/
        ├── kustomization.yaml
        └── machinesets/
            ├── gpu-g6-4xlarge.yaml
            └── gpu-g6-12xlarge.yaml
```

## Design Decisions

> **Driver Toolkit over RHEL entitlements:** OCP 4.20 uses DTK for pre-compiled driver images, eliminating the need for RHEL entitlement secrets on nodes. This simplifies GPU node provisioning significantly.

> **Driver pinned to 570.195.03:** The latest GPU Operator ships CUDA 13.0 drivers which conflict with the RHOAI 3.3 vLLM runtime (CUDA 12.8). Manual approval + version pinning avoids silent breakage.

> **NFD `enableTaints: false`:** Prevents NFD from marking GPU nodes as unschedulable before drivers are ready, avoiding a chicken-and-egg problem.

> **GPU node taints (`nvidia.com/gpu=true:NoSchedule`):** Reserves expensive GPU instances exclusively for workloads that explicitly request GPU resources.

> **RHCL stack for Inference Gateway:** Authorino, Limitador, DNS Operator, and the RHCL operator provide the AuthPolicy CRD and networking primitives required by the llm-d Inference Gateway.

> **Kueue with framework integrations:** Configured for BatchJob, RayJob, RayCluster, PyTorchJob, Pod, and LeaderWorkerSet to support the full range of RHOAI 3.3 workload types.

## References

### Official Documentation
- [RHOAI 3.3 - Installing and Uninstalling](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [RHOAI 3.3 - Distributed Inference Dependencies](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-distributed-inference-dependencies)
- [OCP 4.20 - Understanding the Driver Toolkit](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/using-the-driver-toolkit)
- [OCP 4.20 - NVIDIA GPU Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/hardware_accelerators/nvidia-gpu-architecture)
- [OCP 4.20 - User Workload Monitoring](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/monitoring/configuring-the-monitoring-stack#enabling-monitoring-for-user-defined-projects_configuring-the-monitoring-stack)
- [OCP 4.20 - Controlling Pod Placement](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/controlling-pod-placement-onto-nodes-scheduling)
- [Red Hat Connectivity Link Documentation](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/)

### Knowledge Base & Community
- [NVIDIA GPU driver 580.105.08 compatibility issue (KB 7134740)](https://access.redhat.com/solutions/7134740)
- [NVIDIA GPU Monitoring Dashboard](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/enable-gpu-monitoring-dashboard.html)

## Next Steps

Proceed to [Step 02: RHOAI Operator Installation](../step-02-rhoai-operator/README.md) to deploy the Red Hat OpenShift AI operator and configure the DataScienceCluster.
