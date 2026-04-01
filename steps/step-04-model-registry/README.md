# Step 04: Model Registry & Model Catalog
**"Discover and Govern"** — Enterprise model governance — discover from the Catalog, govern through the Registry.

## Overview

With GPU infrastructure, the AI platform, and access controls in place, organizations need a governed approach to model management. As Red Hat's AI adoption guide observes, *"enterprises are adopting a multimodel approach, using multiple specialized models rather than one monolithic system"* — which makes governance essential. Without it, teams download models from external sources, track versions in spreadsheets, and deploy unvetted artifacts to production — creating shadow AI that no one can audit. *"Without visibility into the datasets that created the model or an understanding of how the model uses that data, organizations are exposed to potential risks related to AI-generated content."* Finding the right model matters: *"The right model is the smallest one that meets your accuracy requirements and has been optimized for your infrastructure."*

**Red Hat OpenShift AI 3.3** provides two complementary model management capabilities. The **Model Catalog** is a curated library of 48+ Red Hat-validated models in OCI ModelCar format — ready to deploy with a click and no external dependencies. The **Model Registry** tracks versions, ownership, and approval status of models before they reach production. Together they provide *"centralized management for predictive and gen AI models and MCP servers and their metadata, and artifacts"* — discover in the Catalog, register for governance, deploy from either.

This step demonstrates the **Operationalized AI** use case of the Red Hat AI platform: centralized management for AI models, their metadata and artifacts — ensuring that the same governed model lifecycle works across any OpenShift cluster.

### What Gets Deployed

