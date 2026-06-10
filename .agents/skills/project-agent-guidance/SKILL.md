---
name: project-agent-guidance
metadata:
  author: rhoai3-demo
  version: 1.1.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Manage shared agent guidance for this project — AGENTS.md, shared rules,
  shared skills, hooks, subagents, and tool bridges. Use when the user asks to
  create a rule, update a skill, audit rules, review skills, add a hook, create
  a subagent, remove duplicated tool-specific guidance, or asks about .agents/,
  .cursor/, .codex/, or .claude/ configuration. Also use when discussing what
  type of component is appropriate for a given need. For the demo skill
  taxonomy and RHOAI component roadmap, pair with project-structure.
  Do NOT use for deploying the demo (use env-deploy-and-evaluate), troubleshooting
  cluster issues (use env-troubleshoot), or chatbot changes (use
  rhoai-chatbot-customization).
---

# Maintain Agent Guidance

Structured workflow for creating, updating, and auditing shared agent guidance
and tool-specific bridges in this project.

## Decision Framework: Which Component Type?

| Need | Component | Why |
|------|-----------|-----|
| Tool-neutral project contract | **AGENTS.md** | Applies across agents and should stay concise |
| Short tool-neutral guidance for a file family or domain | **Rule** (`.agents/rules/*.md`) | Small constraints that should apply across tools |
| Persistent guidance for ALL files | **AGENTS.md** | Keep always-on instructions concise and tool-neutral |
| Multi-step workflow with domain knowledge | **Skill** (`.agents/skills/*/SKILL.md`) | Progressive disclosure; agent invokes when relevant |
| Destructive or sensitive workflow | **Skill** with `disable-model-invocation: true` | Only invoked explicitly via `/skill-name` |
| Complex multi-step task needing context isolation | **Subagent** only when tool-specific isolation is required | Own context window; parallel execution; readonly option |
| Automated validation after file edits | **Tool hook config + script** | Runs scripts automatically; no agent decision needed |
| Gate risky shell commands | **Shared hook implementation** (`.agents/hooks/`) | Reusable safety logic called by tool-specific configs |
| Gate risky Codex shell commands | **Codex hook bridge** (`.codex/hooks.json`) | Calls shared guard before execution |
| Pre-merge Red Hat source audit | **Future script** (`scripts/audit-doc-alignment.sh`) | Reports component alignment against the pinned product baseline in `docs/PLATFORM_BASELINE.md` once recreated |

