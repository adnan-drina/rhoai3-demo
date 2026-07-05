---
name: project-doc-alignment-audit
metadata:
  author: rhoai3-demo
  version: 1.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Comprehensive audit of project documentation alignment with actual
  implementation. Compares stage READMEs, RHOAI skills, and project docs
  against GitOps manifests, scripts, notebooks, and deployed behavior.
  Use when triggered by a Cursor Automation schedule, when the user asks
  to audit documentation freshness, when code changes have accumulated
  without README updates, or when skills need enrichment with
  implementation details. Produces a structured alignment report and
  either directly fixes documentation or proposes a PR with corrections.
  Do NOT use for authoring new documentation from scratch (use
  project-documentation-authoring) or for Red Hat source conformance
  checks (use project-red-hat-doc-alignment-review).
---

# Documentation Alignment Audit

Systematic analysis of implementation artifacts against documentation to ensure
READMEs describe what is actually deployed and skills contain exact
implementation details.

## When To Run

- **Scheduled:** daily via Cursor Automation (see `references/automation-setup.md`)
- **On demand:** when asked to audit docs, after large implementation changes,
  or before a release/demo
- **Incremental:** the `check-docs-consistency.sh` hook handles per-edit
  reminders; this skill handles the comprehensive sweep

## Audit Scope

### Source of Truth: Implementation Artifacts

| Artifact type | Location | What to extract |
|---------------|----------|-----------------|
| GitOps manifests | `gitops/stage-*/**/*.yaml` | Operators, channels, versions, namespaces, CR specs, kustomize overlays |
| Stage scripts | `stage-*/deploy.sh`, `stage-*/validate.sh`, `stage-*/*.sh` | Imperative steps, prerequisites, ordering, environment variables |
| ArgoCD Applications | `gitops/argocd/**/*.yaml` | App names, source paths, sync policies, hook jobs |
| Notebooks | `stage-*/notebooks/*.ipynb` | Pipeline logic, model names, endpoints, data flows |
| KFP pipelines | `stage-*/kfp/**/*.py` | Pipeline steps, parameters, dependencies |
| Chatbot/app code | `stage-*/chatbot/**/*` | Endpoints, models used, RAG configuration |
| Platform baseline | `docs/PLATFORM_BASELINE.md` | Pinned product versions, channels |

### Documentation To Validate

| Document | Expected content |
|----------|-----------------|
| `stage-*/README.md` | Accurate Why + What for each component deployed by the stage |
| `.agents/skills/rhoai-*/SKILL.md` | Exact implementation details matching what this repo deploys |
| `.agents/skills/ocp-*/SKILL.md` | OCP component details matching deployed configuration |
| `.agents/skills/odf-*/SKILL.md` | ODF component details matching deployed configuration |
| `docs/OPERATIONS.md` | Operational procedures matching current scripts |
| `docs/TROUBLESHOOTING.md` | Recovery procedures matching current failure modes |
| `gitops/README.md` | GitOps tree structure matching actual directory layout |

## Execution Workflow

### Phase 1: Inventory

1. List all `gitops/stage-*` directories and their manifest trees
2. List all `stage-*/` directories and their scripts/notebooks
3. List all ArgoCD Application manifests
4. Record the current `docs/PLATFORM_BASELINE.md` version targets

### Phase 2: Extract Implementation Facts

For each stage, extract concrete facts from the implementation:

**From GitOps manifests:**
- Operator names, namespaces, channels, startingCSV values
- Custom Resource kinds, apiVersions, and key spec fields
- Kustomize overlay structure and patch semantics
- Namespace creation and RBAC bindings
- ConfigMaps, Secrets structure (not values), Services, Routes

**From scripts:**
- Prerequisites and ordering requirements
- Environment variables consumed
- Imperative resources created (not managed by ArgoCD)
- Validation checks performed

**From notebooks/pipelines:**
- Model identifiers and endpoints used
- Data sources and sinks
- Pipeline step names and parameters
- Dependencies (pip packages, container images)

**From ArgoCD Applications:**
- Application names and project assignment
- Source repo, path, targetRevision
- Sync policy (automated vs manual, prune, selfHeal)
- Hook jobs and their purpose

### Phase 3: Compare Against Documentation

For each extracted fact, verify it appears accurately in the relevant README
and/or skill:

**README alignment checks:**
- Every operator listed in README matches a Subscription manifest (name, channel, namespace)
- Every CR mentioned in README matches the actual CR spec (apiVersion, kind, key fields)
- Architecture diagrams reflect the actual component relationships
- "What Enables It" sections list all and only the components the stage deploys
- No claims about capabilities that are not implemented
- No stale references to removed or renamed components

**Skill alignment checks:**
- `rhoai-*` skills that reference stage implementations contain exact versions,
  channels, and CR fields matching the active gitops manifests
- Skills reference the correct ArgoCD Application names
- Skills contain correct namespace names
- Skills reference accurate API versions

**Cross-reference checks:**
- `docs/PLATFORM_BASELINE.md` versions match Subscription channels/startingCSV
- `docs/OPERATIONS.md` procedures match current script implementations
- ArgoCD Application sources match actual gitops directory paths

### Phase 4: Report and Fix

Produce a structured report:

