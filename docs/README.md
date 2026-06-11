# Documentation Index

This directory contains promoted project documentation for the reimplementation.
Tracked Markdown files should stay limited to the documents in this index.

| Document | Purpose |
|----------|---------|
| [BACKLOG.md](BACKLOG.md) | Active backlog for the reimplementation. |
| [OPERATIONS.md](OPERATIONS.md) | Active operating model, deployment order, validation strategy, and day-2 notes once the new implementation exists. |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Active symptom-based diagnostics and recovery guidance once the new implementation exists. |
| [PLATFORM_BASELINE.md](PLATFORM_BASELINE.md) | Active RHOAI/OCP product baseline, version-match rule, Red Hat documentation category index, and source hierarchy. |

The previous root README, legacy step READMEs, operational runbooks,
troubleshooting notes, backlog, and generated architecture SVGs are backed up
under:

- `../backup/legacy-implementation-2026-06-09/`

The reimplemented workshop narrative will live in the root README and
root-level stage README files under `../stage-YXX-slug/` folders when new
stages are created.

Documentation rules for this repository:

- READMEs provide concise Why/What content for a technical audience, not
  deployment runbooks.
- Operations content belongs in [OPERATIONS.md](OPERATIONS.md).
- Failure recovery belongs in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
- Code, manifests, scripts, validation, and docs must stay aligned.
- Documentation must not claim capabilities that are not implemented.
- Future or deferred capabilities must be labeled clearly as future or deferred.
- Official Red Hat documentation for the active baseline in
  [PLATFORM_BASELINE.md](PLATFORM_BASELINE.md) is the product source of truth.
