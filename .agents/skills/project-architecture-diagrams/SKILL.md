---
name: project-architecture-diagrams
metadata:
  author: rhoai3-demo
  version: 1.1.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Refactor README architecture capability diagrams for the active-baseline
  RHOAI demo once active README visual assets exist; during the
  reimplementation, use this skill to rebuild the diagram generator and visual
  standards from legacy references. Use when the user asks to align root and
  stage diagrams, update docs/assets/architecture/*.svg, change
  scripts/generate-readme-visuals.py, revise architecture diagram layout, apply
  Red Hat product-layer coloring, or distinguish new, previously introduced,
  and not-yet-introduced capabilities across stages. Use as part of Project
  Structure content work.
  Do NOT use for live cluster troubleshooting (use env-troubleshoot),
  deploying stages (use env-deploy-and-evaluate), or changing chatbot behavior
  (use rhoai-chatbot-customization).
---

# Refactor Architecture Diagrams

Use this workflow to update the root and stage README architecture diagrams
without losing the project-specific story.

## Reimplementation Status

The active implementation is being rewritten. No active README visual generator
or architecture SVG output exists yet. Treat the previous generator and SVGs
under `backup/legacy-implementation-2026-06-09/` as design references until a
new active generator is introduced.

## Source Of Truth

- Future generator location: `scripts/generate-readme-visuals.py`
- Future output directory: `docs/assets/architecture/`
- Legacy generator:
  `backup/legacy-implementation-2026-06-09/scripts/generate-readme-visuals.py`
- Legacy SVGs:
  `backup/legacy-implementation-2026-06-09/docs/assets/architecture/`
- Assets rule: `.agents/rules/assets.md`

Do not hand-edit generated SVG files. Update the generator, regenerate all SVGs,
and visually inspect representative root, early, middle, and final step maps.

## Design Standard

Use the Red Hat Layout B layered table pattern:

- Left product rail.
- Logical layer label column.
- Capability boxes to the right.
- Transparent outer SVG canvas.
- Dark neutral panels, gray borders, white text.
- Red Hat product-layer colors:
  - Red Hat OpenShift / container platform layers: Red Hat red `#ee0000`.
  - Red Hat OpenShift AI layers: teal `#147878`.
  - Add another product-layer color only when a real Red Hat product layer in this demo requires it.

State treatment:

- Root map: all canonical capabilities are active, using dark fill plus a product-colored left stripe.
- New in the current step: dark fill, heavy product-colored border, bold white text.
- Previously introduced: dark fill, gray border, white text, product-colored left stripe.
- Not yet introduced / not demonstrated: dimmed dark fill, muted text, gray border.

Do not use pale product fills for previously introduced capabilities; they look too white in this dark design and compete with the current-step highlight.

Stage maps must remain suitable as slide 3 for each README-derived presentation
segment: they should highlight capabilities introduced in the current demo stage
while keeping previously introduced components visible for architectural
context.

## Refactor Process

1. Read `README.md`, all active `stage-*/README.md` files, and the active
   visual generator if it exists.
2. Identify the canonical root capability list from the demo story, existing tables, and generator data.
3. Preserve the current stage inventory from the repository; do not hard-code
   optional stage names or stage counts in this skill.
4. Map each capability to the current stage where it is first introduced,
   deriving that mapping from the active README and generator data.
5. Recreate or update `scripts/generate-readme-visuals.py` for diagram
   generation unless README links or rules are stale.
6. Regenerate with `python3 scripts/generate-readme-visuals.py` once the
   generator exists.
7. Render representative SVGs to PNG for visual inspection.
8. Run validation when the referenced files exist:

```bash
python3 -m py_compile scripts/generate-readme-visuals.py
python3 scripts/generate-readme-visuals.py
git diff --check
```

If demo-flow validation has been recreated and live cluster validation is
available, run that separately. Otherwise, state that static validation only was
performed.

## Expected Output

The final change should include:

- Updated generator.
- Regenerated root and stage SVGs.
- Any needed README/rule updates.
- A short validation summary with visual inspection notes.
