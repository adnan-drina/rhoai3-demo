# Step 05: GPU-as-a-Service Demo

**"Enterprise Model Portfolio"** - Demonstrating RHOAI 3.3's intelligent GPU allocation with Kueue and 5 Red Hat Validated models.

## The Business Story

In enterprise environments, GPU resources are expensive and shared. Teams can't hoard GPUs indefinitely. **GPU-as-a-Service** means:

1. **Fair Allocation**: Quotas prevent any single team from monopolizing resources
2. **Dynamic Handover**: When one workload finishes, another automatically starts
3. **Predictable Queuing**: Developers know exactly when their job will run
4. **Model Portfolio**: Multiple specialized models available on-demand

## Demo Overview

### GPU Configuration (Sandbox-Optimized)

| Node | Instance | GPUs | vCPU | Active Model |
|------|----------|------|------|-------------|
| GPU Worker 1 | g6.4xlarge | 1x L4 | 16 | `granite-8b-agent` (FP8) |
| GPU Worker 2 | g6.12xlarge | 4x L4 | 48 | `mistral-3-bf16` (BF16) |
| **Total** | | **5 GPUs** | **64 vCPU** | Fits 64 GPU vCPU sandbox limit |

### Enterprise Model Portfolio (5 Red Hat Validated Models)

| Model | GPUs | Status | Node | Use Case |
|-------|------|--------|------|----------|
| **granite-8b-agent** | 1 | ✅ Active | g6.4xlarge | RAG, MCP, Guardrails, Playground |
| **mistral-3-bf16** | 4 | ✅ Active | g6.12xlarge | Full-precision LLM, Playground |
| **mistral-3-int4** | 1 | ⏸️ Queued | (swap with granite-8b) | Cost-efficient chat (75% savings) |
| **devstral-2** | 4 | ⏸️ Queued | (swap with mistral-bf16) | Agentic tool-calling |
| **gpt-oss-20b** | 4 | ⏸️ Queued | (swap with mistral-bf16) | High-reasoning |

**Total Potential:** 14 GPUs | **Quota Limit:** 5 GPUs | **Active:** 5/5

### Demo Scenarios

