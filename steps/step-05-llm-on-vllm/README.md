# Step 05: LLM Serving on vLLM

**Deploy LLMs on vLLM inference servers and validate them in the GenAI Playground.**

## The Business Story

The models are registered. The GPUs are provisioned. Now we serve them. Step-05 deploys two Red Hat-validated models on vLLM using KServe RawDeployment mode and makes them accessible through the GenAI Playground. Three additional models are registered in the Model Registry and can be deployed from GenAI Studio when needed.

## What It Does

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

## Demo Walkthrough

> **Login as** `ai-admin` / `redhat123`

### Scene 1 — Model Portfolio

**Do:** Navigate to **GenAI Studio → AI Asset Endpoints** in the RHOAI Dashboard. Then check CLI:

```bash
oc get inferenceservice -n private-ai
```

**Expect:** 2 InferenceServices listed, both Ready. The Model Registry shows 5 models total.

*"We have two models running on all five GPUs — the agent model on one GPU handles tool-calling and RAG, the larger model on four GPUs handles enterprise chat and evaluation. Three more models are registered in the catalog and ready to deploy when the team needs them."*

### Scene 2 — GenAI Playground

**Do:** Navigate to **GenAI Studio → Playground**. Click **Create playground**, select a deployed model, and send: *"Explain Kubernetes operators in three sentences."*

**Expect:** Streaming response within 2-3 seconds.

*"This model was registered in the Model Registry, now live on an L4 GPU. Developers open the Playground and start experimenting — no API keys, no external accounts, no curl commands. Everything runs on our infrastructure."*

### Scene 3 — GenAI Playground with RAG

**Do:** In the Playground, select `granite-8b-agent`. Toggle **RAG ON**, upload a PDF. Set system instructions:

> *"You MUST use the knowledge_search tool to answer. Ground your response in the retrieved content."*

*"Same model, same GPU — but now grounded in your private data. Upload a PDF, ask a question, get a sourced answer. No vector database setup, no pipeline code."*

> **Known Limitation (RHOAI 3.3):** Mistral models fail with RAG due to a vLLM ToolCall `index` field validation error. Use Granite for RAG demos.

## What to Verify After Deployment

```bash
# ServingRuntime exists
oc get servingruntime -n private-ai
# Expected: at least 1

# InferenceServices Ready
oc get inferenceservice -n private-ai
# Expected: granite-8b-agent and mistral-3-bf16, both READY=True

# GPU scheduling (pods on correct nodes)
oc get pods -n private-ai -l serving.kserve.io/inferenceservice -o wide
# Expected: granite on g6.4xlarge, mistral on g6.12xlarge

# Quick inference test
oc exec deploy/granite-8b-agent-predictor -n private-ai -c kserve-container -- \
  curl -s http://localhost:8080/v1/models
# Expected: JSON with model ID
```

Or run the validation script:

```bash
./steps/step-05-llm-on-vllm/validate.sh
```

## Design Decisions

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

## Operations

```bash
./steps/step-05-llm-on-vllm/deploy.sh    # Deploy runtime + 2 models + register 5 in catalog
./steps/step-05-llm-on-vllm/validate.sh  # Verify InferenceServices + GPU scheduling
```

## Next Steps

- **[Step 06: Model Performance Metrics](../step-06-model-metrics/README.md)** — Grafana dashboards and GuideLLM benchmarks
- **[Step 07: RAG Pipeline](../step-07-rag/README.md)** — pgvector, Docling, document ingestion
