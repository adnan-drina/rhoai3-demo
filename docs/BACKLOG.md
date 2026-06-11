# Backlog

Active backlog for the reimplementation.

## Stage 110: Deferred Items

| Item | Priority | Notes |
|------|----------|-------|
| Verify ODF StorageSystem MCG-only CR fields | high | `storage-system.yaml` uses `spec.kind: noobaa.noobaa.io/v1alpha1`; confirm with `oc explain storagesystem.odf.openshift.io` after ODF operator installs on cluster-klvxt |
| Live validation of stage-110 end-to-end | high | Cluster cluster-klvxt (OCP 4.20.24) is available; run `deploy.sh` then `validate.sh` |
| GPU accelerator foundation | medium | NFD, GPU Operator, AWS GPU MachineSet, RHOAI hardware profile — future `stage-130-gpu-accelerator-foundation` |
| Identity provider and access groups | medium | RHOAI users/groups/RBAC — future stage in 1xx family |
| ODF RHOAI data connection (first OBC) | low | First `ObjectBucketClaim` for RHOAI AI Pipelines backend — can be added to stage-110 GitOps or as a dedicated stage-120 item |
| Repo URL / branch injection in ArgoCD Application | low | `deploy.sh` uses `sed` to inject `GIT_REPO_URL`/`GIT_REPO_BRANCH` from `.env`; consider a Kustomize `configMapGenerator` + `replacements` approach (AI Accelerator pattern) for cleaner handling |
| ArgoCD RBAC group for `rhoai-demo` AppProject | low | Currently cluster-admin only; add a dedicated `rhoai-demo-admins` group for least-privilege demo access |
| TROUBLESHOOTING.md: common stage-110 failures | low | Bootstrap timeout, GitOps operator CrashLoop, NooBaa stuck Initializing, RHOAI operator pending upgrade |

## Candidate Future Stages

These map to the taxonomy ranges defined in `.agents/skills/project-demo-stage-authoring/references/stage-taxonomy.md`.

| Candidate | Theme | Concept |
|-----------|-------|---------|
| `stage-130-gpu-accelerator-foundation` | AI Platform Foundation | NFD + GPU Operator + AWS GPU MachineSet + RHOAI hardware profile |
| `stage-210-model-catalog-and-registry` | Production GenAI | Model catalog, registry, Red Hat validated models |
| `stage-220-private-model-serving` | Production GenAI | vLLM model serving via RHOAI model-serving platform |
| `stage-230-models-as-a-service` | Production GenAI | MaaS governed access to internal and external model endpoints |
| `stage-240-private-data-rag` | Production GenAI | Private data ingestion, RAG application |
| `stage-320-llama-stack-runtime` | Agentic AI | Llama Stack runtime and API integration |
| `stage-410-ai-pipelines` | AI Operations/MLOps | AI Pipelines and KFP workflows |
| `stage-420-model-evaluation` | AI Operations/MLOps | LMEval / EvalHub evaluation and evidence capture |
| `stage-440-observability-and-governance` | AI Operations/MLOps | TrustyAI, Grafana, monitoring |

Legacy backlog content is backed up at:

- `../backup/legacy-implementation-2026-06-09/docs/BACKLOG.md`
