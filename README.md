# RHOAI Demo Reimplementation

This repository is being rebuilt as a staged Red Hat OpenShift AI demo for
private enterprise AI platforms.

The previous implementation has been moved to:

- `backup/legacy-implementation-2026-06-09/`

Active implementation areas:

- `stage-110-rhoai-base-platform/` - GitOps, ODF MCG, RHOAI base platform, access, model registry
- `stage-120-gpu-as-a-service/` - GPU worker, NFD, NVIDIA GPU Operator, Kueue, hardware profiles
- `stage-210-model-serving-foundation/` - KServe/vLLM foundation, Nemotron endpoint, Grafana, GuideLLM
- `stage-220-models-as-a-service/` - MaaS governance for Nemotron and external GPT
- `stage-230-private-data-rag/` - whoami private RAG with DSPA/KFP ingestion, Docling, Llama Stack, pgvector, ODF S3, and MaaS Nemotron
- `gitops/` - active GitOps source tree
- `scripts/` - shared project automation
- `.agents/` and `AGENTS.md` - active shared agent guidance
- `docs/PLATFORM_BASELINE.md` - active product baseline and official docs index

Do not run legacy deploy, validate, bootstrap, or resource-management scripts
from the backup unless explicitly restoring or inspecting the old
implementation.
