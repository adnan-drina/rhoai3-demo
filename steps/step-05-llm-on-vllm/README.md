# Step 05: LLM Serving on vLLM

**Deploy LLMs on vLLM inference servers and validate them in the GenAI Playground.**

## The Business Story

The models are registered. The GPUs are provisioned. Now we serve them. Step-05 deploys five Red Hat-validated models on vLLM using KServe RawDeployment mode, makes them accessible through the GenAI Playground for rapid evaluation, and demonstrates live model swapping across GPU nodes — all governed by the Kueue quotas from step-03.

## What It Does

| Component | Purpose |
|-----------|---------|
| **vLLM ServingRuntime** | KServe runtime (vLLM v0.13.0, RHOAI 3.3) |
| **5 InferenceServices** | 2 active + 3 standby (see table below) |
| **GenAI Playground** | Browser-based chat UI for model evaluation |
| **AI Asset Labels** | `opendatahub.io/genai-asset: true` for Playground discovery |

| Model | GPUs | Status | Use Case |
|-------|------|--------|----------|
| **granite-8b-agent** | 1 | Active | RAG, MCP tools, Guardrails, Playground |
| **mistral-3-bf16** | 4 | Active | Full-precision 24B LLM, Playground, eval judge |
| **mistral-3-int4** | 1 | Standby | Cost-efficient chat (75% memory savings) |
| **devstral-2** | 4 | Standby | Agentic tool-calling |
| **gpt-oss-20b** | 4 | Standby | High-reasoning tasks |

> **Standby models** are deployed with `minReplicas: 0` in the manifest. Since KServe RawDeployment does not support native scale-to-zero, `deploy.sh` explicitly scales their Deployments to 0 replicas after ArgoCD sync. Activate them via `oc patch inferenceservice <name> --type merge -p '{"spec":{"predictor":{"minReplicas":1}}}'`. Ref: [RawDeployment scaling limitations](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/deploying_models).

## Demo Walkthrough

> **Login as** `ai-admin` / `redhat123`

### Scene 1 — Model Portfolio

**Do:** Navigate to **GenAI Studio → AI Asset Endpoints** in the RHOAI Dashboard. Then check CLI:

```bash
oc get inferenceservice -n private-ai
```

**Expect:** 5 InferenceServices listed. `granite-8b-agent` and `mistral-3-bf16` show Ready. The other 3 show no status (0 replicas).

*"We have five models defined but only five GPUs. Granite uses one, Mistral BF16 uses four — that's our full budget. The other three are ready to activate but won't consume resources until we explicitly scale them up."*

### Scene 2 — GenAI Playground (Chat with Granite)

**Do:** Navigate to **GenAI Studio → Playground**. Click **Create playground** and select `granite-8b-agent`. Send: *"Explain Kubernetes operators in three sentences."*

**Expect:** Streaming response within 2–3 seconds.

*"This is the Granite model we registered in the Model Registry, now live on a single L4 GPU. Developers open the Playground and start experimenting — no API keys, no external accounts, no curl commands. Everything runs on our infrastructure."*

### Scene 3 — Live Model Swapping

**Do:** Swap Mistral BF16 for GPT-OSS-20B live:

```bash
oc patch inferenceservice mistral-3-bf16 -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":0}}}'

oc patch inferenceservice gpt-oss-20b -n private-ai --type merge \
  -p '{"spec":{"predictor":{"minReplicas":1}}}'

oc get inferenceservice -n private-ai -w
```

**Expect:** Mistral scales down. GPT-OSS-20B starts loading on the 4-GPU node within 60–90 seconds.

*"We freed four GPUs by scaling Mistral down. Kueue immediately admits GPT-OSS — no tickets, no manual scheduling. Same hardware, different model."*

**Reset:** `oc patch inferenceservice gpt-oss-20b -n private-ai --type merge -p '{"spec":{"predictor":{"minReplicas":0}}}'` then scale mistral-3-bf16 back to 1.

### Scene 4 — GenAI Playground with RAG

**Do:** In the Playground, select `granite-8b-agent`. Toggle **RAG ON**, upload a PDF. Set system instructions:

> *"You MUST use the knowledge_search tool to answer. Ground your response in the retrieved content."*

*"Same model, same GPU — but now grounded in your private data. Upload a PDF, ask a question, get a sourced answer. No vector database setup, no pipeline code."*

> **Known Limitation (RHOAI 3.3):** Mistral models fail with RAG due to a vLLM ToolCall `index` field validation error. Use Granite for RAG demos.

## Design Decisions

> **KServe RawDeployment mode:** RHOAI 3.3 uses RawDeployment (not Knative Serverless) for model serving. RawDeployment does not support native scale-to-zero — `deploy.sh` handles this by explicitly scaling standby model Deployments to 0 replicas after ArgoCD sync. Ref: [Deploying models on the model serving platform](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/deploying_models).

> **Recreate deployment strategy:** All InferenceServices use `deploymentStrategy.type: Recreate` to prevent Kueue admission deadlocks — rolling updates would hold GPU quota on two pods simultaneously.

> **GPU tolerations in ISVC manifests:** All InferenceService manifests include explicit `nvidia.com/gpu` tolerations. This is required because the `private-ai` namespace does not use `kueue.openshift.io/managed=true` (see step-03 design decisions), so Kueue does not inject tolerations from ResourceFlavors. The `deploy.sh` also creates the `hf-token` secret in `minio-storage` before ArgoCD sync to ensure S3 upload jobs can authenticate with HuggingFace.

> **OCI ModelCar for small models, S3 for large:** Models under ~15 GB use OCI ModelCar from the Red Hat Registry (`registry.redhat.io/rhelai1/modelcar-*`), pulled via the cluster pull secret — no HuggingFace download or S3 upload needed. This includes Granite 8B FP8 (~8 GB) and Mistral INT4 (~13.5 GB). Models over 20 GB use S3/MinIO because OCI image layers may hit CRI-O overlay extraction limits on nodes with limited ephemeral storage. Ref: [Red Hat AI Validated ModelCar Images](https://docs.redhat.com/en/documentation/red_hat_ai/3/html-single/validated_models/index#validated-red-hat-ai-modelcar-container-images).

> **vLLM memory tuning:** `--max-model-len=16384` and `--gpu-memory-utilization=0.85` prevent CUDA OOM on L4 GPUs with vLLM v0.13.0.

## References

- [RHOAI 3.3 — Deploying Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/)
- [RHOAI 3.3 — GenAI Playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/experimenting_with_models_in_the_gen_ai_playground/index)
- [RHOAI 3.3 — Model and Runtime Requirements for Playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user)

## Operations

```bash
CONFIRM=true ./steps/step-05-llm-on-vllm/deploy.sh    # Deploy runtime + 5 models + scale standby to 0
./steps/step-05-llm-on-vllm/validate.sh                # Verify InferenceServices + Kueue status
```

## Next Steps

- **[Step 06: Model Performance Metrics](../step-06-model-metrics/README.md)** — Grafana dashboards and GuideLLM benchmarks
- **[Step 07: RAG Pipeline](../step-07-rag/README.md)** — pgvector, Docling, document ingestion
