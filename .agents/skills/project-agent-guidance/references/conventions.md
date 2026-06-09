# Shared Agent Guidance Conventions

Use these conventions when changing `AGENTS.md`, `.agents/`, `.cursor/`,
`.codex/`, or `.claude/` in this repository.

## AGENTS.md

`AGENTS.md` is the root, tool-neutral contract for coding agents.

- Keep it concise enough to be useful on every task.
- Use plain Markdown; do not rely on tool-specific include syntax.
- Include project overview, commands, safety constraints, branch/commit rules,
  and pointers to detailed shared rules and skills.
- Add nested `AGENTS.md` files only for genuinely distinct subprojects with
  local instructions that should override root guidance.
- If instructions conflict, the user's current prompt wins; otherwise the
  closest applicable `AGENTS.md` should be treated as more specific.

## Shared Rules

Rules live under `.agents/rules/` and are short, tool-neutral domain guardrails.
They are not a replacement for root `AGENTS.md`; they give agents a predictable
place to look before work in a specific skill group.

Current rule taxonomy:

| Rule | Skill prefix | Purpose |
|------|--------------|---------|
| `project.md` | `project-` | Repo structure, GitOps authoring, docs, manifest review, Red Hat doc alignment, and shared guidance |
| `env.md` | `env-` | Live demo environment deployment, validation, troubleshooting, shutdown, recovery, and redeploy |
| `rhoai.md` | `rhoai-` | Official-doc-backed RHOAI component behavior and configuration |
| `assets.md` | `assets-` | Visual assets, diagrams, decks, and presentation outputs |

Rule frontmatter should stay simple:

```yaml
---
name: project
skill-group: Project Structure
skill-prefix: project-
applies-to:
  - AGENTS.md
  - .agents/**
---
```

Keep detailed procedure in skills, not rules. A rule should point to the
relevant skills and state the non-negotiable constraints for that domain.

## Shared Skills

Skills live under `.agents/skills/<skill-name>/SKILL.md`.

Skill frontmatter:

```yaml
---
name: project-example
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Use when [specific scenarios]. Do NOT use for [X] (use [Y] instead).
---
```

Conventions:

- `name` must match the parent folder.
- Folder prefix must match `metadata.skill-group`.
- Use `platform-baseline: "repo"` and `ocp-baseline: "repo"` so the active
  versions stay centralized in `docs/PLATFORM_BASELINE.md`.
- Descriptions should enumerate concrete trigger scenarios and negative
  triggers.
- Keep `SKILL.md` focused; put deeper detail in `references/`, executable
  helpers in `scripts/`, and reusable examples in `examples/` when needed.
- Keep tool-specific copies out of the repo.

## Shared Hooks

Reusable hook implementations live under `.agents/hooks/`.

- Tool-specific hook config may call shared hook scripts.
- Keep hook logic deterministic and non-secret.
- Hooks should validate, remind, or block; they should not rewrite project files.
- Security-critical hooks should fail closed when the tool supports that mode.
- Cursor-only hook scripts may remain in `.cursor/hooks/` when they depend on
  Cursor event payloads.
- Codex hook wrappers may remain in `.codex/hooks/` for compatibility with
  running sessions, but reusable logic belongs in `.agents/hooks/`.

## Tool Bridges

Keep tool-specific directories minimal:

| Directory | Shared repo purpose |
|-----------|---------------------|
| `.claude/` | `CLAUDE.md` bridge to root `AGENTS.md` only |
| `.codex/` | Codex hook config and compatibility wrappers only |
| `.cursor/` | Cursor hook config and Cursor-only hook scripts only |

Do not reintroduce tool-specific rules, skills, agents, or worktree state unless
there is a concrete tool-only gap and the bridge is reviewed as source.

## Audit Checklist

Run this after major guidance changes:

- [ ] Root `AGENTS.md` is plain Markdown and self-contained enough to orient a
      new agent.
- [ ] `.agents/rules/` has exactly the four group-level rules unless the skill
      taxonomy changes.
- [ ] Every rule points to the relevant skills instead of duplicating workflows.
- [ ] Every skill `name` matches its folder.
- [ ] Every skill has `metadata.skill-group`, `platform-baseline`, and
      `ocp-baseline`.
- [ ] No active references point to removed tool-specific rule, skill, agent,
      or discovery-bridge paths.
- [ ] Hook scripts pass syntax checks and JSON hook configs parse.
- [ ] `AGENTS.md`, `.agents/rules/*.md`, and `project-agent-guidance`
      inventories match the filesystem.
