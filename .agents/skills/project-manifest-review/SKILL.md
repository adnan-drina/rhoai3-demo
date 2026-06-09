---
name: project-manifest-review
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Review Kubernetes, OpenShift, Argo CD, and RHOAI manifests for structural
  correctness, cross-resource consistency, label compliance, security posture,
  YAML standards, and orphaned resources. Use when reviewing GitOps changes,
  adding a new step, checking a kustomization, auditing labels, or running a
  periodic manifest compliance pass. Do NOT use for authoring new manifests
  unless paired with project-gitops-authoring.
---

# Manifest Review

Use this skill as a readonly review workflow. Report findings; do not modify
files unless the user asks for fixes.

## Workflow

1. Read the affected `gitops/step-XX-name/base/` folder and its
   `kustomization.yaml`.
2. Identify all rendered or referenced resources.
3. Apply `references/review-checklist.md` to each manifest.
4. For labels and annotations, use
   `project-gitops-authoring/references/labels-and-annotations.md`.
5. For YAML standards, cross-resource consistency, and validation, use
   `project-gitops-authoring/references/manifest-standards.md`.
6. For security posture, use
   `project-gitops-authoring/references/security-and-secrets.md`.

## Output Format

```text
Step: step-XX-name
Files reviewed: N
Findings:
  - [LABEL] file.yaml: missing app.kubernetes.io/component
  - [SELECTOR] service.yaml: selector does not match pod template labels
  - [SECURITY] secret.yaml: missing demo-value warning
  - [YAML] configmap.yaml: title comment restates kind
Summary: X findings
```

## References

- `references/review-checklist.md`
