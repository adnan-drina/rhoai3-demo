---
name: project-structure
metadata:
  author: rhoai3-demo
  version: 1.2.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Project Structure"
description: >
  Evolve the rhoai3-demo repository structure, GitOps step layout, documentation
  standards, skill taxonomy, Red Hat narrative alignment, and official-doc
  evidence model. Use when the user asks to reorganize demo steps, create or
  refactor skills, update repository guidance, align READMEs with European
  enterprise messaging, add component documentation standards, or decide where
  project knowledge belongs. Do NOT use for live deployment, live cluster
  troubleshooting, or resource shutdown/recovery; use the Demo Environment
  skills for those. Do NOT use as the source of truth for specific RHOAI CR
  fields; use RHOAI Platform skills and official Red Hat docs.
---

# Project Structure

Use this skill to evolve the demo project itself: repository layout, GitOps
step conventions, documentation structure, shared skill groups, and
Red Hat-aligned narrative standards.

## Source Hierarchy

When changing project structure or documentation, use this evidence model:

1. Official Red Hat product docs for the active `docs/PLATFORM_BASELINE.md`
   versions are the source of truth for supported product configuration.
2. Red Hat articles, blogs, product pages, datasheets, and
   `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` ground README concept
   framing, European enterprise value, and example implementation patterns.
3. Existing repo implementation, scripts, and READMEs show current demo
   behavior but are not product authority.
4. Live cluster schema checks are verification only, using `oc explain` or
   `oc get crd`; never invent CR fields or API versions.

Official docs remain the source of truth for supported configuration. Treat
`rh-brain` as supporting evidence, not product authority. The active product
version target lives in `docs/PLATFORM_BASELINE.md`; skills should reference
that baseline instead of repeating exact versions in every frontmatter block.

## Skill Groups

Keep canonical skill folders flat under `.agents/skills/` for discovery, review,
and reuse. Do not maintain tool-specific skill copies; add a minimal bridge only
for a proven tool-only gap.

| Group | Prefix | Purpose | Current skills |
|-------|--------|---------|----------------|
| Project Structure | `project-*` | Repo architecture, GitOps step layout, docs, Red Hat narrative grounding, skill governance, Red Hat docs-to-skill generation, manifest review, Red Hat source alignment | `project-structure`, `project-agent-guidance`, `project-red-hat-doc-skill-authoring`, `project-rhoai-doc-chapter-skill-authoring`, `project-architecture-diagrams`, `project-gitops-authoring`, `project-documentation-authoring`, `project-manifest-review`, `project-red-hat-doc-alignment-review` |
| Demo Environment | `env-*` | Live AWS/OpenShift demo lifecycle: bootstrap, deploy, validate, troubleshoot, shutdown/recovery, redeploy | `env-deploy-and-evaluate`, `env-troubleshoot`, `env-manage-resources`, `env-validate-demo-flow` |
| RHOAI Platform | `rhoai-*` | Official-doc-backed component guidance for installing, configuring, and using active RHOAI baseline capabilities | `rhoai-architecture-overview`, `rhoai-release-and-support-posture`, `rhoai-platform-planning`, `rhoai-api-tiers`, `rhoai-update-channels`, `rhoai-self-managed-installation`, `rhoai-dsci-dsc-configuration`, `rhoai-distributed-workloads`, `rhoai-kueue-workload-management`, `rhoai-distributed-workload-operations`, `rhoai-distributed-workload-workflows`, `rhoai-kubeflow-spark-operator`, `rhoai-nvidia-gpu-accelerators`, `rhoai-certificate-management`, `rhoai-observability`, `rhoai-logs-and-audit-records`, `rhoai-installation-troubleshooting`, `rhoai-uninstallation`, `rhoai-users-groups-access`, `rhoai-access-group-selection`, `rhoai-central-authentication-service`, `rhoai-dashboard-applications`, `rhoai-connected-applications`, `rhoai-dashboard-customization`, `rhoai-cluster-pvc-size`, `rhoai-storage-classes`, `rhoai-connection-types`, `rhoai-s3-object-storage-data`, `rhoai-project-workflows`, `rhoai-data-science-ide-workflows`, `rhoai-project-scoped-resources`, `rhoai-component-resource-customization`, `rhoai-telemetry-admin-settings`, `rhoai-feature-store`, `rhoai-automl`, `rhoai-basic-workbenches`, `rhoai-workbenches-custom-images`, `rhoai-workbench-image-import`, `rhoai-workbench-gateway-api-migration`, `rhoai-model-serving-platform`, `rhoai-model-deployment`, `rhoai-maas-governance`, `rhoai-distributed-inference-llmd`, `rhoai-model-management-monitoring`, `rhoai-monitoring-trustyai`, `rhoai-model-catalog-sources`, `rhoai-model-catalog-workflows`, `rhoai-gen-ai-playground`, `rhoai-autorag`, `rhoai-model-registry`, `rhoai-model-registry-workflows`, `rhoai-llama-stack`, `rhoai-ai-pipelines`, `rhoai-mlflow`, `rhoai-model-customization-training`, `rhoai-evaluation`, `rhoai-guardrails-safety`, `rhoai-model-evaluation`, `rhoai-chatbot-customization`, `rhoai-kfp-pipeline-authoring`; component skills planned |
| OpenShift Platform | `ocp-*` | Official-doc-backed OpenShift Container Platform infrastructure, networking, auth, monitoring, GitOps, cluster, and storage integration guidance | `ocp-ai-workloads`, `ocp-authentication-identity-providers`, `ocp-cicd-builds`, `ocp-distributed-tracing`, `ocp-etcd`, `ocp-gitops-operator`, `ocp-image-registry-and-mirroring`, `ocp-ingress-gateway-routes`, `ocp-machine-configuration`, `ocp-machine-management`, `ocp-node-feature-discovery`, `ocp-nodes`, `ocp-observability`, `ocp-opentelemetry`, `ocp-security-rbac-scc`, `ocp-storage`, `ocp-web-console`; component skills planned |
| OpenShift Data Foundation | `odf-*` | Official-doc-backed OpenShift Data Foundation storage, object storage, Ceph, NooBaa, storage class, and data-service integration guidance | `odf-storagecluster`, `odf-storage-classes`, `odf-object-bucket-claims`, `odf-multicloud-gateway` |
| Assets & Miscellaneous | `assets-*` | Supporting assets and presentation outputs not tied to live cluster operations | `assets-red-hat-quick-deck` |

