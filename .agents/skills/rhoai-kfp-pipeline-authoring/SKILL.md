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
  rhoai3-demo steps. Use when editing steps/**/kfp/**/*.py, KFP components,
  pipeline runner scripts, DSPA client code, pipeline PVC/RBAC integration,
  Output[Metrics]/Output[Model]/Output[HTML] artifacts, caching behavior, or
  RHOAI Dashboard pipeline visibility. Do NOT use for generic GitOps changes
  unless paired with project-gitops-authoring.
---

# KFP Pipeline Authoring

Use this skill when working on KFP v2 pipelines in the RHOAI demo.

## Workflow

1. Read the affected step README and existing KFP implementation.
2. Treat Step 12 (`steps/step-12-mlops-pipeline/kfp/`) as the reference
   implementation unless the task explicitly changes that standard.
3. Read `references/kfp-patterns.md` before editing pipeline definitions,
   components, runner scripts, artifacts, or DSPA client code.
4. Keep pipeline infrastructure in GitOps and compiled/uploaded pipeline
   definitions in step scripts.
5. Keep component functions hermetic, typed, Dashboard-visible where possible,
   and aligned with the active RHOAI pipeline documentation.

## Validation

- Compile changed pipelines locally when possible.
- Validate runner scripts with shell syntax checks.
- If cluster execution is needed, follow the OpenShift safety guard in
  `AGENTS.md` before suggesting or running live commands.

## References

- `references/kfp-patterns.md`
- `../rhoai-model-evaluation/references/kfp-advanced-patterns.md`
