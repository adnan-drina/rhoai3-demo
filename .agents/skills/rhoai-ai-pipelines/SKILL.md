---
name: rhoai-ai-pipelines
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "RHOAI Platform"
description: >
  Use when documenting, reviewing, or operating Red Hat OpenShift AI AI
  Pipelines from the Working with AI pipelines guide: pipeline server
  configuration, S3-compatible artifact storage, default versus external
  MySQL/MariaDB metadata databases, Kubernetes API pipeline definition storage,
  KFP 2.0 SDK compilation, Pipeline and PipelineVersion custom resources,
  pipeline import/delete/version lifecycle, caching controls, experiments,
  active/scheduled/archived runs, run workspaces, pipeline logs, Elyra
  JupyterLab pipeline workflows, and DSPA component troubleshooting. Do NOT use
  for repo-specific KFP component code edits (use rhoai-kfp-pipeline-authoring),
  generic project/workbench lifecycle (use rhoai-project-workflows), IDE usage
  outside pipelines (use rhoai-data-science-ide-workflows), S3 notebook data
  operations (use rhoai-s3-object-storage-data), certificate trust changes
  outside pipeline context (use rhoai-certificate-management), Spark data
  processing applications (use rhoai-kubeflow-spark-operator), or live cluster
  changes without the OpenShift safety guard.
---

# RHOAI AI Pipelines

Use this skill for Red Hat OpenShift AI AI Pipelines product workflows on the
active product baseline in `docs/PLATFORM_BASELINE.md`.

## Source Grounding

Read `references/source-capture.md` before using product workflow details.
Official Red Hat documentation is product authority. This skill adapts the
official Working with AI pipelines guide to this repo's GitOps and demo
workflow model.

## Scope

This skill covers:

- pipeline concepts: pipeline server, pipeline, pipeline version, experiment,
  artifact, task execution, and run
- pipeline server configuration with S3-compatible object storage and database
  choices
- external MySQL/MariaDB and Amazon RDS certificate trust handoff
- KFP 2.0 SDK pipeline compilation to IR YAML
- Kubernetes API storage, `Pipeline`, `PipelineVersion`, and GitOps-aligned
  pipeline definition management
- KFP SDK authentication to an OpenShift AI pipeline server
- pipeline import, delete, version upload/delete/view/download lifecycle
- caching behavior and cache controls at task, run, compile, and server levels
- experiments, artifacts, task executions, comparisons, archive/restore/delete
- active, scheduled, archived, duplicated, stopped, restored, and deleted runs
- pipeline run workspace support and external artifact copy pattern
- pipeline step logs and download behavior
- Elyra JupyterLab pipeline editor runtime configuration, run, and export
- DSPA component error interpretation and troubleshooting handoff

Use other skills for adjacent work:

- `rhoai-kfp-pipeline-authoring` for editing repo KFP Python code, components,
  runner scripts, and demo-specific pipeline implementation standards
- `rhoai-project-workflows` for project, workbench, connection, and cluster
  storage lifecycle
- `rhoai-data-science-ide-workflows` for non-pipeline JupyterLab and
  code-server IDE workflows
- `rhoai-s3-object-storage-data` for notebook object-storage data operations
- `rhoai-automl` for AutoML optimization runs, leaderboard evaluation,
  AutoGluon pipeline naming, saved notebooks, and AutoGluon serving handoff
- `rhoai-autorag` for AutoRAG optimization runs, imported AutoRAG pipeline
  naming, leaderboard review, and generated indexing/inference notebooks
- `rhoai-model-customization-training` for Docling, SDG Hub, Training Hub, and
  end-to-end model customization pipeline patterns
- `rhoai-evaluation` for EvalHub risk assessment KFP orchestration and
  official LM-Eval or EvalHub evaluation workflows
- `rhoai-certificate-management` for DSCI trusted CA bundle changes
- `rhoai-storage-classes` for OpenShift AI storage class administration
- `rhoai-model-evaluation` for evaluation-specific pipeline evidence and
  metrics patterns
- `rhoai-kubeflow-spark-operator` for Spark data processing applications that
  run through `SparkApplication` resources rather than AI Pipelines

## Demo Policy

For this repo:

- Prefer Kubernetes API pipeline definition storage when the demo needs
  reviewed GitOps desired state for pipeline definitions and versions.
- Keep pipeline server configuration in GitOps only after fields are verified
  against official docs or active CRD schema.
- Treat the default on-cluster database as development/test only. For
  production-positioned pipeline workloads, document the external MySQL or
  MariaDB requirement and CA trust path.
- Use S3-compatible object storage for pipeline artifacts and keep credentials
  project-scoped and out of Git.
- Do not pass OpenShift access tokens as literal command arguments. Use
  environment variables or secure prompts.
- Use exact KFP SDK and Python prerequisites from the active official docs
  before compiling or authenticating pipelines.
- Use caching intentionally. Disable it only for tasks or runs that require
  deterministic re-execution, debugging, or frequently changing inputs.
- Treat archive as retention and delete as destructive. Require explicit
  confirmation for deleting pipeline servers, pipelines, versions, archived
  experiments, and archived runs.
- Use Elyra only with supported JupyterLab workbench images. Do not claim Elyra
  support for code-server, RStudio, Minimal Python, or CUDA-based workbenches.
- If an official example uses placeholder or mutable model artifacts, replace
  them with verified demo artifacts before committing demo content.

## Workflow

1. Confirm the active baseline in `docs/PLATFORM_BASELINE.md`.
2. Read `references/source-capture.md` and
   `references/official-doc-extraction.md`.
3. Decide whether the task is:
   - pipeline server setup or deletion
   - pipeline definition, import, version, or GitOps/Kubernetes API storage
   - KFP SDK compilation or authentication
   - caching configuration
   - experiment, artifact, or run management
   - scheduling and duplicate-run workflow
   - workspace or external artifact use
   - logs, Elyra, or DSPA troubleshooting
4. Use `examples/ai-pipelines-patterns.md` for focused review patterns.
5. For repo KFP code edits, pair with `rhoai-kfp-pipeline-authoring`.
6. For live cluster work, follow the OpenShift safety guard in `AGENTS.md`.
7. Validate with `references/validation-checklist.md`.

## References

- `references/source-capture.md`
- `references/official-doc-extraction.md`
- `references/validation-checklist.md`
- `examples/ai-pipelines-patterns.md`
