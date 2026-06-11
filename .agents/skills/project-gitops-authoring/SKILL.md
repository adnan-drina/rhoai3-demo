---
name: project-gitops-authoring
metadata:
  author: rhoai3-demo
  version: 1.1.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Author and update rhoai3-demo GitOps manifests, Kustomize bases, Argo CD
  Applications, labels, annotations, demo secrets, and per-stage deployment
  scripts. Use when editing gitops/**, kustomization.yaml files, Argo CD
  app-of-apps entries, operator bases and overlays, ServingRuntime annotations,
  OpenShift labels, GitOps deployment flow, demo secrets, self-signed
  certificate handling, container image source, or model artifact source. Also
  use when creating a new demo stage's GitOps folder. Pair with
  project-demo-stage-authoring when creating a new stage end to end, and with
  project-red-hat-operator-gitops when deploying Red Hat Operators through OLM
  and Kustomize. Do NOT use for readonly review only (use
  project-manifest-review) or Red Hat source alignment review only (use
  project-red-hat-doc-alignment-review).
---

# GitOps Authoring

Use this skill to make GitOps changes that remain reproducible, reviewable, and
aligned with the active product baseline.

## Workflow

1. Read `AGENTS.md`, `docs/PLATFORM_BASELINE.md`, and the affected stage README.
2. For a new stage, use `project-demo-stage-authoring` first to define scope,
   source capture, skill routing, and GitOps ownership.
3. Identify the stage folder, Argo CD Application, Kustomize base, and per-stage
   deployment script that must change together.
4. Keep code and docs atomic: manifest changes require README updates, and
   README capability claims require implemented manifests or clear deferred
   wording.
5. For GitOps structure and Argo CD standards, read
   `references/argocd-kustomize.md`.
6. For Red Hat Operator installation through OLM, Kustomize operator bases,
   channel overlays, operand instance overlays, or aggregate overlays, use
   `project-red-hat-operator-gitops`.
7. For OpenShift GitOps Operator, Argo CD product boundary, platform RBAC, or
   resource tracking questions, use `ocp-gitops-operator` first.
8. For YAML, cross-resource consistency, and validation, read
   `references/manifest-standards.md`.
9. For secrets, local `.env` handling, TLS bypasses, and demo security posture,
   read `references/security-and-secrets.md`.
10. For labels, OpenShift Topology annotations, and RHOAI Dashboard annotations,
   read `references/labels-and-annotations.md`.
11. For new or changed images, model artifacts, CR fields, or operator settings,
   use `project-red-hat-doc-alignment-review` to confirm official Red Hat docs,
   Red Hat registry sources, validated model sources, or explicitly documented
   demo exceptions.

## Output Expectations

When proposing or making changes, include:

- exact files changed
- whether the change affects manifests, deployment scripts, READMEs, or all three
- validation performed or still required
- Red Hat documentation alignment evidence when GitOps-managed components changed

## References

- `references/argocd-kustomize.md`
- `references/manifest-standards.md`
- `references/security-and-secrets.md`
- `references/labels-and-annotations.md`
- `.agents/skills/project-red-hat-operator-gitops/SKILL.md`
