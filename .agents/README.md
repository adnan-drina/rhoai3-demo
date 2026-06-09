# Agent Guidance

This directory contains tool-neutral shared agent guidance.

## Layout

| Path | Purpose |
|------|---------|
| `hooks/` | Shared reusable hook implementations |
| `rules/*.md` | Short tool-neutral domain rules |
| `skills/*/SKILL.md` | Canonical shared skills following the Agent Skills layout |

Keep tool-specific hooks, settings, and subagents in their native directories
only when the tool requires that format.

## Tool-Specific Directories

- `.claude/` should contain only `CLAUDE.md`. Keep local Claude settings in
  personal configuration, not the repo.
- `.codex/` should contain only hook configuration or compatibility wrappers
  that call shared hook implementations.
- `.cursor/` should contain only Cursor hook configuration and Cursor-specific
  hook scripts that cannot be shared.
- `.cursor/` should not contain shared rules, skills, agents, or worktree
  state. Keep those tool-specific artifacts local unless the team agrees to
  track a reviewed bridge.
