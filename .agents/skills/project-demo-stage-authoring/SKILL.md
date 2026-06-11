---
name: project-demo-stage-authoring
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Use when creating, planning, implementing, or reviewing a new rhoai3-demo
  demo stage from ideation to validated GitOps implementation. Covers stage
  scope, dependencies, Red Hat narrative and official product source capture,
  Red Hat-team GitHub reference implementation discovery,
  skill routing, README Why/What/Architecture drafting, PLAN.md creation,
  GitOps ownership decisions, Argo CD Application setup, Kustomize manifests,
  official-doc-backed configuration, deploy and validation scripts, operations
  and troubleshooting updates, source-alignment review, manifest review, and
  definition-of-done gates. Do NOT use as product authority for RHOAI, OCP,
  ODF, Grafana, or other component APIs; route those details to the matching
  rhoai-*, ocp-*, odf-*, or project-red-hat-operator-gitops skill.
---

# Demo Stage Authoring

Use this skill as the repeatable process for turning a demo idea into a
validated Red Hat product demo stage. A stage is not complete until its
documentation, GitOps, scripts, validation, source grounding, and operational
notes move together.

## Core Rule

Every new stage must pass the same phase gates:

1. intent and scope
2. source capture
3. skill routing
4. implementation plan
5. README story
6. GitOps ownership
7. manifest generation
8. deploy and validation scripts
9. operations and troubleshooting updates
10. review and acceptance

Do not start the next demo stage until the current stage has an explicit
definition of done and the user accepts any deferred work.

## Stage Artifact Contract

Prefer this artifact set for a normal independent stage:

```text
stage-YXX-slug/
  README.md
  PLAN.md
  deploy.sh
  validate.sh
gitops/
  argocd/app-of-apps/stage-YXX-slug.yaml
  stage-YXX-slug/base/kustomization.yaml
  stage-YXX-slug/overlays/<purpose>/kustomization.yaml
```

Shared platform resources are the main exception. If a stage introduces a
capability by patching a shared owner such as the RHOAI `DataScienceCluster`,
ODF storage layer, OpenShift GitOps bootstrap, or Grafana observability layer,
record the shared owner path in `PLAN.md` and avoid duplicate full-resource
ownership.

## Workflow

1. Read `references/stage-lifecycle.md`.
2. Create or update the stage `PLAN.md` using
   `examples/stage-plan-template.md`.
3. Use `references/stage-taxonomy.md` to choose the `stage-YXX-slug` identifier.
4. Capture sources with `references/source-capture-checklist.md`.
5. Use `.agents/references/red-hat-doc-map.yaml` to route official product
   docs to existing `rhoai-*`, `ocp-*`, or `odf-*` skills.
6. Search for relevant GitHub reference implementations from Red Hat product,
   field, solution, or community-of-practice teams; use them as implementation
   patterns only after official docs are captured.
7. Prefer `rh-brain` narrative sources that link to concrete GitHub projects
   or code examples when multiple Red Hat articles cover the same concept.
8. If required product coverage is missing, create or update the product skill
   before authoring manifests.
9. Draft the stage README with `project-documentation-authoring` and
   `references/stage-lifecycle.md`.
10. Design GitOps with `project-gitops-authoring` and, for Operators,
   `project-red-hat-operator-gitops`.
11. Generate manifests only from official docs, active skills, verified live
   schema, locally curated reference implementations, or explicitly documented
   demo exceptions.
12. Add deploy and validation scripts only after the GitOps ownership decision
   is clear. Scripts that touch a live cluster must use the repo OpenShift
   safety guard.
13. Run the quality gates in `references/definition-of-done.md`.
14. Use `project-manifest-review` and
   `project-red-hat-doc-alignment-review` before treating the stage as ready.

## Required Handoffs

- `project-documentation-authoring`: README, PLAN.md, operations,
  troubleshooting, and backlog updates.
- `project-gitops-authoring`: Kustomize, Argo CD Application, labels,
  annotations, scripts, and secret handling.
- `project-red-hat-operator-gitops`: Operator Subscription, channel overlays,
  operand instance resources, aggregate overlays, and lifecycle management.
- `project-manifest-review`: structural and security review of rendered
  manifests.
- `project-red-hat-doc-alignment-review`: Red Hat narrative, official docs,
  API fields, images, model artifacts, and support posture review.
- `env-deploy-and-evaluate`: live deployment and validation once active
  scripts exist.
- Matching `rhoai-*`, `ocp-*`, and `odf-*` skills: product-specific behavior.

## Stop Conditions

Stop and resolve before implementation if:

- the stage concept has no clear audience value
- required official product docs or product skills are missing
- a custom resource field, API version, operator channel, image, or model
  artifact cannot be sourced or verified
- the GitOps ownership model would create duplicate owners for a shared
  resource
- required credentials or tokens would be committed
- deploy or validate scripts would touch a live cluster without the safety
  guard
- the README claims a capability that manifests and validation do not provide

## References

- `references/stage-lifecycle.md`
- `references/stage-taxonomy.md`
- `references/source-capture-checklist.md`
- `references/definition-of-done.md`
- `examples/stage-plan-template.md`
