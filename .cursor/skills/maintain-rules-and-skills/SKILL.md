---
name: maintain-rules-and-skills
metadata:
  author: rhoai3-demo
  version: 1.1.0
  rhoai-version: "3.4"
  ocp-version: "4.20"
description: >
  Manage the Cursor platform configuration for this project — rules, skills,
  hooks, and subagents. Use when the user asks to create a rule, update a skill,
  audit rules, review skills, add a hook, create a subagent, or asks about
  .cursor/ configuration. Also use when discussing what type of component
  (rule vs skill vs hook vs subagent) is appropriate for a given need.
  Do NOT use for deploying the demo (use deploy-and-evaluate), troubleshooting
  cluster issues (use rhoai-troubleshoot), or chatbot changes (use
  chatbot-customization).
---

# Maintain Rules, Skills, Hooks & Subagents

Structured workflow for creating, updating, and auditing the four Cursor
platform components in this project.

## Decision Framework: Which Component Type?

| Need | Component | Why |
|------|-----------|-----|
| Persistent coding guidance for specific file types | **Rule** (`.cursor/rules/*.mdc`) | Scoped by glob, always in context when editing matching files |
| Persistent guidance for ALL files | **Rule** with `alwaysApply: true` | Budget carefully — currently 194 lines |
| Multi-step workflow with domain knowledge | **Skill** (`.cursor/skills/*/SKILL.md`) | Progressive disclosure; agent invokes when relevant |
| Destructive or sensitive workflow | **Skill** with `disable-model-invocation: true` | Only invoked explicitly via `/skill-name` |
| Complex multi-step task needing context isolation | **Subagent** (`.cursor/agents/*.md`) | Own context window; parallel execution; readonly option |
| Automated validation after file edits | **Hook** (`.cursor/hooks.json`) | Runs scripts automatically; no agent decision needed |
| Gate risky shell commands | **Hook** (`beforeShellExecution`) | Blocks or warns before dangerous operations |
| Pre-merge product-doc evidence | **Script + ledger** (`scripts/audit-doc-alignment.sh`, `docs/alignment-evidence-ledger.md`) | Records component alignment against pinned RHOAI 3.4 / OCP 4.20 docs |

Ref: [Rules](https://cursor.com/docs/context/rules), [Skills](https://cursor.com/docs/skills),
[Hooks](https://cursor.com/docs/hooks), [Subagents](https://cursor.com/docs/subagents)

## Current Inventory

| Type | Count | Location |
|------|-------|----------|
| Rules | 13 | `.cursor/rules/*.mdc` |
| Skills | 8 | `.cursor/skills/*/SKILL.md` |
| Hooks | 4 | `.cursor/hooks.json` |
| Subagents | 3 | `.cursor/agents/*.md` |
| Claude Code rules | 4 | `.claude/rules/*.md` (bridge files) |
| CLAUDE.md | 1 | `CLAUDE.md` (root entry point) |

Design doc: `docs/cursor-skills-and-rules.md`
Audit log: `docs/rules-skills-audit.md`

## Instructions

### Before Creating Any Component

1. Read `docs/cursor-skills-and-rules.md` for current inventory and conventions
2. Read `references/conventions.md` for detailed patterns
3. Check for overlaps — does an existing rule/skill already cover this?
4. Decide the component type using the decision framework above

### Creating a Rule

- Use `.mdc` extension with YAML frontmatter (`description`, `globs`, `alwaysApply`)
- If `alwaysApply: true`, check the budget (currently 194 lines for 4 rules)
- Include a References section with official Red Hat doc links for RHOAI/OCP-specific rules
- Include an Agent Behavior section if the rule requires post-edit verification
- Reference files with `@filename` instead of copying content into the rule
- Add the rule to the inventory in `docs/cursor-skills-and-rules.md`

### Creating a Skill

- `name` in frontmatter MUST match the parent folder name
- Include `metadata` with `version`, `rhoai-version`, `ocp-version`
- Write "pushy" descriptions: enumerate specific scenarios, not generic triggers
- Include negative triggers: "Do NOT use for X (use Y instead)"
- Use `disable-model-invocation: true` for destructive operations
- Keep SKILL.md under 500 lines; use `references/` for detailed knowledge
- If the skill has a companion rule, reference it instead of duplicating content

### Creating a Subagent

- Place in `.cursor/agents/` with `.md` extension
- Set `readonly: true` for information-gathering agents
- Use `model: fast` for high-volume search/verification tasks
- Use `model: inherit` for tasks needing the same reasoning as the parent
- Write focused descriptions — avoid generic "helper" agents

### Creating a Hook

- Define in `.cursor/hooks.json` (project-level)
- Scripts go in `.cursor/hooks/` (paths relative to project root)
- Use matchers to filter by file pattern or command
- Use `failClosed: true` for security-critical hooks
- Test hooks manually before relying on them

### Auditing All Components

Run this audit periodically (monthly or after major changes):

1. Read every rule and skill file
2. Check for content duplication between rules and skills
3. Check for stale references (removed steps, renamed files)
4. Verify skill `name` fields match folder names
5. Verify always-apply budget hasn't crept up
6. Check Red Hat doc links still resolve
7. Update `docs/rules-skills-audit.md` with findings

For detailed conventions and patterns, read `references/conventions.md`.

### Documentation Alignment Loop

When a rules/skills/agent update changes how GitOps manifests or step READMEs
are authored, keep the product-documentation loop current:

1. Check whether the change affects a GitOps-managed component, ArgoCD app, or
   step README.
2. Run the local gate before merge:

   ```bash
   ./scripts/audit-doc-alignment.sh --base origin/main
   ```

3. For scoped follow-up, use:

   ```bash
   ./scripts/audit-doc-alignment.sh --component step-05-maas-model-serving
   ```

4. Commit the refreshed `docs/alignment-evidence-ledger.md` with the branch.
5. Use `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` only for narrative,
   customer framing, and Red Hat article alignment. Do not treat it as product
   configuration truth.

## Dual Ecosystem: Cursor + Claude Code

This project supports both Cursor IDE and Claude Code. The two tools share
skills and agents natively but have different rule formats.

### What's shared automatically
- **Skills** in `.cursor/skills/` — Claude Code discovers this path natively
- **Agents** in `.cursor/agents/` — Claude Code discovers this path natively

### What's bridged
- **Rules**: Cursor uses `.cursor/rules/*.mdc` (globs/alwaysApply frontmatter).
  Claude Code uses `.claude/rules/*.md` (paths frontmatter) + `CLAUDE.md` (@imports).
  The `.claude/rules/` files are thin bridges that `@import` the canonical `.cursor/rules/` content.

### When updating rules
1. Edit the canonical `.cursor/rules/XX-name.mdc` file
2. The `.claude/rules/` bridge files reference it via `@import` — no separate update needed
3. If you add a new rule, consider adding a matching `.claude/rules/` bridge with `paths:` frontmatter

### When updating CLAUDE.md
`CLAUDE.md` is the Claude Code root entry point (~120 lines). Update it when:
- Project structure changes (new steps, renamed directories)
- Key commands change (bootstrap, deploy, validate patterns)
- New skills or agents are added

Both `.cursor/` and `.claude/` are gitignored — local dev configuration only.

### Parallel Agents (Worktrees)
`.cursor/worktrees.json` sets up isolated worktrees for parallel agents. Each worktree
symlinks `.cursor/`, `.claude/`, `.venv-kfp`, and `artifacts/` from the main tree so
agents share the same AI config and tooling. Use parallel agents for multi-step work
(KFP alignment, label fixes, README batch updates) where changes don't overlap.
