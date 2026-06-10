# Source Capture Checklist

Use this checklist before authoring a README, GitOps manifest, script, or
architecture diagram for a new step.

## Baseline

- Active product versions checked in `docs/PLATFORM_BASELINE.md`.
- OCP, RHOAI, ODF, and related product versions match the official docs used.
- Any community Operator, external service, or non-Red Hat artifact is marked
  as a demo exception.

## Narrative Sources

Capture at least one Red Hat narrative source for `## Why This Matters`:

```text
Source title:
Source type: article | blog | product page | datasheet | guide
Source location: /Users/adrina/Sandbox/rh-brain/Red Hat Brain/...
Concept supported:
Enterprise value supported:
```

Narrative sources explain concept and value. They do not define Kubernetes CR
fields, operator channels, images, or API support posture.

## Product Sources

For each product component introduced:

```text
Component:
Skill:
Official docs URL:
Documentation section:
Configuration fields or examples used:
Support posture: GA | Technology Preview | Developer Preview | API tier | community | demo-only
Verification needed: none | oc explain | CRD inspection | package manifest | image lookup
```

Use `.agents/references/red-hat-doc-map.yaml` to find the matching skill.

## Implementation Sources

Capture implementation pattern sources separately:

```text
Pattern source:
Source type: official docs | Red Hat CoP catalog | Red Hat blog | repo legacy reference | internal example
Use in this step:
Verification required:
```

Red Hat CoP catalog examples are curation patterns only. Do not commit remote
Kustomize references to catalog paths.

## Image And Artifact Sources

For every image or model artifact:

```text
Artifact:
Source registry or storage:
Red Hat product or validated source:
Tag or digest:
Credential requirement:
Support/demo posture:
```

Do not commit credentials. Do not present external or community artifacts as
Red Hat-supported unless a Red Hat source says so.

## Missing Source Handling

If a required source is missing:

- stop manifest authoring
- identify the missing product skill or official docs section
- create or update the skill with `project-red-hat-doc-skill-authoring`
- propose a live verification command only after the OpenShift safety guard is
  satisfied
- record the blocker in `PLAN.md`
