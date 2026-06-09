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

The active implementation is being rewritten. RHOAI manifests, notebooks,
pipelines, chatbot code, and evaluation workflows under
`backup/legacy-implementation-2026-06-09/` are legacy references only until
corresponding active content is recreated under `gitops/`, `steps/`, or
`scripts/`.

When a README introduces a RHOAI capability, pair the concept narrative with an
official documentation link for each technical component used. When a manifest
introduces images or model artifacts, verify Red Hat registry, validated model,
or explicitly documented demo-exception provenance before treating it as
aligned.

Do not invent CR fields, API versions, annotations, or operator settings. If a
field is uncertain, verify it through official docs or schema inspection.
