# Step 05: LLM Serving with vLLM (Official S3 Storage Approach)

Deploy production-grade LLMs using vLLM on RHOAI 3.0, following the **official Red Hat recommended S3 storage pattern**.

## Why S3 Storage? (Not OCI Images)

| Aspect | OCI Monolithic Image | **S3 Storage (Official)** |
|--------|---------------------|---------------------------|
| **Image Size** | 94GB+ per model | 3GB runtime only |
| **Pull Time** | 20-45 minutes | Seconds (streaming) |
| **CRI-O Issues** | Image ID failures | None |
| **Disk Usage** | 188GB (overlay+cache) | Model size only |
| **Scalability** | Limited | Production-ready |

> **Red Hat Recommendation:** "For Large Language Models, use S3-compatible storage. This allows the KServe storage-initializer to download weights directly to the node's ephemeral storage, avoiding container runtime issues with massive images."

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     AWS OCP 4.20 Cluster                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      MinIO Storage                               │   │
│  │  s3://models/mistral-small-24b/         (~50GB BF16)            │   │
│  │  s3://models/mistral-small-24b-fp8/     (~25GB FP8)             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│              KServe Storage Initializer downloads at pod startup        │
│                              ▼                                          │
│  ┌─────────────────────────┐  ┌─────────────────────────┐              │
│  │   g6.12xlarge Node      │  │   g6.4xlarge Node       │              │
│  │   (4x NVIDIA L4)        │  │   (1x NVIDIA L4)        │              │
│  │                         │  │                         │              │
│  │  ┌───────────────────┐  │  │  ┌───────────────────┐  │              │
│  │  │ mistral-small-24b │  │  │  │ mistral-small-24b │  │              │
│  │  │     -tp4          │  │  │  │     (FP8)         │  │              │
│  │  │ tensor-parallel=4 │  │  │  │ --quantization fp8│  │              │
│  │  │ --dtype bfloat16  │  │  │  │ 4x cost savings!  │  │              │
│  │  └───────────────────┘  │  │  └───────────────────┘  │              │
│  └─────────────────────────┘  └─────────────────────────┘              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Models Deployed

| Model | Quantization | Hardware | GPUs | VRAM | Use Case |
|-------|-------------|----------|------|------|----------|
| **mistral-small-24b-tp4** | BF16 (Full) | g6.12xlarge | 4 | ~48GB | High-throughput |
| **mistral-small-24b** | FP8 | g6.4xlarge | 1 | ~15GB | Cost-efficient |

## Key Demo Points

### 1. FP8 Quantization Advantage

The **FP8 deployment** demonstrates:
- **4x GPU cost reduction** (1 GPU vs 4 GPUs)
- **Native L4 hardware acceleration** (Ada Lovelace FP8 tensor cores)
- **Near-identical accuracy** (Neural Magic optimized kernels)
- **Same API, same prompts** - transparent to applications

```
┌─────────────────────────────────────────────────────────────────┐
│                      Cost Comparison                            │
├─────────────────────────────────────────────────────────────────┤
│  Mistral BF16:  4x L4 GPUs  →  ~$4.00/hour  →  ~$2,900/month   │
│  Mistral FP8:   1x L4 GPU   →  ~$1.00/hour  →  ~$730/month     │
│                                                                 │
│  Savings: 75% cost reduction with Neural Magic FP8!            │
└─────────────────────────────────────────────────────────────────┘
```

### 2. S3 Storage Pattern

The official RHOAI approach:
1. **Thin Runtime Image** (~3GB): Just the vLLM engine
2. **Model in S3**: Weights stored in MinIO/S3
3. **Storage Initializer**: Downloads weights at pod startup
4. **Ephemeral Cache**: Uses node-local storage, not overlay

## Prerequisites

### 1. Scale AWS MachineSets

```bash
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')

# Scale for dual deployment (5 GPUs total: 4 + 1)
oc scale machineset ${CLUSTER_ID}-gpu-g6-12xlarge-us-east-2b -n openshift-machine-api --replicas=1
oc scale machineset ${CLUSTER_ID}-gpu-g6-4xlarge-us-east-2b -n openshift-machine-api --replicas=1

# Verify nodes are ready (3-5 minutes)
oc get nodes -l nvidia.com/gpu.product=NVIDIA-L4
```

### 2. Upload Model Weights to MinIO

**Option A: Use the helper job (recommended for demo)**

```bash
# Create HuggingFace token secret (for gated model access)
oc create secret generic hf-token -n private-ai --from-literal=token=hf_xxxYOURTOKENxxx

# Run upload job
oc apply -f gitops/step-05-llm-on-vllm/base/model-upload/upload-mistral-job.yaml

# Monitor progress (~30-60 minutes)
oc logs -f job/upload-mistral-to-minio -n private-ai
```

**Option B: Manual upload with mc client**

