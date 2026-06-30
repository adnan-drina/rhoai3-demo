# Red Hat Source Alignment Checklist

Use this checklist to verify that stage READMEs and GitOps artifacts are
grounded in Red Hat source material for the active product baseline.

## Source Roles

| Source | Role |
|--------|------|
| `docs/PLATFORM_BASELINE.md` | Active product versions, version-match rule, RHOAI 3.4 documentation index, and source hierarchy |
| Official docs at `docs.redhat.com` | Source of truth for supported APIs, CR fields, operator installation, product configuration, and supported/preview status |
| `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` | Read-only Red Hat article/blog knowledge base for concept framing, customer value, code examples, and recommended implementation patterns |
| Red Hat-linked GitHub repositories | Reference implementations for concrete manifests, scripts, notebooks, pipelines, and validation ideas; never product API or support authority |
| Existing repo code and READMEs | Current implementation evidence; never product authority by itself |
| Live cluster schema (`oc explain`, CRDs) | Verification when docs are ambiguous; not a substitute for official docs |

Do not invent CR fields, API versions, operator settings, annotations, or
product support claims. If a source cannot be found, mark the item unresolved.

## Version-Match Checks

Use the official RHOAI documentation landing page recorded in
`docs/PLATFORM_BASELINE.md` as the product-doc entry point. For the current
baseline, RHOAI documentation links should use the 3.4 path:

```text
https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/
```

Flag a `[DOC-REF]` finding when:

- README text names one RHOAI version but links to another
- a RHOAI product-documentation link uses `/latest/` without an explicit reason
- a stage README cites older RHOAI documentation for a current-baseline
  configuration
- a skill or rule hard-codes a RHOAI version instead of pointing to
  `docs/PLATFORM_BASELINE.md`, unless that file is intentionally
  version-specific

## README Concept Checks

Each stage README should start by introducing the concept the stage adds to the
demo, such as Private AI, GPU-as-a-Service, Models-as-a-Service, model
registry, RAG, EvalHub, guardrails, MCP, MLOps, or edge AI.

Check that the concept introduction:

- defines the concept in Red Hat terminology
- explains why a European-regulated enterprise should care, from the viewpoint
  of at least one of: enterprise architect, platform engineer, data scientist,
  risk/compliance owner, or business owner
- states the value the concept brings to this demo
- cites at least one relevant Red Hat article, blog, guide, datasheet, or
  product page found through `rh-brain`
- prefers Red Hat narrative sources that link to concrete GitHub
  implementation examples when multiple sources are available
- does not rely on generic community claims when Red Hat messaging exists
- labels future, preview, or deferred capabilities clearly

Useful rh-brain search patterns:

```bash
rg -n "GPU-as-a-Service|Models-as-a-Service|Private AI|sovereign AI|RAG|EvalHub|guardrails|MCP|model registry|vLLM|llm-d|OpenShift AI" \
  "/Users/adrina/Sandbox/rh-brain/Red Hat Brain"
```

Treat rh-brain articles as narrative and example support. Do not treat them as
the final source for product API shape or support status.

## README Technical Component Checks

After the concept introduction, the README should explain which technologies
enable the concept in this project.

For every RHOAI, OCP, MicroShift, OpenShift Pipelines, Red Hat AI, or Red Hat
registry component introduced in the stage:

- include an active-baseline official Red Hat documentation link
- identify the product chapter or docs area used for configuration
- align preview, technology-preview, deprecated, or unsupported posture with
  the official docs
- link to rh-brain examples only as supporting implementation examples
- records any Red Hat-linked GitHub reference implementation that informed the
  stage design, or explicitly notes that no relevant implementation source was
  found
- avoid claiming product-native behavior for custom demo code unless the
  boundary is explicit
- ensure README claims match the GitOps manifests, deploy scripts, and
  validation scripts

## Resource-Specific Checks

