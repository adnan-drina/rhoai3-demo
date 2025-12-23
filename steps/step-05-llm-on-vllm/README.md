# Step 05: LLM Serving - Triple Play

Deploy three production-grade LLMs using vLLM on RHOAI 3.0, demonstrating different quantization strategies and hardware configurations.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     AWS OCP 4.20 Cluster                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────┐  ┌─────────────────────────┐             │
│  │   g6.12xlarge Node 1    │  │   g6.12xlarge Node 2    │             │
│  │   (4x NVIDIA L4)        │  │   (4x NVIDIA L4)        │             │
│  │                         │  │                         │             │
│  │  ┌───────────────────┐  │  │  ┌───────────────────┐  │             │
│  │  │ mistral-3-bf16    │  │  │  │ devstral-2-bf16   │  │             │
│  │  │ tensor-parallel=4 │  │  │  │ tensor-parallel=4 │  │             │
│  │  │ Full Precision    │  │  │  │ Coding Model      │  │             │
│  │  └───────────────────┘  │  │  └───────────────────┘  │             │
│  └─────────────────────────┘  └─────────────────────────┘             │
│                                                                         │
│  ┌─────────────────────────┐                                          │
│  │   g6.4xlarge Node       │                                          │
│  │   (1x NVIDIA L4)        │                                          │
│  │                         │                                          │
│  │  ┌───────────────────┐  │                                          │
│  │  │ mistral-3-fp8     │  │  ← 4x cost reduction vs BF16!           │
│  │  │ FP8 Quantized     │  │                                          │
│  │  │ Neural Magic      │  │                                          │
│  │  └───────────────────┘  │                                          │
│  └─────────────────────────┘                                          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Models Deployed

| Model | Quantization | Hardware | GPUs | VRAM | Use Case |
|-------|-------------|----------|------|------|----------|
| **Mistral 3 24B** | BF16 (Full) | g6.12xlarge | 4 | ~48GB | Production (Quality) |
| **Mistral 3 24B** | FP8 | g6.4xlarge | 1 | ~15GB | Production (Efficiency) |
| **Devstral 2 24B** | BF16 (Full) | g6.12xlarge | 4 | ~48GB | Code Generation |

## Key Demo Points

### 1. FP8 Quantization Advantage

The **Mistral 3 FP8** deployment demonstrates:
- **4x GPU cost reduction** (1 GPU vs 4 GPUs)
- **Native L4 hardware acceleration** (Ada Lovelace FP8 tensor cores)
- **Near-identical accuracy** (Neural Magic optimized kernels)
- **Same API, same prompts** - transparent to applications

```
┌─────────────────────────────────────────────────────────────────┐
│                      Cost Comparison                            │
├─────────────────────────────────────────────────────────────────┤
│  Mistral 3 BF16:  4x L4 GPUs  →  ~$4.00/hour  →  ~$2,900/month │
│  Mistral 3 FP8:   1x L4 GPU   →  ~$1.00/hour  →  ~$730/month   │
│                                                                 │
│  Savings: 75% cost reduction with Neural Magic FP8!            │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Red Hat AI Validated Story

All models are from the **Red Hat AI Validated Collection**:
- Pre-tested on RHOAI 3.0
- Optimized vLLM configurations
- Neural Magic FP8 quantization included
- Support coverage by Red Hat

### 3. Coding Model (Devstral)

Devstral 2 is purpose-built for software development:
- Extended 32K context window for large codebases
- Optimized for code generation, review, and documentation
- Compatible with IDE integrations (Continue, Cursor, etc.)

## Prerequisites

### 1. Scale AWS MachineSets

Before deploying, ensure sufficient GPU nodes:

```bash
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')

# Scale for triple-play deployment (9 GPUs total)
oc scale machineset ${CLUSTER_ID}-gpu-g6-12xlarge -n openshift-machine-api --replicas=2
oc scale machineset ${CLUSTER_ID}-gpu-g6-4xlarge -n openshift-machine-api --replicas=1

# Verify nodes are ready (3-5 minutes)
oc get nodes -l nvidia.com/gpu.product=NVIDIA-L4
```

### 2. Verify Kueue Quota

Ensure ClusterQueue has sufficient GPU quota (minimum 9 GPUs):

```bash
oc get clusterqueue rhoai-cluster-queue -o jsonpath='{.spec.resourceGroups[*].flavors[*].resources}' | jq
```

### 3. Upload Model Weights to MinIO

Models must be available in S3 storage:

```bash
# Example: Download and upload Mistral 3
mc cp -r models/mistral-3-24b-instruct/ minio/models/mistral-3-24b-instruct/
mc cp -r models/mistral-3-24b-instruct-fp8/ minio/models/mistral-3-24b-instruct-fp8/
mc cp -r models/devstral-2-24b/ minio/models/devstral-2-24b/
```

## Deployment

```bash
./steps/step-05-llm-on-vllm/deploy.sh
```

Or apply manually:

```bash
# Apply Kustomize
oc apply -k gitops/step-05-llm-on-vllm/base/

