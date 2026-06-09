---
name: env-deploy-and-evaluate
metadata:
  author: rhoai3-demo
  version: 2.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Demo Environment"
description: >
  Deploy and validate the rhoai3-demo environment on the active OpenShift
  baseline once active scripts and steps exist. During the reimplementation,
  use this skill to rebuild the deployment workflow from legacy references.
  Use when the user asks to deploy the demo, set up a new AWS demo environment,
  evaluate an existing deployment, re-deploy a specific step, check deployment
  status, run the ordered step sequence, or asks "is my cluster ready?". Also
  use for planned ArgoCD sync and deployment reports.
  Do NOT use for chatbot UI/prompt changes (use rhoai-chatbot-customization),
  model evaluation or benchmarking (use rhoai-model-evaluation), or diagnosis after a
  specific failing component is observed (use env-troubleshoot).
---

# Deploy and Evaluate RHOAI Demo

Orchestrates a controlled, step-by-step deployment of the RHOAI demo on the
active product baseline in `docs/PLATFORM_BASELINE.md`.

## Reimplementation Status

The active implementation is being rewritten. No active bootstrap, deploy,
validate, or demo-flow scripts exist yet. Treat the deployment sequence and
legacy command references in this skill as reference material for rebuilding
the workflow, not as runnable active-project instructions.

Do not run scripts from `backup/legacy-implementation-2026-06-09/` unless the
user explicitly asks to restore or inspect the legacy implementation.

## When to Use

- Deploying the demo to a fresh cluster
- Evaluating an existing deployment for completeness
- Re-deploying a specific step after a fix
- Running the full step sequence, including optional edge paths

## Instructions

### Code and Documentation Must Be Aligned

**NEVER update documentation without updating the corresponding code, and vice versa.** Partial changes — updating a README design decision without changing the manifest, or changing a manifest without updating the README — are prohibited. Every change must be atomic: code + docs + SKILL knowledge in the same commit.

### One Step at a Time

**NEVER advance to the next step until the current step fully validates.**

1. **Read** the active step README once a step exists.
2. **Deploy** with the active `deploy.sh` once recreated; it must apply the
   ArgoCD Application as its first action.
3. **Wait** — operators take minutes, GPU nodes take 5-10 min
4. **Diagnose** — consult official docs for the active baseline; use the `env-troubleshoot` skill for issues
5. **Validate** with the active `validate.sh` once recreated; confirm exit code
   0 (exit 2 = warnings only, acceptable).
6. **Record** — note result, move to next step

### Deployment Sequence

```
01  GPU Infrastructure & Prerequisites
02  RHOAI Platform
03  Private AI / GPU-as-a-Service (MinIO, auth, RBAC)
04  Model Registry
05  LLM on vLLM (granite-8b-agent + mistral-3-bf16 active; additional models in Registry)
06  Model Metrics (Grafana, GuideLLM benchmarks)
07  RAG (pgvector, Docling, DSPA, LlamaStack RAG)
08  Model Evaluation (pre/post RAG with LLM-as-Judge)
09  Guardrails (NeMo guardrails)
10  MCP Integration (database-mcp, openshift-mcp, slack-mcp)
11  Face Recognition (YOLO11 + OpenVINO, CPU-only predictive AI)
12  MLOps Pipeline (KFP training + Model Registry + TrustyAI monitoring)
13  Edge AI
13b Edge AI on MicroShift (optional)
```

### Step Dependencies

```
01  (standalone — bootstrap required)
02  requires 01
03  requires 01, 02
04  requires 01, 02, 03
05  requires 01, 02, 03 (+ GPU nodes + model uploads)
06  requires 01, 05
07  requires 01-05
08  requires 07
09  requires 02, 05
10  requires 05, 07
11  requires 01-03 (CPU-only, no GPU needed)
12  requires 03, 05, 11 (KFP pipeline + Model Registry + face-recognition ISVC)
13  requires 05, 11
13b requires 13 and separate MicroShift target preparation
```

### Resource Configuration

| Node | GPUs | Active Model | Role |
|------|------|-------------|------|
| g6.4xlarge (1 GPU) | 1 | `granite-8b-agent` (FP8) | RAG, MCP, Guardrails, Playground |
| g6.12xlarge (4 GPU) | 4 | `mistral-3-bf16` (BF16) | LLM judge, Playground, Benchmarking |

### GitOps Deployment Pattern

Every future `deploy.sh` must apply an ArgoCD Application as its first action:
```bash
oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/$STEP_NAME.yaml"
```
Never apply manifests directly with `oc apply -k` for ArgoCD-managed resources.

### Final E2E Validation

After the demo-flow script has been recreated and all steps pass:
```bash
./scripts/validate-demo-flow.sh
```

### Evaluation Report Template

```markdown
# RHOAI Demo Deployment Report
**Cluster:** <api-url>  **Date:** <YYYY-MM-DD>
**GPU Config:** 1x g6.4xlarge + 1x g6.12xlarge

| Step | Name | Status | Duration |
|------|------|--------|----------|
| 01 | GPU & Prerequisites | PASS | Xm |
| ... | ... | ... | ... |
| E2E | Demo Flow | PASS | Xm |
```

### Prerequisite Check

Before deploying to a fresh cluster, first read the Fresh Environment Checklist
in `docs/OPERATIONS.md`. Confirm local `.env` has the new environment's
`KUBECONFIG`, `RHOAI_EXPECTED_API_SERVER`, `GIT_REPO_URL`, `GIT_REPO_BRANCH`,
and required local credentials. Then run the prerequisite validation if that
skill helper is still present:
```bash
./.agents/skills/env-deploy-and-evaluate/scripts/validate-prerequisites.sh
```
Exit codes: 0 = ready, 1 = blocking failures, 2 = warnings only.

For per-step deploy notes, known issues, and ArgoCD standards, read `references/deploy-notes.md`.
