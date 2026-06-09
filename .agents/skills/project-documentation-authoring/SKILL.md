---
name: project-documentation-authoring
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Author and review rhoai3-demo documentation: root README, step READMEs,
  PLAN.md files, troubleshooting entries, design decisions, references, and
  Red Hat narrative alignment. Use when creating or updating demo docs,
  adding architecture sections, improving European enterprise messaging,
  writing implementation plans, or capturing project knowledge from repeated
  questions or deployment discoveries. Do NOT use for GitOps manifest authoring
  itself (use project-gitops-authoring).
---

# Documentation Authoring

Use this skill to keep repo documentation clear, demonstrable, and aligned with
official Red Hat messaging.

## Workflow

1. Read the relevant step README before changing the step.
2. Confirm whether a companion manifest or script change is required.
3. Use official Red Hat docs for the active baseline first; use Red Hat
   articles and `rh-brain` only as supporting narrative evidence.
4. For step README structure and presentation style, read
   `references/readme-standard.md`.
5. For continuous documentation and troubleshooting knowledge capture, read
   `references/knowledge-governance.md`.
6. For `PLAN.md` and planning documents, read `references/plan-documents.md`.

## Documentation Principles

- Step READMEs are educational technical articles, not command dumps.
- Operational runbook detail belongs in `docs/OPERATIONS.md`.
- Failure recovery detail belongs in `docs/TROUBLESHOOTING.md`.
- Future or deferred capabilities must be labeled explicitly.
- References sections should point to active-baseline official docs.

## References

- `references/readme-standard.md`
- `references/knowledge-governance.md`
- `references/plan-documents.md`
