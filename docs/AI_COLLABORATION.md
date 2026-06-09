# AI-Assisted Collaboration Model

This document defines how AI rules, skills, hooks, and subagents are organized in this repository.

## Operating principle

AI tools are accelerated collaborators, not autonomous maintainers. Every AI-assisted change must remain human-owned, reviewed, and validated.

The contribution flow:

> Human-defined task -> AI-assisted plan -> focused change -> full human diff review -> explicit validation -> PR or commit with AI disclosure.

This matters especially for this demo because repository state, live OpenShift state, and local credentials are separate trust boundaries.

## Shared project guidance

Shared guidance lives in:

- `AGENTS.md` - tool-neutral agent guidance and repository safety rules
- `.agents/rules/*.md` - short tool-neutral domain rules
- `.agents/skills/*/SKILL.md` - canonical repeatable project workflows
- `.agents/hooks/` - shared hook implementations used by tool-specific hook config
- `.cursor/hooks.json` and `.cursor/hooks/` - Cursor automation hooks
- `.codex/hooks.json` and `.codex/hooks/` - Codex command-safety hooks
- `.claude/CLAUDE.md` - Claude Code bridge to `AGENTS.md`

Treat these files as source code. Changes should be reviewed like any other behavior change.

`.claude/` should stay minimal: `CLAUDE.md` only. Do not commit Claude
settings, Claude rule copies, or Claude-specific skill copies.
`.codex/` should stay hook-only unless a future Codex project bridge is needed.

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
| Tool-neutral project contract | `AGENTS.md` | Applies across agents and should stay concise |
| Tool-neutral domain rule | `.agents/rules` | Short constraints for a file family or project domain |
| Repeatable task workflow | `.agents/skills` | Task-specific, invoked when relevant |
| Context-heavy investigation | `.agents/skills` first; tool-specific subagent only if needed | Needs isolation or parallel review beyond normal skill invocation |
| Automated validation or command guard | Tool hook directory | The check should run without agent discretion |
| Explanatory policy | `docs/` | Informational, not automatically enforced |
| Personal setup | Local/private config | Applies to one contributor only |

Do not create a skill when a short rule or doc note is enough. Do not create a rule when a workflow skill is more appropriate.
Do not duplicate shared skills in tool-specific folders; use the canonical
`.agents/skills/` tree and add a minimal bridge only for a proven tool-only gap.
Do not add tool-specific subagent copies unless a shared need has been defined
first.

## Skill taxonomy

Keep canonical skill folders flat under `.agents/skills/`. Tool-specific
discovery paths are not tracked in this repo. Use the prefix and
`metadata.skill-group` taxonomy below for review, ownership, and cleanup instead
of nesting folders.

| Group | Prefix | Skills | Purpose |
|-------|--------|--------|---------|
| Project Structure | `project-*` | `project-structure`, `project-agent-guidance`, `project-architecture-diagrams`, `project-gitops-authoring`, `project-documentation-authoring`, `project-manifest-review`, `project-red-hat-doc-alignment-review` | Evolve repo layout, GitOps step conventions, documentation structure, Red Hat narrative alignment, manifest review, Red Hat doc alignment, and shared AI guidance |
| Demo Environment | `env-*` | `env-deploy-and-evaluate`, `env-troubleshoot`, `env-manage-resources`, `env-validate-demo-flow` | Deploy, validate, troubleshoot, shut down, recover, and redeploy the live AWS/OpenShift demo environment |
| RHOAI Platform | `rhoai-*` | `rhoai-chatbot-customization`, `rhoai-model-evaluation`, `rhoai-kfp-pipeline-authoring`; additional component skills planned | Install, configure, and use active-baseline RHOAI components from official Red Hat documentation, enhanced by verified Red Hat article examples |
| Assets & Miscellaneous | `assets-*` | `assets-red-hat-quick-deck` | Supporting visual, deck, and presentation assets |

Current inventory:

| Type | Count | Location |
|------|-------|----------|
| Shared rules | 4 | `.agents/rules/*.md` |
| Shared skills | 15 | `.agents/skills/*/SKILL.md` |
| Shared hook scripts | 1 | `.agents/hooks/` |
| Cursor hook bridge | 1 config, 2 scripts | `.cursor/hooks.json`, `.cursor/hooks/` |
| Codex hook bridge | 1 config, 1 compatibility wrapper | `.codex/hooks.json`, `.codex/hooks/` |
| Claude bridge | 1 | `.claude/CLAUDE.md` |

## Skill quality bar

Shared skills should:

- have a `name` matching the parent folder
- use the correct group prefix and matching `metadata.skill-group`
- include metadata with version and platform targets when project-specific
- have a specific trigger description and negative triggers
- keep `SKILL.md` under 500 lines when practical
- move large detail into `references/`
- avoid duplicating companion rules
- avoid secrets, local paths, private URLs, and local cluster assumptions
- mark destructive or expensive workflows with `disable-model-invocation: true`
- preserve the source hierarchy: official Red Hat docs first, Red Hat articles and `rh-brain` examples second, repo implementation last

`assets-red-hat-quick-deck` is intentionally shared between both demo repos and is organized as a lean entry-point `SKILL.md` plus detailed `references/` files. Keep future deck-system detail in references instead of expanding the entry point.

Use `project-structure` for the canonical skill taxonomy and `project-structure/references/rhoai-component-skill-roadmap.md` for the planned RHOAI Platform component skills.

## Hooks and cluster safety

Reusable hook logic lives in `.agents/hooks/`. Tool-specific hook config should
call shared implementations when possible instead of duplicating logic.

Cursor hooks provide edit-time validation and command prompts. Codex hooks
provide command-safety checks for risky `oc` and `kubectl` mutations. Hook
configuration is tool-specific by design; keep it small and deterministic.

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
