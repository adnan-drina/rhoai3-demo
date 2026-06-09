# Step README Standard

Each step README is an educational demo document. It should tell the platform
story, show proof, and connect the technical implementation to business value.

## Narrative Alignment

Use official Red Hat terminology and active-baseline docs. Connect the step to
the relevant OpenShift AI capability:

| Capability | Demo steps |
|------------|------------|
| Intelligent GPU and hardware speed | 01, 02, 03 |
| Catalog and registry | 04 |
| Optimized model serving | 05, 06 |
| Model development and customization | 07, 11 |
| AI pipelines | 07, 08, 12 |
| Observability and governance | 06, 08, 09, 12 |
| Agentic AI and GenAI UIs | 05, 09, 10 |
| Training and experimentation | 11, 12 |
| Disconnected environments and edge | 13, 13b |

## Architecture Section

Every root or step README should include a `## Architecture` section using the
generated SVG capability maps under `docs/assets/architecture/`.

- Root map: `docs/assets/architecture/rhoai3-demo-capability-map.svg`
- Step maps: `../../docs/assets/architecture/step-NN-capability-map.svg`

Place the diagram after motivation and before the first technical breakdown.
Change `scripts/generate-readme-visuals.py` and regenerate SVGs instead of
hand-editing generated diagrams.

## Required README Shape

1. H1 title and one-line tagline.
2. Overview that includes problem framing, product introduction,
   `## Architecture`, what gets deployed, design decisions, and concise
   deploy/validate entry points.
3. Demo section with scenes.
4. Key takeaways for business and technical audiences.
5. Step-specific troubleshooting notes only when they help the reader
   understand the demo; link reusable recovery procedures to
   `docs/TROUBLESHOOTING.md`.
6. References to active-baseline official docs and relevant Red Hat pages.
7. Next steps as the final section.

## Content Boundaries

- Keep step READMEs focused on the educational platform story and what the
  step proves.
- Include short deploy and validate commands when they anchor the demo flow,
  but put deployment order, environment preparation, shutdown/recovery, and
  day-2 runbooks in `docs/OPERATIONS.md`.
- Put repeated symptoms, root causes, and repair procedures in
  `docs/TROUBLESHOOTING.md`; the README may link to them.
- Put active product targets and source hierarchy in
  `docs/PLATFORM_BASELINE.md`.
- Put deferred capabilities, future enhancements, and prioritized product
  coverage gaps in `docs/BACKLOG.md`; README references may link to the
  backlog instead of repeating backlog detail.

## Demo Scene Pattern

```markdown
### Scene Title

> Context: what we are about to see and why it matters.

1. Action step
2. Action step
3. Action step

**Expect:** What the audience sees on screen.

> Value: what this proves and why it matters.
```

## Formatting

- Keep heading levels sequential.
- Use `-` for unordered lists.
- Add language identifiers to fenced code blocks.
- Use backticks for filenames, commands, config keys, and resource names.
- Use relative links within the repository.
- Use descriptive link text.
- Narrative blockquotes should be written as spoken demo narration.
- Do not expose Tell-Show-Tell methodology labels in the README.

## Review Checklist

After editing a README:

- `## Architecture` exists and points to the correct SVG.
- The architecture section appears after motivation and before component detail.
- Headings do not skip levels.
- Fenced code blocks include language identifiers.
- Relative links resolve.
- References include active-baseline technical docs and Red Hat product pages
  where relevant.
- Long runbook or recovery content has been routed to `docs/OPERATIONS.md` or
  `docs/TROUBLESHOOTING.md`.
- Deferred work links to `docs/BACKLOG.md` when it is actionable project work.
