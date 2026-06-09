# AI-Assisted Collaboration Model

This document defines how AI rules, skills, hooks, and subagents are organized in this repository.

## Operating principle

AI tools are accelerated collaborators, not autonomous maintainers. Every AI-assisted change must remain human-owned, reviewed, and validated.

The contribution flow:

> Human-defined task -> AI-assisted plan -> focused change -> full human diff review -> explicit validation -> PR or commit with AI disclosure.

This matters especially for this demo because repository state, live OpenShift state, and local credentials are separate trust boundaries.

## Shared project guidance

Shared guidance lives in:

- `AGENTS.md` — tool-neutral agent guidance and repository safety rules
- `.cursor/rules/*.mdc` — Cursor behavior rules
- `.cursor/skills/*/SKILL.md` — repeatable project workflows
- `.cursor/agents/*.md` — context-isolated specialist agents
- `.cursor/hooks.json` and `.cursor/hooks/` — Cursor automation hooks
- `.codex/hooks.json` and `.codex/hooks/` — Codex command-safety hooks

Treat these files as source code. Changes should be reviewed like any other behavior change.

## Local/private guidance

Keep personal or machine-specific guidance outside the repo, for example under `~/.cursor/`, `~/.claude/`, or `~/.codex/`, when it includes:

- personal credentials, tokens, or API keys
- local kubeconfig paths
- private cluster names or API URLs
- personal shell aliases or model preferences
- customer, employer, or private environment details
- experimental workflows that have not been reviewed

Shared repo skills must not contain environment-specific values. Use placeholders and require local `.env` values for target cluster details.

## Decision rule

| Guidance type | Put it in | When to use |
|----------------|-----------|-------------|
| Always-on behavior constraint | Rule | Agent must consistently enforce it |
| Repeatable task workflow | Skill | Task-specific, invoked when relevant |
| Context-heavy investigation | Subagent | Needs isolation or parallel review |
| Automated validation or command guard | Hook | The check should run without agent discretion |
| Explanatory policy | Documentation | Informational, not automatically enforced |
| Personal setup | Local/private config | Applies to one contributor only |

Do not create a skill when a short rule or doc note is enough. Do not create a rule when a workflow skill is more appropriate.

## Skill taxonomy

Keep skill folders flat under `.cursor/skills/` so tool discovery continues to work. Use this taxonomy for review, ownership, and cleanup instead of nesting folders.

| Category | Skills | Purpose |
|----------|--------|---------|
| Deployment and validation | `deploy-and-evaluate`, `validate-demo-flow` | Bring up the demo and verify end-to-end behavior |
| Live operations | `rhoai-troubleshoot`, `manage-resources` | Diagnose or intentionally change live cluster resources |
| Domain workflows | `chatbot-customization`, `model-evaluation`, `refactor-architecture-diagrams`, `red-hat-quick-deck` | Workflows for specific demo content or deliverables |
| Governance | `maintain-rules-and-skills` | Add, update, audit, or retire shared AI guidance |

Current inventory:

| Type | Count | Location |
|------|-------|----------|
| Cursor rules | 13 | `.cursor/rules/*.mdc` |
| Cursor skills | 9 | `.cursor/skills/*/SKILL.md` |
| Cursor hooks | 4 | `.cursor/hooks.json`, `.cursor/hooks/` |
| Codex hooks | 1 | `.codex/hooks.json`, `.codex/hooks/` |
| Subagents | 3 | `.cursor/agents/*.md` |

## Skill quality bar

Shared skills should:

- have a `name` matching the parent folder
- include metadata with version and platform targets when project-specific
- have a specific trigger description and negative triggers
- keep `SKILL.md` under 500 lines when practical
- move large detail into `references/`
- avoid duplicating companion rules
- avoid secrets, local paths, private URLs, and local cluster assumptions
- mark destructive or expensive workflows with `disable-model-invocation: true`

`red-hat-quick-deck` is intentionally shared between both demo repos today, but it is oversized and should be split into a lean `SKILL.md` plus references before further feature growth.

## Hooks and cluster safety

Cursor hooks provide edit-time validation and command prompts. Codex hooks provide command-safety checks for risky `oc` and `kubectl` mutations.

Before any live OpenShift operation:

- open this repo as its own Codex project, not `/Users/adrina/Sandbox`
- load the repo-local `.env`
- require `RHOAI_EXPECTED_API_SERVER` or an explicitly approved override
- do not read credentials from another repo by default
- do not add cross-project `.env` fallbacks

## Governance process

Before changing shared rules or skills:

1. Read this file and `AGENTS.md`.
2. Check existing rules and skills for overlap.
3. Decide whether the change belongs in a rule, skill, hook, subagent, documentation, or local/private config.
4. Keep the change narrow and reviewable.
5. Validate metadata and inventory after editing.

Review shared rules and skills after major repo changes. Look for stale commands, obsolete steps, duplicated guidance, oversized skills, and local-only assumptions.
