# Step 05: LLM Serving on vLLM
**"Serve the Models"** — Deploy production-ready LLMs on the Red Hat AI Inference Server and experiment in the GenAI Playground.

## Overview

Your models are registered. Your GPUs are provisioned. Now it's time to serve them. Moving from experimentation to production inference requires a runtime that balances performance, compatibility, and operational simplicity — all on private infrastructure with no external API dependencies.

**Red Hat OpenShift AI 3.3** delivers this with the **Red Hat AI Inference Server**, powered by vLLM. *"Purpose-built serving infrastructure, such as Red Hat AI Inference Server (based on vLLM), maximizes throughput through techniques such as continuous batching, paged attention, and optimized GPU use."* KServe RawDeployment mode exposes OpenAI-compatible endpoints, the **Model Registry** catalogs available models, and the **GenAI Playground** gives developers a browser-based sandbox for immediate experimentation. Three additional models are registered in the catalog and deployable from **GenAI Studio** when the team needs them.

The model portfolio reflects a deliberate sizing strategy. *"Small language models offer a compelling middle ground. These models deliver strong performance on targeted tasks while requiring significantly fewer resources than their larger counterparts."* Granite 8B — the agent model — runs as an FP8 quantized checkpoint on a single GPU, while Mistral 3 BF16 uses four GPUs for enterprise chat and evaluation. *"Model quantization reduces size and accelerates inference by using lower-precision numerical formats... Red Hat's benchmarks of over half a million evaluations found that 8-bit quantization delivers approximately 1.8x performance speedup with full accuracy recovery."*

This step demonstrates the **Generative AI** use case of the Red Hat AI platform: serving foundation models with optimized inference via vLLM, delivering fast and cost-effective content generation at scale.

### What Gets Deployed

```text
LLM Serving
├── vLLM ServingRuntime   → KServe runtime (vLLM v0.13.0, RHOAI 3.3)
├── 2 InferenceServices   → Active models on GPU (see table)
├── Model Registry Seed   → Registers 5 models for GenAI Studio catalog
├── GenAI Playground      → Browser-based chat UI for model evaluation
└── AI Asset Labels       → opendatahub.io/genai-asset for Playground discovery
```

| Model | GPUs | Source | Use Case | Namespace |
|-------|------|--------|----------|-----------|
| **granite-8b-agent** | 1 (g6.4xlarge) | OCI ModelCar | RAG, MCP tools, Guardrails, Eval candidate | `private-ai` |
| **mistral-3-bf16** | 4 (g6.12xlarge) | S3/MinIO | Playground chat, Benchmarking, Eval judge | `private-ai` |

> **Additional models in the Registry:** Mistral-3-INT4 (1-GPU, OCI), Devstral-2 (4-GPU), and GPT-OSS-20B (4-GPU) are registered in the Model Registry and visible in GenAI Studio AI Available Assets. Deploy them from the Dashboard when needed — no code changes required.

Manifests: [`gitops/step-05-llm-on-vllm/base/`](../../gitops/step-05-llm-on-vllm/base/)

### Design Decisions

> **Recreate deployment strategy:** All InferenceServices use `deploymentStrategy.type: Recreate` to avoid dual-pod GPU contention — rolling updates would require two GPU allocations simultaneously on constrained nodes.

> **GPU tolerations in ISVC manifests:** All InferenceService manifests include explicit `nvidia.com/gpu` tolerations and `nodeSelector` for GPU node targeting. GPU nodes are tainted with `nvidia.com/gpu=true:NoSchedule`; every GPU pod must tolerate this taint.