```markdown
## Documentation Alignment Report — <date>

### Summary
- Stages audited: N
- Findings: N critical, N minor, N info
- Auto-fixable: N

### Critical Findings (documentation claims something not implemented)
1. [stage/file] Finding description
   - **Expected** (from code): ...
   - **Documented** (in README/skill): ...
   - **Fix**: ...

### Minor Findings (documentation omits implemented detail)
1. [stage/file] Finding description
   - **Missing from**: ...
   - **Available in**: ...
   - **Suggested addition**: ...

### Info (style, freshness, enrichment opportunities)
1. [stage/file] Description
```

**Fix strategy:**
- **Critical findings** (doc claims something wrong): fix immediately
- **Minor findings** (doc missing implementation detail): fix immediately
- **Info findings** (style or enrichment): fix if the change is small and clear

When running as a Cursor Automation, create a branch
`docs/alignment-audit-<date>` and commit all fixes. When running on-demand in
an agent session, apply fixes directly to the working tree.

## Stage-Specific Audit Checklists

### Stage 110 — RHOAI Base Platform

- [ ] README lists: OpenShift GitOps, ODF MCG, Observability stack (COO, OpenTelemetry, Tempo), RHOAI operator, platform access
- [ ] Each operator: correct channel, namespace, Subscription name matches manifest
- [ ] DSC/DSCI: correct apiVersion (v2), enabled components match manifest
- [ ] COO lifecycle policy: startingCSV and approval strategy match overlay
- [ ] Access: htpasswd IdP, ai-admin/ai-developer roles, demo-sandbox project
- [ ] Architecture diagram: reflects all deployed namespaces and relationships
- [ ] Demo evidence: screenshots exist for login/IdP, RHOAI dashboard, demo-sandbox project, S3 connection, Model Registry, Argo CD; customer-facing result screenshot present

### Stage 120 — GPU as a Service

- [ ] README lists: NFD operator, NVIDIA GPU Operator, Kueue, hardware profiles
- [ ] GPU MachineSet: instance type, autoscaling config documented
- [ ] Kueue: ClusterQueue, ResourceFlavor, LocalQueue configuration
- [ ] Hardware profiles: names, resource limits, tolerations match manifests
- [ ] Demo evidence: screenshots exist for GPU node/NVIDIA operator status, Kueue queues, hardware profiles dropdown; customer-facing result (GPU profile selection in workbench spawner) present

### Stage 210 — Model Serving Foundation

- [ ] README lists: KServe (via DSC), ServingRuntime (vLLM), InferenceService, model storage
- [ ] DSC component delta: which components are enabled by this stage's hook job
- [ ] ServingRuntime: correct container image, model format support
- [ ] Benchmark tooling: GuideLLM configuration, prompts data
- [ ] Demo evidence: screenshots exist for model serving endpoint, inference result, Grafana dashboard, Model Registry entry; customer-facing result (working inference response) present

### Stage 220 — Models as a Service

- [ ] README lists: MaaS governance (Authorino), local model (Nemotron), external model (GPT), GenAI Playground
- [ ] Authorino: correct deployment mode, auth policies
- [ ] Model configurations: names, endpoints, serving runtime assignments
- [ ] MCP server: configuration and deployment details
- [ ] Gateway/Route configuration for model endpoints
- [ ] Demo evidence: screenshots exist for GenAI Playground, MaaS administration, MCP tool use, subscription/API key management; customer-facing result (governed model chat or MCP tool response) present

### Stage 230 — Private Data RAG

- [ ] README lists: Llama Stack, Milvus, ingestion pipeline, retrieval pipeline, chatbot
- [ ] Llama Stack: deployment configuration, OGX provider setup
- [ ] Milvus: deployment topology, storage configuration
- [ ] Pipelines: KFP pipeline structure, data flow
- [ ] Notebooks: purpose, data sources, model endpoints used
- [ ] AutoRAG: pipeline configuration and evaluation approach
- [ ] Demo evidence: screenshots exist for RAG chatbot, AI Pipelines/Docling run graph, AutoRAG leaderboard, Enterprise RAG Workbench, Llama Stack providers; customer-facing result (grounded RAG answer with sources) present

## Skill Enrichment Guidelines

When updating skills with implementation details, follow these principles:

1. **Exact over approximate:** use the actual channel name (`stable-3.4`), not
   "the stable channel"
2. **Reference the manifest path:** cite `gitops/stage-110/rhoai/operator/base/subscription.yaml`
   so future agents can verify
3. **Include the CR shape:** when a skill discusses a Custom Resource, include
   the key spec fields as they appear in the repo
4. **Note deviations from defaults:** if the implementation differs from the
   product documentation default, explain why
5. **Link to the README section:** skills should cross-reference the stage
   README that provides the business context

## Integration With Other Skills

| Skill | Relationship |
|-------|-------------|
| `project-documentation-authoring` | Called when documentation needs rewriting beyond simple corrections |
| `project-red-hat-doc-alignment-review` | Called when a finding involves product documentation conformance |
| `project-gitops-authoring` | Referenced when understanding manifest structure |
| `project-manifest-review` | Called when manifest accuracy needs deeper validation |
| `env-validate-demo-flow` | Provides runtime validation evidence to confirm documentation claims |