```text
Model Governance
├── Model Catalog         → 48+ Red Hat-validated models (OCI ModelCar)
├── Model Registry        → Custom governance: versions, owners, approval status
├── MariaDB 10.11         → Registry metadata storage (5 Gi PVC)
├── Internal Service      → Unauthenticated endpoint for seed job automation
├── RBAC                  → ai-admin = full control, ai-developer = read-only
└── Seed Job              → Registers initial models on first deploy
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **Model Catalog** | 48+ Red Hat-validated models (OCI ModelCar), browse in GenAI Studio | platform-wide |
| **Model Registry** (`private-ai-registry`) | Custom governance: versions, owners, approval status | `rhoai-model-registries` |
| **MariaDB 10.11** | Registry metadata storage (5 Gi PVC) | `rhoai-model-registries` |
| **Internal Service** (`:8080`) | Unauthenticated endpoint for seed job automation | `rhoai-model-registries` |
| **RBAC** | `ai-admin` = full control, `ai-developer` = read-only | `rhoai-model-registries` |
| **Seed Job** | Registers initial models on first deploy | `rhoai-model-registries` |

Manifests: [`gitops/step-04-model-registry/base/`](../../gitops/step-04-model-registry/base/)

### Design Decisions

> **Model Catalog for discovery, Registry for governance:** The Catalog provides 48+ OCI-ready models for rapid deployment. The Registry adds custom metadata, versioning, and RBAC. In production, the ideal flow is: discover in Catalog → register for governance → deploy from Registry. Our demo uses OCI ModelCar for small models (Granite 8B FP8, Mistral INT4) pulled directly from the Red Hat Registry, and S3/MinIO for large BF16 models (>20GB) where OCI image layers may hit CRI-O overlay limits. Ref: [Working with the Model Catalog](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_the_model_catalog/).

> **External MariaDB instead of embedded:** Explicit PVC control and simpler backup/restore for the demo.

> **Internal service on port 8080:** Bypasses OAuth so Kubernetes Jobs can seed models without token negotiation.

> **PVC sync wave aligned with consumer:** The MariaDB PVC (`model-registry-db-pvc`) uses sync wave `"2"` — the same wave as the MariaDB Deployment. With `WaitForFirstConsumer` storage class, a PVC in an earlier wave than its consumer creates a deadlock: ArgoCD waits for the PVC to become Healthy (Bound), but binding requires a pod to schedule, and the pod is in a later wave that hasn't started. Placing both in the same wave eliminates this.

### Deploy

```bash
./steps/step-04-model-registry/deploy.sh      # ArgoCD app: registry + MariaDB + RBAC + seed job
./steps/step-04-model-registry/validate.sh     # Verify CR status, seed job, API health
```

### What to Verify After Deployment

| Check | What It Tests | Pass Criteria |
|-------|--------------|---------------|
| MariaDB running | Registry metadata storage | 1 pod Running in `rhoai-model-registries` |
| ModelRegistry CR | `private-ai-registry` resource | CR exists |
| Registry pods | Application pods running | At least 1 Running |
| Seed job | Initial model registration | Succeeded (may be cleaned up by TTL) |
| Internal service | Unauthenticated endpoint | `private-ai-registry-internal` on port 8080 |

## The Demo

> In this demo, we explore both sides of model governance — the Model Catalog for discovery and the Model Registry for lifecycle management. We see 48+ validated models ready to deploy, a registered model with version metadata, and role-based access that separates model administrators from consumers.

**Credentials:** `ai-admin` / `redhat123` · `ai-developer` / `redhat123`

### Model Catalog — 48+ Validated Models

> Before teams can serve models, they need to find them. The Model Catalog provides a curated library of Red Hat-validated models — tested against the platform, available with no external dependencies.

1. Log in as `ai-developer`
2. Navigate to **GenAI Studio → AI Available Assets**

**Expect:** A catalog page showing 48+ pre-bundled models grouped by provider — IBM Granite, Meta Llama, Mistral, Qwen, phi-4, DeepSeek, Gemma. Each card shows parameter count, license, and recommended hardware.

> Over 48 models in OCI ModelCar format, ready to deploy with the cluster's pull secret. No HuggingFace account needed, no external downloads, no supply chain concerns. This is Red Hat OpenShift AI's curated model catalog — the starting point for any AI project.

### Registered Model — Granite 3.1 8B

> The Catalog is for discovery. The Registry is for governance. When a model is approved for production use, it gets registered with version metadata, ownership, and an artifact path — creating the audit trail that compliance teams require.

1. Switch to `ai-admin`
2. Navigate to **Settings → Model registries → private-ai-registry**

**Expect:** The Granite 3.1 8B Instruct FP8 model appears — registered by the automated seed job during deployment.

> The admin team has registered Granite with version metadata, owner, and an artifact path pointing to internal S3. This is the audit trail — who approved what, when, and where it's stored. Every model in production should pass through this registry.

### Access Control — Admin vs Developer

> Model governance requires separation of duties. Administrators control what enters the registry. Developers consume only what has been vetted — no shadow AI, no untracked models in production.

1. In the `ai-admin` session, show registry management — register, archive, delete
2. Switch to `ai-developer` — observe read-only view

**Expect:** `ai-admin` has full registry management capabilities. `ai-developer` sees the same models but cannot register, modify, or delete — read-only access.

> Admins control what enters the registry. Developers consume only what has been vetted. This separation of duties — built into the platform with OpenShift RBAC — is how organizations prevent shadow AI and maintain model governance at scale.

## Key Takeaways

**For business stakeholders:**

- The Model Catalog provides 48+ Red Hat-validated models out of the box — no procurement, no license negotiation, no external dependencies
- The Model Registry provides an auditable record of who approved which model, when, and where it is stored — essential for compliance
- Role-based access ensures only vetted models reach production — no shadow AI
- *"Red Hat has always believed in the power of open source to propel innovation, and a transparent approach to software development that gives customers control over the choices they make."* That same philosophy now extends to AI — and the Model Catalog is where it starts

**For technical teams:**

- Model Catalog uses OCI ModelCar format — models pull through the cluster's existing container pull secret, no separate model download infrastructure
- The Registry is backed by MariaDB with explicit PVC control — simple backup, restore, and GitOps lifecycle
- Seed jobs automate initial model registration via the internal service on port 8080 — no OAuth token negotiation needed

## Troubleshooting

### MariaDB pod stuck in Pending

**Symptom:** `model-registry-db` pod is Pending with `unbound immediate PersistentVolumeClaims`.

**Root Cause:** PVC is in an earlier sync wave than the Deployment. With `WaitForFirstConsumer` storage class, the PVC cannot bind without a consuming pod.

**Solution:** Both PVC and Deployment are now in sync wave `"2"`. If the issue recurs, verify:
```bash
oc get pvc model-registry-db-pvc -n rhoai-model-registries -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/sync-wave}'
# Expected: "2"
```

### Seed job fails with connection refused

**Symptom:** `model-registry-seed` job logs show `Connection refused` to the registry internal service.

**Root Cause:** Registry pods not yet ready when the seed job runs.

**Solution:** The seed job retries. If it exhausts retries, wait for registry pods to be Running and recreate:
```bash
oc wait pods -l app=private-ai-registry -n rhoai-model-registries --for=condition=Ready --timeout=120s
oc delete job model-registry-seed -n rhoai-model-registries
oc apply -f gitops/step-04-model-registry/base/seed-job.yaml
```

### Model Registry not visible in Dashboard

**Symptom:** Model Registry doesn't appear in RHOAI Dashboard under Settings.

**Root Cause:** The `modelregistry` component may not be `Managed` in the DataScienceCluster.

**Solution:**
```bash
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.modelregistry.managementState}'
# Expected: Managed
```

## References

- [Working with the Model Catalog](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_the_model_catalog/)
- [Deploying a Model from the Catalog](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_the_model_catalog/deploying-a-model-from-the-model-catalog_working-model-catalog)
- [Working with Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/working_with_model_registries/working_with_model_registries)
- [Managing Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/managing_model_registries/index)
- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet)
- [Get started with AI for enterprise organizations — Red Hat](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)

## Next Steps

- **Step 05**: [LLM Serving on vLLM](../step-05-llm-on-vllm/README.md) — Deploy models as live inference endpoints and validate in the GenAI Playground
