# Documentation Alignment Evidence Ledger

**Generated:** 2026-05-16T15:25:47Z
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
| Status | `aligned` |
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

- [PASS] `oc apply --dry-run=server --validate=strict -f rendered.yaml` accepted rendered resources.
- [PASS] `oc explain Kuadrant --api-version=kuadrant.io/v1beta1`
- [PASS] `oc explain NodeFeatureDiscovery --api-version=nfd.openshift.io/v1`
- [PASS] `oc explain ClusterPolicy --api-version=nvidia.com/v1`
- [PASS] `oc explain KnativeServing --api-version=operator.knative.dev/v1beta1`
- [PASS] `oc explain Subscription --api-version=operators.coreos.com/v1alpha1`
- [PASS] `oc explain OperatorGroup --api-version=operators.coreos.com/v1`
- [PASS] `oc explain ClusterRoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain ConfigMap --api-version=v1`
- [PASS] `oc explain Namespace --api-version=v1`

**rh-brain Research Sources**

- `rh-brain: raw/Autoscaling vLLM with OpenShift AI model serving Performance validation.md`
- `rh-brain: raw/Chapter 9. Reusable system instructions  Experimenting with models in the gen AI playground  Red Hat OpenShift AI Self-Managed  3.4.md`

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
- [PASS] Managed or internal `:latest` image references are classified and accepted:
  - gitops/step-02-rhoai/base/rhoai-operator/maas-postgres-deployment.yaml:30:          image: registry.redhat.io/rhel9/postgresql-16:latest (Red Hat managed version stream)

**Schema Verification**

- [WARN] Server dry-run reported existing PVC immutable spec drift, but the matching Argo CD app intentionally ignores PVC `/spec`.
  Exact warning:
  The PersistentVolumeClaim "maas-postgres-data" is invalid: spec: Forbidden: spec is immutable after creation except resources.requests and volumeAttributesClassName for bound claims
    core.PersistentVolumeClaimSpec{
        AccessModes:      {"ReadWriteOnce"},
        Selector:         nil,
        Resources:        {Requests: {s"storage": {i: {...}, s: "5Gi", Format: "BinarySI"}}},
  -     VolumeName:       "pvc-75b7c9cc-3c07-4bc7-9c17-c890be84c51c",
  +     VolumeName:       "",
  -     StorageClassName: &"gp3-csi",
  +     StorageClassName: nil,
        VolumeMode:       &"Filesystem",
        DataSource:       nil,
        ... // 2 identical fields
    }

- [PASS] `oc explain Deployment --api-version=apps/v1`
- [PASS] `oc explain DataScienceCluster --api-version=datasciencecluster.opendatahub.io/v2`
- [PASS] `oc explain DSCInitialization --api-version=dscinitialization.opendatahub.io/v1`
- [PASS] `oc explain Gateway --api-version=gateway.networking.k8s.io/v1`
- [PASS] `oc explain HardwareProfile --api-version=infrastructure.opendatahub.io/v1`
- [PASS] `oc explain OdhDashboardConfig --api-version=opendatahub.io/v1alpha`
- [PASS] `oc explain Subscription --api-version=operators.coreos.com/v1alpha1`
- [PASS] `oc explain OperatorGroup --api-version=operators.coreos.com/v1`
- [PASS] `oc explain Route --api-version=route.openshift.io/v1`
- [PASS] `oc explain Auth --api-version=services.platform.opendatahub.io/v1alpha1`
- [PASS] `oc explain Namespace --api-version=v1`
- [PASS] `oc explain PersistentVolumeClaim --api-version=v1`
- [PASS] `oc explain Secret --api-version=v1`
- [PASS] `oc explain Service --api-version=v1`

**rh-brain Research Sources**

