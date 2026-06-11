# RHOAI Demo - Codex Instructions

Demo of building Private AI platform infrastructure for enterprise generative
and predictive AI use cases using the product baseline in
`docs/PLATFORM_BASELINE.md`.

The active implementation is being rewritten. Legacy implementation artifacts
are backed up under `backup/legacy-implementation-2026-06-09/` and must be
treated as reference material unless the user explicitly asks to restore or run
them.

## Documentation First

- Official Red Hat docs for the active `docs/PLATFORM_BASELINE.md` versions are
  the source of truth.
- Do not invent CR fields, API versions, annotations, or operator
  configurations.
- If unsure, propose a verification command (`oc explain`, `oc get crd`) or
  consult the official docs index in `docs/PLATFORM_BASELINE.md`.

## Active Implementation State

No active bootstrap, deploy, validate, or demo-flow commands exist yet.

Clean-slate implementation areas:

```text
gitops/      # New GitOps source tree; currently placeholder-only
scripts/     # New project automation; currently placeholder-only
stage-*/     # Future root-level demo stage folders: stage-YXX-slug/
docs/        # Active project docs and product baseline
.agents/     # Shared skills, rules, reference maps, and hooks
```

Legacy implementation areas are preserved under the backup root with their
original relative paths:

```text
backup/legacy-implementation-2026-06-09/gitops/
backup/legacy-implementation-2026-06-09/scripts/
backup/legacy-implementation-2026-06-09/steps/
```

Do not run backup scripts as active project commands.

## Future GitOps Constraints

When the new GitOps implementation is introduced:

- ArgoCD `resourceTrackingMethod` MUST be `annotation` (not `label`).
- All demo Applications should use `project: rhoai-demo` unless the
  reimplementation explicitly changes the project model.
- ArgoCD cluster-admin remains acceptable for this demo only when documented in
  `docs/OPERATIONS.md`.
- New deploy automation must apply ArgoCD Applications first and avoid direct
  `oc apply -k` against ArgoCD-managed resources.

## OpenShift Safety Guard

- Open this repository as its own Codex project; do not open
  `/Users/adrina/Sandbox` as the active project for live cluster work.
- Before running live `oc`/`kubectl` commands, verify the target cluster against
  the repo-local environment guard.
- Set `RHOAI_EXPECTED_API_SERVER` in the local `.env` to a unique target
  API-server substring before deploy, validate, bootstrap, or
  resource-management scripts run.
- If using a project-local kubeconfig, set `KUBECONFIG` in `.env` to an
  absolute path under `tmp/`; never commit kubeconfig files.
- Do not bypass the guard with `RHOAI_ALLOW_UNGUARDED_CLUSTER=true` unless the
  user explicitly confirms the current cluster and the command is low risk.
- Do not read credentials from another project by default. Use
  `RHOAI_OPENAI_ENV_FILE` only when cross-project credential reuse is
  intentional and approved.
- New scripts that touch a live cluster must include the guard behavior before
  they are considered active.

## Code And Docs Must Be Aligned

During reimplementation, every new capability should be introduced as an atomic
stage: documentation, GitOps artifacts, scripts, and validation.

Stage READMEs should provide the Why and What for a technical audience:
concept value, RHOAI technology mapping, and architecture delta. GitOps and
live demos show the How. Put operational details in `docs/OPERATIONS.md` and
failure recovery in `docs/TROUBLESHOOTING.md`.

Do not claim capabilities that are not implemented. Future or deferred
capabilities must be clearly labeled.

## Self-Signed Certs

Use `--insecure-skip-tls-verify=true` (oc) and `-k` (curl) freely. Do not
implement production PKI for this demo.

## Branching And Commits

GitHub Flow + Trunk-Based Development. `main` is the stable trunk for released
demo content. During active refactoring, ArgoCD Applications may temporarily
pin to the active refactoring branch; update the Application `targetRevision`
back to the intended release ref when stabilizing.

Commit format: `type(scope): description` - types: feat, fix, docs, refactor,
chore, ci. Scope: stage identifier or slug for stage-specific changes,
component name for cross-cutting changes.

## Detailed Rules

For project structure, GitOps authoring, documentation, manifest review, Red
Hat source alignment, and shared agent guidance, read `.agents/rules/project.md`.

For live demo environment deployment, validation, troubleshooting, shutdown,
recovery, and redeploy, read `.agents/rules/env.md`.

For RHOAI platform component guidance, chatbot behavior, KFP, and evaluation,
read `.agents/rules/rhoai.md`.

For OpenShift Container Platform infrastructure, control plane, networking,
authentication, monitoring, GitOps, cluster, and storage integration guidance,
read `.agents/rules/ocp.md`.

For OpenShift Data Foundation storage, object storage, NooBaa, and ODF storage
classes, read `.agents/rules/odf.md`.

For visual assets, architecture diagrams, decks, and presentation outputs, read
`.agents/rules/assets.md`.

## Shared Skills

Canonical skills live in `.agents/skills/`, the Codex repo-skill discovery
path. Short tool-neutral rules live in `.agents/rules/`. Do not maintain
tool-specific skill discovery folders in this repo. Use the prefix plus
`metadata.skill-group` taxonomy for skill review:

