---
name: env-troubleshoot
metadata:
  author: rhoai3-demo
  version: 2.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Demo Environment"
description: >
  Diagnose and fix issues in the live rhoai3-demo AWS/OpenShift environment
  once active deploy and validate scripts exist. During the reimplementation,
  use this skill to rebuild troubleshooting coverage from legacy references.
  Use when a deployment stage fails, validate.sh reports errors, pods are in
  CrashLoopBackOff/Pending/Error/ImagePullBackOff, ArgoCD shows OutOfSync or
  Degraded, operators are not installing, GPU nodes are not joining,
  InferenceServices are not Ready, LlamaStack returns errors, Guardrails
  Orchestrator is unhealthy, MCP tools are failing, or the user reports any
  problem with their OpenShift AI environment. Also use when the user asks
  "why isn't X working?" for any demo component.
  Do NOT use for chatbot UI/prompt changes (use rhoai-chatbot-customization) or
  model evaluation workflows (use rhoai-model-evaluation).
---

# RHOAI Troubleshooting

Structured diagnostic workflow for resolving issues with the RHOAI demo on the
active product baseline in `docs/PLATFORM_BASELINE.md`.

## Reimplementation Status

The active implementation is being rewritten. No active deploy or validate
scripts exist yet. Treat legacy step names, validation commands, and diagnostic
patterns in this skill as reference material for rebuilding troubleshooting
coverage, not as active-project instructions.

Do not run scripts from `backup/legacy-implementation-2026-06-09/` unless the
user explicitly asks to restore or inspect the legacy implementation.

## When to Use

- A `validate.sh` script reports failures
- A `deploy.sh` script errors out or hangs
- Pods are stuck in CrashLoopBackOff, Pending, or Error
- ArgoCD shows OutOfSync, ComparisonError, or Degraded
- LlamaStack, Guardrails, or MCP tools are not working

## Instructions

**Never guess.** Every diagnosis must be backed by official documentation or observable cluster state.

### Step 1: Run the Validation Script When It Exists

```bash
./stage-YXX-slug/validate.sh
```
Check exit code: 0 = pass, 1 = failures, 2 = warnings only. During the
reimplementation, skip this check until active validation scripts are recreated.

### Step 2: Consult Official RHOAI Documentation

Use official docs for the active baseline in `docs/PLATFORM_BASELINE.md`.
Focus on the relevant section by using `.agents/references/red-hat-doc-map.yaml`
and the stage family:

| Stage family | Primary docs route |
|--------------|--------------------|
| `1xx` | OCP, ODF, RHOAI install, DSCI/DSC, users/groups, accelerators, observability |
| `2xx` | RHOAI model serving, model catalog, model registry, MaaS, RAG, guardrails |
| `3xx` | RHOAI Llama Stack, Gen AI Studio, MCP, connected applications |
| `4xx` | RHOAI AI Pipelines, MLflow, evaluation, monitoring, distributed workloads |
| `5xx` | Edge or applied AI product docs selected by the stage `PLAN.md` |

### Step 3: Gather Cluster State

Start with the readonly workflow in `references/cluster-inspection.md`, then
run targeted commands from `references/diagnostic-commands.md` for the failing
component.

### Step 4: Match to Known Pattern

Check `references/diagnostic-patterns.md` for the symptom. Common patterns cover ArgoCD, operators, pods, LlamaStack, guardrails, and MCP.

### Step 5: Apply Fix and Verify

Execute the smallest change that fixes the issue. Re-run the active
`validate.sh` to confirm when it exists.

### Step 6: Update Knowledge Base

If this was a new issue, update the `env-deploy-and-evaluate` skill's `references/deploy-notes.md` with the new known issue.

## Escalation Protocol

If unresolved after one diagnostic cycle:
1. Document what was tried and observed
2. Include exact error messages and `oc` output
3. Suggest manual checks
4. Report to the user with full context

## References

- `references/cluster-inspection.md`
- `references/diagnostic-commands.md`
- `references/diagnostic-patterns.md`
