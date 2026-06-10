---
name: rhoai-kfp-pipeline-authoring
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "RHOAI Platform"
description: >
  Author, refactor, and review Kubeflow Pipelines v2 pipelines for the
  rhoai3-demo steps once active KFP content exists; during the reimplementation,
  use this skill to rebuild KFP standards from legacy references. Use when
  editing steps/**/kfp/**/*.py, KFP components, pipeline runner scripts, DSPA
  client code, pipeline PVC/RBAC integration, Output[Metrics]/Output[Model]/
  Output[HTML] artifacts, caching behavior, or RHOAI Dashboard pipeline
  visibility. Do NOT use for AI Pipelines product lifecycle, pipeline server
  setup, dashboard import/version/run/schedule operations, Elyra runtime
  configuration, or DSPA troubleshooting (use rhoai-ai-pipelines). Do NOT use
  for generic GitOps changes unless paired with project-gitops-authoring.
---

# KFP Pipeline Authoring

Use this skill when working on KFP v2 pipelines in the RHOAI demo.

Use `rhoai-ai-pipelines` first for official product behavior around pipeline
servers, KFP SDK prerequisites, Kubernetes API storage, pipeline versions,
caching, experiments, runs, schedules, logs, Elyra, workspaces, and DSPA
troubleshooting. Use this skill when the task reaches repo-specific pipeline
Python, components, compiled artifacts, or runner scripts.

## Reimplementation Status

The active implementation is being rewritten. No active KFP pipeline
implementation or step runner scripts exist yet. Treat references to previous
step folders as legacy examples for rebuilding pipeline standards, not as
active-project paths.

Do not run or modify scripts from `backup/legacy-implementation-2026-06-09/`
unless the user explicitly asks to restore or inspect the legacy implementation.

## Workflow

1. Read the affected step README and existing KFP implementation.
2. Treat Step 12 (`steps/step-12-mlops-pipeline/kfp/`) as the reference
   implementation unless the task explicitly changes that standard.
3. Read `references/kfp-patterns.md` before editing pipeline definitions,
   components, runner scripts, artifacts, or DSPA client code.
4. Keep pipeline infrastructure in GitOps and compiled/uploaded pipeline
   definitions in step scripts.
5. Keep component functions hermetic, typed, Dashboard-visible where possible,
   and aligned with `rhoai-ai-pipelines` and the active official documentation.

## Validation

- Compile changed pipelines locally when possible.
- Validate runner scripts with shell syntax checks.
- If cluster execution is needed, follow the OpenShift safety guard in
  `AGENTS.md` before suggesting or running live commands.

## References

- `references/kfp-patterns.md`
- `../rhoai-model-evaluation/references/kfp-advanced-patterns.md`
