# Demo Step Definition Of Done

Use this checklist before declaring a step ready.

## Scope

- Step number, slug, title, concept, audience, dependencies, and non-goals are
  recorded in `PLAN.md`.
- The step introduces one coherent capability or clearly bounded integration.
- Deferred work is listed in `PLAN.md` or `docs/BACKLOG.md`.

## Sources

- Active baseline versions are checked.
- Red Hat narrative source exists for the concept and enterprise value.
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

- GitOps ownership is explicit: step-owned path or shared platform owner.
- No two Applications render competing full copies of the same shared resource.
- Argo CD Application uses project standards from `project-gitops-authoring`.
- Kustomize renders locally.
- Operator lifecycle state is represented in Git when Operators are involved.
- Secrets, generated tokens, kubeconfigs, API keys, and real credentials are
  not committed.

## Manifests

- API versions and fields are sourced from official docs or verified schema.
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

## Commit Boundary

Commit each completed step as an atomic unit:

- step README and PLAN
- GitOps manifests
- Argo CD Application or shared owner patch
- deploy and validation scripts
- operations, troubleshooting, or backlog updates
- skill/source updates needed by the step
