# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@../AGENTS.md

## Implementation State

The repo is in a **clean-slate reimplementation**. `gitops/`, `scripts/`, and `steps/` are placeholder-only — no active bootstrap, deploy, validate, or demo-flow commands exist yet. Do not run anything under `backup/legacy-implementation-2026-06-09/` as a live command; treat it as reference material.

## Platform Baseline

| Component | Version |
|-----------|---------|
| Red Hat OpenShift AI Self-Managed | 3.4 |
| OpenShift Container Platform | 4.20 |
| OpenShift Data Foundation | 4.20 |

Full version-pinned doc links live in `docs/PLATFORM_BASELINE.md`. Always use that file for official doc URLs; never use `latest` as a version slug.

## Validation

The only active linting command in the project:

```bash
ruby scripts/validate-agent-guidance.rb
```

Checks: skill frontmatter completeness, rule-to-skill reference integrity, doc-map route validity, and guidance inventory count. Run after any change to `.agents/skills/`, `.agents/rules/`, or `.agents/references/red-hat-doc-map.yaml`.

## Environment Setup

Before any live cluster work, create a local `.env` from `env.example`:

```bash
cp env.example .env
```

Set at minimum:

- `RHOAI_EXPECTED_API_SERVER` — a unique substring of the target cluster's API URL (safety guard; scripts refuse to run if this doesn't match)
- `KUBECONFIG` — absolute path under `tmp/` if using a project-local kubeconfig

Never commit `.env` or kubeconfig files.

## Cluster Verification Commands

When unsure about a CR field or API version, verify against the live cluster rather than guessing:

```bash
oc explain <resource>.<group>
oc get crd | grep <component>
oc api-resources | grep <component>
```

The `.agents/hooks/guard-openshift-command.py` hook blocks mutating `oc`/`kubectl` commands and deploy scripts unless `RHOAI_EXPECTED_API_SERVER` is set and the live cluster URL matches.

## Demo Stage Layout

New demo stages are root-level folders. Do not add stages under `gitops/` or `steps/`.

```text
stage-YXX-slug/
  README.md       # Why/What for a technical audience
  PLAN.md         # Implementation plan and definition of done
  deploy.sh
  validate.sh
gitops/
  argocd/app-of-apps/stage-YXX-slug.yaml   # Argo CD Application
  apps/stage-YXX-slug/                      # Kustomize source
```

Use `project-demo-stage-authoring` skill for the full phase-gate process.

## Skill Authoring

When adding a new skill under `.agents/skills/<skill-name>/SKILL.md`, the frontmatter must include:

```yaml
---
name: <skill-name>            # must match folder name
metadata:
  version: 1.0.0
  platform-family: rhoai      # or ocp, odf, project, env, assets
  platform-baseline: "repo"   # reference docs/PLATFORM_BASELINE.md
  ocp-baseline: "repo"
  skill-group: "RHOAI Platform"  # must be one of the six allowed groups
---
```

After adding a skill, add its doc-map route to `.agents/references/red-hat-doc-map.yaml` and run the validation script.

## Skills for Common Tasks

Invoke these skills when working in their domain:

| Task | Skill |
|------|-------|
| Add or update a rule, skill, hook, or agent bridge | `project-agent-guidance` |
| Create or restructure GitOps steps or READMEs | `project-structure` |
| Add a new RHOAI component skill from official docs | `project-red-hat-doc-skill-authoring` |
| Review a manifest against official docs | `project-manifest-review` |
| Check Red Hat doc alignment | `project-red-hat-doc-alignment-review` |
| Write or update step READMEs | `project-documentation-authoring` |
| Deploy or evaluate the demo environment | `env-deploy-and-evaluate` |
| Troubleshoot a live cluster issue | `env-troubleshoot` |
| Any RHOAI component (installation, config, usage) | matching `rhoai-*` skill |

Invoke a skill with `/skill-name` or by describing the task; Claude Code will trigger the matching skill.
