# Documentation Index

This directory has published operational documents and generated evidence:

| Document | Purpose |
|----------|---------|
| [OPERATIONS.md](OPERATIONS.md) | Prerequisites, deployment order, bootstrap behavior, deploy and validate script usage, GitOps operating model, validation strategy, and day-2 notes. |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Symptom-based diagnostics, likely causes, recovery commands, and references. |
| [alignment-evidence-ledger.md](alignment-evidence-ledger.md) | Generated pre-merge evidence that changed GitOps components still align with the pinned RHOAI/OCP product documentation baseline. |

The workshop narrative lives in the root [README.md](../README.md) and the step-level `README.md` files under [steps](../steps/).

Other files that may exist in this directory are local session notes, migration notes, or one-off working documents. Treat them as internal scratch material unless they are promoted into this index. They may describe a specific cluster, a past state of the repository, or a deferred idea.

Documentation rules for this repository:

- READMEs are educational technical articles, not runbooks.
- Operations content belongs in [OPERATIONS.md](OPERATIONS.md).
- Failure recovery belongs in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
- Code, manifests, scripts, validation, and docs must stay aligned.
- Documentation must not claim capabilities that are not implemented.
- Future or deferred capabilities must be labeled clearly as future or deferred.
- Run `./scripts/audit-doc-alignment.sh --base origin/main` before merging GitOps component changes.
