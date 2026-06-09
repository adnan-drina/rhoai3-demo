---
name: rhoai
skill-group: RHOAI Platform
skill-prefix: rhoai-
applies-to:
  - docs/PLATFORM_BASELINE.md
  - docs/rhoai-*/**
  - gitops/**
  - steps/**/*.py
  - steps/**/*.ipynb
  - steps/**/kfp/**
  - steps/step-07-rag/**
  - steps/step-08-model-evaluation/**
---

# RHOAI Platform

Use the `rhoai-*` skills as the source of truth for RHOAI component behavior,
configuration, pipelines, chatbot behavior, and evaluation workflows:

- `.agents/skills/rhoai-chatbot-customization/SKILL.md`
- `.agents/skills/rhoai-model-evaluation/SKILL.md`
- `.agents/skills/rhoai-kfp-pipeline-authoring/SKILL.md`

Official Red Hat documentation for the active baseline in
`docs/PLATFORM_BASELINE.md` is the product source of truth. Use Red Hat articles
and `rh-brain` examples only as supporting implementation evidence.

Do not invent CR fields, API versions, annotations, or operator settings. If a
field is uncertain, verify it through official docs or schema inspection.
