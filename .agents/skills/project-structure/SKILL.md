---
name: project-structure
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Evolve the rhoai3-demo repository structure, GitOps step layout, documentation
  standards, skill taxonomy, Red Hat narrative alignment, and official-doc
  evidence model. Use when the user asks to reorganize demo steps, create or
  refactor skills, update repository guidance, align READMEs with European
  enterprise messaging, add component documentation standards, or decide where
  project knowledge belongs. Do NOT use for live deployment, live cluster
  troubleshooting, or resource shutdown/recovery; use the Demo Environment
  skills for those. Do NOT use as the source of truth for specific RHOAI CR
  fields; use RHOAI Platform skills and official Red Hat docs.
---

# Project Structure

Use this skill to evolve the demo project itself: repository layout, GitOps
step conventions, documentation structure, shared skill groups, and
Red Hat-aligned narrative standards.

## Source Hierarchy

When changing project structure or documentation, use this evidence order:

1. Official Red Hat product docs for the active `docs/PLATFORM_BASELINE.md`
   versions.
2. Red Hat articles, blogs, and product messaging for narrative and examples.
3. `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` as read-only research input.
4. Existing repo implementation, scripts, and READMEs.
5. Live cluster schema checks only as verification, using `oc explain` or
   `oc get crd`; never invent CR fields or API versions.

Official docs remain the source of truth for supported configuration. Treat
`rh-brain` as supporting evidence, not product authority. The active product
version target lives in `docs/PLATFORM_BASELINE.md`; skills should reference
that baseline instead of repeating exact versions in every frontmatter block.

## Skill Groups

Keep canonical skill folders flat under `.agents/skills/` for discovery, review,
and reuse. Do not maintain tool-specific skill copies; add a minimal bridge only
for a proven tool-only gap.

| Group | Prefix | Purpose | Current skills |
|-------|--------|---------|----------------|
| Project Structure | `project-*` | Repo architecture, GitOps step layout, docs, Red Hat narrative alignment, skill governance, manifest review, Red Hat doc alignment | `project-structure`, `project-agent-guidance`, `project-architecture-diagrams`, `project-gitops-authoring`, `project-documentation-authoring`, `project-manifest-review`, `project-red-hat-doc-alignment-review` |
| Demo Environment | `env-*` | Live AWS/OpenShift demo lifecycle: bootstrap, deploy, validate, troubleshoot, shutdown/recovery, redeploy | `env-deploy-and-evaluate`, `env-troubleshoot`, `env-manage-resources`, `env-validate-demo-flow` |
| RHOAI Platform | `rhoai-*` | Official-doc-backed component guidance for installing, configuring, and using active RHOAI baseline capabilities | `rhoai-model-evaluation`, `rhoai-chatbot-customization`, `rhoai-kfp-pipeline-authoring`; component skills planned |
| Assets & Miscellaneous | `assets-*` | Supporting assets and presentation outputs not tied to live cluster operations | `assets-red-hat-quick-deck` |

Use `references/rhoai-component-skill-roadmap.md` when planning new RHOAI
Platform skills.

## Project Change Workflow

1. Identify the group and owner skill for the work.
2. Read the relevant `.agents/rules/*.md` files before editing GitOps,
   README, labels, secrets, or generated architecture diagrams.
3. Keep code and docs aligned: manifest changes require README updates, and
   README capability claims require implemented manifests or a clear deferred
   label.
4. Keep operational details in `docs/OPERATIONS.md` and recovery details in
   `docs/TROUBLESHOOTING.md`; step READMEs should teach the platform story.
5. For RHOAI component claims, cite official docs and record supporting
   `rh-brain` examples only as secondary evidence.
6. Update `AGENTS.md`, `docs/AI_COLLABORATION.md`, and this skill when skill
   groups, inventory, or source hierarchy change.

## Naming Guidance

Prefer stable names that describe responsibility:

- `project-*` for repository structure, docs, GitOps conventions, and narrative.
- `env-*` for live demo environment operations.
- `rhoai-*` for official-doc-backed RHOAI component knowledge.
- `assets-*` for visual, deck, diagram, or generated media workflows.

Renames should be incremental. Keep compatibility by updating negative triggers
and cross-references before deleting old skill folders.
