---
name: assets
skill-group: Assets & Miscellaneous
skill-prefix: assets-
applies-to:
  - docs/assets/**
  - scripts/generate-readme-visuals.py
  - "**/*.svg"
  - "**/*.png"
  - "**/*.jpg"
  - "**/*.jpeg"
  - "**/*.pptx"
---

# Assets And Miscellaneous

Use the `assets-*` skills as the source of truth for visual, deck, and
presentation assets:

- `.agents/skills/assets-red-hat-quick-deck/SKILL.md`

For README architecture diagrams, also use:

- `.agents/skills/project-architecture-diagrams/SKILL.md`

Keep visual outputs aligned with Red Hat brand guidance and the implemented
demo story. Do not hand-edit generated architecture SVGs; update the generator
and regenerate outputs.
