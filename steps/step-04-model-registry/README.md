# Step 04: Enterprise Model Governance

Implements the **Model Registry** as a governance layer for enterprise AI deployments. This step establishes the "Secure Gateway" pattern where only vetted, validated models are available for deployment.

---

## The Gatekeeper Pattern

In enterprise environments, developers should **not** pull models directly from the public internet (Hugging Face) into production. The Model Registry acts as the organization's "Secure Gateway":

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     The Gatekeeper Pattern                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────┐                                        ┌─────────────┐   │
│   │  Hugging    │     ╔════════════════════════╗         │ ai-developer│   │
│   │  Face       │     ║   MODEL REGISTRY       ║         │             │   │
│   │             │     ║   ════════════════     ║         │  ┌───────┐  │   │
│   │  ┌───────┐  │     ║                        ║         │  │ GenAI │  │   │
│   │  │ Public│  │     ║  ┌──────────────────┐  ║         │  │ Studio│  │   │
│   │  │ Models│──┼──X──║  │ Validated Models │  ║◀────────│  │       │  │   │
│   │  └───────┘  │     ║  │ ✓ Granite 3.1    │  ║         │  └───────┘  │   │
│   │             │     ║  │ ✓ Mistral 7B     │  ║         │             │   │
│   └─────────────┘     ║  │ ✓ Llama 3.1      │  ║         │  Discovers  │   │
│                       ║  └──────────────────┘  ║         │  models via │   │
│   ┌─────────────┐     ║                        ║         │  catalog    │   │
│   │  ai-admin   │     ║  Governance:           ║         │             │   │
│   │             │     ║  • Vetted by admin     ║         └─────────────┘   │
│   │  Downloads, │     ║  • Version tracked     ║                           │
│   │  validates, │─────║  • Hardware tagged     ║                           │
│   │  registers  │     ║  • Audit logged        ║                           │
│   │             │     ║                        ║                           │
│   └─────────────┘     ╚════════════════════════╝                           │
│                                                                             │
│   This prevents "Shadow AI" - unauthorized model usage in production        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Benefits:**
- **Governance**: Only models approved by `ai-admin` appear in the catalog
- **Versioning**: Track model updates without breaking existing applications
- **Discovery**: Developers find models in GenAI Studio, not external sources
- **Hardware Alignment**: Models are tagged with optimal hardware requirements

---

## May 2025 Red Hat Validated Collection

This step registers the **Granite 3.1 8B Instruct FP8** model from the Red Hat AI Validated Models collection:

| Property | Value |
|----------|-------|
| **Model** | `Granite-3.1-8b-Instruct-FP8` |
| **Version** | `3.1-May2025-Validated` |
| **Vendor** | IBM |
| **Quantization** | FP8-dynamic |
| **Hardware Target** | NVIDIA L4 (AWS G6) |
| **Serving Runtime** | vLLM |
| **Status** | Ready to Deploy |

