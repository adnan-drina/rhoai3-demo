# Step 05: LLM Serving with vLLM

Deploy production-grade LLMs using vLLM on RHOAI 3.0 with **Red Hat Validated ModelCar images** and **S3 storage**.

## Storage Strategy: OCI vs S3

### ⚠️ OCI Image Size Limitation

**Critical Discovery:** OCI ModelCar images larger than ~20GB can cause CRI-O overlay filesystem failures:

```
Error: unpacking failed: write /models/model-00009-of-00010.safetensors: no space left on device
```

This occurs because CRI-O's overlay filesystem has limited capacity for extracting large container layers, even when the node has sufficient disk space.

### Recommended Approach

| Model Size | Storage Method | Example |
|------------|---------------|---------|
| **< 20GB** | OCI ModelCar ✅ | INT4 quantized (~13.5GB) |
| **> 20GB** | S3/MinIO ✅ | BF16 full precision (~48GB) |

### Our Deployment

| Model | Size | Storage | Source |
|-------|------|---------|--------|
| **mistral-small-24b** (INT4) | ~13.5GB | **OCI** | `registry.redhat.io/rhelai1/modelcar-mistral-...-quantized-w4a16:1.5` |
| **mistral-small-24b-tp4** (BF16) | ~48GB | **S3** | `s3://models/mistral-small-24b/` (MinIO) |

## Why Red Hat ModelCars?

| Aspect | Custom OCI Build | **Red Hat ModelCar** |
|--------|------------------|----------------------|
| **Validation** | DIY testing | Red Hat tested |
| **Support** | Community | Red Hat supported |
| **Compatibility** | Unknown | RHOAI 3.0 certified |
| **Size Limit** | ~20GB max | ~20GB max |

> **Red Hat Recommendation:** Use ModelCar images for quantized models (<20GB). For full-precision models (>20GB), use S3/MinIO storage with the KServe storage-initializer.

## Architecture Overview

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
│  │  │ mistral-small-24b │  │  │  │ mistral-small-24b │  │              │
│  │  │     -tp4 (BF16)   │  │  │  │   (INT4 W4A16)    │  │              │
│  │  │ S3 → Storage Init │  │  │  │ OCI ModelCar      │  │              │
│  │  │ 32k context, 96GB │  │  │  │ 4k context, 24GB  │  │              │
│  │  └───────────────────┘  │  │  └───────────────────┘  │              │
│  └─────────────────────────┘  └─────────────────────────┘              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Model Comparison

| Model | Variant | Hardware | VRAM (Weights) | Context | Status |
|-------|---------|----------|----------------|---------|--------|
| **Mistral 24B** | BF16 | 4x L4 (TP4) | ~48GB | 32k | ✅ Working |
| **Mistral 24B** | FP8 | 1x L4 | ~22GB | ❌ OOM | ⛔ Too large |
| **Mistral 24B** | **INT4 W4A16** | 1x L4 | **~13.5GB** | 4k | 🏆 **Red Hat Validated** |
| Granite 8B | FP8 | 1x L4 | ~8.5GB | 16k+ | ⚡ Alt option |

> **Why INT4?** FP8 (1 byte/param × 24B = 24GB) exceeds L4 capacity. INT4 W4A16 (0.5 bytes/param × 24B = 13.5GB) leaves 8.5GB for KV cache.
> 
> **Red Hat Validated:** `registry.redhat.io/rhelai1/modelcar-mistral-small-24b-instruct-2501-quantized-w4a16:1.5` - 98.9% accuracy recovery

## Models Deployed

| Model | Quantization | Hardware | GPUs | VRAM | Use Case |
|-------|-------------|----------|------|------|----------|
| **mistral-small-24b-tp4** | BF16 (Full) | g6.12xlarge | 4 | ~48GB | High-throughput |
| **mistral-small-24b** | INT4 W4A16 | g6.4xlarge | 1 | ~13.5GB | Cost-efficient |

## Key Demo Points

### 1. INT4 W4A16 Quantization (Red Hat Validated)

The **INT4 deployment** demonstrates:
- **4x GPU cost reduction** (1 GPU vs 4 GPUs)
- **98.9% accuracy recovery** (Neural Magic validated)
- **Red Hat ModelCar** - pre-built, validated OCI image
- **Same API, same prompts** - transparent to applications
- **Fits on L4** where FP8 does not (21.5GB > 24GB limit)

