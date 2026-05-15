# Documentation Alignment Evidence Ledger

**Generated:** 2026-05-15T23:09:04Z
**Command:** `./scripts/audit-doc-alignment.sh --base origin/main`
**Base ref:** `origin/main`
**Docs baseline:** RHOAI 3.4 / OCP 4.20
**rh-brain source:** `/Users/adrina/Sandbox/rh-brain/Red Hat Brain`

This ledger is produced by `scripts/audit-doc-alignment.sh`. Official product documentation is the source of truth for supported configuration. `rh-brain` is read-only research input for narrative and Red Hat article alignment.

## Baseline References

- [Red Hat OpenShift AI Self-Managed 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/)
- [RHOAI 3.4 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/release_notes/index)
- [OpenShift Container Platform 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/)

## Component Evidence

### step-01-gpu-and-prereq

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-01-gpu-and-prereq/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-01-gpu-and-prereq.yaml` |
| README | `steps/step-01-gpu-and-prereq/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-01-gpu-and-prereq/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [PASS] No unpinned `:latest` image references found in GitOps path.

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-01-gpu-and-prereq/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Kuadrant --api-version=kuadrant.io/v1beta1`.
- [DEFERRED] Verify with `oc explain NodeFeatureDiscovery --api-version=nfd.openshift.io/v1`.
- [DEFERRED] Verify with `oc explain ClusterPolicy --api-version=nvidia.com/v1`.
- [DEFERRED] Verify with `oc explain KnativeServing --api-version=operator.knative.dev/v1beta1`.
- [DEFERRED] Verify with `oc explain Subscription --api-version=operators.coreos.com/v1alpha1`.
- [DEFERRED] Verify with `oc explain OperatorGroup --api-version=operators.coreos.com/v1`.
- [DEFERRED] Verify with `oc explain ClusterRoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain ConfigMap --api-version=v1`.
- [DEFERRED] Verify with `oc explain Namespace --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Autoscaling vLLM with OpenShift AI model serving Performance validation.md`
- `rh-brain: raw/Customize Models for Gen AI and Agentic AI Applications  Red Hat OpenShift AI Self-Managed  3.4.md`

### step-02-rhoai

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-02-rhoai/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-02-rhoai.yaml` |
| README | `steps/step-02-rhoai/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-02-rhoai/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-02-rhoai/base/rhoai-operator/maas-postgres-deployment.yaml:30:          image: registry.redhat.io/rhel9/postgresql-16:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-02-rhoai/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Deployment --api-version=apps/v1`.
- [DEFERRED] Verify with `oc explain DataScienceCluster --api-version=datasciencecluster.opendatahub.io/v2`.
- [DEFERRED] Verify with `oc explain DSCInitialization --api-version=dscinitialization.opendatahub.io/v1`.
- [DEFERRED] Verify with `oc explain Gateway --api-version=gateway.networking.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain HardwareProfile --api-version=infrastructure.opendatahub.io/v1`.
- [DEFERRED] Verify with `oc explain OdhDashboardConfig --api-version=opendatahub.io/v1alpha`.
- [DEFERRED] Verify with `oc explain Subscription --api-version=operators.coreos.com/v1alpha1`.
- [DEFERRED] Verify with `oc explain OperatorGroup --api-version=operators.coreos.com/v1`.
- [DEFERRED] Verify with `oc explain Auth --api-version=services.platform.opendatahub.io/v1alpha1`.
- [DEFERRED] Verify with `oc explain Namespace --api-version=v1`.
- [DEFERRED] Verify with `oc explain PersistentVolumeClaim --api-version=v1`.
- [DEFERRED] Verify with `oc explain Secret --api-version=v1`.
- [DEFERRED] Verify with `oc explain Service --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Autoscaling vLLM with OpenShift AI model serving Performance validation.md`
- `rh-brain: raw/Customize Models for Gen AI and Agentic AI Applications  Red Hat OpenShift AI Self-Managed  3.4.md`