> **Reference**: [Red Hat AI Validated Models - May 2025](https://huggingface.co/collections/RedHatAI/red-hat-ai-validated-models-may-2025)

The FP8 quantization is specifically optimized for NVIDIA L4 GPUs, providing:
- **50% memory reduction** vs FP16
- **2x faster inference** with minimal accuracy loss
- **Single GPU deployment** (fits in 16GB VRAM)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Model Registry Architecture                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────┐         ┌─────────────────┐         ┌─────────────┐  │
│   │   ai-admin      │         │  Model Registry │         │  GenAI      │  │
│   │   Workbench     │────────▶│                 │────────▶│  Studio     │  │
│   │                 │         │  private-ai-    │         │             │  │
│   │  ┌───────────┐  │         │  registry       │         │  ┌───────┐  │  │
│   │  │ Download  │  │         │                 │         │  │ Model │  │  │
│   │  │ & Validate│  │         │  ┌───────────┐  │         │  │Catalog│  │  │
│   │  │ Model     │  │         │  │ MariaDB   │  │         │  └───────┘  │  │
│   │  └───────────┘  │         │  │ Metadata  │  │         │             │  │
│   └─────────────────┘         │  └───────────┘  │         └─────────────┘  │
│                               └─────────────────┘                │         │
│                                       │                          │         │
│                                       ▼                          ▼         │
│                               ┌─────────────────┐         ┌─────────────┐  │
│                               │   MinIO S3      │         │  Step 05:   │  │
│                               │   (Artifacts)   │────────▶│  KServe     │  │
│                               │  models/        │         │  Inference  │  │
│                               └─────────────────┘         └─────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Demo Credentials

| Username | Password | Registry Access |
|----------|----------|-----------------|
| `ai-admin` | `redhat123` | Full access - register, archive, delete models |
| `ai-developer` | `redhat123` | Read-only - discover and deploy models |

---

## What Gets Installed

### Metadata Database (private-ai namespace)

| Resource | Name | Purpose |
|----------|------|---------|
| **Secret** | `model-registry-db-creds` | MariaDB credentials |
| **PVC** | `model-registry-db-pvc` | 5Gi persistent storage |
| **Deployment** | `model-registry-db` | MariaDB 10.11 |
| **Service** | `model-registry-db` | Port 3306 |

### Model Registry (rhoai-model-registries namespace)

| Resource | Name | Purpose |
|----------|------|---------|
| **Secret** | `private-ai-registry-db-creds` | DB connection |
| **ModelRegistry** | `private-ai-registry` | Registry instance (v1beta1) |
| **Job** | `model-registry-seed` | Register Granite 3.1 model |

### Registered Model

| Field | Value |
|-------|-------|
| **RegisteredModel** | `Granite-3.1-8b-Instruct-FP8` |
| **ModelVersion** | `3.1-May2025-Validated` |
| **ModelArtifact** | `s3://models/granite-3.1-8b-instruct-FP8-dynamic/` |
| **Status** | Ready to Deploy |

---

## Prerequisites

- [x] Step 01 completed (GPU infrastructure)
- [x] Step 02 completed (RHOAI 3.0 with ModelRegistry component)
- [x] Step 03 completed (MinIO for artifact storage)

---

## Deploy

```bash
./steps/step-04-model-registry/deploy.sh
```

The script will:
1. Deploy MariaDB database in `private-ai` namespace
2. Create ModelRegistry CR in `rhoai-model-registries`
3. Configure RBAC for ai-admin and ai-developer
4. Register the Granite 3.1 FP8 model (metadata only - no deployment)

---

## Validation Commands

### 1. Check Model Registry

```bash
# Verify ModelRegistry CR (v1beta1 API)
oc get modelregistry.modelregistry.opendatahub.io -n rhoai-model-registries

# Expected output:
# NAME                  AGE
# private-ai-registry   5m

# Check registry pods
oc get pods -n rhoai-model-registries | grep private-ai-registry
```

### 2. Check Database

```bash
# Verify MariaDB is running
oc get pods -n private-ai -l app=model-registry-db

# Check database connectivity
oc exec -n private-ai deployment/model-registry-db -- \
  mysql -u mlmd -pmlmd-secret-123 -e "SHOW DATABASES;"
```

### 3. Check Seed Job

```bash
# Verify seed job completed
oc get job model-registry-seed -n rhoai-model-registries

# Check logs - should show "Model Registration Complete"
oc logs job/model-registry-seed -n rhoai-model-registries
```

### 4. Verify in Dashboard

1. Login as `ai-admin` to RHOAI Dashboard
2. Go to **Settings** → **Model registries**
3. Click **private-ai-registry**
4. Verify **Granite-3.1-8b-Instruct-FP8** appears with version `3.1-May2025-Validated`

### 5. Verify in Model Catalog

1. Login as `ai-developer` to RHOAI Dashboard
2. Go to **GenAI Studio** → **AI Available Assets**
3. Find **Granite-3.1-8b-Instruct-FP8**
4. Status should show "Ready to Deploy"

---

## What This Prepares

### Step 05: Model Inference
The `ai-developer` will:
1. Find the model in **AI Available Assets**
2. Click **Deploy**
3. Select **Hardware Profile**: NVIDIA L4 1GPU
4. The S3 URI and metadata are automatically populated from the registry

### Step 06: AI Agents
Because we registered a "Validated" model:
- The **Agent Playground** shows this as a trusted endpoint
- RAG-enabled agents can reference this model directly
- Governance trail is maintained for compliance

---

## Registry vs. Catalog

| Component | Purpose | Location | Access |
|-----------|---------|----------|--------|
| **Model Registry** | Backend storage for metadata | Settings → Model registries | ai-admin |
| **Model Catalog** | Discovery UI for developers | GenAI Studio → AI Available Assets | ai-developer |

---

## Model Lifecycle Management

### Governance Workflow

```
1. DOWNLOAD           2. VALIDATE           3. REGISTER           4. DISCOVER
─────────────────────────────────────────────────────────────────────────────────

┌───────────────┐     ┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ ai-admin      │     │ ai-admin      │     │ Model         │     │ ai-developer  │
│               │     │               │     │ Registry      │     │               │
│ Downloads     │────▶│ Tests on L4   │────▶│               │────▶│ Finds model   │
│ from HF       │     │ Validates FP8 │     │ Registers     │     │ in Catalog    │
│               │     │               │     │ metadata      │     │               │
└───────────────┘     └───────────────┘     └───────────────┘     └───────────────┘

                                                     │
                                                     ▼
                                             ┌───────────────┐
                                             │ Step 05:      │
                                             │ Deploy to     │
                                             │ KServe        │
                                             └───────────────┘
```

### Archiving Models (Compliance)

When a model version is superseded or deprecated:

```bash
# Archive a model version (admin only)
# Models are soft-deleted for audit compliance
oc exec -n rhoai-model-registries deployment/private-ai-registry -- \
  curl -X PATCH "http://localhost:8080/api/model_registry/v1alpha3/model_versions/{VERSION_ID}" \
  -H "Content-Type: application/json" \
  -d '{"state": "ARCHIVED"}'
```

> **Note**: Archived models are hidden from the catalog but preserved for regulatory audit.

---

## Kustomize Structure

```
gitops/step-04-model-registry/
├── base/
│   ├── kustomization.yaml
│   │
│   ├── database/                    # MariaDB for metadata
│   │   ├── kustomization.yaml
│   │   ├── credentials-secret.yaml
│   │   ├── pvc.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   │
│   ├── registry/                    # ModelRegistry CR
│   │   ├── kustomization.yaml
│   │   ├── db-credentials-secret.yaml
│   │   └── model-registry.yaml
│   │
│   ├── rbac/                        # Access control
│   │   ├── kustomization.yaml
│   │   ├── registry-user-rolebinding.yaml
│   │   └── registry-admin-rolebinding.yaml
│   │
│   └── seed-job.yaml                # Register Granite 3.1 model
```

---

## Troubleshooting

### ModelRegistry Not Ready

```bash
# Check operator logs
oc logs -n redhat-ods-operator -l app=rhods-operator --tail=50

# Check ModelRegistry status
oc describe modelregistry.modelregistry.opendatahub.io private-ai-registry -n rhoai-model-registries
```

### Database Connection Failed

```bash
# Test database connectivity
oc exec -n private-ai deployment/model-registry-db -- \
  mysql -u mlmd -pmlmd-secret-123 -e "SELECT 1"

# Verify credentials match
oc get secret model-registry-db-creds -n private-ai -o jsonpath='{.data.database-password}' | base64 -d
oc get secret private-ai-registry-db-creds -n rhoai-model-registries -o jsonpath='{.data.database-password}' | base64 -d
```

### Seed Job Failed

```bash
# Check job logs
oc logs job/model-registry-seed -n rhoai-model-registries

# Re-run seed job
oc delete job model-registry-seed -n rhoai-model-registries
oc apply -f gitops/step-04-model-registry/base/seed-job.yaml
```

### Model Not Appearing in Catalog

```bash
# Verify registry is connected to dashboard
oc get modelregistry.modelregistry.opendatahub.io private-ai-registry -n rhoai-model-registries -o yaml

# Check for registered models via API
oc exec -n rhoai-model-registries deployment/private-ai-registry -- \
  curl -sf "http://localhost:8080/api/model_registry/v1alpha3/registered_models" | jq .
```

---

## Documentation Links

### Official Red Hat Documentation
- [Enabling Model Registry Component](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/enabling_the_model_registry_component/index)
- [Managing Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/managing_model_registries/index)
- [Working with Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/working_with_model_registries/index)

### Model Reference
- [Red Hat AI Validated Models - May 2025](https://huggingface.co/collections/RedHatAI/red-hat-ai-validated-models-may-2025)
- [Granite 3.1 8B Instruct FP8](https://huggingface.co/RedHatAI/granite-3.1-8b-instruct-FP8-dynamic)

---

## Summary

| Component | Purpose | Status |
|-----------|---------|--------|
| **MariaDB** | Metadata storage | ✅ Deployed |
| **ModelRegistry** | Registry instance | ✅ Deployed |
| **Granite 3.1 FP8** | Validated model | ✅ Registered |
| **Model Catalog** | Discovery UI | ✅ Populated |
| **KServe Deployment** | Inference endpoint | ⏳ Step 05 |

**This step establishes the "Model Warehouse":**
- ✅ Registry infrastructure deployed
- ✅ Database connected
- ✅ Granite model registered with governance metadata
- ⏳ Ready for Step 05: Deploy to inference endpoint
