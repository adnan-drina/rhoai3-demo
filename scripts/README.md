# Scripts

Clean slate for project automation.

Legacy scripts are backed up under:

- `../backup/legacy-implementation-2026-06-09/scripts/`

New scripts should be deterministic, safe to rerun, and must use the project
OpenShift safety guard before live cluster mutations.

Per-stage `deploy.sh` and `validate.sh` scripts should be created through the
`../.agents/skills/project-demo-stage-authoring/SKILL.md` process so scripts,
GitOps ownership, README claims, and validation outcomes stay aligned.

## Local Validation

- `validate-agent-guidance.rb` checks `.agents/` rules, skills, and Red Hat
  documentation routing for logical consistency. It is read-only and does not
  contact a live OpenShift cluster.
