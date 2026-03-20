# Step 04: Model Registry & Model Catalog

**Enterprise model governance — discover from the Catalog, govern through the Registry.**

## The Business Story

RHOAI 3.3 provides two complementary model management capabilities. The **Model Catalog** is a curated library of 48+ Red Hat-validated models in OCI ModelCar format — ready to deploy with a click. The **Model Registry** is where your organization tracks versions, ownership, and approval status of models before they reach production. Together they form a governed pipeline: discover in the Catalog, register for governance, deploy from either.

## What It Does

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

## Demo Walkthrough

> **Credentials:** `ai-admin` / `redhat123` · `ai-developer` / `redhat123`

### Scene 1 — Model Catalog (48+ Validated Models)

**Do:** Log in as `ai-developer`. Navigate to **GenAI Studio → AI Available Assets**.

**Expect:** A catalog page showing 48+ pre-bundled models grouped by provider — IBM Granite, Meta Llama, Mistral, Qwen, phi-4, DeepSeek, Gemma. Each card shows parameter count, license, and recommended hardware.

*"Out of the box, RHOAI ships a curated catalog of over 48 validated models in OCI ModelCar format. These are Red Hat-tested — you know they'll run on your hardware. You can deploy directly from the catalog using the cluster's pull secret — no HuggingFace account needed."*

### Scene 2 — Registered Model (Granite 3.1 8B from Seed Job)

**Do:** Switch to `ai-admin`. Navigate to **Settings → Model registries → private-ai-registry**.

**Expect:** The Granite 3.1 8B Instruct FP8 model appears — registered by the automated seed job during deployment.

*"The catalog is for discovery. The registry is for governance. Here, the admin team has registered Granite with version metadata, owner, and an artifact path pointing to our internal S3. This is the audit trail — who approved what, when, and where it's stored."*

### Scene 3 — Access Control (ai-admin vs ai-developer)

**Do:** In the `ai-admin` session, show registry management — register, archive, delete. Switch to `ai-developer` — read-only view.

*"Admins control what enters the registry. Developers consume only what's been vetted. No Shadow AI."*

## What to Verify After Deployment

```bash
# MariaDB running
oc get pods -n rhoai-model-registries -l app=model-registry-db --no-headers
# Expected: 1 pod Running

# ModelRegistry CR
oc get modelregistry private-ai-registry -n rhoai-model-registries -o jsonpath='{.metadata.name}'
# Expected: private-ai-registry

# Registry pods running
oc get pods -n rhoai-model-registries -l app=private-ai-registry --no-headers
# Expected: at least 1 Running

# Seed job completed
oc get job model-registry-seed -n rhoai-model-registries -o jsonpath='{.status.succeeded}'
# Expected: 1 (may be cleaned up by TTL)

# Internal service
oc get svc private-ai-registry-internal -n rhoai-model-registries
# Expected: service exists on port 8080
```

Or run the validation script:

```bash
./steps/step-04-model-registry/validate.sh
```

## Design Decisions

> **Model Catalog for discovery, Registry for governance:** The Catalog provides 48+ OCI-ready models for rapid deployment. The Registry adds custom metadata, versioning, and RBAC. In production, the ideal flow is: discover in Catalog → register for governance → deploy from Registry. Our demo uses OCI ModelCar for small models (Granite 8B FP8, Mistral INT4) pulled directly from the Red Hat Registry, and S3/MinIO for large BF16 models (>20GB) where OCI image layers may hit CRI-O overlay limits. Ref: [Working with the Model Catalog](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_the_model_catalog/).

> **External MariaDB instead of embedded:** Explicit PVC control and simpler backup/restore for the demo.

> **Internal service on port 8080:** Bypasses OAuth so Kubernetes Jobs can seed models without token negotiation.

> **PVC sync wave aligned with consumer:** The MariaDB PVC (`model-registry-db-pvc`) uses sync wave `"2"` — the same wave as the MariaDB Deployment. With `WaitForFirstConsumer` storage class, a PVC in an earlier wave than its consumer creates a deadlock: ArgoCD waits for the PVC to become Healthy (Bound), but binding requires a pod to schedule, and the pod is in a later wave that hasn't started. Placing both in the same wave eliminates this.

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

## Operations

```bash
./steps/step-04-model-registry/deploy.sh      # Deploy registry, MariaDB, RBAC, seed job
./steps/step-04-model-registry/validate.sh     # Verify CR status, seed job, API health
```

## Next Steps

Proceed to **[Step 05: LLM Serving on vLLM](../step-05-llm-on-vllm/README.md)** — deploy models as live inference endpoints and validate in the GenAI Playground.