Use `project-red-hat-doc-skill-authoring` for new `rhoai-*`, `ocp-*`, and
`odf-*` product skills generated from official Red Hat documentation. Use
`project-rhoai-doc-chapter-skill-authoring` and
`references/rhoai-component-skill-roadmap.md` for existing RHOAI-only component
planning, and use `references/ocp-component-skill-roadmap.md` for OpenShift
Platform component planning. Use `references/odf-component-skill-roadmap.md`
for OpenShift Data Foundation component planning. Use
`.agents/references/red-hat-doc-map.yaml` as the product/category/book/topic
routing layer; keep skill folders flat under `.agents/skills/`.

## Project Change Workflow

1. Identify the group and owner skill for the work.
2. Read the relevant `.agents/rules/*.md` files before editing GitOps,
   README, labels, secrets, or generated architecture diagrams.
3. Keep code and docs aligned: manifest changes require README updates, and
   README capability claims require implemented manifests or a clear deferred
   label.
4. Keep operational details in `docs/OPERATIONS.md` and recovery details in
   `docs/TROUBLESHOOTING.md`; keep deferred capabilities and future work in
   `docs/BACKLOG.md`; step READMEs should stay focused on concise Why/What
   content, technology mapping, and architecture delta.
5. For README concepts, cite Red Hat narrative sources from `rh-brain`; for
   RHOAI component configuration, cite official active-baseline docs. Use
   `project-red-hat-doc-alignment-review` to check both.
6. Update `AGENTS.md`, `.agents/rules/*.md`, and the relevant project skills
   when skill groups, inventory, or source hierarchy change.

## Naming Guidance

Prefer stable names that describe responsibility:

- `project-*` for repository structure, docs, GitOps conventions, and narrative.
- `env-*` for live demo environment operations.
- `rhoai-*` for official-doc-backed RHOAI component knowledge.
- `ocp-*` for official-doc-backed OpenShift Container Platform knowledge.
- `odf-*` for official-doc-backed OpenShift Data Foundation knowledge.
- `assets-*` for visual, deck, diagram, or generated media workflows.

Renames should be incremental. Keep compatibility by updating negative triggers
and cross-references before deleting old skill folders.
