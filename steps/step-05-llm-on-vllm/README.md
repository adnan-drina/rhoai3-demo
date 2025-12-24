# Step 05: GPU-as-a-Service Demo

**"The Dynamic Resource Handover"** - Demonstrating RHOAI 3.0's intelligent GPU allocation with Kueue.

## The Business Story

In enterprise environments, GPU resources are expensive and shared. Teams can't hoard GPUs indefinitely. **GPU-as-a-Service** means:

1. **Fair Allocation**: Quotas prevent any single team from monopolizing resources
2. **Dynamic Handover**: When one workload finishes, another automatically starts
3. **Predictable Queuing**: Developers know exactly when their job will run

## Demo Overview

### The Setup: Full Quota Saturation

Our cluster has **5 GPUs** with a **5 GPU quota**:

```
┌─────────────────────────────────────────────────────────────┐
│                    BASELINE STATE                           │
├─────────────────────────────────────────────────────────────┤
│  mistral-3-bf16  │ 4 GPUs │ 🟢 ON  │ g6.12xlarge           │
│  mistral-3-int4  │ 1 GPU  │ 🟢 ON  │ g6.4xlarge            │
│  devstral-2      │ 4 GPUs │ ⚫ OFF │ g6.12xlarge (waiting) │
├─────────────────────────────────────────────────────────────┤
│  GPU Usage: ████████████████████ 5/5 (100%)                 │
└─────────────────────────────────────────────────────────────┘
```

### The Demo Flow

```
Step 1: BASELINE
─────────────────
BF16 (4) + INT4 (1) = 5 GPUs
Devstral-2 = OFF (waiting)


Step 2: ATTEMPT TO START DEVSTRAL-2
───────────────────────────────────
Developer enables Devstral-2 → PENDING ⏳
Kueue says: "4 + 1 + 4 = 9 > 5 (over quota)"


Step 3: THE HANDOVER
────────────────────
Admin disables BF16 → 4 GPUs freed
Devstral-2 INSTANTLY starts! ⚡
New state: INT4 (1) + Devstral (4) = 5 GPUs


THE MESSAGE:
"This is GPU-as-a-Service. The platform ensures fair access 
and prevents any team from hoarding resources."
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     AWS OCP 4.20 Cluster                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────────┐  ┌────────────────────────────────────┐  │
│  │     MinIO (S3 Storage)   │  │    Red Hat Registry (OCI)          │  │
│  │  s3://models/mistral-24b │  │  registry.redhat.io/rhelai1/       │  │
│  │      (~48GB BF16)        │  │  modelcar-...-quantized-w4a16:1.5  │  │
│  │  For models > 20GB       │  │  (~13.5GB INT4) For models < 20GB  │  │
│  └──────────────────────────┘  └────────────────────────────────────┘  │
│              │                                    │                     │
│              ▼                                    ▼                     │
│  ┌─────────────────────────┐  ┌─────────────────────────┐              │
│  │   g6.12xlarge Node      │  │   g6.4xlarge Node       │              │
│  │   (4x NVIDIA L4)        │  │   (1x NVIDIA L4)        │              │
│  │                         │  │                         │              │
│  │  ┌───────────────────┐  │  │  ┌───────────────────┐  │              │
│  │  │ mistral-3-bf16    │  │  │  │ mistral-3-int4    │  │              │
│  │  │      OR           │  │  │  │ Always Running    │  │              │
│  │  │ devstral-2        │  │  │  │                   │  │              │
│  │  │ (swapped via Kueue)│ │  │  │                   │  │              │
│  │  └───────────────────┘  │  │  └───────────────────┘  │              │
│  └─────────────────────────┘  └─────────────────────────┘              │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        Kueue Controller                          │   │
│  │  ClusterQueue: rhoai-main-queue (quota: 5 GPUs)                 │   │
│  │  ResourceFlavors: nvidia-l4-1gpu, nvidia-l4-4gpu                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Models

| Name | GPUs | Hardware | Storage | minReplicas | Role |
|------|------|----------|---------|-------------|------|
| **mistral-3-bf16** | 4 | g6.12xlarge | S3 | 1 | Primary Load |
| **mistral-3-int4** | 1 | g6.4xlarge | OCI | 1 | Secondary Load |
| **devstral-2** | 4 | g6.12xlarge | S3 | 0 | Queued Asset |

### Storage Strategy

| Model Size | Storage | Why |
|------------|---------|-----|
| **< 20GB** | OCI ModelCar | Fits in CRI-O overlay |
| **> 20GB** | S3/MinIO | Avoids "no space left on device" |

## Prerequisites

### 1. Scale AWS MachineSets

```bash
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')

# Scale for 5 total GPUs
oc scale machineset ${CLUSTER_ID}-gpu-g6-12xlarge-us-east-2b -n openshift-machine-api --replicas=1
oc scale machineset ${CLUSTER_ID}-gpu-g6-4xlarge-us-east-2b -n openshift-machine-api --replicas=1

# Verify nodes (3-5 minutes)
oc get nodes -l nvidia.com/gpu.product=NVIDIA-L4
```

### 2. Upload BF16 Model to MinIO

```bash
# Create HuggingFace token secret
oc create secret generic hf-token -n minio-storage --from-literal=token=hf_xxxYOURTOKENxxx

