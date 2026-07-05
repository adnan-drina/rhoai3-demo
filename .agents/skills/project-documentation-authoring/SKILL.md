---
name: project-documentation-authoring
metadata:
  author: rhoai3-demo
  version: 1.6.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Author and improve rhoai3-demo documentation: root README, docs/README.md,
  docs/BACKLOG.md, stage READMEs, docs/OPERATIONS.md,
  docs/TROUBLESHOOTING.md, PLAN.md files, design decisions, references, and
  Red Hat narrative alignment. Use when creating or updating demo prose, adding
  architecture sections, introducing concepts such as Private AI,
  GPU-as-a-Service, Models-as-a-Service, RAG, guardrails, MCP, or MLOps,
  improving European enterprise messaging, preparing concise Why/What README
  content for later slide generation, adding demo visual evidence (screenshots
  and animated GIFs), writing implementation plans, documenting deferred
  capabilities, or routing captured project knowledge to the correct
  documentation home. Also use when documentation needs to explain implemented
  GitOps behavior in business and technical terms. Pair with
  project-demo-stage-authoring when creating a new stage end to end. Do NOT use
  for GitOps manifest authoring itself (use project-gitops-authoring) or
  official Red Hat source conformance audits (use
  project-red-hat-doc-alignment-review).
---

# Documentation Authoring

Use this skill to keep repo documentation clear, demonstrable, and aligned with
official Red Hat messaging and the implemented demo story.

## Workflow

1. Identify the documentation home before writing:
   root README for demo overview, `docs/README.md` for the promoted docs
   index, `docs/BACKLOG.md` for deferred capabilities and future work, stage
   README for concise Why/What story, `docs/OPERATIONS.md` for runbooks,
   `docs/TROUBLESHOOTING.md` for recovery, `docs/PLATFORM_BASELINE.md` for
   product targets, and `PLAN.md` files for implementation planning.
   For a new stage, start with `project-demo-stage-authoring`.
2. Read the relevant existing document before changing it.
3. Confirm whether a companion manifest, script, README, or operations document
   change is required.
4. For README concept introductions, use Red Hat articles and `rh-brain` to
   define the concept and European enterprise value. Prefer articles that link
   to GitHub reference implementations or code examples when several sources
   are relevant. For product configuration, use active-baseline official Red
   Hat docs first.
5. For stage README structure and presentation style, read
   `references/readme-standard.md`.
6. For implementation detail boundaries in READMEs, read
   `references/implementation-detail-boundary.md`.
7. For demo visual evidence (screenshots, GIFs, `## Demo` section), read
   the "Demo Visual Evidence" section in `references/readme-standard.md`.
   Ensure at least one screenshot per key component and one customer-facing
   demo result per stage.
8. For continuous documentation and troubleshooting knowledge capture, read
   `references/knowledge-governance.md`.
9. For `PLAN.md` and planning documents, read `references/plan-documents.md`.
10. When adding product claims, baseline-specific component details, or official
    documentation references, pair with `project-red-hat-doc-alignment-review`.
11. After substantive README edits, verify alignment using the
    `project-doc-alignment-audit` skill's stage-specific checklists.

## Documentation Principles

- Stage READMEs are concise Why/What documents, not deployment runbooks.
- Stage READMEs should introduce the concept first, explain why a
  European-regulated enterprise should care, and cite Red Hat narrative
  material from `rh-brain`; prefer sources that include concrete GitHub
  projects or code examples when available.
- Stage READMEs should support a three-part presentation extraction contract:
  concept/value (Why), technology enablers (What), and architecture delta +
  demo visual evidence (How).
- Each stage README must include a `## Demo` section with annotated
  screenshots (at least one per key component, at least one customer-facing
  result) and an animated GIF walkthrough. Visual evidence lives in
  `docs/assets/demos/stage-NNN/`.
- Implementation details that affect understanding, troubleshooting, or
  cross-stage dependencies belong in the README. Operational procedures and
  step-by-step commands do not. See `references/implementation-detail-boundary.md`.
- Operational runbook detail belongs in `docs/OPERATIONS.md`.
- Failure recovery detail belongs in `docs/TROUBLESHOOTING.md`.
- Future or deferred capabilities must be labeled explicitly and tracked in
  `docs/BACKLOG.md` when they are actionable project work.
- References sections should point to active-baseline official docs.
- Official Red Hat source conformance belongs to
  `project-red-hat-doc-alignment-review`; do not infer RHOAI API behavior from
  narrative sources.

## References

- `references/readme-standard.md`
- `references/implementation-detail-boundary.md`
- `references/knowledge-governance.md`
- `references/plan-documents.md`
