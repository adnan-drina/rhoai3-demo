# Cursor Automation Setup — Documentation Alignment Audit

This document provides the exact configuration to create a Cursor Automation
that runs the documentation alignment audit daily and can also be triggered
manually.

## Setup Instructions

1. Open the **Agents Window** in Cursor (Cmd+Shift+P → "Cursor: Open Agents
   Window")
2. Say: "Create a Cursor Automation for daily documentation alignment audit"
3. Use the configuration below when prompted

## Automation Configuration

| Field | Value |
|-------|-------|
| **Name** | Documentation Alignment Audit |
| **Description** | Daily audit ensuring project READMEs, RHOAI skills, and operational docs accurately reflect implemented GitOps manifests, scripts, and pipelines |
| **Trigger** | Scheduled — every day at 06:00 UTC (`0 6 * * *`) |
| **Tools** | Comment on PRs |
| **Repository** | `<your-org>/rhoai3-demo` |
| **Branch** | `main` |

## Automation Prompt (Instructions)

Copy this prompt into the automation's Instructions field:

---

You are a documentation alignment auditor for the rhoai3-demo project. Your job
is to ensure that project documentation accurately reflects what is actually
implemented in GitOps manifests, scripts, notebooks, and pipelines.

**Read the skill first:** Start by reading
`.agents/skills/project-doc-alignment-audit/SKILL.md` and follow its execution
workflow exactly.

**Execution steps:**

1. Read `docs/PLATFORM_BASELINE.md` to get the current product version targets.

2. For each active stage (`stage-110-rhoai-base-platform`,
   `stage-120-gpu-as-a-service`, `stage-210-model-serving-foundation`,
   `stage-220-models-as-a-service`, `stage-230-private-data-rag`):

   a. Read all GitOps manifests under `gitops/<stage-name>/`
   b. Read all scripts under `<stage-name>/`
   c. Read the `<stage-name>/README.md`
   d. Compare: does the README accurately describe what the manifests deploy?
   e. Check: are operator channels, versions, namespaces, CR apiVersions exact?
   f. Check: does the architecture diagram reflect the actual component topology?
   g. Check: are there claims about capabilities not backed by manifests?

3. For each relevant `.agents/skills/rhoai-*/SKILL.md`:
   a. Cross-reference implementation details against the actual GitOps manifests
   b. Verify: channels, versions, namespace names, CR field names are accurate
   c. Check: are there manifest paths or patterns cited that have moved or been renamed?

4. Check `docs/OPERATIONS.md` and `docs/TROUBLESHOOTING.md` against current
   scripts for procedure accuracy.

5. Check `gitops/README.md` against the actual `gitops/` directory tree.

**Output:** If findings exist, create a branch `docs/alignment-audit-<date>`,
fix all critical and minor findings directly, commit with message
`docs(audit): align documentation with implementation — <date>`, and create a
PR. In the PR body, include the full alignment report.

If no findings exist, comment on the most recent open PR (if any) confirming
documentation is aligned, or simply report "All documentation aligned — no
action needed."

**Constraints:**
- Never invent CR fields, versions, or annotations not present in the manifests
- Never claim a capability is implemented unless a manifest or script proves it
- Follow the stage-specific checklists from the skill
- Keep README prose concise; add implementation details to skills, not READMEs

---

## Manual Trigger

To run this audit on-demand in any Cursor agent session, simply ask:

> Run the documentation alignment audit using the project-doc-alignment-audit skill.

Or invoke it via the agent loop mechanism for recurring local checks:

> /loop 4h Run the documentation alignment audit using .agents/skills/project-doc-alignment-audit/SKILL.md

## Webhook Trigger (Alternative)

If you prefer webhook-based triggering (e.g., from a CI pipeline after merge to
main), select "On an incoming HTTP webhook" as the trigger type instead of the
cron schedule. After saving, the Automations editor will provide a webhook URL
you can call from your CI pipeline's post-merge step.

## Complementary Mechanisms

| Mechanism | Scope | When |
|-----------|-------|------|
| **This Cursor Automation** | Full audit across all stages | Daily or on webhook |
| **`check-docs-consistency.sh` hook** | Incremental per-edit reminders | Every file edit during agent sessions |
| **Manual agent invocation** | Full audit in current session | On demand |
| **`/loop` agent loop** | Recurring in-session audit | During active development sessions |
