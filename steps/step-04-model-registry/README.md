# Step 04: Model Registry & Model Catalog

**Enterprise model governance — discover from the Catalog, govern through the Registry.**

## The Business Story

RHOAI 3.3 provides two complementary model management capabilities. The **Model Catalog** is a curated library of 48+ Red Hat-validated models in OCI ModelCar format — ready to deploy with a click. The **Model Registry** is where your organization tracks versions, ownership, and approval status of models before they reach production. Together they form a governed pipeline: discover in the Catalog, register for governance, deploy from either.

## What It Does

```
  Model Catalog (48+ models)          Model Registry (governance)
  ┌────────────────────────┐          ┌────────────────────────┐
  │ IBM Granite             │  deploy  │ ✓ Granite 3.1 8B FP8  │
  │ Meta Llama              │◄────────▶│ ✓ Mistral 24B         │
  │ Mistral, Qwen, Gemma   │ register │   version, owner,     │
  │ OCI ModelCar format     │          │   S3/OCI artifact path │
  └────────────────────────┘          └────────────────────────┘
         │                                      │
         ▼                                      ▼
  Deploy directly (OCI pull)          Deploy from registry
  via global cluster pull secret      via S3 or OCI reference
```

| Component | Purpose |
|-----------|---------|
| **Model Catalog** | 48+ Red Hat-validated models (OCI ModelCar), browse in GenAI Studio |
| **Model Registry** (`private-ai-registry`) | Custom governance: versions, owners, approval status |
| **MariaDB 10.5** | Registry metadata storage (5 Gi PVC) |
| **Internal Service** (`:8080`) | Unauthenticated endpoint for seed job automation |
| **RBAC** | `ai-admin` = full control, `ai-developer` = read-only |
| **Seed Job** | Registers Granite 3.1 8B Instruct FP8 on first deploy |

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

## Design Decisions

> **Model Catalog for discovery, Registry for governance:** The Catalog provides 48+ OCI-ready models for rapid deployment. The Registry adds custom metadata, versioning, and RBAC. In production, the ideal flow is: discover in Catalog → register for governance → deploy from Registry. Our demo currently uses S3/HuggingFace for Granite — migrating to OCI ModelCar from the Catalog is a future improvement. Ref: [Working with the Model Catalog](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_the_model_catalog/).

> **External MariaDB instead of embedded:** Explicit PVC control and simpler backup/restore for the demo.

> **Internal service on port 8080:** Bypasses OAuth so Kubernetes Jobs can seed models without token negotiation.

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
