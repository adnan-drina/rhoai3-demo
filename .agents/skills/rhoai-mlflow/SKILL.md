---
name: rhoai-mlflow
metadata:
  author: rhoai3-demo
  version: 1.1.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "RHOAI Platform"
description: >
  Use when documenting, reviewing, installing, configuring, or operating
  MLflow in Red Hat OpenShift AI from the official Working with MLflow guide:
  shared cluster MLflow instance, project-to-workspace mapping, Kubernetes
  RBAC authorization, DataScienceCluster mlflowoperator enablement, MLflow and
  MLflowConfig custom resources, SQLite/PVC development deployments,
  PostgreSQL and S3-compatible production-oriented deployments, aggregate
  ClusterRoles, MLflow pseudo-resources, SDK installation and authentication,
  kubernetes-namespaced auth, local workstation and pod environment variables,
  version compatibility, experiment tracking, and project-specific artifact
  storage. Do NOT use for project/workbench lifecycle (use
  rhoai-project-workflows), generic S3 object operations (use
  rhoai-s3-object-storage-data), OpenShift AI model registry workflows (use
  rhoai-model-registry or rhoai-model-registry-workflows), formal custom
  evaluation workflows (use rhoai-model-evaluation), Gen AI playground prompt
  workflows outside MLflow availability checks (use rhoai-gen-ai-playground),
  or live cluster changes without the OpenShift safety guard.
---

# RHOAI MLflow

Use this skill for Red Hat OpenShift AI MLflow platform and SDK workflows on
the active product baseline in `docs/PLATFORM_BASELINE.md`.

## Source Grounding

Read `references/source-capture.md` before using product workflow details.
Official Red Hat documentation is product authority. This skill adapts the
official Working with MLflow guide to this repo's demo workflow and GitOps
review model.

## Scope

This skill covers:

- MLflow concept model in OpenShift AI
- single shared MLflow instance deployed through the MLflow Operator
- one-to-one mapping from OpenShift projects to MLflow workspaces
- Kubernetes RBAC authorization through MLflow pseudo-resources
- enabling the `mlflowoperator` component on the `DataScienceCluster`
- cluster-scoped `MLflow` custom resource named `mlflow`
- namespace-scoped `MLflowConfig` custom resource named `mlflow`
- development/test storage with SQLite and PVC-backed artifacts
- production-oriented storage with PostgreSQL and S3-compatible object storage
- aggregate `mlflow-view`, `mlflow-edit`, and `mlflow-integration` roles
- MLflow SDK installation and `kubernetes-namespaced` authentication
- local workstation and in-cluster pod SDK configuration
- compatible MLflow server and SDK versions
- experiment tracking with parameters, metrics, and artifacts
- project-specific S3 artifact storage overrides
- common MLflow SDK troubleshooting signals

Use other skills for adjacent work:

- `rhoai-project-workflows` for project lifecycle, workbench lifecycle,
  project access, project connections, and connection creation
- `rhoai-s3-object-storage-data` for Boto3 and general object operations from
  workbenches
- `rhoai-model-registry` for OpenShift AI model registry administrator
  provisioning
- `rhoai-model-registry-workflows` for OpenShift AI model registry user
  workflows
- `rhoai-gen-ai-playground` for product prompt workflows that rely on MLflow
  availability
- `rhoai-model-customization-training` for Training Hub MLflow tracking
  parameters, run evidence, and rank-0 distributed logging context
- `rhoai-evaluation` for official EvalHub MLflow tracking and evaluation
  result evidence workflows
- `rhoai-model-evaluation` for custom EvalHub, LM-Eval, RAGAS, and
  MLflow-backed evidence workflows outside the MLflow product guide
- `rhoai-dashboard-customization` for dashboard feature flags and application
  visibility
- `rhoai-api-tiers` for MLflow REST API and `mlflows.opendatahub.io/v1`
  support posture

## Demo Policy

For this repo:

- Treat MLflow as the tracking and evidence store for experiments, runs,
  metrics, artifacts, prompts, datasets, traces, and registered model records
  when the demo needs those lifecycle records.
- Manage project and workspace lifecycle through OpenShift AI projects. Do not
  claim the MLflow API creates, updates, or deletes workspaces.
- Use GitOps for the cluster-level `MLflow` deployment once active manifests
  exist, but verify fields with official docs or `oc explain` before authoring.
- Use SQLite and file/PVC artifacts only for development, testing, or small
  demo flows. Label this as non-production.
- Use PostgreSQL and S3-compatible artifact storage for production-shaped
  enterprise narratives.
- Store database URIs with credentials in Secrets referenced by
  `backendStoreUriFrom`; do not commit database credentials.
- Keep S3 credentials in project-scoped connections or Secrets. Never commit
  access keys, secret keys, session tokens, or bucket-specific credentials.
