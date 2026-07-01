# Demo Stage Definition Of Done

Use this checklist before declaring a stage ready.

## Scope

- Stage identifier, slug, title, concept, audience, dependencies, and non-goals are
  recorded in `PLAN.md`.
- The stage introduces one coherent capability or clearly bounded integration.
- Deferred work is listed in `PLAN.md` or `docs/BACKLOG.md` only after the user
  explicitly accepts the deferral.
- No component from an agreed stage scope, Red Hat reference pattern,
  source-derived acceptance criteria, or user requirement has been silently
  removed, downgraded, or moved to future work.

## Sources

- Active baseline versions are checked.
- Red Hat narrative source exists for the concept and enterprise value.
- Relevant Red Hat-linked GitHub reference implementations were searched,
  captured, and bounded as examples, or their absence is documented.
- Official Red Hat docs exist for every product component introduced.
- Required product skills are named and available.
- Unsupported, Technology Preview, Developer Preview, community, or demo-only
  posture is explicit.

## README

- README follows the Why/What/Architecture/References shape.
- Why/value section is concise and source-grounded.
- Technology mapping links to official product docs.
- Architecture section identifies new and existing components.
- README does not contain deployment runbooks or long command transcripts.

## GitOps

- GitOps ownership is explicit: stage-owned path or shared platform owner.
- No two Applications render competing full copies of the same shared resource.
- Argo CD Application uses project standards from `project-gitops-authoring`.
- Kustomize renders locally.
- Operator lifecycle state is represented in Git when Operators are involved.
- Secrets, generated tokens, kubeconfigs, API keys, and real credentials are
  not committed.

## Manifests

- API versions and fields are sourced from official docs or verified schema.
- GitHub reference implementations are locally curated and never used as
  product API or support authority.
- Images and model artifacts have documented provenance.
- Labels and annotations follow project standards.
- Cross-resource references resolve.
- Security-sensitive RBAC, SCC, Route, Gateway, and token choices are reviewed.

## Scripts

- `deploy.sh` applies the Argo CD Application or shared owner Application
  before waiting for resources.
- `validate.sh` proves the user-visible outcome.
- Live-cluster scripts use the OpenShift safety guard.
- Scripts are deterministic and safe to rerun.

## Reviews

- `project-manifest-review` has no unresolved blocking findings.
- `project-red-hat-doc-alignment-review` has no unresolved blocking findings.
- `rhoai-api-tiers` is used when RHOAI API support posture matters.
- Product skill gaps are resolved before implementation claims are accepted.

## Validation

- Local render and static checks pass.
- Live validation passes when a target environment is available.
- If live validation is unavailable, the missing validation is documented as a
  blocker or accepted deferred item.
- Operations and troubleshooting docs are updated when reusable knowledge was
  created.
- Any hard-won implementation lesson, source/schema discrepancy, product
  compatibility decision, or validated working configuration is captured in the
  relevant product or project skill before the stage is considered complete.

## Commit Boundary

Commit each completed stage as an atomic unit:

- stage README and PLAN
- GitOps manifests
- Argo CD Application or shared owner patch
- deploy and validation scripts
- operations, troubleshooting, or backlog updates
- skill/source updates needed by the stage
