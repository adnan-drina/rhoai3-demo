# Knowledge Governance

Use this reference when converting repeated project knowledge into durable
documentation.

## Read Before Writing

Before changing documentation, read the document that owns the knowledge you are
about to edit and its nearest companion docs. Step READMEs are not the catch-all
for every operational detail.

Step READMEs should contain:

- the step-specific concept and business framing
- the value the concept brings to a European-regulated enterprise
- the RHOAI, OpenShift, or Red Hat AI technologies that enable the concept
- the architecture delta between this step and previous steps
- short source-focused references

Other durable knowledge belongs elsewhere:

- deferred capabilities, future enhancements, and prioritized gaps:
  `docs/BACKLOG.md`
- operational procedures and deployment order: `docs/OPERATIONS.md`
- repeated failure symptoms, root causes, and recovery: `docs/TROUBLESHOOTING.md`
- active product targets, documentation category index, version-match rule, and
  source hierarchy: `docs/PLATFORM_BASELINE.md`
- promoted documentation index and ownership notes: `docs/README.md`

## Knowledge Sources

| Source | Purpose |
|--------|---------|
| `README.md` | overall architecture and demo flow |
| `docs/README.md` | index of promoted project documents and documentation ownership rules |
| `docs/BACKLOG.md` | deferred capabilities, future enhancements, and prioritized product coverage gaps |
| `steps/step-XX-name/README.md` | concise step-specific Why/What story, RHOAI technology mapping, architecture delta, and references |
| `docs/OPERATIONS.md` | prerequisites, deployment order, bootstrap behavior, deploy and validate script usage, GitOps operating model, validation strategy, and day-2 operations |
| `docs/TROUBLESHOOTING.md` | symptom-based diagnostics, likely causes, recovery commands, and recurring failure notes |
| `docs/PLATFORM_BASELINE.md` | active RHOAI/OCP product baseline, documentation category index, version-match rule, and source hierarchy |
| `rh-brain` | read-only Red Hat narrative and article research |

## Capture New Knowledge

When fixing a bug or discovering a pattern, update the relevant documentation:

- Put repeated symptoms, root causes, and recovery steps in
  `docs/TROUBLESHOOTING.md`.
- Put deployment order, validation strategy, day-2 operations, and script usage
  in `docs/OPERATIONS.md`.
- Put non-obvious design decisions in the step README only when they are needed
  to understand the concept, technology choice, or architecture delta;
  otherwise place operational detail in `docs/OPERATIONS.md`.
- Put known limitations in the document where the reader needs them most, with
  active-baseline version notes and a link to the source.
- Put deferred capabilities, future enhancements, and prioritized product
  coverage gaps in `docs/BACKLOG.md`.
- Cross-reference related steps or docs instead of duplicating long procedures.
- For GitOps-managed component changes, request or run the Red Hat
  documentation alignment workflow rather than hand-editing product-doc
  evidence by guesswork.

## Recommended Snippets

Troubleshooting:

Use this shape:

- `### <Symptom or error message>`
- `**Root Cause:** <short explanation>`
- `**Solution:** <safe verification or repair steps>`

Design decision:

```markdown
> **Design Decision:** We use X instead of Y because...
```

Known limitation:

```markdown
> **Known Limitation (active baseline):** <description>
> **Workaround:** <solution>
> **Ref:** <official or verified source>
```

## Source Hierarchy

Repository documentation supplements official product documentation; it does not
replace it. If official docs and implementation disagree, document the gap in
the relevant human-facing doc and use `project-red-hat-doc-alignment-review` to
decide whether the product-doc evidence needs refresh.
