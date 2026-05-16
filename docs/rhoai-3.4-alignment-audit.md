# RHOAI 3.4 Alignment Audit

**Generated:** 2026-05-16
**Live cluster:** `cluster-5dmgr.5dmgr.sandbox3664.opentlc.com`
**Target baseline:** Red Hat OpenShift AI 3.4 on OpenShift Container Platform 4.20
**Audit mode:** Non-destructive inspection of repo, live cluster state, official documentation, and local `rh-brain` research.

## Executive Summary

The remediation batch removed the strict audit blockers and aligned the demo's guardrails story with the current RHOAI 3.4 NeMo Guardrails documentation.

Validated baseline:

- OCP is `4.20.22`.
- Red Hat OpenShift AI CSV is `rhods-operator.3.4.0`.
- `DataScienceCluster/default-dsc` is ready.
- RHOAI component CRDs needed by the demo are installed, including KServe, Llama Stack, Model Registry, TrustyAI, NeMo Guardrails, MLflow, Kueue, and MaaS CRDs.
- `AUDIT_STRICT_CLUSTER=true OC_REQUEST_TIMEOUT=20s ./scripts/audit-doc-alignment.sh --base origin/main` now reports `Blocking findings: 0`.

## Remediation Results

| Area | Result |
|---|---|
| Step 09 Guardrails | Migrated from legacy FMS `GuardrailsOrchestrator` resources to TrustyAI-managed `NemoGuardrails`. |
| Step 07 RAG | Removed unsupported `Notebook.spec.template.metadata`; strict server validation now passes. |
| Audit gate | Existing PVC immutable spec drift is recorded as a non-blocking note when the matching Argo CD app ignores PVC `/spec`. |
| Step 10 MCP | `acme-equipment-0007` `CrashLoopBackOff` is documented and validated as intentional demo state. Platform and MCP resources still must be healthy. |
| GitOps cleanup | Removed central-cluster direct applies for resources now managed by Argo CD in Steps 03 and 07. Remote MicroShift bootstrap actions remain Step 13b exceptions. |
| Audit artifacts | `docs/alignment-evidence-ledger.md` refreshed; this audit report is tracked with `git add -f` because `docs/**` is ignored for new files. |

## Official Documentation Baseline

- RHOAI 3.4 main documentation: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/
- RHOAI 3.4 NeMo Guardrails: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/enabling_ai_safety_with_guardrails/deploying-nemo-guardrails_nemo-guardrails
- RHOAI 3.4 Llama Stack / RAG: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_llama_stack/index
- RHOAI 3.4 KServe RawDeployment: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/deploying_models/index
- OCP 4.20 documentation: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/

`rh-brain` sources used for narrative alignment:

- `raw/From inference to agents Scaling AI in the enterprise with Red Hat AI 3.4.md`
- `raw/Deploy an enterprise RAG chatbot with Red Hat OpenShift AI.md`
- `raw/Building effective AI agents with Model Context Protocol (MCP).md`
- `raw/MCP security Containerization and Red Hat OpenShift integration.md`
- `raw/Build resilient guardrails for OpenClaw AI agents on Kubernetes.md`
- `raw/Eval-driven development Build and evaluate reliable AI agents.md`

## Step Findings

| Step | Status | Notes |
|---|---|---|
| 01 GPU and prerequisites | Aligned | Kustomize and schema checks pass; README references RHOAI 3.4/OCP 4.20. |
| 02 RHOAI platform | Aligned with notes | Existing `maas-postgres-data` PVC immutable drift is non-blocking because Argo CD intentionally ignores PVC `/spec`. |
| 03 Enterprise projects | Aligned with notes | MinIO console route is now GitOps-managed; OpenShift Groups remain deploy-time because Argo CD cannot reliably diff Group resources. |
| 04 Model registry | Aligned with notes | In-cluster DB remains a demo/evaluation choice. |
| 05 MaaS model serving | Aligned with notes | Active KServe resources validate; `qwen3-8b-agent.yaml` remains deferred because it is not in the active kustomization. |
| 06 Model metrics | Aligned with notes | GuideLLM and metrics story aligns with Red Hat inference evaluation guidance. |
| 07 RAG | Aligned with notes | Notebook strict validation passes; workbench connectivity is handled by NetworkPolicy. |
| 08 Model evaluation | Aligned with notes | `LMEvalJob` resources use the documented TrustyAI API. |
| 09 Guardrails | Aligned with notes | Uses `NemoGuardrails`; README explicitly notes Red Hat Technology Preview support scope. |
| 10 MCP integration | Aligned with intentional degraded sample | MCP/platform resources must be healthy; `acme-equipment-0007` is expected `CrashLoopBackOff` incident data. |
| 11 Face recognition | Aligned with notes | CPU OpenVINO/KServe story remains valid. |
| 12 MLOps pipeline | Aligned with notes | DSPA, MLflow, Model Registry, and `TrustyAIService` remain the strongest predictive AI platform story. |
| 13 Edge AI | Aligned with notes | Central edge simulation remains distinct from MicroShift edge deployment. |
| 13b MicroShift edge | Aligned with notes | Remote MicroShift bootstrap remains intentionally imperative; central Argo apps are still the source of truth for central resources. |

## Image Tag Classification

Broad image pinning is deferred to a follow-up backlog. Current `:latest` references are classified below so reviewers can distinguish internal build outputs, demo utilities, and external dependencies.

| Classification | Images / Areas | Decision |
|---|---|---|
| Internal build output | `enterprise-rag/rag-chatbot:latest`, `enterprise-rag/rag-ingestion-service:latest`, `quay.io/adrina/edge-camera:latest` | Accept for demo build artifacts; pin or promote immutable tags for production. |
| Demo utility | `alpine/git:latest`, `quay.io/curl/curl:latest`, `registry.access.redhat.com/ubi9/ubi-minimal:latest`, `registry.access.redhat.com/ubi9/python-311:latest`, `registry.redhat.io/ubi9/python-312:latest`, `image-registry.openshift-image-registry.svc:5000/openshift/cli:latest`, `quay.io/minio/mc:latest` | Accept temporarily for short-lived Jobs/init tasks; pin in supply-chain hardening backlog. |
| External service dependency | `quay.io/minio/minio:latest`, `registry.redhat.io/rhel9/postgresql-15:latest`, `registry.redhat.io/rhel9/postgresql-16:latest`, `registry.redhat.io/rhel9/mariadb-1011:latest`, `quay.io/docling-project/docling-serve:latest` | Higher priority for follow-up pinning because these are long-running services. |
| Removed by this batch | `quay.io/trustyai_testing/detectors/granite-guardian-hap-38m:latest` | Removed with the FMS detector stack during the NeMo migration. |

## Remaining Backlog

P1:

1. Pin high-risk long-running external dependency images by digest or immutable version.
2. Normalize Step 13b Argo CD sync options and ignore differences to match the shared app standard.
3. Decide whether deferred `qwen3-8b-agent.yaml` should be documented as future scope or removed.

P2:

1. Add custom Argo CD health checks for long-lived CRs such as `DataScienceCluster`, `ModelRegistry`, `LlamaStackDistribution`, `NemoGuardrails`, and `TrustyAIService`.
2. Add a deploy-script lint that fails on `oc apply -f gitops/<step>/base/...` unless the step is a documented remote-edge exception.
3. Expand README per-step references so each component points at the exact official documentation page used for implementation decisions.
