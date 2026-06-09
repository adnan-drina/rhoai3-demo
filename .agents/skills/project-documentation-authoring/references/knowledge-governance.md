# Knowledge Governance

Use this reference when converting repeated project knowledge into durable
documentation.

## Read Before Writing

Before changing a step, read its README. Step READMEs contain:

- design decisions and rationale
- known limitations and workarounds
- troubleshooting notes from real deployments
- official documentation references

## Knowledge Sources

| Source | Purpose |
|--------|---------|
| `README.md` | overall architecture and demo flow |
| `steps/step-XX-name/README.md` | step-specific platform story and details |
| `docs/alignment-evidence-ledger.md` | product-doc alignment evidence |
| `docs/OPERATIONS.md` | operational procedures |
| `docs/TROUBLESHOOTING.md` | failure recovery |
| `rh-brain` | read-only Red Hat narrative and article research |

## Capture New Knowledge

When fixing a bug or discovering a pattern, update the relevant documentation:

- Add troubleshooting entries for repeated symptoms.
- Add design decisions for non-obvious choices.
- Add known limitations with active-baseline version notes.
- Cross-reference related steps when one step affects another.
- Refresh alignment evidence for GitOps-managed component changes.

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

README knowledge supplements official documentation; it does not replace it.
If official docs and implementation disagree, document the gap and explain the
validated demo choice.