### step-03-enterprise-projects

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-03-enterprise-projects/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-03-enterprise-projects.yaml` |
| README | `steps/step-03-enterprise-projects/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-03-enterprise-projects/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-03-enterprise-projects/base/minio/init-job.yaml:31:          image: quay.io/minio/mc:latest
  - gitops/step-03-enterprise-projects/base/minio/deployment.yaml:26:          image: quay.io/minio/minio:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-03-enterprise-projects/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Deployment --api-version=apps/v1`.
- [DEFERRED] Verify with `oc explain Job --api-version=batch/v1`.
- [DEFERRED] Verify with `oc explain OAuth --api-version=config.openshift.io/v1`.
- [DEFERRED] Verify with `oc explain Kueue --api-version=kueue.openshift.io/v1`.
- [DEFERRED] Verify with `oc explain ClusterQueue --api-version=kueue.x-k8s.io/v1beta1`.
- [DEFERRED] Verify with `oc explain LocalQueue --api-version=kueue.x-k8s.io/v1beta1`.
- [DEFERRED] Verify with `oc explain ResourceFlavor --api-version=kueue.x-k8s.io/v1beta1`.
- [DEFERRED] Verify with `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain Namespace --api-version=v1`.
- [DEFERRED] Verify with `oc explain PersistentVolumeClaim --api-version=v1`.
- [DEFERRED] Verify with `oc explain Secret --api-version=v1`.
- [DEFERRED] Verify with `oc explain Service --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Autoscaling vLLM with OpenShift AI model serving Performance validation.md`
- `rh-brain: raw/Customize Models for Gen AI and Agentic AI Applications  Red Hat OpenShift AI Self-Managed  3.4.md`

### step-04-model-registry

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-04-model-registry/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-04-model-registry.yaml` |
| README | `steps/step-04-model-registry/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-04-model-registry/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-04-model-registry/base/database/deployment.yaml:32:          image: registry.redhat.io/rhel9/mariadb-1011:latest
  - gitops/step-04-model-registry/base/seed-job.yaml:30:          image: quay.io/curl/curl:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-04-model-registry/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Deployment --api-version=apps/v1`.
- [DEFERRED] Verify with `oc explain Job --api-version=batch/v1`.
- [DEFERRED] Verify with `oc explain ModelRegistry --api-version=modelregistry.opendatahub.io/v1beta1`.
- [DEFERRED] Verify with `oc explain NetworkPolicy --api-version=networking.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain PersistentVolumeClaim --api-version=v1`.
- [DEFERRED] Verify with `oc explain Secret --api-version=v1`.
- [DEFERRED] Verify with `oc explain Service --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Autoscaling vLLM with OpenShift AI model serving Performance validation.md`
- `rh-brain: raw/Customize Models for Gen AI and Agentic AI Applications  Red Hat OpenShift AI Self-Managed  3.4.md`

### step-05-maas-model-serving

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-05-maas-model-serving/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-05-maas-model-serving.yaml` |
| README | `steps/step-05-maas-model-serving/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-05-maas-model-serving/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-05-maas-model-serving/base/model-registration/seed-job.yaml:38:          image: quay.io/curl/curl:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-05-maas-model-serving/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Job --api-version=batch/v1`.
- [DEFERRED] Verify with `oc explain ServingRuntime --api-version=serving.kserve.io/v1alpha1`.
- [DEFERRED] Verify with `oc explain InferenceService --api-version=serving.kserve.io/v1beta1`.
- [DEFERRED] Verify with `oc explain PersistentVolumeClaim --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/A guide to Models-as-a-Service.md`
- `rh-brain: raw/Building on the outstanding performance of vLLM with llm-d.md`
- `rh-brain: raw/Combining KServe and llm-d for optimized generative AI inference.md`
- `rh-brain: raw/Models-as-a-Service - ODH Models-as-a-Service Documentation.md`

### step-06-model-metrics

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-06-model-metrics/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-06-model-metrics.yaml` |
| README | `steps/step-06-model-metrics/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-06-model-metrics/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-06-model-metrics/base/guidellm/cronjob.yaml:43:              image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
  - gitops/step-06-model-metrics/base/model-benchmarking-wb/workbench.yaml:87:          image: alpine/git:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-06-model-metrics/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain CronJob --api-version=batch/v1`.