```
═══════════════════════════════════════════════════════════════
SCENARIO 1: 4-GPU MODEL SWAP
───────────────────────────────────────────────────────────────
Story: "Switch from general-purpose Mistral to high-reasoning GPT-OSS"

Before: granite-8b (1) + mistral-bf16 (4) = 5 GPUs
Action: Scale bf16 → 0, scale gpt-oss-20b → 1
After:  granite-8b (1) + gpt-oss-20b (4) = 5 GPUs

═══════════════════════════════════════════════════════════════
SCENARIO 2: 1-GPU MODEL SWAP
───────────────────────────────────────────────────────────────
Story: "Switch agent model to quantized chat model"

Before: granite-8b (1) + mistral-bf16 (4) = 5 GPUs
Action: Scale granite-8b → 0, scale mistral-int4 → 1
After:  mistral-int4 (1) + mistral-bf16 (4) = 5 GPUs

═══════════════════════════════════════════════════════════════
SCENARIO 3: FULL SWAP (both nodes)
───────────────────────────────────────────────────────────────
Story: "Completely different model portfolio, same hardware"

Before: granite-8b (1) + mistral-bf16 (4) = 5 GPUs
Action: Scale both → 0, enable gpt-oss-20b + mistral-int4
After:  mistral-int4 (1) + gpt-oss-20b (4) = 5 GPUs

═══════════════════════════════════════════════════════════════
THE KEY MESSAGE:
"This is GPU-as-a-Service. 5 models registered, 2 active at
any time, swappable on demand. Kueue enforces quotas while
Model Registry provides governance."
═══════════════════════════════════════════════════════════════
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
│  │  s3://models/granite-8b  │  │  modelcar-...-quantized-w4a16:1.5  │  │
│  │  s3://models/gpt-oss-20b │  │  (~13.5GB INT4)                    │  │
│  └──────────────────────────┘  └────────────────────────────────────┘  │
│              │                                    │                     │
│              ▼                                    ▼                     │
│  ┌─────────────────────────┐  ┌─────────────────────────┐              │
│  │   g6.12xlarge Node      │  │   g6.4xlarge Node       │              │
│  │   (4x NVIDIA L4)        │  │   (1x NVIDIA L4)        │              │
│  │                         │  │                         │              │
│  │  ┌───────────────────┐  │  │  ┌───────────────────┐  │              │
│  │  │ mistral-3-bf16    │  │  │  │ granite-8b-agent  │  │              │
│  │  │      OR           │  │  │  │      OR           │  │              │
│  │  │ gpt-oss-20b       │  │  │  │ mistral-3-int4    │  │              │
│  │  │ (swapped via Kueue)│ │  │  │ (swapped via Kueue)│ │              │
│  │  └───────────────────┘  │  │  └───────────────────┘  │              │
│  └─────────────────────────┘  └─────────────────────────┘              │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        Kueue Controller                          │   │
│  │  ClusterQueue: rhoai-main-queue (1 + 4 = 5 GPUs quota)         │   │
│  │  ResourceFlavors: default-flavor, nvidia-l4-1gpu, nvidia-l4-4gpu│   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Model Portfolio

### Active Models (Baseline)

| Name | GPUs | Hardware | Storage | Provider | Description |
|------|------|----------|---------|----------|-------------|
| **granite-8b-agent** | 1 | g6.4xlarge | S3 | IBM/Red Hat | RAG, MCP tools, Guardrails, Eval (Steps 06-10) |
| **mistral-3-bf16** | 4 | g6.12xlarge | S3 | Mistral AI | Full-precision 24B LLM, Playground chat |

### Queued Models (Swap to Activate)

| Name | GPUs | Hardware | Storage | Provider | Swap With |
|------|------|----------|---------|----------|-----------|
| **mistral-3-int4** | 1 | g6.4xlarge | OCI | Neural Magic | granite-8b-agent |
| **devstral-2** | 4 | g6.12xlarge | S3 | Mistral AI | mistral-3-bf16 |
| **gpt-oss-20b** | 4 | g6.12xlarge | S3 | RedHatAI | mistral-3-bf16 |

### Storage Strategy

| Model Size | Storage | Why |
|------------|---------|-----|
| **< 20GB** | OCI ModelCar | Fits in CRI-O overlay |
| **> 20GB** | S3/MinIO | Avoids "no space left on device" |

## Prerequisites

### 1. GPU Nodes

```bash
# Verify GPU nodes are Ready
oc get nodes -l node-role.kubernetes.io/gpu -o custom-columns='NAME:.metadata.name,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,GPU:.status.allocatable.nvidia\.com/gpu'

# Expected:
# NAME          TYPE           GPU
# ip-...        g6.4xlarge     1
# ip-...        g6.12xlarge    4
```

### 2. Upload Models to MinIO

```bash
# Create HuggingFace token secret
oc create secret generic hf-token -n minio-storage --from-literal=token=hf_xxxYOURTOKENxxx

# Upload models (granite-8b is fastest ~10 min, mistral-bf16 ~30 min, gpt-oss ~30 min)
oc apply -f gitops/step-05-llm-on-vllm/base/model-upload/upload-granite-8b.yaml
oc apply -f gitops/step-05-llm-on-vllm/base/model-upload/upload-mistral-bf16.yaml
oc apply -f gitops/step-05-llm-on-vllm/base/model-upload/upload-gpt-oss-20b.yaml
```

### 3. Verify Kueue Quota

```bash
oc get clusterqueue rhoai-main-queue -o yaml | grep -A20 "resourceGroups"
# Should show: default-flavor (0 GPU), nvidia-l4-1gpu (1 GPU), nvidia-l4-4gpu (4 GPU)
```

## Deployment

### A) One-shot (recommended)

```bash
CONFIRM=true ./steps/step-05-llm-on-vllm/deploy.sh
```

### B) Step-by-step

```bash
# 1. Apply active models FIRST (get admitted by Kueue)
oc apply -f gitops/step-05-llm-on-vllm/base/serving-runtime/vllm-runtime.yaml
oc apply -f gitops/step-05-llm-on-vllm/base/inference/granite-8b-agent.yaml
oc apply -f gitops/step-05-llm-on-vllm/base/inference/mistral-3-bf16.yaml

# 2. Wait for active models to be Ready
oc get inferenceservice -n private-ai -w
# Wait until granite-8b-agent and mistral-3-bf16 show Ready=True

