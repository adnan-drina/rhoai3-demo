---
name: project-demo-step-authoring
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Use when creating, planning, implementing, or reviewing a new rhoai3-demo
  demo step from ideation to validated GitOps implementation. Covers step
  scope, dependencies, Red Hat narrative and official product source capture,
  skill routing, README Why/What/Architecture drafting, PLAN.md creation,
  GitOps ownership decisions, Argo CD Application setup, Kustomize manifests,
  official-doc-backed configuration, deploy and validation scripts, operations
  and troubleshooting updates, source-alignment review, manifest review, and
  definition-of-done gates. Do NOT use as product authority for RHOAI, OCP,
  ODF, Grafana, or other component APIs; route those details to the matching
  rhoai-*, ocp-*, odf-*, or project-red-hat-operator-gitops skill.
---

# Demo Step Authoring

Use this skill as the repeatable process for turning a demo idea into a
validated Red Hat product demo step. A step is not complete until its
documentation, GitOps, scripts, validation, source grounding, and operational
notes move together.

## Core Rule

Every new step must pass the same phase gates:

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

Do not start the next demo step until the current step has an explicit
definition of done and the user accepts any deferred work.

## Step Artifact Contract

Prefer this artifact set for a normal independent step:

```text
steps/step-XX-slug/
  README.md
  PLAN.md
  deploy.sh
  validate.sh
gitops/
  argocd/app-of-apps/step-XX-slug.yaml
  step-XX-slug/base/kustomization.yaml
  step-XX-slug/overlays/<purpose>/kustomization.yaml
```

Shared platform resources are the main exception. If a step introduces a
capability by patching a shared owner such as the RHOAI `DataScienceCluster`,
ODF storage layer, OpenShift GitOps bootstrap, or Grafana observability layer,
record the shared owner path in `PLAN.md` and avoid duplicate full-resource
ownership.

## Workflow

1. Read `references/step-lifecycle.md`.
2. Create or update the step `PLAN.md` using
   `examples/step-plan-template.md`.
3. Capture sources with `references/source-capture-checklist.md`.
4. Use `.agents/references/red-hat-doc-map.yaml` to route official product
   docs to existing `rhoai-*`, `ocp-*`, or `odf-*` skills.
5. If required product coverage is missing, create or update the product skill
   before authoring manifests.
6. Draft the step README with `project-documentation-authoring` and
   `references/step-lifecycle.md`.
7. Design GitOps with `project-gitops-authoring` and, for Operators,
   `project-red-hat-operator-gitops`.
8. Generate manifests only from official docs, active skills, verified live
   schema, or explicitly documented demo exceptions.
9. Add deploy and validation scripts only after the GitOps ownership decision
   is clear. Scripts that touch a live cluster must use the repo OpenShift
   safety guard.
10. Run the quality gates in `references/definition-of-done.md`.
11. Use `project-manifest-review` and
   `project-red-hat-doc-alignment-review` before treating the step as ready.

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

- the step concept has no clear audience value
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

- `references/step-lifecycle.md`
- `references/source-capture-checklist.md`
- `references/definition-of-done.md`
- `examples/step-plan-template.md`