- [DEFERRED] Verify with `oc explain Grafana --api-version=grafana.integreatly.org/v1beta1`.
- [DEFERRED] Verify with `oc explain GrafanaDashboard --api-version=grafana.integreatly.org/v1beta1`.
- [DEFERRED] Verify with `oc explain GrafanaDatasource --api-version=grafana.integreatly.org/v1beta1`.
- [DEFERRED] Verify with `oc explain Notebook --api-version=kubeflow.org/v1`.
- [DEFERRED] Verify with `oc explain Subscription --api-version=operators.coreos.com/v1alpha1`.
- [DEFERRED] Verify with `oc explain OperatorGroup --api-version=operators.coreos.com/v1`.
- [DEFERRED] Verify with `oc explain ClusterRoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain Role --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain ConfigMap --api-version=v1`.
- [DEFERRED] Verify with `oc explain Namespace --api-version=v1`.
- [DEFERRED] Verify with `oc explain PersistentVolumeClaim --api-version=v1`.
- [DEFERRED] Verify with `oc explain Secret --api-version=v1`.
- [DEFERRED] Verify with `oc explain ServiceAccount --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/A guide to Models-as-a-Service.md`
- `rh-brain: raw/Building on the outstanding performance of vLLM with llm-d.md`
- `rh-brain: raw/Combining KServe and llm-d for optimized generative AI inference.md`
- `rh-brain: raw/Models-as-a-Service - ODH Models-as-a-Service Documentation.md`

### step-07-rag

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-07-rag/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-07-rag.yaml` |
| README | `steps/step-07-rag/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-07-rag/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-07-rag/base/chatbot/chatbot.yaml:59:          image: image-registry.openshift-image-registry.svc:5000/enterprise-rag/rag-chatbot:latest
  - gitops/step-07-rag/base/docling/deployment.yaml:34:          image: quay.io/docling-project/docling-serve:latest
  - gitops/step-07-rag/base/rag-wb/workbench.yaml:69:          image: alpine/git:latest
  - gitops/step-07-rag/base/minio-rag-bucket/init-job.yaml:28:          image: quay.io/minio/mc:latest
  - gitops/step-07-rag/base/ingestion-service/job.yaml:22:          image: image-registry.openshift-image-registry.svc:5000/enterprise-rag/rag-ingestion-service:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-07-rag/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Deployment --api-version=apps/v1`.
- [DEFERRED] Verify with `oc explain Job --api-version=batch/v1`.
- [DEFERRED] Verify with `oc explain BuildConfig --api-version=build.openshift.io/v1`.
- [DEFERRED] Verify with `oc explain DataSciencePipelinesApplication --api-version=datasciencepipelinesapplications.opendatahub.io/v1`.
- [DEFERRED] Verify with `oc explain ImageStream --api-version=image.openshift.io/v1`.
- [DEFERRED] Verify with `oc explain Notebook --api-version=kubeflow.org/v1`.
- [DEFERRED] Verify with `oc explain LlamaStackDistribution --api-version=llamastack.io/v1alpha1`.
- [DEFERRED] Verify with `oc explain NetworkPolicy --api-version=networking.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain Role --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain Route --api-version=route.openshift.io/v1`.
- [DEFERRED] Verify with `oc explain ConfigMap --api-version=v1`.
- [DEFERRED] Verify with `oc explain PersistentVolumeClaim --api-version=v1`.
- [DEFERRED] Verify with `oc explain Secret --api-version=v1`.
- [DEFERRED] Verify with `oc explain Service --api-version=v1`.
- [DEFERRED] Verify with `oc explain ServiceAccount --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Breaking the RAG bottleneck Scalable document processing with Ray Data and Docling 1.md`
- `rh-brain: raw/Breaking the RAG bottleneck Scalable document processing with Ray Data and Docling.md`
- `rh-brain: raw/Evaluation Quickstart  MLflow AI Platform.md`
- `rh-brain: raw/Synthetic data for RAG evaluation Why your RAG system needs better testing.md`

### step-08-model-evaluation

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-08-model-evaluation/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-08-model-evaluation.yaml` |
| README | `steps/step-08-model-evaluation/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-08-model-evaluation/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-08-model-evaluation/base/eval-configs/job-copy-configs.yaml:25:          image: registry.access.redhat.com/ubi9/ubi-minimal:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-08-model-evaluation/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Job --api-version=batch/v1`.
- [DEFERRED] Verify with `oc explain ConfigMap --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Breaking the RAG bottleneck Scalable document processing with Ray Data and Docling 1.md`
- `rh-brain: raw/Breaking the RAG bottleneck Scalable document processing with Ray Data and Docling.md`
- `rh-brain: raw/Evaluation Quickstart  MLflow AI Platform.md`
- `rh-brain: raw/Synthetic data for RAG evaluation Why your RAG system needs better testing.md`

