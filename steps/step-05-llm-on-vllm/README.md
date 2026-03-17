# Step 05: LLM Serving on vLLM

**Deploy LLMs on vLLM inference servers and validate them in the GenAI Playground.**

## The Business Story

The models are registered. The GPUs are provisioned. Now we serve them. Step-05 deploys two Red Hat-validated models on vLLM using KServe RawDeployment mode and makes them accessible through the GenAI Playground. Three additional models are registered in the Model Registry and can be deployed from GenAI Studio when needed.

## What It Does

| Component | Purpose |
|-----------|---------|
| **vLLM ServingRuntime** | KServe runtime (vLLM v0.13.0, RHOAI 3.3) |
| **2 InferenceServices** | Both active (see table below) |
| **Model Registry Seed Job** | Registers 5 models for GenAI Studio catalog |
| **GenAI Playground** | Browser-based chat UI for model evaluation |
| **AI Asset Labels** | `opendatahub.io/genai-asset: true` for Playground discovery |

| Model | GPUs | Source | Use Case |
|-------|------|--------|----------|
| **granite-8b-agent** | 1 (g6.4xlarge) | OCI ModelCar | RAG, MCP tools, Guardrails, Eval candidate |
| **mistral-3-bf16** | 4 (g6.12xlarge) | S3/MinIO | Playground chat, Benchmarking, Eval judge |

> **Additional models in the Registry:** Mistral-3-INT4 (1-GPU, OCI), Devstral-2 (4-GPU), and GPT-OSS-20B (4-GPU) are registered in the Model Registry and visible in GenAI Studio AI Available Assets. Deploy them from the Dashboard when needed — no code changes required.

## Demo Walkthrough

> **Login as** `ai-admin` / `redhat123`

### Scene 1 — Model Portfolio

**Do:** Navigate to **GenAI Studio → AI Asset Endpoints** in the RHOAI Dashboard. Then check CLI:

```bash
oc get inferenceservice -n private-ai
```

**Expect:** 2 InferenceServices listed, both Ready. The Model Registry shows 5 models total.

*"We have two models running on all five GPUs — Granite on one GPU handles tool-calling and RAG, Mistral BF16 on four GPUs handles enterprise chat and evaluation. Three more models are registered in the catalog and ready to deploy when the team needs them."*

### Scene 2 — GenAI Playground (Chat with Granite)

**Do:** Navigate to **GenAI Studio → Playground**. Click **Create playground** and select `granite-8b-agent`. Send: *"Explain Kubernetes operators in three sentences."*

**Expect:** Streaming response within 2-3 seconds.

*"This is the Granite model we registered in the Model Registry, now live on a single L4 GPU. Developers open the Playground and start experimenting — no API keys, no external accounts, no curl commands. Everything runs on our infrastructure."*

### Scene 3 — GenAI Playground with RAG

**Do:** In the Playground, select `granite-8b-agent`. Toggle **RAG ON**, upload a PDF. Set system instructions:

> *"You MUST use the knowledge_search tool to answer. Ground your response in the retrieved content."*

*"Same model, same GPU — but now grounded in your private data. Upload a PDF, ask a question, get a sourced answer. No vector database setup, no pipeline code."*

> **Known Limitation (RHOAI 3.3):** Mistral models fail with RAG due to a vLLM ToolCall `index` field validation error. Use Granite for RAG demos.

## Design Decisions

> **Recreate deployment strategy:** All InferenceServices use `deploymentStrategy.type: Recreate` to avoid dual-pod GPU contention — rolling updates would require two GPU allocations simultaneously on constrained nodes.

> **GPU tolerations in ISVC manifests:** All InferenceService manifests include explicit `nvidia.com/gpu` tolerations and `nodeSelector` for GPU node targeting. GPU nodes are tainted with `nvidia.com/gpu=true:NoSchedule`; every GPU pod must tolerate this taint.

> **OCI ModelCar for small models, S3 for large:** Models under ~15 GB use OCI ModelCar from the Red Hat Registry (`registry.redhat.io/rhelai1/modelcar-*`), pulled via the cluster pull secret — no HuggingFace download or S3 upload needed. Granite 8B FP8 (~8 GB) uses this path. Models over 20 GB (Mistral BF16 at ~48 GB) use S3/MinIO because OCI image layers may hit CRI-O overlay extraction limits. Ref: [Red Hat AI Validated ModelCar Images](https://docs.redhat.com/en/documentation/red_hat_ai/3/html-single/validated_models/index#validated-red-hat-ai-modelcar-container-images).

> **vLLM memory tuning:** `--max-model-len=16384` and `--gpu-memory-utilization=0.85` prevent CUDA OOM on L4 GPUs with vLLM v0.13.0.

> **Registry-first for on-demand models:** Rather than deploying standby models with `minReplicas: 0` and managing scale-down logic in deploy.sh, additional models are registered in the Model Registry only. Users deploy them from GenAI Studio when needed, which aligns with the RHOAI Dashboard-driven workflow.

> **Upload-before-serve ordering:** `deploy.sh` runs the S3 upload job for `mistral-3-bf16` and waits for completion **before** applying the ArgoCD Application. This prevents a race condition where KServe's `storage-initializer` lists S3 while the upload is still in progress, resulting in a partial download and vLLM `CrashLoopBackOff` ("Invalid repository ID or local directory"). The upload job is idempotent — it skips if the model is already in MinIO.

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