- `rh-brain: raw/Autoscaling vLLM with OpenShift AI model serving Performance validation.md`
- `rh-brain: raw/Chapter 9. Reusable system instructions  Experimenting with models in the gen AI playground  Red Hat OpenShift AI Self-Managed  3.4.md`

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
- [WARN] Unmanaged external `:latest` image references found:
  - gitops/step-03-enterprise-projects/base/minio/init-job.yaml:31:          image: quay.io/minio/mc:latest (unmanaged external dependency)
  - gitops/step-03-enterprise-projects/base/minio/deployment.yaml:26:          image: quay.io/minio/minio:latest (unmanaged external dependency)

**Schema Verification**

- [PASS] `oc apply --dry-run=server --validate=strict -f rendered.yaml` accepted rendered resources.
- [PASS] `oc explain Deployment --api-version=apps/v1`
- [PASS] `oc explain Job --api-version=batch/v1`
- [PASS] `oc explain OAuth --api-version=config.openshift.io/v1`
- [PASS] `oc explain Kueue --api-version=kueue.openshift.io/v1`
- [PASS] `oc explain ClusterQueue --api-version=kueue.x-k8s.io/v1beta1`
- [PASS] `oc explain LocalQueue --api-version=kueue.x-k8s.io/v1beta1`
- [PASS] `oc explain ResourceFlavor --api-version=kueue.x-k8s.io/v1beta1`
- [PASS] `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain Route --api-version=route.openshift.io/v1`
- [PASS] `oc explain Namespace --api-version=v1`
- [PASS] `oc explain PersistentVolumeClaim --api-version=v1`
- [PASS] `oc explain Secret --api-version=v1`
- [PASS] `oc explain Service --api-version=v1`

**rh-brain Research Sources**

- `rh-brain: raw/Autoscaling vLLM with OpenShift AI model serving Performance validation.md`
- `rh-brain: raw/Chapter 9. Reusable system instructions  Experimenting with models in the gen AI playground  Red Hat OpenShift AI Self-Managed  3.4.md`

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
- [WARN] Unmanaged external `:latest` image references found:
  - gitops/step-04-model-registry/base/seed-job.yaml:30:          image: quay.io/curl/curl:latest (unmanaged external dependency)
- [PASS] Managed or internal `:latest` image references are classified and accepted:
  - gitops/step-04-model-registry/base/database/deployment.yaml:32:          image: registry.redhat.io/rhel9/mariadb-1011:latest (Red Hat managed version stream)

**Schema Verification**

- [PASS] `oc apply --dry-run=server --validate=strict -f rendered.yaml` accepted rendered resources.
- [PASS] `oc explain Deployment --api-version=apps/v1`
- [PASS] `oc explain Job --api-version=batch/v1`
- [PASS] `oc explain ModelRegistry --api-version=modelregistry.opendatahub.io/v1beta1`
- [PASS] `oc explain NetworkPolicy --api-version=networking.k8s.io/v1`
- [PASS] `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain PersistentVolumeClaim --api-version=v1`
- [PASS] `oc explain Secret --api-version=v1`
- [PASS] `oc explain Service --api-version=v1`

**rh-brain Research Sources**

- `rh-brain: raw/Autoscaling vLLM with OpenShift AI model serving Performance validation.md`
- `rh-brain: raw/Chapter 9. Reusable system instructions  Experimenting with models in the gen AI playground  Red Hat OpenShift AI Self-Managed  3.4.md`

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
- [WARN] Unmanaged external `:latest` image references found:
  - gitops/step-05-maas-model-serving/base/model-registration/seed-job.yaml:38:          image: quay.io/curl/curl:latest (unmanaged external dependency)

**Schema Verification**

- [PASS] `oc apply --dry-run=server --validate=strict -f rendered.yaml` accepted rendered resources.
- [PASS] `oc explain Job --api-version=batch/v1`
- [PASS] `oc explain ExternalModel --api-version=maas.opendatahub.io/v1alpha1`
- [PASS] `oc explain MaaSAuthPolicy --api-version=maas.opendatahub.io/v1alpha1`
- [PASS] `oc explain MaaSModelRef --api-version=maas.opendatahub.io/v1alpha1`
- [PASS] `oc explain MaaSSubscription --api-version=maas.opendatahub.io/v1alpha1`
- [PASS] `oc explain ServingRuntime --api-version=serving.kserve.io/v1alpha1`
- [PASS] `oc explain InferenceService --api-version=serving.kserve.io/v1beta1`
- [PASS] `oc explain Secret --api-version=v1`

