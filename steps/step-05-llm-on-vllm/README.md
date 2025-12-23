# Step 05: High-Efficiency LLM Inference with vLLM

Deploys **Mistral-Small-24B** in two configurations to demonstrate FP8 efficiency on NVIDIA L4 GPUs.

---

## The L4 Advantage: FP8 Quantization

The **NVIDIA L4** GPU (Ada Lovelace architecture) provides **native hardware acceleration for FP8** math, making it the optimal choice for cost-efficient LLM inference.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        FP8 vs BF16 Comparison                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Mistral-24B (BF16)                  Mistral-24B (FP8)                    │
│   ══════════════════                  ═══════════════════                  │
│                                                                             │
│   ┌───┐ ┌───┐ ┌───┐ ┌───┐            ┌───┐                                │
│   │L4 │ │L4 │ │L4 │ │L4 │            │L4 │  ~15GB VRAM                    │
│   └───┘ └───┘ └───┘ └───┘            └───┘                                │
│                                                                             │
│   4x GPUs (64GB total)                1x GPU (16GB)                        │
│   ~$4.00/hr on AWS                    ~$1.00/hr on AWS                     │
│   Maximum quality                     Near-identical accuracy              │
│   Tensor parallelism                  FP8 hardware acceleration            │
│                                                                             │
│   ────────────────────────────────────────────────────────────────────     │
│   Result: 4x cost reduction with minimal accuracy loss                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Red Hat Validated: Neural Magic Partnership

> "OpenShift AI 3.0 supports FP8 quantization through the vLLM runtime. This allows larger models to be served on hardware with smaller memory footprints, such as the NVIDIA L4, without significant impact on perplexity or latency."
> — [RHOAI 3.0 GA Serving Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index)

Red Hat collaborates with **Neural Magic** to provide optimized FP8 kernels in the vLLM runtime:
- Pre-quantized model weights
- Optimized CUDA kernels for Ada Lovelace
- Validated accuracy benchmarks

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          private-ai namespace                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                    Model Registry (Step 04)                         │  │
│   │   ┌─────────────────────────┐   ┌─────────────────────────┐        │  │
│   │   │ Mistral-24B-BF16        │   │ Mistral-24B-FP8         │        │  │
│   │   │ s3://rhoai-artifacts/...│   │ s3://rhoai-artifacts/...│        │  │
│   │   └─────────────────────────┘   └─────────────────────────┘        │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                    │                            │                          │
│                    ▼                            ▼                          │
│   ┌────────────────────────────┐   ┌────────────────────────────┐         │
│   │ InferenceService           │   │ InferenceService           │         │
│   │ mistral-24b-full           │   │ mistral-24b-fp8            │         │
│   │                            │   │                            │         │
│   │ vLLM Runtime               │   │ vLLM Runtime               │         │
│   │ --tensor-parallel-size 4   │   │ --quantization fp8         │         │
│   │ --dtype bfloat16           │   │ --kv-cache-dtype fp8       │         │
│   │                            │   │                            │         │
│   │ ┌───┐┌───┐┌───┐┌───┐      │   │ ┌───┐                      │         │
│   │ │L4 ││L4 ││L4 ││L4 │      │   │ │L4 │ 15GB used            │         │
│   │ └───┘└───┘└───┘└───┘      │   │ └───┘                      │         │
│   └────────────────────────────┘   └────────────────────────────┘         │
│                                                                             │
│   API: OpenAI-compatible (/v1/chat/completions)                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Deployments

### Deployment A: Full Precision (BF16)

| Property | Value |
|----------|-------|
| **Name** | `mistral-24b-full` |
| **Model** | Mistral-Small-24B-Instruct |
| **Precision** | BF16 (bfloat16) |
| **GPUs** | 4x NVIDIA L4 |
| **VRAM** | ~48GB across 4 GPUs |
| **vLLM Args** | `--tensor-parallel-size 4 --dtype bfloat16` |
| **Use Case** | Maximum quality, research workloads |

### Deployment B: FP8 Quantized (Recommended)

| Property | Value |
|----------|-------|
| **Name** | `mistral-24b-fp8` |
| **Model** | Mistral-Small-24B-Instruct-FP8 (Neural Magic) |
| **Precision** | FP8 |
| **GPUs** | 1x NVIDIA L4 |
| **VRAM** | ~15GB |
| **vLLM Args** | `--quantization fp8 --kv-cache-dtype fp8` |
| **Use Case** | Cost-efficient production inference |

---

## Prerequisites

- [x] Step 01: GPU infrastructure (NVIDIA L4 nodes)
- [x] Step 02: RHOAI 3.0 with KServe
- [x] Step 03: MinIO storage
- [x] Step 04: Model Registry configured

---

## Deploy

