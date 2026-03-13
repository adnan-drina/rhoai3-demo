# Step 05: GPU-as-a-Service
**Five models, five GPUs, two active at a time — swappable on demand.**

## The Business Story

GPUs are the scarcest resource in the enterprise. Teams can't hoard them. **GPU-as-a-Service** means fair allocation via quotas, dynamic handover when workloads finish, and a model portfolio where multiple specialized LLMs share a fixed GPU budget. Kueue enforces the rules; the platform handles the rest.

## What It Does

Deploys an **enterprise model portfolio** of 5 Red Hat-validated models on a 5-GPU cluster. Two models run active at baseline; three sit queued at zero replicas, ready to swap in when GPU capacity frees up.

| Component | Purpose |
|-----------|---------|
| **vLLM ServingRuntime** | KServe runtime (v0.13.0, RHOAI 3.3 default) |
| **Kueue ClusterQueue** | Enforces 5-GPU quota across all workloads |
| **ResourceFlavors** | `nvidia-l4-1gpu` (g6.4xlarge) + `nvidia-l4-4gpu` (g6.12xlarge) |
| **InferenceServices** (×5) | 2 active + 3 queued, all in `private-ai` namespace |

| Model | GPUs | Status | Use Case |
|-------|------|--------|----------|
| **granite-8b-agent** | 1 | Active | RAG, MCP tools, Guardrails, Playground |
| **mistral-3-bf16** | 4 | Active | Full-precision 24B LLM, Playground chat |
| **mistral-3-int4** | 1 | Queued | Cost-efficient chat (75% memory savings) |
| **devstral-2** | 4 | Queued | Agentic tool-calling |
| **gpt-oss-20b** | 4 | Queued | High-reasoning tasks |

**Total registered:** 14 GPUs · **Quota limit:** 5 GPUs · **Active at any time:** 5/5

## Demo Walkthrough

> **Login as** `ai-admin` / `redhat123` for all scenes.

---

### Scene 1 — Model Portfolio (Active vs. Queued)

**Do:** Open the RHOAI Dashboard → **Observe & Monitor → Workload Metrics → Distributed workload status**. Then navigate to **GenAI Studio** → select the **Private AI - GPU as a Service** project.

**Expect:** The workload metrics page shows 5 InferenceServices — 2 admitted (green), 3 queued (yellow). The GenAI Studio project view lists the active models with green status indicators.

*"We have five models registered but only five GPUs. The platform is running Granite on one GPU and Mistral BF16 across four — that's our full budget. Three more models are queued at zero replicas. They're defined, governed, and ready to go — but Kueue won't let them start until GPU capacity frees up. This is GPU-as-a-Service: fair sharing, not first-come-first-served."*

**CLI shortcut:**

```bash
oc get inferenceservice -n private-ai
# granite-8b-agent   Ready    (1 GPU)
# mistral-3-bf16     Ready    (4 GPUs)
# mistral-3-int4     —        (0 replicas)
# devstral-2         —        (0 replicas)
# gpt-oss-20b        —        (0 replicas)
```

---

### Scene 2 — GenAI Playground (Chat with Granite)

**Do:** Navigate to **GenAI Studio → Playground**. Click **Create playground** and select `granite-8b-agent`. Send a prompt: *"Explain Kubernetes operators in three sentences."*

**Expect:** A streaming response within 2–3 seconds. The model answers coherently — this is the same Granite that was registered in Step 04, now live on a GPU.

*"This is the model we registered in the Model Registry, now served through vLLM on a single L4 GPU. Developers don't need API keys, external accounts, or curl commands — they open the Playground and start experimenting. The model runs entirely on our infrastructure, behind our firewall."*

---

### Scene 3 — Model Swapping (4-GPU Swap)

**Do:** In a terminal, run the swap commands live. Scale down Mistral BF16 and scale up GPT-OSS-20B:

```bash
oc patch inferenceservice mistral-3-bf16 -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":0}}}'

oc patch inferenceservice gpt-oss-20b -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":1}}}'

oc get inferenceservice -n private-ai -w
```

**Expect:** Mistral BF16 scales to zero. After 60–90 seconds, GPT-OSS-20B starts loading on the 4-GPU node. Kueue automatically admits the new workload once the old one releases its quota.

*"Watch what happens — we scale Mistral down, freeing four GPUs. Kueue immediately notices the freed capacity and admits GPT-OSS. No manual scheduling, no ticket to the infra team. The platform handles the handover. Same hardware, different model, zero downtime for the rest of the portfolio."*

**Reset to baseline after the demo:**

```bash
oc patch inferenceservice gpt-oss-20b -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":0}}}'
oc patch inferenceservice mistral-3-bf16 -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":1}}}'
```

---

### Scene 4 — GenAI Playground with RAG

**Do:** Return to the Playground. Select `granite-8b-agent`. Toggle **RAG ON**. Upload a PDF (product spec, internal doc, etc.). Set the system instructions:

> *"You are a knowledgeable AI assistant. When documents are available, always use the knowledge_search tool before answering. Ground your response in the retrieved content."*

Ask a question about the uploaded document.

**Expect:** The model retrieves relevant chunks from the PDF and grounds its answer in the document content. Responses cite specific sections rather than hallucinating.

*"Same model, same GPU — but now it's grounded in your private data. The Playground handles chunking and retrieval behind the scenes via LlamaStack. This is the simplest RAG experience you can get: upload a PDF, ask a question, get a sourced answer. No vector database setup, no pipeline code — just toggle RAG on."*

> **Known Limitation (RHOAI 3.3):** Mistral models fail with RAG due to a vLLM ToolCall `index` field validation error. Use Granite for RAG demos.

## Design Decisions

> **Recreate deployment strategy:** All InferenceServices use `deploymentStrategy.type: Recreate` to prevent Kueue admission deadlocks — rolling updates would hold GPU quota on two pods simultaneously.

> **Active-before-queued deploy order:** Kueue admits in creation order. Active models (minReplicas: 1) must be created first, or a queued model may grab the quota.

> **Automatic toleration injection:** Workloads must NOT define GPU tolerations. Kueue injects them from ResourceFlavor — defining them in the manifest causes a `SchedulingGated` conflict.

> **S3 for large models, OCI ModelCar for small:** Models over 20 GB use S3/MinIO to avoid `no space left on device` in CRI-O overlay. Mistral INT4 (~13.5 GB) uses OCI for faster cold starts.

> **vLLM memory tuning:** vLLM v0.13.0 uses more VRAM during warmup than earlier versions. Models set `--max-model-len=16384` and `--gpu-memory-utilization=0.85` to avoid CUDA OOM on L4 GPUs.

## References

- [RHOAI 3.3 Deploying Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/)
- [RHOAI 3.3 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/working_with_distributed_workloads/index)
- [RHOAI 3.3 GenAI Playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/experimenting_with_models_in_the_gen_ai_playground/index)
- [Kueue ResourceFlavor](https://kueue.sigs.k8s.io/docs/concepts/resource_flavor/)

## Operations

```bash
CONFIRM=true ./steps/step-05-llm-on-vllm/deploy.sh      # Deploy runtime, 5 models, seed registry
./steps/step-05-llm-on-vllm/validate.sh                  # Verify InferenceServices + Kueue status
```

## Next Steps

- **[Step 06: Model Performance Metrics](../step-06-model-metrics/README.md)** — Grafana dashboards and GuideLLM benchmarks
- **[Step 07: RAG Pipeline](../step-07-rag/README.md)** — pgvector, Docling, document ingestion
