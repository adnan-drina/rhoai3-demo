# Step 03: Private AI — GPU as a Service
**"Governed GPU-as-a-Service"** — Dynamic GPU allocation, S3 storage, quota enforcement, and role-based access control.

## Overview

At platform scale, private AI requires a **governance layer** — who may use GPUs, where artifacts live, and how roles are separated — so multi-tenant use stays **sovereign-ready** (data and workloads remain under your operational control). **Red Hat OpenShift AI 3.3** supplies self-service GPU access, quota management, and priority scheduling through Hardware Profiles, alongside OpenShift-native RBAC and integrated S3-style storage that separate Service Governors from Service Consumers.

This step demonstrates RHOAI's **Intelligent GPU and hardware speed** capability — quota management, priority access, and visibility of use through hardware profiles — with governance that scales from a single team to an entire organization.

### What Gets Deployed

```text
Private AI Infrastructure
├── MinIO                → S3-compatible storage (models, pipelines, workbench data)
├── MinIO API Route      → External S3 endpoint for DSPA artifact preview
├── Authentication       → HTPasswd identity provider (ai-admin, ai-developer)
├── RBAC                 → Role bindings for Governor / Consumer personas
├── Data Connection      → Auto-appears in Dashboard dropdowns
└── Namespace (private-ai) → Shared project for all AI workloads
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **MinIO** | S3-compatible storage (models, pipelines, workbench data) | `minio-storage` |
| **MinIO API Route** | External S3 endpoint — enables DSPA artifact preview in Dashboard | `minio-storage` |
| **Auth** | HTPasswd: `ai-admin` / `ai-developer` (password: `redhat123`) | cluster-scoped |
| **RBAC** | `ai-admin` → admin role, `ai-developer` → edit role | `private-ai` |
| **Data Connection** | Auto-appears in Dashboard dropdowns for workbenches and model serving | `private-ai` |

Manifests: [`gitops/step-03-private-ai/base/`](../../gitops/step-03-private-ai/base/)

#### Platform Features

| | Feature | Status |
|---|---|---|
| RHOAI | Intelligent GPU and hardware speed (GPU-as-a-Service) | Used |
| OCP | Authentication and Authorization (OAuth, RBAC) | Introduced |

<details>
<summary>Design Decisions</summary>

> **Direct GPU scheduling (no Kueue):** Kueue was evaluated and removed because its SchedulingGate mechanism gates ALL pods in managed namespaces — including build pods, DSPA pipeline executors, and chatbot Deployments — not just GPU workloads. GPU scheduling uses direct `nodeSelector` + `tolerations` defined in Hardware Profiles and InferenceService manifests. This provides reliable GPU placement without the SchedulingGate side effects.

> **OpenShift Groups created by `deploy.sh`:** Groups are created at deploy time (not via ArgoCD) because ArgoCD cannot parse the `user.openshift.io/v1 Group` schema.

> **No `opendatahub.io/managed` label on `storage-config`:** The ODH model controller watches for secrets with `opendatahub.io/managed: "true"` and deletes any it did not create. Since ArgoCD creates `storage-config`, the controller deletes it within seconds, causing an infinite create-delete loop. This label is only needed on `minio-connection` (the Data Connection that appears in Dashboard dropdowns), not on `storage-config` (the KServe credential used by storage-initializer). See also: `.cursor/rules/30-secrets-and-certs.mdc`.

</details>

<details>
<summary>Deploy</summary>

```bash
./steps/step-03-private-ai/deploy.sh     # ArgoCD app: MinIO + auth + RBAC + data connections
./steps/step-03-private-ai/validate.sh   # Verify storage, auth, RBAC, groups
```

</details>

<details>
<summary>What to Verify After Deployment</summary>

| Check | What It Tests | Pass Criteria |
|-------|--------------|---------------|
| MinIO ready | Deployment available | 1 replica running in `minio-storage` |
| Data connections | `minio-connection` + `storage-config` secrets | Both present in `private-ai` |
| Authentication | HTPasswd identity provider | Provider registered in OAuth |
| RBAC | Role bindings for ai-admin and ai-developer | Both present in `private-ai` |
| Groups | `rhoai-admins` and `rhoai-users` | ai-admin in rhoai-admins, ai-developer in rhoai-users |

</details>

## The Demo

> In this demo, we show the GPU-as-a-Service model in action — a data scientist self-serves a GPU workbench, a platform admin monitors resource utilization, and shared S3 storage is pre-configured for every AI workflow.

### The Service Consumer Experience

> A data scientist needs a GPU-enabled notebook to experiment with a model. On a traditional platform, this means filing a ticket and waiting days. On RHOAI, they select a Hardware Profile and start working in minutes.

1. Log in as `ai-developer` (`redhat123`) in the RHOAI Dashboard
2. Go to **Data Science Projects** → **private-ai**
3. Create a **Workbench** → select Hardware Profile **"NVIDIA L4 1GPU"**
4. Under Data Connection, **"MinIO Storage"** appears automatically
5. Click **Create** → workbench starts, scheduled to GPU node

**Expect:** The workbench is created and scheduled to a GPU node matching the selected Hardware Profile. The S3 data connection is pre-configured with no manual credential setup.

> The developer selects a GPU profile from a curated list — the Hardware Profile's nodeSelector targets the right GPU node type automatically. The S3 storage is pre-configured. No tickets, no waiting, no credentials to hunt for. This is self-service GPU access on Red Hat OpenShift AI.

### The Service Governor View

> While data scientists consume GPU resources, the platform team needs visibility into utilization and capacity. The admin role provides monitoring access without giving developers infrastructure-level permissions.

1. Log in as `ai-admin` (`redhat123`) in the RHOAI Dashboard
2. Go to **Observe & monitor** → **Workload metrics**
3. Select project **private-ai**
4. Check node capacity:

```bash
oc describe node -l nvidia.com/gpu.present=true
```

**Expect:** GPU utilization metrics visible in the Dashboard. Node descriptions show GPU allocatable capacity and current usage.

> The platform admin monitors GPU utilization and node capacity from a single pane. Hardware Profiles ensure workloads land on the correct GPU node type — no accidental scheduling, no resource conflicts between teams. Governance and self-service, working together.

### MinIO Storage Console

> Every AI workflow needs shared storage — model weights, pipeline artifacts, training data. MinIO provides S3-compatible storage that integrates natively with RHOAI data connections.

1. Get the MinIO console URL:

```bash
MINIO_URL=$(oc get route minio-console -n minio-storage -o jsonpath='{.spec.host}')
echo "https://${MINIO_URL}"
```

2. Log in: `minio-admin` / `minio-secret-123`
3. Browse the buckets: `rhoai-storage`, `models`, `pipelines`

**Expect:** Three pre-created buckets visible in the MinIO console — these are where all subsequent steps store their data.

> Shared S3 storage, pre-configured data connections, and role-based access — the platform is ready for any AI workload. Every step that follows inherits this storage layer automatically.

## Key Takeaways

**For business stakeholders:**

- Run AI with more control in regulated and sovereignty-sensitive environments
- Separate access to GPUs, data, and projects by role
- Keep shared AI capacity usable without turning it into a free-for-all

**For technical teams:**

- Add multitenancy, RBAC, and shared object storage to the AI platform
- Enforce who can use GPUs and where artifacts live
- Make private AI operational with identity, quotas, and governed access patterns

<details>
<summary>Troubleshooting</summary>

### MinIO init job fails or minio-connection secret missing

**Symptom:** `minio-init` job shows `Failed` or `minio-connection` secret not found in `private-ai`.

**Root Cause:** MinIO pod not ready when init job runs (race condition with `WaitForFirstConsumer` PVC binding).

**Solution:** Wait for MinIO pod to be ready, then recreate the job:
```bash
oc wait deploy/minio -n minio-storage --for=condition=Available --timeout=180s
oc delete job minio-init -n minio-storage 2>/dev/null
oc apply -f gitops/step-03-private-ai/base/minio/init-job.yaml
```

### storage-config secret disappears after ArgoCD sync

**Symptom:** `storage-config` secret is deleted shortly after ArgoCD creates it.

**Root Cause:** The `opendatahub.io/managed: "true"` label was set on the secret. The ODH model controller watches for this label and deletes secrets it didn't create.

**Solution:** Remove the label from the manifest. See Design Decisions section for details.

### ArgoCD OutOfSync on operator-managed resources

**Symptom:** Step-03 ArgoCD app shows OutOfSync but health is Healthy.

**Root Cause:** Operators (OLM, OAuth) mutate secrets and ConfigMaps with additional annotations/fields. ArgoCD detects this as drift.

**Solution:** The ArgoCD Application includes `ignoreDifferences` for Secret `/data` and operator-managed annotations. If drift persists, check the ArgoCD diff view for the specific field and add it to `ignoreDifferences`.

</details>

## References

- [RHOAI 3.3 — Managing Resources](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/managing_resources/index)
- [RHOAI 3.3 — User Management](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_users/index)
- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet)
- [Get started with AI for enterprise organizations — Red Hat](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)

## Next Steps

- **Step 04**: [Model Registry & Model Catalog](../step-04-model-registry/README.md) — Enterprise model governance with a curated catalog and versioned registry
