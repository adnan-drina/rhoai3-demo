# Stage PLAN.md Template

Use this as the starting shape for `stage-YXX-slug/PLAN.md`.

```markdown
# Stage YXX: <Title> Plan

## Intent

- Stage identifier: `YXX`
- Stage family: `1xx AI Platform Foundation | 2xx Production GenAI & Private Data | 3xx Agentic AI & Enterprise Integration | 4xx AI Operations, Evaluation & MLOps | 5xx Edge & Applied AI`
- Stage slug: `stage-YXX-slug`
- Concept introduced:
- Target audience:
- Enterprise value:
- Depends on:
- New components:
- Existing components reused:
- Non-goals:

## Acceptance Criteria

- [ ] README explains Why and What without runbook detail.
- [ ] Why and business value are grounded in at least one Red Hat narrative source from `rh-brain/`.
- [ ] What and related product components are grounded in active-baseline official Red Hat docs.
- [ ] Relevant Red Hat-linked GitHub reference implementations were searched and captured, or absence is documented.
- [ ] Official Red Hat docs are captured for every product component.
- [ ] Design decisions and applied configuration choices reference the sources used.
- [ ] GitOps ownership model is explicit.
- [ ] Manifests render and configuration is cross-checked against official sources or verified schema.
- [ ] Deploy script applies the Argo CD Application or shared owner first and handles sensitive data through documented non-committed paths.
- [ ] Validate script proves the user-visible outcome.
- [ ] Manifest and Red Hat source-alignment reviews pass.

## Source Capture

| Purpose | Source | Skill | Notes |
|---------|--------|-------|-------|
| Concept/value | <rh-brain or Red Hat narrative source> | project-documentation-authoring | <why it matters> |
| Product config | <official docs URL> | <rhoai/ocp/odf skill> | <fields/examples used> |
| Pattern | <CoP/blog/legacy reference> | <skill> | <curation boundary> |
| Reference implementation | <GitHub repo/path/ref> | <skill> | <Red Hat linkage and reuse boundary> |

### `rh-brain` Article Selection

- Candidate articles reviewed:
- Selected article:
- Reason selected:
- Links to GitHub/code examples: yes | no
- Linked implementation source:

## Skill Routing

- Coordinator: `project-demo-stage-authoring`
- Documentation:
- GitOps:
- Product skills:
- Review skills:
- Environment skills:

## GitOps Ownership

- Ownership model: stage-owned | shared-owner
- Owning Application:
- Source path:
- Shared resources touched:
- Argo CD sync or ordering requirements:
- Secret and credential handling:

## Manifest Inventory

| File | Kind | Source authority | Validation |
|------|------|------------------|------------|
| `gitops/...` | <kind> | <docs/skill/schema> | <check> |

## Script Plan

### `deploy.sh`

- Guard behavior:
- First action:
- Wait/report behavior:

### `validate.sh`

- Readiness checks:
- Functional checks:
- Expected success output:

## Operations And Troubleshooting

- `docs/OPERATIONS.md` update needed: yes | no
- `docs/TROUBLESHOOTING.md` update needed: yes | no
- `docs/BACKLOG.md` update needed: yes | no

## Risks And Deferred Work

| Item | Type | Resolution |
|------|------|------------|
| <risk/deferred item> | risk | <mitigation> |

## Review Log

- Manifest review:
- Red Hat source-alignment review:
- Live validation:

## Retrospective And Skill Updates

- Validated working configuration captured:
- Product docs versus installed schema discrepancies:
- Compatibility or operator lifecycle decisions:
- Generated resources observed but not GitOps-owned:
- Issues that took longest and earliest future detection gate:
- Skills updated:
```
