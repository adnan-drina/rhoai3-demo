# Documentation Index

This directory has promoted project documentation. Tracked Markdown files
should stay limited to the documents in this index; architecture SVGs under
`docs/assets/architecture/` are generated README assets.

| Document | Purpose |
|----------|---------|
| [BACKLOG.md](BACKLOG.md) | Deferred capabilities, future enhancements, and prioritized product coverage gaps. |
| [OPERATIONS.md](OPERATIONS.md) | Prerequisites, deployment order, bootstrap behavior, deploy and validate script usage, GitOps operating model, validation strategy, and day-2 notes. |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Symptom-based diagnostics, likely causes, recovery commands, and references. |
| [PLATFORM_BASELINE.md](PLATFORM_BASELINE.md) | Active RHOAI/OCP product baseline and documentation source hierarchy. |

The workshop narrative lives in the root [README.md](../README.md) and the step-level `README.md` files under [steps](../steps/).

Keep session notes, migration notes, one-off working documents, and generated
evidence outside tracked `docs/` content unless they are promoted into this
index.

Documentation rules for this repository:

- READMEs are educational technical articles, not runbooks.
- Operations content belongs in [OPERATIONS.md](OPERATIONS.md).
- Failure recovery belongs in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
- Code, manifests, scripts, validation, and docs must stay aligned.
- Documentation must not claim capabilities that are not implemented.
- Future or deferred capabilities must be labeled clearly as future or deferred.
- Run `./scripts/audit-doc-alignment.sh --base origin/main` before merging GitOps component changes.
