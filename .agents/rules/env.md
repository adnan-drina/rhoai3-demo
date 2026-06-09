---
name: env
skill-group: Demo Environment
skill-prefix: env-
applies-to:
  - .env.example
  - env.example
  - docs/OPERATIONS.md
  - docs/TROUBLESHOOTING.md
  - scripts/bootstrap.sh
  - scripts/lib.sh
  - scripts/validate-lib.sh
  - scripts/validate-demo-flow.sh
  - steps/**/deploy.sh
  - steps/**/validate.sh
---

# Demo Environment

Use the `env-*` skills as the source of truth for work with live AWS/OpenShift
demo environments:

- `.agents/skills/env-deploy-and-evaluate/SKILL.md`
- `.agents/skills/env-troubleshoot/SKILL.md`
- `.agents/skills/env-manage-resources/SKILL.md`
- `.agents/skills/env-validate-demo-flow/SKILL.md`

Before live cluster work, load the repo-local environment, verify the expected
API server guard, and keep credentials scoped to this project. Do not bypass the
OpenShift safety guard without explicit user confirmation.

Use GitOps and the per-step scripts for environment changes. Keep operational
runbooks in `docs/OPERATIONS.md` and recovery guidance in
`docs/TROUBLESHOOTING.md`.
