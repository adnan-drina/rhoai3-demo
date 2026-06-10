# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@../AGENTS.md

## Implementation State

The repo is in a **clean-slate reimplementation**. `gitops/`, `scripts/`, and `steps/` are placeholder-only — no active bootstrap, deploy, validate, or demo-flow commands exist yet. Do not run anything under `backup/legacy-implementation-2026-06-09/` as a live command; treat it as reference material.

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
