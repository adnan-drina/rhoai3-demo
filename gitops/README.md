# GitOps

Clean slate for the RHOAI demo reimplementation.

Legacy manifests are backed up under:

- `../backup/legacy-implementation-2026-06-09/gitops/`

Add new GitOps content here only when it is aligned with
`../docs/PLATFORM_BASELINE.md` and the matching step README.

For each new step, first use
`../.agents/skills/project-demo-step-authoring/SKILL.md` to decide whether the
step owns its own GitOps path or patches a shared platform owner. Avoid
duplicate ownership of shared resources such as RHOAI `DataScienceCluster`,
ODF, NFD, GPU Operator, or Grafana platform layers.
