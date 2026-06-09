---
name: project-architecture-diagrams
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Refactor README architecture capability diagrams for the active-baseline
  RHOAI demo.
  Use when the user asks to align root and step diagrams, update
  docs/assets/architecture/*.svg, change scripts/generate-readme-visuals.py,
  revise architecture diagram layout, apply Red Hat product-layer coloring,
  or distinguish new, previously introduced, and not-yet-introduced
  capabilities across steps. Use as part of Project Structure content work.
  Do NOT use for live cluster troubleshooting (use env-troubleshoot),
  deploying steps (use env-deploy-and-evaluate), or changing chatbot behavior
  (use rhoai-chatbot-customization).
---

# Refactor Architecture Diagrams

Use this workflow to update the root and step README architecture diagrams
without losing the project-specific story.

## Source Of Truth

- Generator: `scripts/generate-readme-visuals.py`
- Output directory: `docs/assets/architecture/`
- Root SVG: `docs/assets/architecture/rhoai3-demo-capability-map.svg`
- Step SVGs: `docs/assets/architecture/step-NN-capability-map.svg`
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

## Refactor Process

1. Read `README.md`, all `steps/*/README.md`, and `scripts/generate-readme-visuals.py`.
2. Identify the canonical root capability list from the demo story, existing tables, and generator data.
3. Preserve the step sequence, including optional `13b`.
4. Map each capability to the step where it is first introduced.
5. Update only `scripts/generate-readme-visuals.py` for diagram generation unless README links or rules are stale.
6. Regenerate with `python3 scripts/generate-readme-visuals.py`.
7. Render representative SVGs to PNG for visual inspection.
8. Run validation:

```bash
python3 -m py_compile scripts/generate-readme-visuals.py
python3 scripts/generate-readme-visuals.py
./scripts/validate-demo-flow.sh
git diff --check
```

If live cluster validation is unavailable, state that static validation only was performed.

## Expected Output

The final change should include:

- Updated generator.
- Regenerated root and step SVGs.
- Any needed README/rule updates.
- A short validation summary with visual inspection notes.