# 3. Then deploy queued models (minReplicas: 0)
oc apply -f gitops/step-05-llm-on-vllm/base/inference/mistral-3-int4.yaml
oc apply -f gitops/step-05-llm-on-vllm/base/inference/devstral-2.yaml
oc apply -f gitops/step-05-llm-on-vllm/base/inference/gpt-oss-20b.yaml
```

> **Important**: Deploy active models BEFORE queued models. Kueue admits in creation order —
> if a queued 4-GPU model is created before the active 4-GPU model, it grabs the quota first.

## Running the Demo: Model Swapping

### Swap 4-GPU Model (bf16 → gpt-oss-20b)

```bash
# Scale down mistral-3-bf16
oc patch inferenceservice mistral-3-bf16 -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":0}}}'

# Scale up gpt-oss-20b
oc patch inferenceservice gpt-oss-20b -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":1}}}'

# Watch the swap
oc get inferenceservice -n private-ai -w
```

### Swap 1-GPU Model (granite-8b → mistral-int4)

```bash
# Scale down granite-8b-agent
oc patch inferenceservice granite-8b-agent -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":0}}}'

# Scale up mistral-3-int4
oc patch inferenceservice mistral-3-int4 -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":1}}}'

# Watch the swap
oc get inferenceservice -n private-ai -w
```

### Reset to Baseline

```bash
# Restore active models
oc patch inferenceservice granite-8b-agent -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":1}}}'
oc patch inferenceservice mistral-3-bf16 -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":1}}}'

# Scale down swapped models
oc patch inferenceservice gpt-oss-20b -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":0}}}'
oc patch inferenceservice mistral-3-int4 -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":0}}}'
```

## Validation

### Test Active Models

```bash
# Granite-8B Agent (1-GPU) — the demo workhorse
curl -s -k https://granite-8b-agent-private-ai.apps.<cluster>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "granite-8b-agent", "messages": [{"role": "user", "content": "Hello!"}]}' | jq .

# Mistral-3-BF16 (4-GPU)
curl -s -k https://mistral-3-bf16-private-ai.apps.<cluster>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "mistral-3-bf16", "messages": [{"role": "user", "content": "Hello!"}]}' | jq .
```

### Check Kueue Status

```bash
# View in RHOAI Dashboard: Observe & monitor → Workload metrics → Distributed workload status
oc get workload -n private-ai
oc describe clusterqueue rhoai-main-queue
```

## Troubleshooting

### Kueue Admits Wrong Model First

**Symptom:** A queued model (minReplicas:0) gets admitted instead of an active model.

**Root Cause:** All InferenceServices created simultaneously — Kueue admits in creation order.

**Fix:** Deploy active models first, wait for Ready, then deploy queued models. See Deployment section.

### vLLM v0.13.0 CUDA Out of Memory (RHOAI 3.3)

**Symptom:** `CUDA out of memory occurred when warming up sampler with 256 dummy requests`

**Root Cause:** vLLM v0.13.0 (RHOAI 3.3) uses more VRAM during warmup than v0.9.x.

**Fix:** Reduce memory parameters:
```yaml
args:
  - --max-model-len=16384        # was 32768
  - --gpu-memory-utilization=0.85 # was 0.9
  - --max-num-seqs=128           # reduces warmup memory
```

### Kueue Toleration Conflict (SchedulingGated)

**Symptom:** Pod stays `SchedulingGated` with error: `spec.tolerations: Forbidden: existing toleration can not be modified`

**Root Cause:** Kueue injects tolerations from ResourceFlavor. If the pod already defines tolerations, Kubernetes rejects the modification.

**Fix (RHOAI 3.3 / Kueue 1.2):** Do NOT define GPU tolerations in workload manifests. Let Kueue inject them from the ResourceFlavor. See [Kueue ResourceFlavor docs](https://kueue.sigs.k8s.io/docs/concepts/resource_flavor/).

### Kueue + Rolling Update Deadlock

**Symptom:** Two predictor pods — one Running, one `SchedulingGated`.

**Fix:** All InferenceServices use `deploymentStrategy.type: Recreate` (already configured).

### ServingRuntime Shows "Outdated"

**Symptom:** RHOAI dashboard shows "Outdated" label on serving runtime.

**Root Cause:** Custom ServingRuntime uses older vLLM image than RHOAI 3.3 default.

**Fix:** Update runtime image to match RHOAI 3.3 default:
```bash
# Check RHOAI 3.3 default image
oc get template vllm-cuda-runtime-template -n redhat-ods-applications \
  -o jsonpath='{.objects[0].spec.containers[0].image}'