Ref: [Skills](https://cursor.com/docs/skills), [Hooks](https://cursor.com/docs/hooks),
[Subagents](https://cursor.com/docs/subagents)

## Current Inventory

| Type | Count | Location |
|------|-------|----------|
| Shared rules | 6 | `.agents/rules/*.md` |
| Shared skills | 98 | `.agents/skills/*/SKILL.md` |
| Shared reference maps | 1 | `.agents/references/` |
| Shared hook scripts | 1 | `.agents/hooks/` |
| Cursor hook bridge | 1 config, 2 scripts | `.cursor/hooks.json`, `.cursor/hooks/` |
| Codex hook bridge | 1 config, 1 compatibility wrapper | `.codex/hooks.json`, `.codex/hooks/` |
| Claude Code bridge | 1 | `.claude/CLAUDE.md` |

Canonical governance: `AGENTS.md`, `.agents/rules/*.md`,
`.agents/references/red-hat-doc-map.yaml`, and this skill.

## Skill Groups

Keep folders flat and use the prefix plus frontmatter `metadata.skill-group`
for logical ownership:

| Group | Prefix | Purpose |
|-------|--------|---------|
| Project Structure | `project-*` | Repo layout, demo step authoring, GitOps authoring, documentation structure, RHOAI docs-to-skill generation, manifest review, Red Hat source alignment, Red Hat narrative grounding, and shared AI guidance |
| Demo Environment | `env-*` | Live AWS/OpenShift demo deployment, validation, troubleshooting, shutdown, recovery, and redeploy |
| RHOAI Platform | `rhoai-*` | Official-doc-backed active-baseline RHOAI component installation, configuration, KFP pipelines, and usage |
| OpenShift Platform | `ocp-*` | Official-doc-backed OpenShift Container Platform guidance plus repo-approved OpenShift platform extensions for infrastructure, networking, auth, monitoring, GitOps, cluster, and storage integration |
| OpenShift Data Foundation | `odf-*` | Official-doc-backed OpenShift Data Foundation storage, object storage, Ceph, NooBaa, storage class, and data-service integration guidance |
| Assets & Miscellaneous | `assets-*` | Visual, deck, and presentation assets |

Use `project-structure` for the taxonomy,
`project-structure/references/rhoai-component-skill-roadmap.md` for RHOAI
component skills, and
`project-structure/references/ocp-component-skill-roadmap.md` for OpenShift
Platform component skills, and
`project-structure/references/odf-component-skill-roadmap.md` for OpenShift
Data Foundation component skills. Use `project-red-hat-doc-skill-authoring`
for new `rhoai-*`, `ocp-*`, and `odf-*` skills generated from official Red Hat
docs, and use `.agents/references/red-hat-doc-map.yaml` to route Red Hat
product documentation categories and books to flat skills.

## Instructions

### Before Creating Any Component

1. Read `AGENTS.md`, `.agents/rules/*.md`, and this skill for current governance, taxonomy, and inventory
2. Read `references/conventions.md` for detailed patterns
3. Check for overlaps — does an existing rule/skill already cover this?
4. Decide the component type using the decision framework above

### Creating a Rule

- Use `.md` extension under `.agents/rules/`
- Keep rules short, tool-neutral, and focused on one domain or file family
- Include YAML frontmatter with `name` and optional `applies-to` patterns
- Point to `.agents/skills/<skill>/SKILL.md` and specific references instead
  of copying workflow content
- Put always-on project instructions in `AGENTS.md`
- Put multi-step procedures in `.agents/skills/`

### Creating a Skill

- `name` in frontmatter MUST match the parent folder name
- Include `metadata` with `version`, `platform-family`, `platform-baseline`, `ocp-baseline`, and `skill-group`
- Write "pushy" descriptions: enumerate specific scenarios, not generic triggers
- Include negative triggers: "Do NOT use for X (use Y instead)"
- Use `disable-model-invocation: true` for destructive operations
- Keep SKILL.md under 500 lines; use `references/` for detailed knowledge
- If the skill has a companion rule, reference it instead of duplicating content
- Create and edit skills only under `.agents/skills/`; update tool bridges only
  when skill folders are added, renamed, or removed

### Creating a Subagent

- Prefer a shared skill first. Add a tool-specific subagent only when normal
  skill invocation does not provide enough context isolation or parallelism.
- If tool-specific isolation is needed, follow that tool's native subagent
  format and keep it local unless the team agrees to track a reviewed bridge.
- Set `readonly: true` for information-gathering agents
- Use `model: fast` for high-volume search/verification tasks
- Use `model: inherit` for tasks needing the same reasoning as the parent
- Write focused descriptions — avoid generic "helper" agents

### Creating a Hook

- Put reusable hook logic in `.agents/hooks/`
- Define tool-specific wiring in the tool's hook config
- Cursor-only scripts go in `.cursor/hooks/` when they depend on Cursor payloads
- Use matchers to filter by file pattern or command
- Use `failClosed: true` for security-critical hooks
- Test hooks manually before relying on them

### Creating a Codex Hook

- Define in `.codex/hooks.json` only for project-local Codex behavior
- Prefer calling shared scripts from `.agents/hooks/`
- Keep `.codex/hooks/` limited to compatibility wrappers when needed
- Keep hooks deterministic and non-secret; never print full commands containing credentials
- Use them for safety checks such as blocking risky `oc`/`kubectl` mutations when the expected cluster guard is absent or mismatched
- Document user-visible behavior in `AGENTS.md` and the relevant shared skill

### Auditing All Components

Run this audit periodically (monthly or after major changes):

1. Run `scripts/validate-agent-guidance.rb`.
2. Read every rule and skill file.
3. Check for content duplication between rules and skills.
4. Check for stale references (removed steps, renamed files).
5. Verify skill `name` fields match folder names.
6. Verify always-apply budget hasn't crept up.
7. Check Red Hat doc links still resolve.
8. Update `AGENTS.md`, `.agents/rules/*.md`, and this skill when inventory or taxonomy changes.
9. Keep dated deep-audit notes out of `docs/` unless they are promoted to one of the maintained docs.

For detailed conventions and patterns, read `references/conventions.md`.

### Documentation Alignment Loop

When a rules/skills/agent update changes how GitOps manifests or step READMEs
are authored, keep the product-documentation loop current:

1. Check whether the change affects a GitOps-managed component, ArgoCD app, or
   step README.
2. If `scripts/audit-doc-alignment.sh` exists in the active implementation, run
   the local gate before merge:

   ```bash
   ./scripts/audit-doc-alignment.sh --base origin/main
   ```

3. For scoped follow-up, use:

   ```bash
   ./scripts/audit-doc-alignment.sh --component step-05-maas-model-serving
   ```

4. If the active audit script has not been recreated yet, document the missing
   gate in the change summary and use the Red Hat source-alignment checklist
   manually.
5. Review the script output before merge when the script exists.
6. Use `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` only for narrative,
   customer framing, and Red Hat article alignment. Do not treat it as product
   configuration truth.

## Tool Bridges

This project keeps shared guidance in tool-neutral locations where possible,
then exposes that guidance to tools through small bridge files only when needed.

### Canonical shared sources

- **Project contract**: `AGENTS.md`
- **Rules**: `.agents/rules/*.md`
- **Skills**: `.agents/skills/*/SKILL.md`
- **Reference maps**: `.agents/references/*.yaml`
- **Reusable hook implementations**: `.agents/hooks/`
- **Platform baseline**: `docs/PLATFORM_BASELINE.md`

### Tool-specific bridges

- `.claude/CLAUDE.md` imports `AGENTS.md`; keep it as a bridge, not a second
  project manual.
- `.cursor/` remains hook-only for this repo; local Cursor state is ignored.
- `.codex/` remains hook-only for command safety and may keep a tiny wrapper
  for compatibility with already-running sessions.

Do not add tool-specific rule copies unless there is a proven tool-only gap.
Prefer improving `AGENTS.md`, `.agents/rules/`, or a shared skill first.

Shared `.agents/`, `.cursor/`, `.claude/`, and `.codex/` files in this repo are
project guidance and should be reviewed like source. Personal or
machine-specific guidance belongs in home-directory config, not the repo.

### Parallel Agents And Worktrees
No repo-local Cursor worktree config is tracked currently. Keep personal
worktree setup in local/private Cursor config unless the team agrees to share a
reviewed bridge. If parallel agents are used locally, ensure generated worktrees
can access `.agents/`, `.claude/`, `.venv-kfp`, and `artifacts/` from the main
tree.
