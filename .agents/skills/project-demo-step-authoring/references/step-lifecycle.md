# Demo Step Lifecycle

Use this lifecycle for every new rhoai3-demo step. The goal is methodical
product-demo delivery: each step introduces a clear Red Hat-aligned concept,
implements it with GitOps, and proves it with validation.

## Phase 0: Intake

Define the step before creating files:

- step number and slug: `step-XX-slug`
- working title and one-line tagline
- concept introduced by the step
- target audience: architect, platform engineer, data scientist, risk owner,
  or business stakeholder
- enterprise value: control, governance, compliance, cost, scale, safety,
  portability, productivity, traceability, or resilience
- dependency on previous steps
- new components introduced now
- reused components from earlier steps
- explicit non-goals
- acceptance criteria

If scope does not fit in one concise README and one deployable GitOps slice,
split the step or move future work to `docs/BACKLOG.md`.

## Phase 1: Source Capture

Before writing implementation:

- confirm active product versions in `docs/PLATFORM_BASELINE.md`
- capture at least one Red Hat narrative source from
  `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` for concept/value framing
- capture active-baseline official Red Hat docs for every product component
  introduced by the step
- use `.agents/references/red-hat-doc-map.yaml` to find matching skills
- search for reference implementations in GitHub repositories published by or
  used by Red Hat product, field, solution, demo, or community-of-practice
  teams
- identify Red Hat articles or blogs that provide implementation examples,
  but keep official docs as product authority
- when multiple `rh-brain` articles cover the same concept, prefer articles
  that link to concrete GitHub repositories, manifests, notebooks, pipelines,
  or application code that can inform the implementation
- record unsupported, technology-preview, community, or demo-only exceptions

Do not create manifests from memory. If the required product skill is missing,
create or update that skill before authoring GitOps.

Use this implementation-source preference order:

1. official Red Hat docs examples for the active baseline
2. GitHub repositories linked from official Red Hat docs
3. GitHub repositories linked from Red Hat articles in `rh-brain`
4. Red Hat CoP or Red Hat team repositories with active, relevant examples
5. upstream or third-party examples only as explicitly labeled demo exceptions

Reference implementations can inform layout, scripts, example manifests, and
validation ideas. They do not override official docs for CR fields, support
posture, operator channels, image provenance, or API tier.

## Phase 2: Skill Routing

List the skills that will govern the step:

- one coordinator skill: `project-demo-step-authoring`
- product skills: `rhoai-*`, `ocp-*`, `odf-*`, or approved repo extension
- GitOps skills: `project-gitops-authoring` and possibly
  `project-red-hat-operator-gitops`
- documentation skill: `project-documentation-authoring`
- review skills: `project-manifest-review`,
  `project-red-hat-doc-alignment-review`, and `rhoai-api-tiers` when RHOAI API
  support posture matters
- environment skills for live deployment and validation

The step `PLAN.md` must name the active skills so future agents know which
rules apply.

## Phase 3: Plan

Create `steps/step-XX-slug/PLAN.md` before implementation. The plan must cover:

- scope and non-goals
- source list
- selected skills
- GitOps ownership decision
- manifest inventory
- deploy script behavior
- validation script behavior
- required live-cluster checks
- expected user-visible outcome
- rollback or cleanup notes
- risks and deferred items

Use `examples/step-plan-template.md` as the starting point.

## Phase 4: README

Write `steps/step-XX-slug/README.md` using
`project-documentation-authoring/references/readme-standard.md`.

The README should answer Why and What:

- `## Why This Matters`: define the concept and explain enterprise value
- `## What Enables It`: map technology to official Red Hat docs
- `## Architecture`: show the architecture delta and new components
- `## References`: keep source links short and relevant

Do not put runbooks, long command walkthroughs, or validation transcripts in
the README.

## Phase 5: GitOps Ownership

Decide where resources live before creating manifests.

Use a step-owned GitOps path when the step owns independent resources:

```text
gitops/step-XX-slug/base/
gitops/step-XX-slug/overlays/<purpose>/
gitops/argocd/app-of-apps/step-XX-slug.yaml
```

Use a shared-owner path when the step changes global platform state:

```text
gitops/<shared-platform-owner>/instance/components/<feature>/
gitops/<shared-platform-owner>/instance/overlays/<profile>/
```

Shared-owner examples:

- RHOAI `DataScienceCluster` and `DSCInitialization`
- ODF storage foundation
- OpenShift GitOps bootstrap
- NFD, GPU Operator, Grafana, or platform observability layers

Never render competing full copies of a shared resource from multiple Argo CD
Applications.

## Phase 6: Manifest Authoring

Author manifests from verified sources:

- official Red Hat product docs
- active product skills
- locally reviewed GitHub reference implementations from Red Hat teams or
  Red Hat-linked articles
- Red Hat CoP catalog patterns only after local curation
- live schema verification with `oc explain` or CRD inspection when needed
- explicit demo exceptions documented in README or PLAN

Use Red Hat product images, Red Hat registry sources, Red Hat validated model
artifacts, or internally built demo images unless a demo exception is approved.

## Phase 7: Scripts

Each step normally has:

- `deploy.sh`: applies the Argo CD Application or shared owner Application
  first, then waits or reports status
- `validate.sh`: performs deterministic readiness, API, route, model, metric,
  or workflow checks for the step

Scripts that touch a live cluster must:

- load repo-local environment settings
- verify `RHOAI_EXPECTED_API_SERVER`
- respect `KUBECONFIG` from `.env`
- fail closed if the target cluster cannot be confirmed
- avoid direct `oc apply -k` against Argo CD-managed resources

## Phase 8: Validation

Run the narrowest useful checks before live deployment:

- `kustomize build` for GitOps paths
- YAML and manifest review checklists
- source-alignment review
- script syntax checks where available
- dry-run or `oc explain` only after the safety guard confirms the target
  cluster

Live validation should prove the user-visible step outcome, not just resource
existence.

## Phase 9: Operations And Troubleshooting

Update promoted docs only when the step creates reusable operational knowledge:

- `docs/OPERATIONS.md`: deployment order, day-2 operation, shutdown/recovery,
  credential setup, or environment-specific procedure
- `docs/TROUBLESHOOTING.md`: repeated symptoms, diagnostics, root causes, and
  recovery commands
- `docs/BACKLOG.md`: deferred capabilities or follow-up work
- `docs/PLATFORM_BASELINE.md`: product baseline changes only

Do not scatter runbook content across step READMEs.

## Phase 10: Acceptance

A step is ready only when:

- source capture is complete
- README, PLAN, GitOps, scripts, and validation agree
- manifests render
- product source alignment review passes or findings are resolved
- manifest review passes or findings are resolved
- live validation passes when a live environment is available
- deferred work is explicit and accepted
