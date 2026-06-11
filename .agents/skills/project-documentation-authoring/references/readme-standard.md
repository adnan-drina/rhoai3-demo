# Step README Standard

Each step README is a concise Why/What document for a technical audience. It
should educate a new reader, explain the RHOAI value introduced by the step,
and stay short enough to become a three-slide presentation segment.

GitOps manifests, deploy scripts, validation scripts, and the live demo show
How. Step READMEs explain Why the step matters and What Red Hat technologies
make it possible.

## Reader Promise

Each step README should let an enterprise architect, platform engineer, data
scientist, risk owner, or business stakeholder quickly answer:

- What concept is introduced in this step?
- Why should a European-regulated enterprise care?
- What business or platform value does it provide?
- Which RHOAI, OpenShift, or Red Hat AI technologies enable it?
- Which components are new in this step, and which were introduced earlier?

## Required README Shape

Use this shape for step READMEs:

1. H1 title and one-line tagline.
2. `## Why This Matters`
3. `## What Enables It`
4. `## Architecture`
5. `## References`

Avoid extra sections unless the step genuinely needs a short known limitation
or explicit demo boundary. Put operational detail elsewhere.

## Why This Matters

This section is the source for slide 1: concept and value.

Keep it short. Define the concept introduced by the step and explain why a
European-regulated enterprise should care. Focus on the value to the audience,
not implementation mechanics.

Include:

- a plain definition of the concept in Red Hat terminology
- the enterprise concern it addresses, such as governance, control, cost,
  compliance, traceability, productivity, portability, safety, or scale
- the specific value this step adds to the demo story
- at least one Red Hat article, blog, guide, datasheet, or product page found
  through `/Users/adrina/Sandbox/rh-brain/Red Hat Brain`

When several Red Hat narrative sources are available, prefer sources that link
to concrete GitHub reference implementations, manifests, notebooks, pipelines,
or application code used by Red Hat product, field, solution, demo, or
community-of-practice teams.

Do not use generic market claims when a Red Hat source exists.

## What Enables It

This section is the source for slide 2: technology enablers.

Explain the RHOAI, OpenShift, or Red Hat AI components that make the concept
real in this demo. Prefer a short table over long prose.

Recommended table:

```markdown
| Technology | Role in this step | Source |
|------------|-------------------|--------|
| Red Hat OpenShift AI <component> | <what it enables> | <official Red Hat docs link> |
```

For every RHOAI technical component introduced in the README:

- link to the active-baseline official Red Hat documentation used as the
  configuration source
- describe the component's role in one sentence
- distinguish product capability from custom demo glue
- state preview, technology-preview, deferred, or demo-only posture when
  relevant

If a Red Hat-linked GitHub reference implementation informed the component
selection or demo shape, mention it in `## References` or `PLAN.md` as an
example source. Do not use the GitHub example as the authority for product API
fields or support posture.

## Architecture

This section is the source for slide 3: architecture delta.

Every root or step README should include a generated SVG capability map once the
active diagram generator has been recreated.

- Root map: `docs/assets/architecture/rhoai3-demo-capability-map.svg`
- Step maps: `../../docs/assets/architecture/step-NN-capability-map.svg`

The step diagram must make the current-step components visually distinct from
previously introduced components. Follow the architecture diagram skill for
the exact styling and regeneration workflow.

After the diagram, add a short architecture delta list:

```markdown
- New in this step: <components introduced now>
- Already available: <relevant components from earlier steps>
- Value of the integration: <why the combined architecture matters>
```

Once the active generator exists, change `scripts/generate-readme-visuals.py`
and regenerate SVGs instead of hand-editing generated diagrams.

## References

References should be short and source-focused:

- one or more Red Hat narrative sources from `rh-brain` for concept/value
- Red Hat-linked GitHub reference implementations when they informed the demo
  shape or code
- active-baseline official Red Hat docs for product configuration
- links to `docs/BACKLOG.md` only for actionable deferred capabilities
- links to `docs/OPERATIONS.md` or `docs/TROUBLESHOOTING.md` only when the
  reader needs the operational path or recovery procedure

## Presentation Extraction Contract

Write READMEs so a future deck-generation skill can create three slides per
step without guessing:

| Slide | README source | Purpose |
|-------|---------------|---------|
| 1 | `## Why This Matters` | Define the concept and explain why the audience should care |
| 2 | `## What Enables It` | Explain the RHOAI and Red Hat technologies used |
| 3 | `## Architecture` | Show new components in context with previous steps |

Keep each section concise enough that the deck generator can lift the main
message directly instead of summarizing long runbook content.

## Content Boundaries

- Step READMEs should not be deployment runbooks.
- Do not include scripted walkthroughs, long command blocks, or repeated
  validation output.
- Put deployment order, environment preparation, shutdown/recovery, and day-2
  operations in `docs/OPERATIONS.md`.
- Put repeated symptoms, root causes, and repair procedures in
  `docs/TROUBLESHOOTING.md`.
- Put active product targets, documentation category index, version-match rule,
  and source hierarchy in `docs/PLATFORM_BASELINE.md`.
- Put deferred capabilities, future enhancements, and prioritized product
  coverage gaps in `docs/BACKLOG.md`.

## Formatting

- Keep heading levels sequential.
- Use `-` for unordered lists.
- Add language identifiers to fenced code blocks.
- Use backticks for filenames, commands, config keys, and resource names.
- Use relative links within the repository.
- Use descriptive link text.
- Prefer short paragraphs and compact tables.

## Review Checklist

After editing a README:

- The README follows the Why/What/Architecture/References shape.
- `## Why This Matters` defines the concept and states enterprise value.
- Concept framing cites Red Hat narrative material from `rh-brain`.
- When available, selected `rh-brain` sources are preferred because they link
  to concrete GitHub projects or code examples relevant to the step.
- `## What Enables It` maps each RHOAI technical component to an official Red
  Hat documentation link for the active baseline.
- Product capability, custom demo glue, preview posture, and deferred work are
  clearly separated.
- `## Architecture` points to the correct SVG and distinguishes current-step
  components from previously introduced components.
- Long runbook, demo-scene, validation, and recovery content has been routed to
  `docs/OPERATIONS.md` or `docs/TROUBLESHOOTING.md`.
- Deferred work links to `docs/BACKLOG.md` when it is actionable project work.
