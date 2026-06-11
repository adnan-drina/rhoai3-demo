# Stage 110: RHOAI Base Platform — Plan

## Intent

- Stage identifier: `110`
- Stage family: `1xx AI Platform Foundation`
- Stage slug: `stage-110-rhoai-base-platform`
- Concept introduced: End-to-end AI platform foundation — GitOps reconciliation, S3-compatible object storage (ODF MCG), and the RHOAI Operator with a minimal `DataScienceCluster` (Dashboard + Workbenches). All subsequent demo stages build on top of this base.
- Target audience: Platform engineer, solution architect
- Enterprise value: Control, governance, portability, compliance, cost (on-premises object storage replaces cloud dependency)
- Depends on: None (first stage)
- New components: OpenShift GitOps, ODF MCG, RHOAI Operator, DSCInitialization, DataScienceCluster
- Existing components reused: Underlying OCP 4.20 cluster on AWS
- Non-goals:
  - GPU/accelerator setup (deferred to a future `stage-130-gpu-accelerator-foundation`)
  - Full ODF StorageCluster/Ceph block and file storage
  - RHOAI model serving, Kueue, Ray, model registry, pipelines, TrustyAI (all deferred)
  - Identity provider integration (deferred)

**Scope note:** The stage taxonomy lists stages 110–140 as separate foundation slices. This stage deliberately compresses that range into a single deployable unit following the Red Hat AI Accelerator reference pattern. The rationale: a standalone GitOps bootstrap with no AI platform has no demo value. The minimum demonstrable foundation is GitOps + object storage + RHOAI base. Stages 120+ in the taxonomy are superseded by this stage's implementation scope.

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
| Enterprise AI value / hybrid cloud | [From inference to agents: Scaling AI in the enterprise with Red Hat AI 3.4](https://www.redhat.com/en/blog/inference-agentic-ai-scaling-enterprise-foundation-red-hat-ai-34) | `project-documentation-authoring` | Metal-to-agent platform, consistent across environments |
| Infrastructure foundation narrative | [Our journey to AI-centricity, Part 1](https://www.redhat.com/en/blog/our-journey-ai-centricity-part-1-building-stable-foundation) | `project-documentation-authoring` | Standardise first, then AI — Red Hat's own experience |
| Open source vs proprietary model flexibility | [The state of open source AI models in 2025](https://developers.redhat.com/articles/2026/01/07/state-open-source-ai-models-2025) | `project-documentation-authoring` | Regulated sectors, sovereignty, vLLM, open model ecosystem |
| ODF MCG for AI developers | [ODF for developers and data scientists](https://developers.redhat.com/articles/2024/07/31/red-hat-openshift-data-foundation-developers-and-data-scientists) | `odf-multicloud-gateway` | MCG standalone, OBC workflow, S3 endpoint discovery |
| RHOAI install | [RHOAI 3.4 install guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed/installing-and-deploying-openshift-ai_install) | `rhoai-self-managed-installation` | Namespace, OperatorGroup, Subscription, DSCI, DSC |
| RHOAI DSCI/DSC config | [Managing RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai) | `rhoai-dsci-dsc-configuration` | Component managementState, predefined namespaces |
| ODF MCG standalone | [ODF 4.20 on AWS](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.20/html-single/deploying_openshift_data_foundation_using_amazon_web_services/index) | `odf-storagecluster`, `odf-multicloud-gateway` | MCG deployment type, StorageSystem CR |
| OCP GitOps | [OCP 4.20 GitOps](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/gitops/index) | `ocp-gitops-operator` | Operator channel, ArgoCD instance, resource tracking |
| GitOps manifests pattern | [github.com/redhat-ai-services/ai-accelerator](https://github.com/redhat-ai-services/ai-accelerator) | `project-red-hat-operator-gitops` | CoP operator/instance/aggregate Kustomize layout, DSC base |

### `rh-brain` Article Selection

- Candidate articles reviewed: "From inference to agents" (2026-04-30), "Our journey to AI-centricity Part 1" (2026-03-20), "The state of open source AI models in 2025" (2026-01-07), "ODF for developers" (2024-07-31), "From lab to ledger: Scaling enterprise AI at Red Hat Summit 2026" (2026-04-20)
- Selected for Why section: "From inference to agents" (enterprise platform value), "Our journey to AI-centricity Part 1" (infrastructure-first narrative), "The state of open source AI models in 2025" (open vs proprietary)
- Reasons selected: "From inference to agents" provides the most comprehensive and recent Red Hat AI 3.4 enterprise value framing; "AI-centricity Part 1" provides the concrete infrastructure-first lesson from Red Hat's own experience; "Open source AI models" directly addresses the proprietary vs open model question with regulated-sector examples
- Links to GitHub/code examples: "Open source AI models" links to vLLM, Ollama, RamaLama GitHub repos; "ODF for developers" includes concrete YAML examples
- Linked implementation source: https://github.com/vllm-project/vllm (vLLM), https://github.com/containers/ramalama (RamaLama)

## Skill Routing

- Coordinator: `project-demo-stage-authoring`
- Documentation: `project-documentation-authoring`
- GitOps: `project-gitops-authoring`, `project-red-hat-operator-gitops`
- Product skills: `rhoai-self-managed-installation`, `rhoai-dsci-dsc-configuration`, `rhoai-update-channels`, `odf-storagecluster`, `odf-multicloud-gateway`, `ocp-gitops-operator`
- Review skills: `project-manifest-review`, `project-red-hat-doc-alignment-review`, `rhoai-api-tiers`
- Environment skills: `env-deploy-and-evaluate`, `env-troubleshoot`

## GitOps Ownership

- Ownership model: stage-owned (bootstrap is imperative; ODF + RHOAI resources are ArgoCD-managed after bootstrap)
- Owning Application: `stage-110-rhoai-base-platform` in `openshift-gitops` namespace
- Source path: `gitops/stage-110-rhoai-base-platform`
- Shared resources touched: `DataScienceCluster` (owned here; later stages patch it), ODF `StorageSystem` (owned here)
- Argo CD sync or ordering requirements:
  - GitOps operator is bootstrapped imperatively before ArgoCD exists
  - ODF operator must be `Succeeded` before the MCG StorageSystem is applied (handled by `SkipDryRunOnMissingResource=true` + retry)
  - RHOAI operator must be `Succeeded` before DSCI/DSC are applied (same mechanism)
  - `argocd.argoproj.io/sync-wave` annotations manage within-Application ordering
- Secret and credential handling: No credentials committed. NooBaa admin credentials and OBC-generated secrets are runtime-only.

## Manifest Inventory

| File | Kind | Source authority | Validation |
|------|------|------------------|------------|
| `gitops/bootstrap/base/subscription.yaml` | Subscription (openshift-gitops-operator, placeholder channel) | OCP 4.20 GitOps docs | `oc get csv -n openshift-operators` |
| `gitops/bootstrap/overlays/operator/patch-channel.yaml` | Subscription channel patch (`gitops-1.20`) | OCP 4.20 GitOps docs (verified live) | `oc get subscription openshift-gitops-operator -n openshift-operators -o jsonpath='{.spec.channel}'` |
| `gitops/bootstrap/overlays/demo/argocd-instance.yaml` | ArgoCD (annotation resource tracking) | ai-accelerator instance/base pattern | `oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.spec.resourceTrackingMethod}'` |
| `gitops/bootstrap/overlays/demo/argocd-project.yaml` | AppProject | ArgoCD docs | `oc get appproject rhoai-demo -n openshift-gitops` |
| `gitops/stage-110-rhoai-base-platform/odf/operator/base/namespace.yaml` | Namespace | ODF 4.20 AWS guide | `oc get ns openshift-storage` |
| `gitops/stage-110-rhoai-base-platform/odf/operator/base/operator-group.yaml` | OperatorGroup | ODF 4.20 install | `oc get operatorgroup -n openshift-storage` |
| `gitops/stage-110-rhoai-base-platform/odf/operator/base/subscription.yaml` | Subscription (odf-operator, `stable-4.20`) | ODF 4.20 AWS guide (verified live) | `oc get csv -n openshift-storage` |
| `gitops/stage-110-rhoai-base-platform/odf/instance/base/storage-system.yaml` | StorageSystem (MCG-only) | ODF 4.20 AWS guide (MCG standalone section) | `oc get noobaa -n openshift-storage` |
| `gitops/stage-110-rhoai-base-platform/odf/instance/base/ocs-initialization.yaml` | OCSInitialization (enableCephTools:false) | colleague config (adapted) | `oc get ocsinitialization -n openshift-storage` |
| `gitops/stage-110-rhoai-base-platform/odf/instance/base/console-plugin-{rbac,script,job}.yaml` | SA/ClusterRole/CRB/ConfigMap/Job | colleague config (adapted) | `oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}'` |
| `gitops/stage-110-rhoai-base-platform/rhoai/operator/base/namespace.yaml` | Namespace | RHOAI 3.4 install guide | `oc get ns redhat-ods-operator` |
| `gitops/stage-110-rhoai-base-platform/rhoai/operator/base/operator-group.yaml` | OperatorGroup | RHOAI 3.4 install guide | `oc get operatorgroup -n redhat-ods-operator` |
| `gitops/stage-110-rhoai-base-platform/rhoai/operator/base/subscription.yaml` | Subscription (rhods-operator) | RHOAI 3.4 install guide | `oc get csv -n redhat-ods-operator` |
| `gitops/stage-110-rhoai-base-platform/rhoai/instance/base/dsc-init.yaml` | DSCInitialization | RHOAI 3.4 Managing RHOAI docs | `oc get dscinitialization default-dsci` |
| `gitops/stage-110-rhoai-base-platform/rhoai/instance/base/datasciencecluster.yaml` | DataScienceCluster (dashboard + workbenches + modelregistry Managed) | RHOAI 3.4 Managing RHOAI + Model registry docs | `oc get datasciencecluster default-dsc` |
| `gitops/argocd/app-of-apps/stage-110-rhoai-base-platform.yaml` | Application | project-gitops-authoring | `oc get application stage-110-rhoai-base-platform -n openshift-gitops` |

## Script Plan

### `deploy.sh`

- Guard behavior: reads `.env`, validates `RHOAI_EXPECTED_API_SERVER` against current cluster API server URL; exits if mismatch
- First action: `oc apply -k gitops/bootstrap/base` (installs OpenShift GitOps operator)
- Wait/report behavior:
  1. Wait for `openshift-gitops-operator` CSV to be `Succeeded`
  2. Wait for `openshift-gitops` ArgoCD instance to become Available
  3. `oc apply -k gitops/bootstrap/overlays/demo` (resource tracking patch + AppProject)
  4. Apply the stage-110 Application to ArgoCD
  5. Report ArgoCD Application sync URL to console

### `validate.sh`

- Readiness checks:
  - `openshift-gitops-operator` CSV phase = `Succeeded`
  - ArgoCD instance `openshift-gitops` Available
  - `odf-operator` CSV phase = `Succeeded`
  - `rhods-operator` CSV phase = `Succeeded`
  - `noobaa` phase = `Ready` in `openshift-storage`
  - `dscinitialization` phase = `Ready`
  - `datasciencecluster` phase = `Ready`
  - RHOAI Dashboard route responds HTTP 200
- Functional checks:
  - ArgoCD Application `stage-110-rhoai-base-platform` Synced + Healthy
- Expected success output: all checks print `✓` and exit 0

## Operations And Troubleshooting

- `docs/OPERATIONS.md` update needed: yes — bootstrap sequence, day-2 ArgoCD access, ODF MCG S3 endpoint discovery
- `docs/TROUBLESHOOTING.md` update needed: yes — common bootstrap failures, RHOAI operator stuck, NooBaa not Ready
- `docs/BACKLOG.md` update needed: yes — deferred GPU stage, GitOps channel verification, identity provider

## Risks And Deferred Work

| Item | Type | Resolution |
|------|------|------------|
| OpenShift GitOps channel for OCP 4.20 | resolved | Verified live on cluster-klvxt (OCP 4.20.24): pinned to `gitops-1.20`; operator v1.20.4 installed |
| ODF StorageSystem MCG-only CR fields | risk | Verify with `oc explain storagesystem.odf.openshift.io` once the ODF CRD installs during sync |
| GPU accelerator foundation | deferred | Future stage `stage-130-gpu-accelerator-foundation` (NFD + GPU Operator + AWS GPU MachineSet) |
| Identity provider / access groups | deferred | Future stage in 1xx family |
| RHOAI component enablement (kserve, kueue, ray, etc.) | deferred | Each component added by its dedicated 2xx/4xx stage via DSC patch |
| ODF full StorageCluster | deferred | Added only if a future stage needs block/file storage |

## Review Log

- Manifest review: pending
- Red Hat source-alignment review: pending
- Live deploy: bootstrap succeeded on cluster-klvxt (OCP 4.20.24) 2026-06-11; ArgoCD Application created, ODF + RHOAI syncing
- Live validation: in progress (run `validate.sh` after sync completes)