| Resource or Component | Required source check |
|-----------------------|-----------------------|
| `DataScienceCluster`, `DSCInitialization` | RHOAI install/configuration docs, component management, observability, certificates |
| Operator `Subscription` and `OperatorGroup` | Active channel, package name, catalog source, install-plan posture from official docs or cluster operator catalog |
| NVIDIA GPU Operator, NFD, Driver Toolkit | OCP hardware accelerator docs and Red Hat/NVIDIA operator guidance |
| Red Hat build of Kueue | OCP AI workloads docs |
| RHCL/Kuadrant/MaaS dependencies | RHOAI MaaS docs and Red Hat-supported dependency posture |
| `InferenceService`, `ServingRuntime` | RHOAI model serving docs; KServe deployment mode and dashboard labels |
| vLLM and Red Hat AI Inference Server images | RHOAI/RHAI validated model and inference docs; prefer Red Hat registry images |
| ModelCar and validated model artifacts | Red Hat AI validated-model documentation or Red Hat registry source |
| `LlamaStackDistribution` | RHOAI Llama Stack docs and documented examples |
| `GuardrailsOrchestrator` and detectors | RHOAI AI safety and guardrails docs |
| Model Catalog and Model Registry | RHOAI catalog and registry docs |
| `DataSciencePipelinesApplication` and KFP components | RHOAI AI pipelines docs and supported KFP patterns |
| EvalHub, `LMEvalJob`, RAGAS, Garak | RHOAI evaluating AI systems docs |
| MLflow and `MLflowConfig` | RHOAI MLflow docs and technology-preview posture |
| `TrustyAIService` | RHOAI monitoring/evaluating AI systems docs |
| `Notebook`, workbench images, hardware profiles | RHOAI projects, workbenches, and accelerator docs |
| OpenShift Pipelines/Tekton | OpenShift Pipelines official docs |
| MicroShift edge AI | MicroShift AI models and RHEL edge/image-mode docs |

## GitOps Artifact Checks

For every touched manifest:

- Are custom resource API versions documented for this baseline?
- Are top-level spec fields documented for this CR version?
- Are operator Subscription channels, names, and catalog sources documented or
  verified?
- Are Dashboard annotations and template names valid for the installed
  platform?
- Are container images from Red Hat registries, Red Hat validated model
  sources, or internal build outputs?
- Are non-Red Hat images explicitly justified as demo-only or external
  dependencies in the README?
- Are explicit image tags or digests used only when Red Hat documentation,
  validated artifact guidance, or a documented non-operator demo-app exception
  requires them?
- Are operator-generated image fields, CSV `relatedImages`, copied CSVs, and
  operator-created Deployments left under operator ownership rather than
  patched as GitOps desired state?
- Are GitHub reference implementations locally curated instead of consumed as
  remote Kustomize bases or unreviewed scripts?
- Is each GitHub example linked to Red Hat docs, a Red Hat article, a Red Hat
  organization/team, or explicitly labeled as a demo exception?
- Are model artifacts from Red Hat validated sources, Model Registry, MinIO
  demo storage, or documented external providers?
- Are secrets, tokens, and kubeconfigs kept out of GitOps and documented as
  local/runtime prerequisites?
- Do the README, GitOps manifests, deploy script, and validation script agree?

## Verification When Docs Are Ambiguous

If official docs do not establish a field or value, mark it as unresolved and
propose one of:

- `oc explain <kind>.<field>`
- `oc get crd <crd-name> -o yaml`
- checking platform templates in `redhat-ods-applications`
- checking the installed operator package, CSV, or image stream
- checking Red Hat registry or validated-model documentation for image/artifact
  provenance

Do not infer fields from upstream projects or older product versions.

## Pre-Merge Audit

For touched GitOps-managed components, run or request
`./scripts/audit-doc-alignment.sh --base origin/main` once the active audit
script has been recreated. If the script or live evidence is unavailable,
record the reason as deferred in the review notes or PR description.

## Review Output

Report findings in these categories:

- `NARRATIVE`: README concept framing, European enterprise value, and rh-brain
  source grounding.
- `DOC-REF`: Official Red Hat documentation links, active baseline, preview or
  support status.
- `API`: API versions, CR fields, annotations, and operator configuration.
- `IMAGE`: Red Hat product images, validated model artifacts, and approved
  external dependencies.
- `CONSISTENCY`: README, GitOps manifests, scripts, and validation alignment.
