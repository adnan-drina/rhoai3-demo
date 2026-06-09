# Platform Baseline

This file is the canonical platform target for the demo and shared skills.
Update it first when preparing an upgrade.

## Current Baseline

| Component | Version | Documentation |
|-----------|---------|---------------|
| Red Hat OpenShift AI Self-Managed | 3.4 | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/ |
| Red Hat OpenShift Container Platform | 4.20 | https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/ |

## Source Hierarchy

1. Official Red Hat product documentation for the active baseline.
2. Official Red Hat articles, blogs, and product messaging for narrative and examples.
3. `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` as read-only research input.
4. Existing repo implementation, scripts, and READMEs.
5. Live cluster schema verification with commands such as `oc explain` and `oc get crd`.

Official product documentation remains the source of truth for supported
configuration. Do not invent CR fields, API versions, annotations, or operator
configuration.

## Skill Metadata Policy

Shared skills should reference this repository baseline rather than repeating
exact platform versions in every skill frontmatter. Use exact version-specific
reference files only when a workflow genuinely differs across platform versions.