| Group | Prefix | Skills | Purpose |
|-------|--------|--------|---------|
| Project Structure | `project-*` | `project-structure`, `project-agent-guidance`, `project-red-hat-doc-skill-authoring`, `project-rhoai-doc-chapter-skill-authoring`, `project-red-hat-operator-gitops`, `project-demo-stage-authoring`, `project-architecture-diagrams`, `project-gitops-authoring`, `project-documentation-authoring`, `project-manifest-review`, `project-red-hat-doc-alignment-review` | Repo layout, demo stage lifecycle, GitOps stage conventions, documentation structure, Red Hat narrative grounding, Red Hat docs-to-skill generation, Red Hat Operator GitOps deployment patterns, manifest review, Red Hat source alignment, and shared AI guidance |
| Demo Environment | `env-*` | `env-deploy-and-evaluate`, `env-troubleshoot`, `env-manage-resources`, `env-validate-demo-flow` | Live AWS/OpenShift demo deployment, validation, troubleshooting, shutdown, recovery, and redeploy. These skills are planning/reference aids until active scripts are recreated. |
| RHOAI Platform | `rhoai-*` | `rhoai-architecture-overview`, `rhoai-release-and-support-posture`, `rhoai-platform-planning`, `rhoai-api-tiers`, `rhoai-update-channels`, `rhoai-self-managed-installation`, `rhoai-dsci-dsc-configuration`, `rhoai-distributed-workloads`, `rhoai-kueue-workload-management`, `rhoai-distributed-workload-operations`, `rhoai-distributed-workload-workflows`, `rhoai-kubeflow-spark-operator`, `rhoai-nvidia-gpu-accelerators`, `rhoai-certificate-management`, `rhoai-observability`, `rhoai-logs-and-audit-records`, `rhoai-installation-troubleshooting`, `rhoai-uninstallation`, `rhoai-users-groups-access`, `rhoai-access-group-selection`, `rhoai-central-authentication-service`, `rhoai-dashboard-applications`, `rhoai-connected-applications`, `rhoai-dashboard-customization`, `rhoai-cluster-pvc-size`, `rhoai-storage-classes`, `rhoai-connection-types`, `rhoai-s3-object-storage-data`, `rhoai-project-workflows`, `rhoai-data-science-ide-workflows`, `rhoai-project-scoped-resources`, `rhoai-component-resource-customization`, `rhoai-telemetry-admin-settings`, `rhoai-feature-store`, `rhoai-automl`, `rhoai-basic-workbenches`, `rhoai-workbenches-custom-images`, `rhoai-workbench-image-import`, `rhoai-workbench-gateway-api-migration`, `rhoai-model-serving-platform`, `rhoai-model-deployment`, `rhoai-maas-governance`, `rhoai-distributed-inference-llmd`, `rhoai-model-management-monitoring`, `rhoai-monitoring-trustyai`, `rhoai-model-catalog-sources`, `rhoai-model-catalog-workflows`, `rhoai-gen-ai-playground`, `rhoai-autorag`, `rhoai-model-registry`, `rhoai-model-registry-workflows`, `rhoai-llama-stack`, `rhoai-ai-pipelines`, `rhoai-mlflow`, `rhoai-model-customization-training`, `rhoai-evaluation`, `rhoai-guardrails-safety`, `rhoai-chatbot-customization`, `rhoai-model-evaluation`, `rhoai-kfp-pipeline-authoring`; additional component skills planned | Official-doc-backed active-baseline RHOAI component installation, configuration, and usage |
| OpenShift Platform | `ocp-*` | `ocp-ai-workloads`, `ocp-authentication-identity-providers`, `ocp-cicd-builds`, `ocp-distributed-tracing`, `ocp-etcd`, `ocp-grafana-operator`, `ocp-gitops-operator`, `ocp-image-registry-and-mirroring`, `ocp-ingress-gateway-routes`, `ocp-machine-configuration`, `ocp-machine-management`, `ocp-node-feature-discovery`, `ocp-nodes`, `ocp-observability`, `ocp-opentelemetry`, `ocp-security-rbac-scc`, `ocp-storage`, `ocp-web-console`; additional component skills planned | Official-doc-backed OpenShift Container Platform guidance plus repo-approved OpenShift platform extensions for infrastructure, networking, auth, monitoring, GitOps, cluster, and storage integration |
| OpenShift Data Foundation | `odf-*` | `odf-storagecluster`, `odf-storage-classes`, `odf-object-bucket-claims`, `odf-multicloud-gateway` | Official-doc-backed OpenShift Data Foundation storage, object storage, Ceph, NooBaa, storage class, and data-service integration guidance |
| Assets & Miscellaneous | `assets-*` | `assets-red-hat-quick-deck` | Visual, deck, and presentation assets |

Use `.agents/skills/project-agent-guidance/SKILL.md` for the full governance
model.

## Subagents

No shared subagents are currently tracked. Add tool-specific subagents only for
genuinely tool-specific context isolation needs; shared workflows belong in
`.agents/skills/`.