```bash
# Configure mc (MinIO client)
mc alias set minio http://minio.minio-storage.svc:9000 rhoai-access-key rhoai-secret-key-12345

# Upload pre-downloaded model weights
mc cp -r /path/to/mistral-small-24b/ minio/models/mistral-small-24b/
mc cp -r /path/to/mistral-small-24b-fp8/ minio/models/mistral-small-24b-fp8/

# Verify
mc ls minio/models/
```

### 3. Verify storage-config Secret

```bash
# Check secret exists with MinIO credentials
oc get secret storage-config -n private-ai -o jsonpath='{.data.minio-connection}' | base64 -d | jq
```

## Deployment

```bash
./steps/step-05-llm-on-vllm/deploy.sh
```

Or apply manually:

```bash
# Apply Kustomize
oc apply -k gitops/step-05-llm-on-vllm/base/

# Watch deployment (storage-initializer downloads first, then model loads)
oc get inferenceservice -n private-ai -w
```

## Validation

### 1. Check InferenceService Status

```bash
oc get inferenceservice -n private-ai

# Expected output:
NAME                   URL                                                               READY
mistral-small-24b      http://mistral-small-24b.private-ai.svc.cluster.local             True
mistral-small-24b-tp4  http://mistral-small-24b-tp4.private-ai.svc.cluster.local         True
```

### 2. Test Mistral (4-GPU BF16)

```bash
MISTRAL_TP4="http://mistral-small-24b-tp4.private-ai.svc.cluster.local"

curl -s "${MISTRAL_TP4}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-24b-tp4",
    "messages": [{"role": "user", "content": "What is new in Red Hat OpenShift AI 3.0?"}],
    "max_tokens": 200
  }' | jq .
```

### 3. Test Mistral FP8 (1-GPU, Same Quality)

```bash
MISTRAL_FP8="http://mistral-small-24b.private-ai.svc.cluster.local"

curl -s "${MISTRAL_FP8}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-small-24b",
    "messages": [{"role": "user", "content": "Explain Kubernetes GPU scheduling in 3 sentences."}],
    "max_tokens": 150
  }' | jq .
```

## Monitoring

### Pod Startup (Watch Storage Initializer)

```bash
# Watch pod progress
oc get pods -n private-ai -l serving.kserve.io/inferenceservice -w

# Storage initializer logs (downloading from S3)
oc logs -n private-ai -l serving.kserve.io/inferenceservice=mistral-small-24b -c storage-initializer
```

### GPU Utilization

```bash
# Check GPU utilization via NVIDIA DCGM
oc exec -n nvidia-gpu-operator $(oc get pod -n nvidia-gpu-operator -l app=nvidia-dcgm-exporter -o name | head -1) -- dcgmi dmon -d 1
```

## Troubleshooting

### Storage Initializer Stuck

```bash
# Check init container logs
oc logs -n private-ai <pod-name> -c storage-initializer

# Common issues:
# 1. "Access Denied" → Check storage-config secret
# 2. "No such bucket" → Ensure model is uploaded to MinIO
# 3. "Connection refused" → Check MinIO service is running
```

### Model Loading Slow

```bash
# Check node ephemeral storage
oc describe node <gpu-node> | grep -A5 "Allocated resources"

# Ensure node has enough ephemeral storage (100GB+)
# Model download to /mnt/models can be 50GB+
```

### Kueue Workload Pending

```bash
# Check GPU quota
oc get clusterqueue rhoai-main-queue -o yaml | grep -A10 nominalQuota

# Ensure quota >= 5 GPUs (4 + 1)
```

## GitOps Structure

```
gitops/step-05-llm-on-vllm/base/
├── kustomization.yaml
├── model-registration/
│   ├── kustomization.yaml
│   └── seed-job.yaml              # Register models in Registry
├── serving-runtime/
│   ├── kustomization.yaml
│   └── vllm-runtime.yaml          # Thin vLLM runtime (~3GB)
├── inference/
│   ├── kustomization.yaml
│   ├── mistral-small-24b.yaml     # 1-GPU, FP8, S3 storage
│   └── mistral-small-24b-tp4.yaml # 4-GPU, BF16, S3 storage
└── model-upload/                   # Optional: Helper for demo
    ├── kustomization.yaml
    └── upload-mistral-job.yaml     # Downloads from HF, uploads to MinIO
```

## API Reference

All endpoints are OpenAI-compatible:

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Health check |
| `GET /v1/models` | List available models |
| `POST /v1/chat/completions` | Chat completions API |
| `POST /v1/completions` | Text completions API |

## Official Documentation

- [RHOAI 3.0 Deploying Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index)
- [KServe Storage Configuration](https://kserve.github.io/website/latest/modelserving/storage/)
- [vLLM Serving Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#supported-model-serving-runtimes_serving)

## Next Steps

- **Step 06**: RAG Pipeline with LangChain
- **Step 07**: Agent Playground with Bee Framework
