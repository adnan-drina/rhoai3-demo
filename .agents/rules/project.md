---
name: project
skill-group: Project Structure
skill-prefix: project-
applies-to:
  - AGENTS.md
  - .agents/**
  - .claude/**
  - .codex/**
  - .cursor/**
  - .gitignore
  - README.md
  - "**/README.md"
  - docs/**/*.md
  - gitops/**
  - steps/**
  - scripts/**
---

# Project Structure

Use the `project-*` skills as the source of truth for work that changes the
repository, GitOps layout, step content, documentation structure, manifest
standards, Red Hat source alignment, or shared agent guidance:

- `.agents/skills/project-structure/SKILL.md`
- `.agents/skills/project-agent-guidance/SKILL.md`
- `.agents/skills/project-gitops-authoring/SKILL.md`
- `.agents/skills/project-documentation-authoring/SKILL.md`
- `.agents/skills/project-manifest-review/SKILL.md`
- `.agents/skills/project-red-hat-doc-alignment-review/SKILL.md`
- `.agents/skills/project-architecture-diagrams/SKILL.md`

Keep the demo coherent as a RHOAI platform story for European enterprises.
GitOps, step READMEs, operational docs, architecture diagrams, and agent
guidance must stay aligned with the active baseline in
`docs/PLATFORM_BASELINE.md`.

The active implementation is being rewritten. Current implementation folders
`gitops/`, `scripts/`, and `steps/` are placeholder-only until new content is
introduced. Legacy implementation artifacts live under
`backup/legacy-implementation-2026-06-09/` and should be used as reference
material, not as active project structure.

Step READMEs should be concise Why/What documents: introduce the business
concept, ground European enterprise value in Red Hat narrative sources from
`rh-brain`, map the concept to official Red Hat product documentation, and show
the architecture delta. GitOps artifacts and live demos show the How. GitOps
artifacts should use Red Hat product images, validated model artifacts, or
explicitly documented demo exceptions.

Do not use this rule as the source of truth for specific RHOAI API fields or
live cluster operations. Use the `rhoai` or `env` rule and matching skills for
those domains.
