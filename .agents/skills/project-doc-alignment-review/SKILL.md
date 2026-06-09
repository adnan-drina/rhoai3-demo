---
name: project-doc-alignment-review
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Review GitOps manifests, step READMEs, and RHOAI resources against official
  Red Hat documentation for the active product baseline. Use when creating or
  modifying CRs, operator configuration, InferenceServices, ServingRuntimes,
  LlamaStack, Guardrails, Model Registry, DSPA, LMEvalJob, TrustyAI, Notebook,
  or any RHOAI-managed resource. Also use for periodic documentation alignment
  audits and evidence-ledger refreshes.
---

# Documentation Alignment Review

Use this skill to verify product documentation alignment. This is stricter than
YAML validity: a manifest can render but still use unsupported fields or stale
product assumptions.

## Workflow

1. Read `docs/PLATFORM_BASELINE.md` to identify the active RHOAI and OCP docs.
2. Read the changed manifests and companion README.
3. For each custom resource, verify API version, top-level spec fields,
   annotations, image sources, and operator configuration against official docs.
4. Use `references/doc-alignment-checklist.md` for resource-specific checks.
5. Use `rh-brain` only for narrative or article examples; do not treat it as
   product configuration truth.
6. If a field cannot be verified from docs, flag it and propose a schema
   verification command such as `oc explain` or CRD inspection.

## Output Format

```text
Step: step-XX-name
Files reviewed: N

Doc-aligned:
  - file.yaml: apiVersion and documented fields match active baseline docs

Misaligned:
  - [API] file.yaml: expected documented API version X, found Y
  - [FIELD] file.yaml: field foo is not documented for this CR version
  - [DOC-REF] README.md: references stale product documentation

Summary: X aligned, Y misaligned
```

## References

- `references/doc-alignment-checklist.md`
