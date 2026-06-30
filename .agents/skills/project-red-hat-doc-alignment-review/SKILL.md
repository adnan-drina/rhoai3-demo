---
name: project-red-hat-doc-alignment-review
metadata:
  author: rhoai3-demo
  version: 1.2.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Review rhoai3-demo stage READMEs, Red Hat concept narratives, official
  documentation references, GitOps manifests, images, and RHOAI resources
  against Red Hat source material for the active product baseline. Use when
  creating or modifying README concept framing, European enterprise value
  claims, CRs, operator configuration, InferenceServices, ServingRuntimes,
  LlamaStack, Guardrails, Model Registry, DSPA, LMEvalJob, TrustyAI, Notebook,
  container images, model artifacts, or any RHOAI-managed resource. Also use
  when adding baseline-specific product claims or running periodic Red Hat
  source alignment audits. Do NOT use for general prose drafting,
  PLAN.md writing, or knowledge capture (use project-documentation-authoring);
  use this skill to verify the source grounding before merge.
---

# Red Hat Source Alignment Review

Use this skill to verify that the demo story and implementation are grounded in
Red Hat sources. This is stricter than YAML validity and separate from prose
authoring: a manifest can render, and a README can read well, while still
relying on unsupported fields, stale product references, ungrounded enterprise
claims, or undocumented assumptions.

## Workflow

1. Read `docs/PLATFORM_BASELINE.md` to identify the active RHOAI, OCP, and
   related Red Hat documentation baselines.
2. Read the changed README and companion GitOps manifests together.
3. Check the README concept narrative:
   - the first major section defines the concept being introduced
   - it explains why a European-regulated enterprise architect, engineer, or
     business owner should care
   - it cites at least one relevant Red Hat article or blog from
     `/Users/adrina/Sandbox/rh-brain/Red Hat Brain`
4. Check the README technical mapping:
   - every RHOAI, OCP, MicroShift, OpenShift Pipelines, or Red Hat AI component
     introduced in the stage has an active-baseline official documentation link
   - configuration guidance comes from official docs first, with rh-brain
     articles used only for examples, implementation patterns, and narrative
     support
5. Check GitOps manifests:
   - custom resource API versions, API tier support posture, top-level spec
     fields, annotations, operator channels, image sources, and model artifacts
     match official Red Hat documentation or verified installed schemas
   - Red Hat product images and validated artifacts are preferred whenever the
     demo claims Red Hat-supported posture
   - operator-generated images, CSV `relatedImages`, copied CSVs, and
     operator-created Deployments are not treated as project-owned desired
     state unless official product docs expose a supported override field
6. Use `references/doc-alignment-checklist.md` for the detailed review model.
7. Use `rhoai-api-tiers` when the change depends on RHOAI API stability,
   Technology Preview, Developer Preview, or Tier 4 support posture.
8. If a field or artifact cannot be verified from docs, flag it and propose a
   schema or catalog verification command such as `oc explain`, CRD inspection,
   or image/catalog lookup.
9. For prose rewrites, README structure, plans, or troubleshooting entries,
   switch to `project-documentation-authoring`.

## Output Format

```text
Stage: stage-YXX-slug
Files reviewed: N

Source-aligned:
  - README.md: concept framing cites Red Hat article X and official docs Y
  - file.yaml: apiVersion, fields, image, and artifact source match active docs

Misaligned:
  - [NARRATIVE] README.md: concept claim has no rh-brain/Red Hat article source
  - [API] file.yaml: expected documented API version X, found Y
  - [FIELD] file.yaml: field foo is not documented for this CR version
  - [IMAGE] file.yaml: image is not Red Hat product, validated, internal, or explicitly approved
  - [DOC-REF] README.md: references stale product documentation

Summary: X aligned, Y misaligned
```

## References

- `references/doc-alignment-checklist.md`