# Run upload job
oc apply -f gitops/step-05-llm-on-vllm/base/model-upload/upload-mistral-bf16.yaml

# Monitor (~30-60 minutes for 50GB)
oc logs -f job/upload-mistral-bf16 -n minio-storage
```

### 3. Verify Kueue Quota

```bash
# ClusterQueue should show nominalQuota: 5 for nvidia.com/gpu
oc get clusterqueue rhoai-main-queue -o yaml | grep -A20 "resourceGroups"
```

## Deployment

```bash
./steps/step-05-llm-on-vllm/deploy.sh
```

Or apply manually:

```bash
oc apply -k gitops/step-05-llm-on-vllm/base/
```

## Running the Demo

### Option 1: GPU Switchboard Notebook

1. Open the RHOAI Dashboard
2. Navigate to **Data Science Projects** → **private-ai**
3. Launch a workbench with the `GPU-Switchboard.ipynb` notebook
4. Follow the interactive toggles to demonstrate the handover

### Option 2: CLI Commands

```bash
# Step 1: Verify baseline (5/5 GPUs used)
oc get inferenceservice -n private-ai
oc get pods -n private-ai | grep -E "mistral|devstral"

# Step 2: Enable Devstral-2 (will be PENDING)
oc patch inferenceservice devstral-2 -n private-ai \
  --type=merge -p '{"spec":{"predictor":{"minReplicas":1}}}'

# Watch it get queued
oc get workload -n private-ai -w

# Step 3: Disable BF16 to trigger handover
oc patch inferenceservice mistral-3-bf16 -n private-ai \
  --type=merge -p '{"spec":{"predictor":{"minReplicas":0}}}'

# Watch Devstral-2 start instantly!
oc get pods -n private-ai -w
```

## Validation

### Test the Models

```bash
# Mistral-3-BF16 (4-GPU)
curl -s -k https://mistral-3-bf16-private-ai.apps.<cluster>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "mistral-3-bf16", "messages": [{"role": "user", "content": "Hello!"}]}' | jq .

# Mistral-3-INT4 (1-GPU)
curl -s -k https://mistral-3-int4-private-ai.apps.<cluster>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "mistral-3-int4", "messages": [{"role": "user", "content": "Hello!"}]}' | jq .
```

### Check Kueue Status

```bash
# Workloads in the queue
oc get workload -n private-ai

# ClusterQueue admission status
oc describe clusterqueue rhoai-main-queue
```

## Troubleshooting

### Workload Stuck in Pending

```bash
# Check why workload isn't admitted
oc describe workload -n private-ai <workload-name>

# Common causes:
# 1. Insufficient quota → Check nominalQuota in ClusterQueue
# 2. No matching ResourceFlavor → Check nodeLabels match actual nodes
# 3. Missing tolerations → Check ResourceFlavor has tolerations
```

### OCI Image Pull Fails: "No Space Left"

```bash
# OCI images > 20GB exceed CRI-O overlay limits
# Solution: Use S3 storage instead (see mistral-3-bf16.yaml)
```

### CUDA Driver Error 803

See [Red Hat KB 7134740](https://access.redhat.com/solutions/7134740) for driver downgrade instructions.

## GitOps Structure

```
gitops/step-05-llm-on-vllm/base/
├── kustomization.yaml
├── serving-runtime/
│   └── vllm-runtime.yaml          # Thin vLLM runtime
├── inference/
│   ├── kustomization.yaml
│   ├── mistral-3-bf16.yaml        # 4-GPU, S3, minReplicas: 1
│   ├── mistral-3-int4.yaml        # 1-GPU, OCI, minReplicas: 1
│   └── devstral-2.yaml            # 4-GPU, S3, minReplicas: 0
├── model-registration/
│   └── seed-job.yaml              # Register models in Registry
├── model-upload/
│   └── upload-mistral-bf16.yaml   # Upload BF16 weights to MinIO
└── controller/
    └── GPU-Switchboard.ipynb      # Interactive demo notebook
```

## Key RHOAI 3.0 Design Patterns

### Dynamic Admission (Kueue)

> *"Kueue allows for the declarative management of resource quotas. By submitting more work than the quota allows, administrators can demonstrate the deterministic queueing behavior required for shared enterprise GPU clusters."*

### KServe Replica Management

> *"Setting minReplicas to 1 ensures immediate availability, while minReplicas 0 allows for cost-optimization. Managing these fields via API allows for higher-level orchestration of inference capacity."*

## Official Documentation

- [RHOAI 3.0 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/working_with_distributed_workloads/index)
- [Kueue Integration](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/working_with_distributed_workloads/index#configuring-quota-management-for-distributed-workloads_distributed-workloads)
- [KServe Storage Configuration](https://kserve.github.io/website/latest/modelserving/storage/)
- [Red Hat KB: NVIDIA Driver 580.x Compatibility](https://access.redhat.com/solutions/7134740)

## Next Steps

- **Step 06**: RAG Pipeline with LangChain
- **Step 07**: Agent Playground with Bee Framework
