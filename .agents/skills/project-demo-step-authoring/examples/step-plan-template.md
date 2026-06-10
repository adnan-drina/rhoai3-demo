# Step PLAN.md Template

Use this as the starting shape for `steps/step-XX-slug/PLAN.md`.

```markdown
# Step XX: <Title> Plan

## Intent

- Step slug: `step-XX-slug`
- Concept introduced:
- Target audience:
- Enterprise value:
- Depends on:
- New components:
- Existing components reused:
- Non-goals:

## Acceptance Criteria

- [ ] README explains Why and What without runbook detail.
- [ ] Official Red Hat docs are captured for every product component.
- [ ] GitOps ownership model is explicit.
- [ ] Manifests render.
- [ ] Deploy script applies Argo CD Application or shared owner first.
- [ ] Validate script proves the user-visible outcome.
- [ ] Manifest and Red Hat source-alignment reviews pass.

## Source Capture

| Purpose | Source | Skill | Notes |
|---------|--------|-------|-------|
| Concept/value | <rh-brain or Red Hat narrative source> | project-documentation-authoring | <why it matters> |
| Product config | <official docs URL> | <rhoai/ocp/odf skill> | <fields/examples used> |
| Pattern | <CoP/blog/legacy reference> | <skill> | <curation boundary> |

## Skill Routing

- Coordinator: `project-demo-step-authoring`
- Documentation:
- GitOps:
- Product skills:
- Review skills:
- Environment skills:

## GitOps Ownership

- Ownership model: step-owned | shared-owner
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
```
