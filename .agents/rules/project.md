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
  - stage-*/**
  - scripts/**
---

# Project Structure

Use the `project-*` skills as the source of truth for work that changes the
repository, GitOps layout, stage content, documentation structure, manifest
standards, Red Hat source alignment, or shared agent guidance:

- `.agents/skills/project-structure/SKILL.md`
- `.agents/skills/project-agent-guidance/SKILL.md`
- `.agents/skills/project-red-hat-doc-skill-authoring/SKILL.md`
- `.agents/skills/project-rhoai-doc-chapter-skill-authoring/SKILL.md`
- `.agents/skills/project-red-hat-operator-gitops/SKILL.md`
- `.agents/skills/project-demo-stage-authoring/SKILL.md`
- `.agents/skills/project-gitops-authoring/SKILL.md`
- `.agents/skills/project-documentation-authoring/SKILL.md`
- `.agents/skills/project-manifest-review/SKILL.md`
- `.agents/skills/project-red-hat-doc-alignment-review/SKILL.md`
- `.agents/skills/project-architecture-diagrams/SKILL.md`

Keep the demo coherent as a RHOAI platform story for European enterprises.
GitOps, stage READMEs, operational docs, architecture diagrams, and agent
guidance must stay aligned with the active baseline in
`docs/PLATFORM_BASELINE.md`.

Use `project-red-hat-doc-skill-authoring` when turning official Red Hat product
documentation into `rhoai-*`, `ocp-*`, or `odf-*` component skills. The older
`project-rhoai-doc-chapter-skill-authoring` remains compatible for RHOAI-only
chapter work. Before selecting or creating a product skill, consult
`.agents/references/red-hat-doc-map.yaml` to map the official Red Hat product,
version, category, book, and chapter topic to an existing or planned flat
skill. Generated component skills must capture official sources, extraction
notes, validation rules, examples, and the corresponding doc-map route before
they are treated as reusable product guidance.

Use `project-red-hat-operator-gitops` when deploying Red Hat Operators through
GitOps. Follow the Red Hat Community of Practice catalog structure as a local
curation pattern: operator base, channel overlay, instance resources, optional
components, and aggregate overlays. Do not commit direct remote Kustomize
references to the community catalog; product fields and channels still come
from official Red Hat docs and product skills. Operator lifecycle management
is also GitOps state: channel changes, approval strategy, selected overlay,
product baseline, and operand patches should be changed in Git and reconciled
by Argo CD, not maintained as live Subscription drift.

Classify image ownership before changing any image value. Do not pin images
solely to create repeatability; Red Hat Operators package operational
knowledge so platform components are installed, configured, and managed in an
automated, repeatable, and supported way. Explicit image tags or digests are
exceptions that require Red Hat documentation, a validated artifact reference,
or a documented non-operator demo-app exception. OLM/operator-owned images,
CSV `relatedImages`, generated CR image fields, copied CSVs, and
operator-created operand Deployments are not project-owned. Diagnose those
with Subscription, installed CSV, CRD, and generated-resource inspection, then
fix durable compatibility issues through operator lifecycle policy or product
baseline alignment instead of generated image patches.

The active implementation is being rewritten. Current implementation folders
`gitops/` and `scripts/` are placeholder-only until new content is introduced.
New demo stages must be created as root-level `stage-YXX-slug/` folders.
Legacy implementation artifacts live under
`backup/legacy-implementation-2026-06-09/` and should be used as reference
material, not as active project structure.

Use `project-demo-stage-authoring` for every new demo stage. Start with intent,
source capture, skill routing, and `PLAN.md`; then author the README, GitOps,
Argo CD Application, manifests, deploy script, validation script, and review
evidence as one atomic stage. Do not let README claims, GitOps manifests, and
validation scripts drift apart.

Stage READMEs should be concise Why/What documents: introduce the business
concept, ground European enterprise value in Red Hat narrative sources from
`rh-brain`, map the concept to official Red Hat product documentation, and show
the architecture delta. GitOps artifacts and live demos show the How. GitOps
artifacts should use Red Hat product images, validated model artifacts, or
explicitly documented demo exceptions.

Do not use this rule as the source of truth for specific RHOAI API fields or
live cluster operations. Use the `rhoai` or `env` rule and matching skills for
those domains.