```
┌─────────────────────────────────────────────────────────────────┐
│                      Cost Comparison                            │
├─────────────────────────────────────────────────────────────────┤
│  Mistral BF16:  4x L4 GPUs  →  ~$4.00/hour  →  ~$2,900/month   │
│  Mistral INT4:  1x L4 GPU   →  ~$1.00/hour  →  ~$730/month     │
│                                                                 │
│  Savings: 75% cost reduction with Neural Magic INT4!           │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Why Not FP8?

A 24B parameter model in FP8 requires exactly **24GB** of memory:
- 24 billion parameters × 1 byte = 24GB
- NVIDIA L4 has 24GB VRAM
- Driver/kernel overhead: ~1.2GB
- **Result:** No room for KV cache → OOM

INT4 W4A16 uses **0.5 bytes per parameter**:
- 24B × 0.5 bytes = 12GB weights + quantization overhead = ~13.5GB
- Remaining for KV cache: ~8.5GB
- **Supports 4k context window**

### 3. Red Hat Validated ModelCar

The 1-GPU model uses a **Red Hat Validated ModelCar**:

```
oci://registry.redhat.io/rhelai1/modelcar-mistral-small-24b-instruct-2501-quantized-w4a16:1.5
```

Benefits:
- Pre-built, tested OCI image
- No S3 upload required
- Validated for RHOAI 3.0
- 98.9% accuracy vs full precision

### 4. Dual Storage Patterns

We use both patterns based on model size:

**OCI ModelCar (for < 20GB models):**
- Pre-built container image with model weights
- Direct pod startup, no init container
- Used for: INT4 quantized (~13.5GB)

**S3 Storage (for > 20GB models):**
- Thin runtime image (~3GB)
- Storage-initializer downloads weights at startup
- Used for: BF16 full precision (~48GB)

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

### 3. Test Mistral AWQ (1-GPU, Same Quality)

```bash
MISTRAL_AWQ="http://mistral-small-24b.private-ai.svc.cluster.local"

curl -s "${MISTRAL_AWQ}/v1/chat/completions" \
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

### OCI Image Pull Fails: "No Space Left on Device"

**Symptom:**
```
Error: unpacking failed: write /models/model-00009-of-00010.safetensors: no space left on device
```

**Cause:** OCI ModelCar image exceeds CRI-O overlay filesystem limits (~20GB).

**Solution:** Use S3/MinIO storage instead of OCI for models > 20GB:

```yaml
# Instead of:
storageUri: oci://registry.redhat.io/rhelai1/modelcar-mistral-...:1.5

# Use:
storageUri: s3://models/mistral-small-24b/
storage:
  key: minio-connection
```

**Prevention:**
- Use OCI ModelCar only for quantized models < 20GB (INT4, FP8)
- Use S3 storage for full-precision models > 20GB (BF16, FP32)

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

### CUDA Driver Error 803

**Symptom:**
```
RuntimeError: Unexpected error from cudaGetDeviceCount()... Error 803: system has unsupported display driver / cuda driver combination
```

**Cause:** NVIDIA driver 580.x (CUDA 13.0) is incompatible with RHOAI 3.0's vLLM image (CUDA 12.x).

**Solution:** Downgrade GPU driver to 570.195.03 per [Red Hat KB 7134740](https://access.redhat.com/solutions/7134740):

```yaml
# In ClusterPolicy:
spec:
  driver:
    repository: nvcr.io/nvidia
    image: driver
    version: "570.195.03"
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
│   ├── mistral-small-24b.yaml     # 1-GPU, INT4 W4A16, OCI ModelCar
│   └── mistral-small-24b-tp4.yaml # 4-GPU, BF16, S3 storage
└── model-upload/                   # For S3-based models only
    ├── kustomization.yaml
    └── upload-mistral-bf16.yaml   # BF16 model for 4-GPU (~50GB)
```

### Storage Strategy by Model Size

| Model | Size | Storage | InferenceService Config |
|-------|------|---------|------------------------|
| INT4 (quantized) | ~13.5GB | OCI | `storageUri: oci://registry.redhat.io/...` |
| BF16 (full) | ~48GB | S3 | `storageUri: s3://models/...` + `storage.key` |

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
