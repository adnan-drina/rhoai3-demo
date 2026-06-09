---
name: project-gitops-authoring
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Author and update rhoai3-demo GitOps manifests, Kustomize bases, Argo CD
  Applications, labels, annotations, demo secrets, and per-step deployment
  scripts. Use when editing gitops/**, kustomization.yaml files, Argo CD
  app-of-apps entries, ServingRuntime annotations, OpenShift labels, GitOps
  deployment flow, demo secrets, or self-signed certificate handling. Also use
  when creating a new demo step's GitOps folder. Do NOT use for readonly review
  only (use project-manifest-review) or product-doc conformance review only
  (use project-red-hat-doc-alignment-review).
---

# GitOps Authoring

Use this skill to make GitOps changes that remain reproducible, reviewable, and
aligned with the active product baseline.

## Workflow

1. Read `AGENTS.md`, `docs/PLATFORM_BASELINE.md`, and the affected step README.
2. Identify the step folder, Argo CD Application, Kustomize base, and per-step
   deployment script that must change together.
3. Keep code and docs atomic: manifest changes require README updates, and
   README capability claims require implemented manifests or clear deferred
   wording.
4. For GitOps structure and Argo CD standards, read
   `references/argocd-kustomize.md`.
5. For YAML, cross-resource consistency, and validation, read
   `references/manifest-standards.md`.
6. For secrets, local `.env` handling, TLS bypasses, and demo security posture,
   read `references/security-and-secrets.md`.
7. For labels, OpenShift Topology annotations, and RHOAI Dashboard annotations,
   read `references/labels-and-annotations.md`.

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
