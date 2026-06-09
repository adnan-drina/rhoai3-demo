# Documentation Alignment Checklist

Use this checklist to verify manifests and READMEs against official Red Hat
documentation for the active product baseline.

## General Checks

- Does `docs/PLATFORM_BASELINE.md` identify the active RHOAI and OCP versions?
- Does the README reference active-baseline documentation, not stale product
  versions?
- Are custom resource API versions documented for this baseline?
- Are top-level spec fields documented for this CR version?
- Are operator Subscription channels, names, and catalog sources documented or
  verified?
- Are container images from Red Hat registries or approved sources?
- Are image tags pinned where reproducibility matters?
- Are Dashboard annotations and template names valid for the installed platform?

## Resource-Specific Checks

| Resource | Primary docs area |
|----------|-------------------|
| DataScienceCluster | installing and configuring OpenShift AI |
| InferenceService | deploying models |
| ServingRuntime | deploying models |
| LlamaStackDistribution | working with LlamaStack |
| GuardrailsOrchestrator | AI safety with guardrails |
| ModelRegistry | model registry |
| DataSciencePipelinesApplication | AI pipelines |
| LMEvalJob | evaluating AI systems |
| TrustyAIService | evaluating AI systems |
| Notebook | data science IDEs and workbenches |

## Verification When Docs Are Ambiguous

If official docs do not establish a field or value, mark it as unresolved and
propose one of:

- `oc explain <kind>.<field>`
- `oc get crd <crd-name> -o yaml`
- checking platform templates in `redhat-ods-applications`

Do not infer fields from upstream projects or older product versions.

## Evidence Ledger

For touched GitOps-managed components, refresh or request refresh of
`docs/alignment-evidence-ledger.md`. If evidence cannot be refreshed, record the
reason as deferred.
