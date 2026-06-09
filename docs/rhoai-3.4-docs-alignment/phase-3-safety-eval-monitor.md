# Phase 3: Training, Evaluation, Safety, and Monitoring

## Intent

This phase covers trustworthy AI practices: model customization, repeatable evaluation, safety guardrails, drift/bias monitoring, and operational model quality signals.

## Chapter Analysis

| Chapter | Intent | Components and recommended setup | RHOAI 3.4 specifics | Demo coverage and alignment |
|---|---|---|---|---|
| Model customization | Customize models for Gen AI and agentic applications. | Training/customization workflows, data, accelerators, evaluation loops. | 3.4 positions customization as part of the Gen AI application lifecycle. | `intentionally-deferred`: demo focuses on RAG, prompt/tool orchestration, and evaluation rather than fine-tuning. |
| LM-Eval and EvalHub | Evaluate LLMs with benchmark tasks, provider registries, tenant-scoped jobs, and metrics. | EvalHub, LMEvalJob, TrustyAI operator, model endpoint access, online/code execution controls, MLflow tracking. | `trustyai.opendatahub.io/v1alpha1` LMEvalJob and EvalHub are the documented APIs for the two evaluation paths. | `covered`: Step 08 implements EvalHub smoke, LM-Eval, and RAG/model evaluation assets. |
| Guardrails | Protect inputs/outputs with safety controls. | TrustyAI, NemoGuardrails, guardrails config, model endpoint, route/API. | RHOAI 3.4 release notes classify NeMo Guardrails as fully supported, while the guardrails chapter page still carries Technology Preview text. | `covered`: Step 09 migrated to `NemoGuardrails` and notes the support-status discrepancy. |
| Monitoring AI systems | Monitor drift, bias, metrics, and model quality. | TrustyAIService, metrics, dashboards, model monitoring configuration. | Monitoring is broader than generic Prometheus metrics. | `partially-covered`: Step 06 provides vLLM/Grafana observability; Step 12 includes TrustyAI. More direct RHOAI monitoring comparison is needed. |
| Managing and monitoring models | Operate model lifecycle and monitoring after deployment. | Model registry, deployed models, metrics, monitoring, alerts. | Model lifecycle should connect registry, serving, monitoring, and promotion. | `partially-covered`: Step 12 links model registry, KFP, MLflow, and TrustyAI; Step 06 covers serving metrics. Need clearer model-monitoring docs alignment. |

## Implemented Alignment

| Demo step | Alignment assessment |
|---|---|
| Step 06 Model Metrics | Strong for vLLM/KServe operational metrics and GuideLLM load testing; partial for RHOAI TrustyAI model monitoring. |
| Step 08 Model Evaluation | Strong alignment with EvalHub, LM-Eval, and repeatable benchmark/evaluation story. |
| Step 09 Guardrails | Strong alignment after NeMo migration; keep support status explicit. |
| Step 12 MLOps Pipeline | Strong lifecycle story with KFP, Model Registry, MLflow, and TrustyAI; improve exact docs references. |

## Recommended Improvements

| Priority | Recommendation | Demo area |
|---|---|---|
| P1 | Add a support-status table for NeMo Guardrails, Llama Stack, MaaS, OpenAI-compatible APIs, and MCP usage. | Cross-cutting docs |
| P1 | Run and record post-sync Step 09 validation once live Argo has reconciled the NeMo resources. | Step 09 |
| P2 | Add a TrustyAI monitoring section that maps Step 12 resources to the RHOAI monitoring chapter. | Step 12 |
| P2 | Clarify that model customization/fine-tuning is intentionally deferred, with RAG/eval as the current adaptation pattern. | Step 07/08 or backlog |
| P3 | Expand EvalHub beyond smoke to Garak/RAGAS/custom providers and optional OCI export. | Step 08 |

## rh-brain Alignment

Relevant sources:

- `raw/Eval-driven development Build and evaluate reliable AI agents.md`
- `raw/Build resilient guardrails for OpenClaw AI agents on Kubernetes.md`
- `raw/Evaluating (Production) Traces  MLflow AI Platform.md`
- `raw/Evaluation Quickstart  MLflow AI Platform.md`
- `raw/Synthetic data for RAG evaluation Why your RAG system needs better testing.md`

Narrative fit: strong. The demo already follows an evaluation-before-production story and has a safety layer. The main remaining issue is to distinguish platform-native RHOAI monitoring from general observability and to keep preview support status visible.