> **OCI ModelCar for small models, S3 for large:** Models under ~15 GB use OCI ModelCar from the Red Hat Registry (`registry.redhat.io/rhelai1/modelcar-*`), pulled via the cluster pull secret — no HuggingFace download or S3 upload needed. Granite 8B FP8 (~8 GB) uses this path. Models over 20 GB (Mistral BF16 at ~48 GB) use S3/MinIO because OCI image layers may hit CRI-O overlay extraction limits. Ref: [Red Hat AI Validated ModelCar Images](https://docs.redhat.com/en/documentation/red_hat_ai/3/html-single/validated_models/index#validated-red-hat-ai-modelcar-container-images).

> **vLLM performance tuning (benchmarked with GuideLLM):**
>
> | Parameter | Granite (1x L4) | Mistral (4x L4 TP=4) | Rationale |
> |-----------|----------------|----------------------|-----------|
> | `--gpu-memory-utilization` | 0.92 | 0.90 | Safe maximum; 0.95 OOMs during CUDA graph capture on L4 |
> | `--kv-cache-dtype` | fp8 | fp8 | L4 Ada Lovelace native FP8; doubles KV cache capacity |
> | `--max-model-len` | 32768 | 16384 | Agent needs 32K for multi-turn MCP conversations (~24K peak); eval judge needs long context |
> | `--enable-chunked-prefill` | auto (V1) | explicit | V1 engine enables by default; prevents prefill blocking |
>
> **KV cache capacity after tuning:**
> - Granite: 155K tokens (was 74K), max concurrency 9.5x at 16K context (+108% over baseline)
> - Mistral: 426K tokens (was 368K), max concurrency 26.0x at 16K context
>
> **ITL is hardware-bound on L4 GPUs:** Granite ~40ms, Mistral ~53ms. These are near the L4 memory bandwidth floor (~300 GB/s). Reducing ITL further requires higher-bandwidth GPUs (e.g., A100, H100). See [Practical strategies for vLLM performance tuning](https://developers.redhat.com/articles/2026/03/03/practical-strategies-vllm-performance-tuning).

> **Registry-first for on-demand models:** Rather than deploying standby models with `minReplicas: 0` and managing scale-down logic in deploy.sh, additional models are registered in the Model Registry only. Users deploy them from GenAI Studio when needed, which aligns with the RHOAI Dashboard-driven workflow.

> **Upload-before-serve ordering:** `deploy.sh` runs the S3 upload job for `mistral-3-bf16` and waits for completion **before** applying the ArgoCD Application. This prevents a race condition where KServe's `storage-initializer` lists S3 while the upload is still in progress, resulting in a partial download and vLLM `CrashLoopBackOff` ("Invalid repository ID or local directory"). The upload job is idempotent — it skips if the model is already in MinIO.

> **ArgoCD `selfHeal: false`:** This step's ArgoCD Application uses `selfHeal: false` (unlike other steps) to allow operators to manually scale InferenceServices (e.g. `minReplicas: 0` to stop a model) without ArgoCD reverting the change. ArgoCD shows OutOfSync for visibility but does not auto-heal. Git-triggered syncs still work. See the `manage-resources` skill for scaling workflows.

### Deploy

```bash
./steps/step-05-llm-on-vllm/deploy.sh    # Deploy runtime + 2 models + register 5 in catalog
./steps/step-05-llm-on-vllm/validate.sh  # Verify InferenceServices + GPU scheduling
```

### What to Verify After Deployment

| Check | What It Tests | Pass Criteria |
|-------|--------------|---------------|
| ServingRuntime | Runtime exists in namespace | At least 1 |
| InferenceServices Ready | granite-8b-agent and mistral-3-bf16 | Both READY=True |
| GPU scheduling | Pods on correct GPU nodes | granite on g6.4xlarge, mistral on g6.12xlarge |
| Quick inference test | vLLM model endpoint responds | JSON with model ID |

```bash
oc get servingruntime -n private-ai
oc get inferenceservice -n private-ai
oc get pods -n private-ai -l serving.kserve.io/inferenceservice -o wide
oc exec deploy/granite-8b-agent-predictor -n private-ai -c kserve-container -- \
  curl -s http://localhost:8080/v1/models
```

## The Demo

> In this demo, we verify that two production-ready LLMs are serving on vLLM and interact with them through the GenAI Playground — proving that LLM inference runs entirely on Red Hat infrastructure with no external dependencies.

> **Login as** `ai-admin` / `redhat123`

### Model Portfolio

> Before experimenting, we verify that our model serving infrastructure is live. Two InferenceServices are running on all five GPUs, and the Model Registry holds three more models ready to deploy on demand.

1. Navigate to **GenAI Studio → AI Asset Endpoints** in the RHOAI Dashboard
2. Check via CLI:

```bash
oc get inferenceservice -n private-ai
```

**Expect:** 2 InferenceServices listed, both Ready. The Model Registry shows 5 models total.

> Two models running on all five GPUs — a deliberate multimodel strategy. *"Enterprises are adopting a multimodel approach, using multiple specialized models rather than one monolithic system, with large-scale reasoning models for complex planning tasks while routing simpler requests to models with 7-13 billion parameters."* Our Granite 8B agent handles tool-calling and RAG on one GPU, while Mistral 3 BF16 on four GPUs handles enterprise chat and evaluation. Three more models are registered in the catalog and ready to deploy when the team needs them — all served by the Red Hat AI Inference Server.

### GenAI Playground

> The GenAI Playground gives developers immediate access to deployed models — no API keys, no external accounts, no setup required. We open a chat session and interact with a live model on GPU.

1. Navigate to **GenAI Studio → Playground**
2. Click **Create playground**, select a deployed model
3. Send: *"Explain Kubernetes operators in three sentences."*

**Expect:** Streaming response within 2-3 seconds.

> The model was registered in the Model Registry and is now live on an L4 GPU. Developers open the Playground and start experimenting immediately — everything runs on our infrastructure, served by Red Hat OpenShift AI.

### GenAI Playground with RAG

> The same model can be augmented with document context directly in the Playground — upload a PDF, set grounding instructions, and get sourced answers without configuring a vector database or writing pipeline code.

1. In the Playground, select `granite-8b-agent`
2. Toggle **RAG ON**, upload a PDF
3. Set system instructions:
   > *"You MUST use the knowledge_search tool to answer. Ground your response in the retrieved content."*

**Expect:** The model answers grounded in the uploaded document content.

> Same model, same GPU — but now grounded in your private data. Upload a PDF, ask a question, get a sourced answer. The GenAI Playground makes RAG experimentation accessible to any developer on the team.

> **Known Limitation (RHOAI 3.3):** Mistral models fail with RAG due to a vLLM ToolCall `index` field validation error. Use Granite for RAG demos.

## Key Takeaways

**For business stakeholders:**

- LLM inference runs entirely on your infrastructure — no external API calls, no data leaving the platform
- The GenAI Playground gives developers immediate access to experiment with models, reducing time to first value
- A model portfolio strategy (agent model + enterprise model) optimizes GPU cost per use case

**For technical teams:**

- Red Hat AI Inference Server with vLLM supports OCI ModelCar and S3 model sources — choose based on model size and deployment speed
- KServe RawDeployment with `Recreate` strategy avoids dual-pod GPU contention on constrained nodes
- vLLM performance tuning (FP8 KV cache, chunked prefill) doubles effective capacity — see Step 06 for benchmarks

## Troubleshooting

### InferenceService stuck in Pending (untolerated taint)

**Symptom:** Predictor pod is Pending with `node(s) had untolerated taint {nvidia.com/gpu: true}`.

**Root Cause:** The InferenceService manifest is missing GPU tolerations.

**Solution:** Verify the ISVC has the correct tolerations:
```bash
oc get inferenceservice granite-8b-agent -n private-ai -o jsonpath='{.spec.predictor.tolerations}' | python3 -m json.tool
```
Expected: toleration for `nvidia.com/gpu`.

### mistral-3-bf16 CrashLoopBackOff ("Invalid repository ID")

**Symptom:** vLLM container crashes with `ValueError: Invalid repository ID or local directory`.

**Root Cause:** S3 upload was incomplete when KServe's `storage-initializer` downloaded the model. Partial model files cause vLLM to fail.

**Solution:** `deploy.sh` now runs the upload job and waits for completion before applying the ArgoCD Application. If the model is already corrupted in the PVC:
```bash
oc delete pvc mistral-3-bf16-pvc -n private-ai
# ArgoCD will recreate the PVC and trigger a fresh download
```

### vLLM OOMKilled during startup

**Symptom:** Pod killed with `OOMKilled` during CUDA graph capture.

**Root Cause:** `--gpu-memory-utilization` set too high (e.g., 0.95). CUDA graph capture needs headroom.

**Solution:** Reduce to 0.92 (Granite) or 0.90 (Mistral). Current manifests already use these tuned values.

## References

- [RHOAI 3.3 — Deploying Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/)
- [RHOAI 3.3 — GenAI Playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/experimenting_with_models_in_the_gen_ai_playground/index)
- [RHOAI 3.3 — Model and Runtime Requirements for Playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user)
- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet)
- [Get started with AI for enterprise organizations — Red Hat](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)

## Next Steps

- **Step 06**: [Model Performance Metrics](../step-06-model-metrics/README.md) — Grafana dashboards and GuideLLM benchmarks
- **Step 07**: [RAG Pipeline](../step-07-rag/README.md) — pgvector, Docling, document ingestion