# Watch deployment
oc get inferenceservice -n private-ai -w
```

## Validation

### 1. Check InferenceService Status

```bash
oc get inferenceservice -n private-ai

# Expected output:
NAME               URL                                                            READY
mistral-3-bf16     http://mistral-3-bf16-predictor.private-ai.svc.cluster.local   True
mistral-3-fp8      http://mistral-3-fp8-predictor.private-ai.svc.cluster.local    True
devstral-2-bf16    http://devstral-2-bf16-predictor.private-ai.svc.cluster.local  True
```

### 2. Get External URLs

```bash
# Get routes (OpenAI-compatible endpoints)
oc get route -n private-ai

# Or via HTTPRoute (Gateway API)
oc get httproute -n private-ai
```

### 3. Test Mistral 3 (General Purpose)

```bash
# Internal URL
MISTRAL_BF16="http://mistral-3-bf16-predictor.private-ai.svc.cluster.local"

# Test query
curl -s "${MISTRAL_BF16}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-3-bf16",
    "messages": [{"role": "user", "content": "What is new in Red Hat OpenShift AI 3.0?"}],
    "max_tokens": 200
  }' | jq .
```

### 4. Test Mistral 3 FP8 (Same Quality, Lower Cost)

```bash
MISTRAL_FP8="http://mistral-3-fp8-predictor.private-ai.svc.cluster.local"

curl -s "${MISTRAL_FP8}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-3-fp8",
    "messages": [{"role": "user", "content": "Explain Kubernetes GPU scheduling in 3 sentences."}],
    "max_tokens": 150
  }' | jq .
```

### 5. Test Devstral 2 (Coding)

```bash
DEVSTRAL="http://devstral-2-bf16-predictor.private-ai.svc.cluster.local"

curl -s "${DEVSTRAL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "devstral-2-bf16",
    "messages": [
      {"role": "system", "content": "You are a Kubernetes expert. Write clean, production-ready YAML."},
      {"role": "user", "content": "Write a Kueue ClusterQueue with 4 GPUs quota for NVIDIA L4 nodes."}
    ],
    "max_tokens": 500
  }' | jq -r '.choices[0].message.content'
```

## Monitoring

### GPU Utilization

```bash
# Check GPU utilization via NVIDIA DCGM
oc exec -n nvidia-gpu-operator $(oc get pod -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter -o name | head -1) -- dcgmi dmon -d 1
```

### Kueue Workload Status

```bash
# Check admitted workloads
oc get workload -n private-ai

# Check local queue status
oc get localqueue -n private-ai
```

### InferenceService Logs

```bash
# Mistral 3 BF16 logs
oc logs -n private-ai -l serving.kserve.io/inferenceservice=mistral-3-bf16 -f

# Mistral 3 FP8 logs
oc logs -n private-ai -l serving.kserve.io/inferenceservice=mistral-3-fp8 -f

# Devstral 2 logs
oc logs -n private-ai -l serving.kserve.io/inferenceservice=devstral-2-bf16 -f
```

## Troubleshooting

### InferenceService Stuck in "Not Ready"

```bash
# Check pod status
oc get pods -n private-ai -l serving.kserve.io/inferenceservice=mistral-3-bf16

# Check events
oc get events -n private-ai --sort-by='.lastTimestamp'

# Common issues:
# 1. Insufficient GPU quota → Scale MachineSets
# 2. Model not in S3 → Upload weights to MinIO
# 3. Image pull error → Check registry credentials
```

### Kueue Workload Pending

```bash
# Check workload status
oc describe workload -n private-ai

# Check ClusterQueue capacity
oc get clusterqueue -o yaml
```

## API Reference

All endpoints are OpenAI-compatible:

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Health check |
| `GET /v1/models` | List available models |
| `POST /v1/chat/completions` | Chat completions API |
| `POST /v1/completions` | Text completions API |
| `POST /v1/embeddings` | Embeddings (if supported) |

## GitOps Structure

```
gitops/step-05-llm-on-vllm/base/
├── kustomization.yaml
├── model-registration/
│   ├── kustomization.yaml
│   └── seed-job.yaml          # Register 3 models in Registry
├── serving-runtime/
│   ├── kustomization.yaml
│   └── vllm-runtime.yaml      # vLLM ServingRuntime
└── inference/
    ├── kustomization.yaml
    ├── mistral-3-bf16.yaml    # 4-GPU, BF16
    ├── mistral-3-fp8.yaml     # 1-GPU, FP8
    └── devstral-2-bf16.yaml   # 4-GPU, Coding
```

## Next Steps

- **Step 06**: RAG Pipeline with LangChain
- **Step 07**: Agent Playground with Bee Framework
