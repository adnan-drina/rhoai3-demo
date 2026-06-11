# Source Capture Checklist

Use this checklist before authoring a README, GitOps manifest, script, or
architecture diagram for a new stage.

## Baseline

- Active product versions checked in `docs/PLATFORM_BASELINE.md`.
- OCP, RHOAI, ODF, and related product versions match the official docs used.
- Any community Operator, external service, or non-Red Hat artifact is marked
  as a demo exception.

## Narrative Sources

Capture at least one Red Hat narrative source for `## Why This Matters`.
When multiple Red Hat sources cover the same concept, prefer sources that also
link to concrete GitHub projects, manifests, notebooks, pipelines, or
application code:

```text
Source title:
Source type: article | blog | product page | datasheet | guide
Source location: /Users/adrina/Sandbox/rh-brain/Red Hat Brain/...
Concept supported:
Enterprise value supported:
Links to GitHub implementation: yes | no
Linked implementation URL:
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
Source type: official docs | Red Hat-linked GitHub repo | Red Hat CoP catalog | Red Hat blog | repo legacy reference | internal example
Use in this stage:
Verification required:
```

Red Hat CoP catalog examples are curation patterns only. Do not commit remote
Kustomize references to catalog paths.

## GitHub Reference Implementations

For most demo stages, actively look for relevant GitHub repositories used by
Red Hat product, field, solution, demo, or community-of-practice teams.

Prefer this order:

1. repository linked from official Red Hat documentation
2. repository linked from a Red Hat article or blog captured in `rh-brain`
3. Red Hat organization or team repository with active, relevant examples
4. Red Hat CoP catalog or demo repository
5. upstream or third-party repository only as a documented demo exception

Capture each candidate:

```text
Repository URL:
Owner or organization:
Red Hat linkage: official docs | Red Hat article | Red Hat org/team | CoP | unknown
Relevant path or file:
Commit, tag, or branch reviewed:
License or usage note:
Implementation idea reused:
Product fields still sourced from official docs: yes | no
Support posture: product docs authority | example only | demo exception
```

Do not treat GitHub examples as product authority. Use them for concrete
implementation patterns, manifests, scripts, notebooks, pipelines, and
validation ideas only after official docs or live schema verify the product
fields.

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