```bash
./steps/step-05-llm-on-vllm/deploy.sh
```

---

## Validation Commands

### 1. Check InferenceServices

```bash
# Check both deployments
oc get inferenceservice -n private-ai

# Expected output:
# NAME              URL                                    READY
# mistral-24b-full  https://mistral-24b-full-private...    True
# mistral-24b-fp8   https://mistral-24b-fp8-private...     True
```

### 2. Check GPU Allocation

```bash
# View GPU usage via NVIDIA DCGM Dashboard
# Or check pod resources:
oc get pods -n private-ai -l serving.kserve.io/inferenceservice -o wide

# Check GPU requests
oc describe pod -n private-ai -l serving.kserve.io/inferenceservice=mistral-24b-fp8 | grep -A5 "Limits:"
```

### 3. Check Model Registry

```bash
# Verify models are registered
oc run test-api --rm -i --restart=Never \
  --image=curlimages/curl -n rhoai-model-registries -- \
  curl -sf http://private-ai-registry-internal:8080/api/model_registry/v1alpha3/registered_models | grep -i mistral
```

---

## API Usage

Both endpoints expose an **OpenAI-compatible API**.

### Test FP8 Endpoint

```bash
# Get the route URL
FP8_URL=$(oc get route mistral-24b-fp8 -n private-ai -o jsonpath='{.spec.host}')

# Chat completion
curl -X POST "https://${FP8_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-24b-fp8",
    "messages": [
      {"role": "user", "content": "Explain FP8 quantization in one paragraph."}
    ],
    "max_tokens": 256,
    "temperature": 0.7
  }'
```

### Test BF16 Endpoint

```bash
# Get the route URL
FULL_URL=$(oc get route mistral-24b-full -n private-ai -o jsonpath='{.spec.host}')

# Chat completion
curl -X POST "https://${FULL_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-24b-full",
    "messages": [
      {"role": "user", "content": "Explain tensor parallelism in one paragraph."}
    ],
    "max_tokens": 256,
    "temperature": 0.7
  }'
```

### Compare Performance

```bash
# Measure Time to First Token (TTFT) for both endpoints
# FP8 should show comparable latency despite using 4x fewer GPUs

time curl -X POST "https://${FP8_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model": "mistral-24b-fp8", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 1}'

time curl -X POST "https://${FULL_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model": "mistral-24b-full", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 1}'
```

---

## Demo Walkthrough

### 1. Show Hardware Awareness

Open the **NVIDIA DCGM Dashboard** (from Step 01):
- Point out that the FP8 version uses **only ~15GB of VRAM**
- The BF16 version distributes load across 4 GPUs

### 2. Show Performance

Prompt both models with the same query:
- The FP8 version on a single GPU generates tokens **almost as fast** as the 4-GPU BF16 version
- This demonstrates incredible cost-to-performance gains

### 3. Show Governance

In the RHOAI Dashboard:
- Navigate to **Settings → Model registries**
- Show that both models were deployed from the **Model Registry**
- This ensures developers use "Company Approved" Mistral weights

---

## Kustomize Structure

```
gitops/step-05-llm-on-vllm/
├── base/
│   ├── kustomization.yaml
│   │
│   ├── model-registration/          # Register Mistral variants
│   │   ├── kustomization.yaml
│   │   └── seed-job.yaml
│   │
│   ├── serving-runtime/             # vLLM runtime
│   │   ├── kustomization.yaml
│   │   └── vllm-runtime.yaml
│   │
│   └── inference/                   # InferenceServices
│       ├── kustomization.yaml
│       ├── mistral-24b-full.yaml    # 4-GPU BF16
│       └── mistral-24b-fp8.yaml     # 1-GPU FP8
```

---

## Documentation Links

- [RHOAI 3.0 Serving Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index)
- [Run Mistral on vLLM (Red Hat Developer)](https://developers.redhat.com/articles/2025/12/02/run-mistral-large-3-ministral-3-vllm-red-hat-ai)
- [Neural Magic Mistral FP8](https://huggingface.co/neuralmagic/Mistral-Small-Instruct-24B-FP8)
- [vLLM Documentation](https://docs.vllm.ai/)

---

## Summary

| Deployment | GPUs | VRAM | Hourly Cost | Use Case |
|------------|------|------|-------------|----------|
| `mistral-24b-full` | 4x L4 | ~48GB | ~$4.00 | Maximum quality |
| `mistral-24b-fp8` | 1x L4 | ~15GB | ~$1.00 | **Recommended** for production |

**Key Takeaway**: FP8 quantization on NVIDIA L4 delivers **4x cost reduction** with **near-identical accuracy** thanks to Ada Lovelace's native FP8 hardware acceleration and Neural Magic's optimized kernels.