### step-09-guardrails

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-09-guardrails/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-09-guardrails.yaml` |
| README | `steps/step-09-guardrails/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-09-guardrails/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [PASS] No unpinned `:latest` image references found in GitOps path.

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-09-guardrails/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain ServingRuntime --api-version=serving.kserve.io/v1alpha1`.
- [DEFERRED] Verify with `oc explain InferenceService --api-version=serving.kserve.io/v1beta1`.
- [DEFERRED] Verify with `oc explain GuardrailsOrchestrator --api-version=trustyai.opendatahub.io/v1alpha1`.
- [DEFERRED] Verify with `oc explain ConfigMap --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Build resilient guardrails for OpenClaw AI agents on Kubernetes 1.md`
- `rh-brain: raw/Build resilient guardrails for OpenClaw AI agents on Kubernetes.md`

### step-10-mcp-integration

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-10-mcp-integration/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-10-mcp-integration.yaml` |
| README | `steps/step-10-mcp-integration/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-10-mcp-integration/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-10-mcp-integration/base/postgresql/deployment.yaml:27:          image: registry.redhat.io/rhel9/postgresql-15:latest
  - gitops/step-10-mcp-integration/base/acme-corp/demo-pods.yaml:24:      image: registry.access.redhat.com/ubi9/ubi-minimal:latest
  - gitops/step-10-mcp-integration/base/acme-corp/demo-pods.yaml:66:      image: registry.access.redhat.com/ubi9/ubi-minimal:latest
  - gitops/step-10-mcp-integration/base/acme-corp/demo-pods.yaml:110:      image: registry.access.redhat.com/ubi9/ubi-minimal:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-10-mcp-integration/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Deployment --api-version=apps/v1`.
- [DEFERRED] Verify with `oc explain ClusterRoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain Role --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain Route --api-version=route.openshift.io/v1`.
- [DEFERRED] Verify with `oc explain ConfigMap --api-version=v1`.
- [DEFERRED] Verify with `oc explain Namespace --api-version=v1`.
- [DEFERRED] Verify with `oc explain PersistentVolumeClaim --api-version=v1`.
- [DEFERRED] Verify with `oc explain Pod --api-version=v1`.
- [DEFERRED] Verify with `oc explain Secret --api-version=v1`.
- [DEFERRED] Verify with `oc explain Service --api-version=v1`.
- [DEFERRED] Verify with `oc explain ServiceAccount --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Advanced authentication and authorization for MCP Gateway.md`
- `rh-brain: raw/Agentic AI vs. generative AI.md`
- `rh-brain: raw/Agentic AI with Red Hat AI.md`
- `rh-brain: raw/Building effective AI agents with Model Context Protocol (MCP).md`

