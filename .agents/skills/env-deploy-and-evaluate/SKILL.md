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
  baseline once active scripts and stages exist. During the reimplementation,
  use this skill to rebuild the deployment workflow from legacy references.
  Use when the user asks to deploy the demo, set up a new AWS demo environment,
  evaluate an existing deployment, re-deploy a specific stage, check deployment
  status, run the ordered stage sequence, or asks "is my cluster ready?". Also
  use for planned ArgoCD sync and deployment reports.
  Do NOT use for chatbot UI/prompt changes (use rhoai-chatbot-customization),
  model evaluation or benchmarking (use rhoai-model-evaluation), or diagnosis after a
  specific failing component is observed (use env-troubleshoot).
---

# Deploy and Evaluate RHOAI Demo

Orchestrates a controlled, stage-by-stage deployment of the RHOAI demo on the
active product baseline in `docs/PLATFORM_BASELINE.md`.

## Reimplementation Status

The active implementation is being rewritten. Stage 110 and Stage 120 have
active deploy and validate wrappers. Later stages remain planned until their
root-level stage folders and Argo CD Applications are created.

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

### One Stage at a Time

**NEVER advance to the next stage until the current stage fully validates.**

1. **Read** the active stage README once a stage exists.
2. **Deploy** with the active `deploy.sh` once recreated; it must apply the
   ArgoCD Application as its first action.
3. **Wait** — operators take minutes, GPU nodes take 5-10 min
4. **Diagnose** — consult official docs for the active baseline; use the `env-troubleshoot` skill for issues
5. **Validate** with the active `validate.sh` once recreated; confirm exit code
   0 (exit 2 = warnings only, acceptable).
6. **Record** — note result, move to the next stage

### Deployment Sequence

Use the taxonomy in
`.agents/skills/project-demo-stage-authoring/references/stage-taxonomy.md`.
The active sequence is defined by existing root-level `stage-YXX-slug/`
folders and their Argo CD Applications.

Candidate flow for the reimplementation:

```
100  AI Platform Foundation
200  Production GenAI & Private Data
300  Agentic AI & Enterprise Integration
400  AI Operations, Evaluation & MLOps
```

Within each family, deploy lower stage identifiers before higher ones unless a
stage `PLAN.md` documents a different dependency.

### Resource Configuration

| Node | GPUs | Active Model | Role |
|------|------|-------------|------|
| g6e.2xlarge | 1 L40S node, time-sliced to 4 units | `nemotron-3-nano-30b-a3b` (FP8 modelcar) in later stages | Private GenAI serving and benchmarking |
| External provider | 0 | OpenAI `gpt-5.4-mini` through MaaS using resource alias `gpt-5-4-mini` | Approved external model path when policy allows |

### GitOps Deployment Pattern

Every future `deploy.sh` must apply an ArgoCD Application as its first action:
```bash
oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/$STAGE_NAME.yaml"
```
Never apply manifests directly with `oc apply -k` for ArgoCD-managed resources.

### Final E2E Validation

After the demo-flow script has been recreated and all stages pass:
```bash
./scripts/validate-demo-flow.sh
```

### Evaluation Report Template

```markdown
# RHOAI Demo Deployment Report
**Cluster:** <api-url>  **Date:** <YYYY-MM-DD>
**GPU Config:** 1x g6e.2xlarge by default; 1 GPU per node

| Stage | Name | Status | Duration |
|------|------|--------|----------|
| 110 | RHOAI Base Platform | PASS | Xm |
| 120 | GPU-as-a-Service | PASS | Xm |
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

For per-stage deploy notes, known issues, and ArgoCD standards, read `references/deploy-notes.md`.