- When `serveArtifacts` is enabled, do not set `defaultArtifactRoot` to a
  direct `s3://` URI that bypasses the MLflow server artifact proxy.
- For per-project artifact overrides, use a project Secret named
  `mlflow-artifact-connection` and an `MLflowConfig` named `mlflow`.
- Prefer `MLFLOW_TRACKING_AUTH=kubernetes-namespaced` over manual token
  exports. Treat manual `MLFLOW_TRACKING_TOKEN` use as local troubleshooting,
  not production guidance.
- Use `MLFLOW_TRACKING_INSECURE_TLS=true` only for the demo's accepted
  self-signed certificate posture.

## Workflow

1. Confirm the active baseline in `docs/PLATFORM_BASELINE.md`.
2. Read `references/source-capture.md` and
   `references/official-doc-extraction.md`.
3. Decide whether the task is:
   - MLflow concept or README authoring
   - cluster-level MLflow Operator enablement
   - `MLflow` custom resource review
   - storage and database configuration
   - RBAC and API authorization review
   - SDK installation and authentication
   - local workstation or in-pod SDK setup
   - experiment tracking code review
   - project-specific artifact storage override
   - troubleshooting MLflow SDK errors
4. Use `examples/mlflow-patterns.md` for focused review patterns.
5. For live cluster work, follow the OpenShift safety guard in `AGENTS.md`.
6. Validate with `references/validation-checklist.md`.

## Live-Verified GenAI Behaviors (2026-07-16, product MLflow 3.10.1)

Verified on cluster-qt67m against the deployed product server; these fill
gaps the guide capture does not cover. Re-verify on new product versions.

1. **AI Gateway is not exposed in this build.** `gatewayendpoints`,
   `gatewaymodeldefinitions`, and `gatewaysecrets` exist ONLY as RBAC
   pseudo-resources (rules in the `mlflow-operator-mlflow-*` ClusterRoles);
   they are NOT CRDs (`oc api-resources` lists only `mlflows` and
   `mlflowconfigs`) and the tracking server 404s every gateway REST path.
   Consequence: LLM judges cannot run from the UI; run them SDK-side
   (`mlflow.genai.scorers` / `make_judge`) with a direct OpenAI-compatible
   endpoint (`OPENAI_BASE_URL` + `OPENAI_API_KEY`, judge URI
   `openai:/<model>`); verdicts land as trace assessments.
2. **Scorers have no server-side registry** (all `/scorers` REST paths
   404): the Judges UI stays sparse; assessments on traces are the visible
   artifact.
3. **Feature-to-REST map:** evaluation datasets are a v3-only surface
   (`POST /api/3.0/mlflow/datasets/search`; 2.0 paths 404); traces are v3
   (`POST /api/3.0/mlflow/traces/search`, requires structured `locations`
   plus the workspace header); logged-models search is 2.0-only and
   requires `experiment_ids`; prompts have NO dedicated REST path - the
   SDK (`mlflow.genai.register_prompt` / `load_prompt` / `search_prompts`)
   layers them on the registered-models registry.
4. **Sessions** = trace metadata key `mlflow.trace.session`; set per
   interaction with `mlflow.update_current_trace` and filter with
   ``metadata.`mlflow.trace.session` = '<id>'``.
5. **Agent versions** = LoggedModels: `mlflow.set_active_model(name=...)`
   links subsequent traces to the app version (`mlflow.modelId` metadata).
6. **Every request needs workspace context**: bearer SA token plus
   `X-MLFLOW-WORKSPACE: <namespace>` (or `?workspace=`); a valid token
   without it gets HTTP 400.
7. **`oc auth can-i` is misleading for pseudo-resources**: it reports "no"
   even for identities the server authorizes; ground truth is a REST call
   with the SA token.
8. **Client telemetry**: the SDK posts usage telemetry to
   api.mlflow-telemetry.io unless `MLFLOW_DISABLE_TELEMETRY=true` is set
   on the CLIENT (the server env only covers the server).
9. **Gen AI studio "Prompts" page** is the dashboard surface of the
   workspace prompt registry (official 3.4 docs).
10. **KFP interplay**: DSPA MariaDB rejects pipeline manifests whose
    embedded component source contains multi-byte characters (Error 1366)
    - keep evaluation-component source ASCII-only. Binary chatbot builds
    reject `--build-arg`; ship version identity as a file in the build
    context.

Working integration reference: Stage 230 chatbot
(`stage-230-private-data-rag/chatbot/.../modules/tracing.py` - tracing,
sessions, agent versions, prompt registration) and
`stage-230-private-data-rag/kfp/mlflow_genai_evaluation_pipeline.py` +
`run-mlflow-evaluation.sh` (datasets, evaluation runs, judges).

## References

- `references/source-capture.md`
- `references/official-doc-extraction.md`
- `references/validation-checklist.md`
- `examples/mlflow-patterns.md`
