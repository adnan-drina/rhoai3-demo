# Backlog

Active backlog for the reimplementation.

## Stage 110: Status — COMPLETE

Deployed and validated 2026-06-11 on cluster-klvxt (OCP 4.20.24); `validate.sh` 17/17. User-validated end to end: login as both personas, workbench with RWO PVC, model registry instance with a registered model, S3 from the workbench.

Completed: GitOps bootstrap, ODF MCG (S3 verified), RHOAI 3.4 (dashboard, workbenches, model registry), htpasswd IdP + `ai-admin`/`ai-developer` + groups, `demo-sandbox` project + first OBC + S3 connection, model registry instance (day-2 dashboard).

### Open / deferred from Stage 110

| Item | Priority | Notes |
|------|----------|-------|
| Capture model registry instance in GitOps | low | `default-modelregistry` + registered models are day-2 dashboard-created (runtime, with DB secrets); optional to capture for from-scratch reproducibility |
| Repo URL / branch injection in ArgoCD Application | low | `deploy.sh` uses `sed` to inject `GIT_REPO_URL`/`GIT_REPO_BRANCH` from `.env`; consider a Kustomize `configMapGenerator` + `replacements` approach (AI Accelerator pattern) |
| Dedicated `rhoai-demo-admins` group | low | RHOAI admin uses `rhods-admins`; a separate demo-admin group is optional |
| Least-privilege role for Argo CD application-controller | low | Bootstrap grants `cluster-admin` to `openshift-gitops-argocd-application-controller` (`gitops/bootstrap/overlays/demo/argocd-cluster-admin.yaml`); replace with a scoped role |
| Per-project admin RBAC for future projects | low | `rhods-admins` is bound `admin` per project (currently `demo-sandbox` only); each new project needs its own binding, by design |

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
