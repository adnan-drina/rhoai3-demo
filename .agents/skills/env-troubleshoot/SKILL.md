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
  Diagnose and fix issues in the live rhoai3-demo AWS/OpenShift environment.
  Use when a deployment step fails, validate.sh reports errors, pods are in
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

## When to Use

- A `validate.sh` script reports failures
- A `deploy.sh` script errors out or hangs
- Pods are stuck in CrashLoopBackOff, Pending, or Error
- ArgoCD shows OutOfSync, ComparisonError, or Degraded
- LlamaStack, Guardrails, or MCP tools are not working

## Instructions

**Never guess.** Every diagnosis must be backed by official documentation or observable cluster state.

### Step 1: Run the Validation Script

```bash
./steps/step-XX-<name>/validate.sh
```
Check exit code: 0 = pass, 1 = failures, 2 = warnings only.

### Step 2: Consult Official RHOAI Documentation

Use official docs for the active baseline in `docs/PLATFORM_BASELINE.md`.
Focus on the relevant section:

| Steps | Doc Section |
|-------|-------------|
| 01, 02 | Installing and Uninstalling |
| 03 | Managing Resources |
| 04 | Enabling Model Registry |
| 05 | Deploying Models, GenAI Playground |
| 07 | Working with LlamaStack / RAG |
| 08 | Evaluating AI Systems |
| 09 | AI Safety with Guardrails |
| 10 | GenAI Playground (MCP Servers) |
| 11 | Deploying Models (OpenVINO, KServe) |
| 12 | Working with AI Pipelines, Managing Model Registries |

### Step 3: Gather Cluster State

Start with the readonly workflow in `references/cluster-inspection.md`, then
run targeted commands from `references/diagnostic-commands.md` for the failing
component.

### Step 4: Match to Known Pattern

Check `references/diagnostic-patterns.md` for the symptom. Common patterns cover ArgoCD, operators, pods, LlamaStack, guardrails, and MCP.

### Step 5: Apply Fix and Verify

Execute the smallest change that fixes the issue. Re-run `validate.sh` to confirm.

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