# Update annotation
opendatahub.io/runtime-version: v0.13.0
```

## GitOps Structure

```
gitops/step-05-llm-on-vllm/base/
├── kustomization.yaml
├── serving-runtime/
│   └── vllm-runtime.yaml              # vLLM v0.13.0 (RHOAI 3.3)
├── inference/
│   ├── kustomization.yaml
│   ├── granite-8b-agent.yaml          # 1-GPU, S3, minReplicas: 1 (Active)
│   ├── mistral-3-bf16.yaml            # 4-GPU, S3, minReplicas: 1 (Active)
│   ├── mistral-3-int4.yaml            # 1-GPU, OCI, minReplicas: 0 (Queued)
│   ├── devstral-2.yaml                # 4-GPU, S3, minReplicas: 0 (Queued)
│   └── gpt-oss-20b.yaml              # 4-GPU, S3, minReplicas: 0 (Queued)
├── model-registration/
│   └── seed-job.yaml                  # Register 5 models in Registry
└── model-upload/
    ├── upload-mistral-bf16.yaml       # Mistral BF16 (~48GB)
    ├── upload-gpt-oss-20b.yaml        # GPT-OSS (~44GB)
    └── upload-granite-8b.yaml         # Granite (~8GB)
```

## Key RHOAI 3.3 Design Patterns

### Kueue Tolerations (Automatic Injection)

> *Kueue injects tolerations from ResourceFlavor into pods when unsuspending. Workloads must NOT define their own GPU tolerations — Kueue handles it.*
> Ref: [Kueue ResourceFlavor](https://kueue.sigs.k8s.io/docs/concepts/resource_flavor/)

### Deployment Strategy: Recreate (GPU Quota Safety)

> *All InferenceServices use `deploymentStrategy.type: Recreate` to prevent Kueue admission deadlocks in GPU-constrained environments.*

### ServingRuntime Alignment

> *The vllm-runtime ServingRuntime uses the RHOAI 3.3 default image (v0.13.0). Verify alignment with: `oc get template vllm-cuda-runtime-template -n redhat-ods-applications -o jsonpath='{.objects[0].metadata.annotations.opendatahub\.io/runtime-version}'`*

---

## Official Documentation

- [RHOAI 3.3 Deploying Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/)
- [RHOAI 3.3 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/working_with_distributed_workloads/index)
- [Kueue ResourceFlavor](https://kueue.sigs.k8s.io/docs/concepts/resource_flavor/)
- [Red Hat KB: NVIDIA Driver Compatibility](https://access.redhat.com/solutions/7134740)

## Next Steps

- **Step 06**: Model Performance & Benchmarks (Grafana dashboards, GuideLLM)
- **Step 07**: RAG Pipeline (Milvus, Docling, document ingestion)

## GenAI Playground Validation

After deploying models, validate them in the RHOAI GenAI Playground:

1. Open RHOAI Dashboard → **GenAI Studio** → **Playground**
2. Select the **Private AI - GPU as a Service** project
3. Click **Create playground** and select the running models (granite-8b-agent, mistral-3-bf16)
4. Test basic chat: Select a model and send a prompt
5. Test RAG: Toggle RAG ON, upload a PDF, set System instructions:
   > "You are a knowledgeable AI assistant. When documents are available, always use the knowledge_search tool before answering. Ground your response in the retrieved content. If no relevant information is found, say so and offer general knowledge as a fallback."
6. Ask a question about the uploaded document

> **Important:** Only register running models (with active predictor pods) in the Playground.
> Non-running models cause LlamaStack connection errors that affect all models.

> **Known Limitation (RHOAI 3.3):** Mistral models fail with RAG due to a vLLM ToolCall
> `index` field validation error. Use Granite for RAG demos, Mistral for basic chat.

> **Ref:** [RHOAI 3.3 — Experimenting with Models in the GenAI Playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/experimenting_with_models_in_the_gen_ai_playground/index)
