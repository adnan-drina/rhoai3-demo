# RHOAI 3.4 Documentation Alignment Review

**Generated:** 2026-05-16
**Scope:** Red Hat OpenShift AI Self-Managed 3.4 official documentation index.
**Demo baseline:** RHOAI 3.4 on OpenShift Container Platform 4.20.

This review maps the official Red Hat OpenShift AI Self-Managed 3.4 documentation to the `rhoai3-demo` implementation. It is intentionally chapter-oriented rather than step-oriented: each documentation chapter is assessed for intent, platform components, recommended setup, RHOAI 3.4 specifics, demo coverage, gaps, and improvement backlog.

Official documentation remains the source of truth:

- [Red Hat OpenShift AI Self-Managed 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/)
- [Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/release_notes)
- [OpenShift Container Platform 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/)

`rh-brain` is used only as read-only Red Hat narrative and blog alignment input.

## Files

| File | Purpose |
|---|---|
| [chapter-coverage-matrix.md](chapter-coverage-matrix.md) | Master matrix for every RHOAI 3.4 documentation category and chapter. |
| [phase-1-platform-admin.md](phase-1-platform-admin.md) | What is new, planning, install, administration, hardware, API stability, catalog, and registry administration. |
| [phase-2-develop-deploy.md](phase-2-develop-deploy.md) | Projects, workbenches, storage, pipelines, model catalog/registry usage, RAG, Gen AI Playground, KServe, MaaS, llm-d, and distributed workloads. |
| [phase-3-safety-eval-monitor.md](phase-3-safety-eval-monitor.md) | Model customization, LM-Eval, NeMo Guardrails, TrustyAI monitoring, drift/bias, and model quality. |
| [phase-4-supported-config-cross-cutting.md](phase-4-supported-config-cross-cutting.md) | Supported configurations, support status, preview claims, rh-brain narrative alignment, and cross-cutting gaps. |
| [remediation-backlog.md](remediation-backlog.md) | Consolidated backlog grouped by priority and demo area. |

## Rating Model

| Rating | Meaning |
|---|---|
| `covered` | Demo implements the documented component or workflow with strong alignment. |
| `partially-covered` | Demo implements the core idea but misses recommended setup, scope, or production caveats. |
| `not-covered` | Documentation chapter is relevant but absent from the demo. |
| `not-applicable` | Chapter is outside the demo story or cannot reasonably be demonstrated here. |
| `intentionally-deferred` | Gap is known and should remain future work for this demo batch. |

## Current Summary

The demo strongly covers platform installation, project/RBAC/storage setup, GPU prerequisites, KServe RawDeployment, MaaS, model registry, RAG with Llama Stack and pgvector, LM-Eval, NeMo Guardrails, MCP-based agentic workflows, predictive model serving, MLOps pipelines, MLflow, TrustyAI, and edge deployment patterns.

The largest remaining gaps are Feature Store, AutoML, AutoRAG, full distributed training/data processing, disconnected installation, production API support-tier governance, llm-d, production-grade external databases, and supported-configuration proof beyond the current AWS GPU demo baseline.