### step-11-face-recognition

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-11-face-recognition/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-11-face-recognition.yaml` |
| README | `steps/step-11-face-recognition/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-11-face-recognition/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-11-face-recognition/base/workbench/workbench.yaml:65:          image: alpine/git:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-11-face-recognition/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Job --api-version=batch/v1`.
- [DEFERRED] Verify with `oc explain Notebook --api-version=kubeflow.org/v1`.
- [DEFERRED] Verify with `oc explain Role --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain ServingRuntime --api-version=serving.kserve.io/v1alpha1`.
- [DEFERRED] Verify with `oc explain InferenceService --api-version=serving.kserve.io/v1beta1`.
- [DEFERRED] Verify with `oc explain PersistentVolumeClaim --api-version=v1`.
- [DEFERRED] Verify with `oc explain ServiceAccount --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Enhance LLMs and streamline MLOps using InstructLab and KitOps.md`
- `rh-brain: raw/Evaluating (Production) Traces  MLflow AI Platform 1.md`
- `rh-brain: raw/Evaluating (Production) Traces  MLflow AI Platform.md`
- `rh-brain: raw/From experiment to production A reliable architecture for version-controlled MLOps.md`

### step-12-mlops-pipeline

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-12-mlops-pipeline/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-12-mlops-pipeline.yaml` |
| README | `steps/step-12-mlops-pipeline/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-12-mlops-pipeline/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-12-mlops-pipeline/base/trustyai-adapter/deployment.yaml:27:          image: registry.redhat.io/ubi9/python-312:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-12-mlops-pipeline/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Deployment --api-version=apps/v1`.
- [DEFERRED] Verify with `oc explain DataSciencePipelinesApplication --api-version=datasciencepipelinesapplications.opendatahub.io/v1`.
- [DEFERRED] Verify with `oc explain ClusterRoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain Role --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`.
- [DEFERRED] Verify with `oc explain TrustyAIService --api-version=trustyai.opendatahub.io/v1`.
- [DEFERRED] Verify with `oc explain ConfigMap --api-version=v1`.
- [DEFERRED] Verify with `oc explain PersistentVolumeClaim --api-version=v1`.
- [DEFERRED] Verify with `oc explain Secret --api-version=v1`.
- [DEFERRED] Verify with `oc explain Service --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Enhance LLMs and streamline MLOps using InstructLab and KitOps.md`
- `rh-brain: raw/Evaluating (Production) Traces  MLflow AI Platform 1.md`
- `rh-brain: raw/Evaluating (Production) Traces  MLflow AI Platform.md`
- `rh-brain: raw/From experiment to production A reliable architecture for version-controlled MLOps.md`

### step-13-edge-ai

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-13-edge-ai/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-13-edge-ai.yaml` |
| README | `steps/step-13-edge-ai/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-13-edge-ai/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-13-edge-ai/base/edge-camera/deployment.yaml:31:          image: quay.io/adrina/edge-camera:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-13-edge-ai/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Deployment --api-version=apps/v1`.
- [DEFERRED] Verify with `oc explain Route --api-version=route.openshift.io/v1`.
- [DEFERRED] Verify with `oc explain ServingRuntime --api-version=serving.kserve.io/v1alpha1`.
- [DEFERRED] Verify with `oc explain InferenceService --api-version=serving.kserve.io/v1beta1`.
- [DEFERRED] Verify with `oc explain Namespace --api-version=v1`.
- [DEFERRED] Verify with `oc explain Secret --api-version=v1`.
- [DEFERRED] Verify with `oc explain Service --api-version=v1`.

**rh-brain Research Sources**

- `rh-brain: raw/What is edge AI?.md`

### step-13b-edge-ai-microshift

| Field | Evidence |
|-------|----------|
| Status | `aligned-with-notes` |
| GitOps path | `gitops/step-13b-edge-ai-microshift/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-13b-edge-ai-microshift.yaml` |
| README | `steps/step-13b-edge-ai-microshift/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-13b-edge-ai-microshift/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [WARN] Unpinned `:latest` image references found:
  - gitops/step-13b-edge-ai-microshift/base/update-gitops.yaml:28:      image: registry.access.redhat.com/ubi9/ubi-minimal:latest
  - gitops/step-13b-edge-ai-microshift/base/build-modelcar.yaml:30:      image: registry.access.redhat.com/ubi9/python-311:latest
  - gitops/step-13b-edge-ai-microshift/base/build-modelcar.yaml:69:      image: registry.access.redhat.com/ubi9/buildah:latest

**Schema Verification**

- [DEFERRED] Verify rendered schema and CR fields with `kustomize build gitops/step-13b-edge-ai-microshift/base | oc apply --dry-run=server --validate=strict -f -`.
- [DEFERRED] Verify with `oc explain Pipeline --api-version=tekton.dev/v1`.
- [DEFERRED] Verify with `oc explain Task --api-version=tekton.dev/v1`.

**rh-brain Research Sources**

- `rh-brain: raw/Autoscaling vLLM with OpenShift AI model serving Performance validation.md`
- `rh-brain: raw/Customize Models for Gen AI and Agentic AI Applications  Red Hat OpenShift AI Self-Managed  3.4.md`

## Summary

| Result | Count |
|--------|-------|
| Blocking findings | 0 |
| Notes / deferred checks | 26 |

**Decision:** aligned. Notes and deferred checks may be handled as follow-up work.