**rh-brain Research Sources**

- `rh-brain: raw/A guide to Models-as-a-Service.md`
- `rh-brain: raw/Building on the outstanding performance of vLLM with llm-d.md`
- `rh-brain: raw/Combining KServe and llm-d for optimized generative AI inference.md`
- `rh-brain: raw/Govern LLM access with Models-as-a-Service  Red Hat OpenShift AI Self-Managed  3.4.md`

### step-06-model-metrics

| Field | Evidence |
|-------|----------|
| Status | `aligned` |
| GitOps path | `gitops/step-06-model-metrics/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-06-model-metrics.yaml` |
| README | `steps/step-06-model-metrics/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-06-model-metrics/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [PASS] Managed or internal `:latest` image references are classified and accepted:
  - gitops/step-06-model-metrics/base/guidellm/cronjob.yaml:43:              image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest (OpenShift platform ImageStream)

**Schema Verification**

- [PASS] `oc apply --dry-run=server --validate=strict -f rendered.yaml` accepted rendered resources.
- [PASS] `oc explain CronJob --api-version=batch/v1`
- [PASS] `oc explain Grafana --api-version=grafana.integreatly.org/v1beta1`
- [PASS] `oc explain GrafanaDashboard --api-version=grafana.integreatly.org/v1beta1`
- [PASS] `oc explain GrafanaDatasource --api-version=grafana.integreatly.org/v1beta1`
- [PASS] `oc explain Subscription --api-version=operators.coreos.com/v1alpha1`
- [PASS] `oc explain OperatorGroup --api-version=operators.coreos.com/v1`
- [PASS] `oc explain ClusterRoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain Role --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain ConfigMap --api-version=v1`
- [PASS] `oc explain Namespace --api-version=v1`
- [PASS] `oc explain PersistentVolumeClaim --api-version=v1`
- [PASS] `oc explain Secret --api-version=v1`
- [PASS] `oc explain ServiceAccount --api-version=v1`

**rh-brain Research Sources**

- `rh-brain: raw/A guide to Models-as-a-Service.md`
- `rh-brain: raw/Building on the outstanding performance of vLLM with llm-d.md`
- `rh-brain: raw/Combining KServe and llm-d for optimized generative AI inference.md`
- `rh-brain: raw/Govern LLM access with Models-as-a-Service  Red Hat OpenShift AI Self-Managed  3.4.md`

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
- [WARN] Unmanaged external `:latest` image references found:
  - gitops/step-07-rag/base/docling/deployment.yaml:34:          image: quay.io/docling-project/docling-serve:latest (unmanaged external dependency)
  - gitops/step-07-rag/base/rag-wb/workbench.yaml:65:          image: alpine/git:latest (unmanaged external dependency)
  - gitops/step-07-rag/base/minio-rag-bucket/init-job.yaml:28:          image: quay.io/minio/mc:latest (unmanaged external dependency)
- [PASS] Managed or internal `:latest` image references are classified and accepted:
  - gitops/step-07-rag/base/chatbot/chatbot.yaml:60:          image: image-registry.openshift-image-registry.svc:5000/enterprise-rag/rag-chatbot:latest (internal demo build output)
  - gitops/step-07-rag/base/ingestion-service/job.yaml:22:          image: image-registry.openshift-image-registry.svc:5000/enterprise-rag/rag-ingestion-service:latest (internal demo build output)
- [PASS] Chatbot example prompts are GitOps-managed in `RAG_QUESTION_SUGGESTIONS` and grouped by RAG/MCP use case.
- [PASS] Browser validation reads the deployed example prompt configuration and exercises each non-side-effect example prompt.
- [PASS] Direct RAG examples cover `whoami` identity, expertise, and event discovery.
- [PASS] Direct RAG examples cover `acme_corporate` corporate profile and L-900 equipment troubleshooting.
- [PASS] Agent examples cover OpenShift MCP pod listing and database MCP asset lookup.
- [PASS] Slack-send prompts are excluded from the chatbot regression set to avoid external side effects; Step 10 keeps the Slack MCP path.

**Schema Verification**

- [PASS] `oc apply --dry-run=server --validate=strict -f rendered.yaml` accepted rendered resources.
- [PASS] `oc explain Deployment --api-version=apps/v1`
- [PASS] `oc explain Job --api-version=batch/v1`
- [PASS] `oc explain BuildConfig --api-version=build.openshift.io/v1`
- [PASS] `oc explain DataSciencePipelinesApplication --api-version=datasciencepipelinesapplications.opendatahub.io/v1`
- [PASS] `oc explain ImageStream --api-version=image.openshift.io/v1`
- [PASS] `oc explain Notebook --api-version=kubeflow.org/v1`
- [PASS] `oc explain LlamaStackDistribution --api-version=llamastack.io/v1alpha1`
- [PASS] `oc explain NetworkPolicy --api-version=networking.k8s.io/v1`
- [PASS] `oc explain Role --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain Route --api-version=route.openshift.io/v1`
- [PASS] `oc explain ConfigMap --api-version=v1`
- [PASS] `oc explain PersistentVolumeClaim --api-version=v1`
- [PASS] `oc explain Secret --api-version=v1`
- [PASS] `oc explain Service --api-version=v1`
- [PASS] `oc explain ServiceAccount --api-version=v1`

**rh-brain Research Sources**

- `rh-brain: raw/Breaking the RAG bottleneck Scalable document processing with Ray Data and Docling 1.md`
- `rh-brain: raw/Breaking the RAG bottleneck Scalable document processing with Ray Data and Docling.md`
- `rh-brain: raw/Evaluation Quickstart  MLflow AI Platform.md`
- `rh-brain: raw/Synthetic data for RAG evaluation Why your RAG system needs better testing.md`

### step-08-model-evaluation

| Field | Evidence |
|-------|----------|
| Status | `aligned` |
| GitOps path | `gitops/step-08-model-evaluation/base` |
| Argo CD app | `gitops/argocd/app-of-apps/step-08-model-evaluation.yaml` |
| README | `steps/step-08-model-evaluation/README.md` |
| Official docs | [RHOAI 3.4](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/), [OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/) |

**Findings**

- [PASS] `kustomize build gitops/step-08-model-evaluation/base` rendered successfully.
- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope.
- [PASS] README contains pinned official product documentation references.
- [PASS] Managed or internal `:latest` image references are classified and accepted:
  - gitops/step-08-model-evaluation/base/eval-configs/job-copy-configs.yaml:25:          image: registry.access.redhat.com/ubi9/ubi-minimal:latest (Red Hat managed version stream)

**Schema Verification**

- [PASS] `oc apply --dry-run=server --validate=strict -f rendered.yaml` accepted rendered resources.
- [PASS] `oc explain Job --api-version=batch/v1`
- [PASS] `oc explain MLflowConfig --api-version=mlflow.kubeflow.org/v1`
- [PASS] `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain ConfigMap --api-version=v1`
- [PASS] `oc explain Secret --api-version=v1`

**rh-brain Research Sources**

- `rh-brain: raw/Breaking the RAG bottleneck Scalable document processing with Ray Data and Docling 1.md`
- `rh-brain: raw/Breaking the RAG bottleneck Scalable document processing with Ray Data and Docling.md`
- `rh-brain: raw/Evaluation Quickstart  MLflow AI Platform.md`
- `rh-brain: raw/Synthetic data for RAG evaluation Why your RAG system needs better testing.md`

### step-09-guardrails

| Field | Evidence |
|-------|----------|
| Status | `aligned` |
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

- [PASS] `oc apply --dry-run=server --validate=strict -f rendered.yaml` accepted rendered resources.
- [PASS] `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain NemoGuardrails --api-version=trustyai.opendatahub.io/v1alpha1`
- [PASS] `oc explain ConfigMap --api-version=v1`
- [PASS] `oc explain Secret --api-version=v1`
- [PASS] `oc explain ServiceAccount --api-version=v1`

**rh-brain Research Sources**

- `rh-brain: raw/Build resilient guardrails for OpenClaw AI agents on Kubernetes 1.md`
- `rh-brain: raw/Build resilient guardrails for OpenClaw AI agents on Kubernetes.md`

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
- [WARN] Unmanaged external `:latest` image references found:
  - gitops/step-11-face-recognition/base/workbench/workbench.yaml:65:          image: alpine/git:latest (unmanaged external dependency)

**Schema Verification**

- [PASS] `oc apply --dry-run=server --validate=strict -f rendered.yaml` accepted rendered resources.
- [PASS] `oc explain Job --api-version=batch/v1`
- [PASS] `oc explain Notebook --api-version=kubeflow.org/v1`
- [PASS] `oc explain Role --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain ServingRuntime --api-version=serving.kserve.io/v1alpha1`
- [PASS] `oc explain InferenceService --api-version=serving.kserve.io/v1beta1`
- [PASS] `oc explain PersistentVolumeClaim --api-version=v1`
- [PASS] `oc explain ServiceAccount --api-version=v1`

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
- [PASS] Managed or internal `:latest` image references are classified and accepted:
  - gitops/step-12-mlops-pipeline/base/trustyai-adapter/deployment.yaml:27:          image: registry.redhat.io/ubi9/python-312:latest (Red Hat managed version stream)

**Schema Verification**

- [WARN] Server dry-run reported existing PVC immutable spec drift, but the matching Argo CD app intentionally ignores PVC `/spec`.
  Exact warning:
  The PersistentVolumeClaim "face-pipeline-workspace" is invalid: spec: Forbidden: spec is immutable after creation except resources.requests and volumeAttributesClassName for bound claims
    core.PersistentVolumeClaimSpec{
        AccessModes:      {"ReadWriteOnce"},
        Selector:         nil,
        Resources:        {Requests: {s"storage": {i: {...}, s: "10Gi", Format: "BinarySI"}}},
  -     VolumeName:       "pvc-f1257313-8b0c-438b-878f-8d7217f4d929",
  +     VolumeName:       "",
        StorageClassName: &"gp3-csi",
        VolumeMode:       &"Filesystem",
        ... // 3 identical fields
    }

- [PASS] `oc explain Deployment --api-version=apps/v1`
- [PASS] `oc explain DataSciencePipelinesApplication --api-version=datasciencepipelinesapplications.opendatahub.io/v1`
- [PASS] `oc explain MLflowConfig --api-version=mlflow.kubeflow.org/v1`
- [PASS] `oc explain MLflow --api-version=mlflow.opendatahub.io/v1`
- [PASS] `oc explain ClusterRoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain Role --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain RoleBinding --api-version=rbac.authorization.k8s.io/v1`
- [PASS] `oc explain TrustyAIService --api-version=trustyai.opendatahub.io/v1`
- [PASS] `oc explain ConfigMap --api-version=v1`
- [PASS] `oc explain PersistentVolumeClaim --api-version=v1`
- [PASS] `oc explain Secret --api-version=v1`
- [PASS] `oc explain Service --api-version=v1`

**rh-brain Research Sources**

- `rh-brain: raw/Enhance LLMs and streamline MLOps using InstructLab and KitOps.md`
- `rh-brain: raw/Evaluating (Production) Traces  MLflow AI Platform 1.md`
- `rh-brain: raw/Evaluating (Production) Traces  MLflow AI Platform.md`
- `rh-brain: raw/From experiment to production A reliable architecture for version-controlled MLOps.md`

## Summary

| Result | Count |
|--------|-------|
| Blocking findings | 0 |
| Notes / deferred checks | 7 |

**Decision:** aligned. Notes and deferred checks may be handled as follow-up work.
