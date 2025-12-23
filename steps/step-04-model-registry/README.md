# Step 04: Model Registry & Governance

Implements centralized model versioning, metadata management, and lifecycle tracking using RHOAI 3.0 Model Registry.

---

## Overview

Model Registry provides the **governance layer** for ML models:
- **Version Control**: Track model versions and lineage
- **Metadata Management**: Store parameters, metrics, and artifact references
- **Lifecycle Management**: Promote models through dev → staging → production
- **One-Click Deployment**: Deploy directly to KServe using Hardware Profiles

---

## Registry vs. Catalog

| Component | Purpose | Location |
|-----------|---------|----------|
| **Model Registry** | Backend storage for model metadata and versions | Settings → Model registries |
| **Model Catalog** | Discovery interface in GenAI Studio | AI Available Assets |

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Registry vs. Catalog                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                    Model Registry (Backend)                         │  │
│   │  • Stores versions, metadata, artifact URIs                         │  │
│   │  • REST/gRPC API for programmatic access                           │  │
│   │  • MariaDB for metadata, S3 for artifacts                          │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│                                    ▼                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                    Model Catalog (Frontend)                         │  │
│   │  • GenAI Studio "AI Available Assets"                               │  │
│   │  • Browse, search, filter models                                    │  │
│   │  • One-click Deploy button                                          │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Model Registry Architecture                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────┐         ┌─────────────────┐         ┌─────────────┐  │
│   │   Data Science  │────────▶│  Model Registry │────────▶│   KServe    │  │
│   │   Workbench     │         │                 │         │   Model     │  │
│   │                 │         │  private-ai-    │         │   Serving   │  │
│   │  ┌───────────┐  │         │  registry       │         │             │  │
│   │  │ Train &   │  │         │                 │         │  ┌───────┐  │  │
│   │  │ Export    │  │         │  ┌───────────┐  │         │  │ vLLM  │  │  │
│   │  │ Model     │  │         │  │ MariaDB   │  │         │  │ TGI   │  │  │
│   │  └───────────┘  │         │  │ Metadata  │  │         │  └───────┘  │  │
│   └─────────────────┘         │  └───────────┘  │         └─────────────┘  │
│                               └─────────────────┘                          │
│                                       │                                     │
│                                       ▼                                     │
│                               ┌─────────────────┐                          │
│                               │   MinIO S3      │                          │
│                               │   (Artifacts)   │                          │
│                               │  models/        │                          │
│                               └─────────────────┘                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Demo Credentials

| Username | Password | Registry Access |
|----------|----------|-----------------|
| `ai-admin` | `redhat123` | Full access (archive/delete) |
| `ai-developer` | `redhat123` | Register and deploy models |

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

> **Note**: The `rhoai-model-registries` namespace is managed by the ModelRegistry operator. All registry instances are deployed there automatically.

| Resource | Name | Purpose |
|----------|------|---------|
| **Secret** | `private-ai-registry-db-creds` | DB connection |
| **ModelRegistry** | `private-ai-registry` | Registry instance (v1beta1 API) |
| **Job** | `model-registry-seed` | Pre-populate demo model |

### RBAC

| Resource | Subjects | Access Level |
|----------|----------|--------------|
| `ai-admin-registry-admin` | ai-admin, rhoai-admins | Full access |
| `ai-developer-registry-user` | ai-developer, rhoai-users | Register/deploy |

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
2. Create ModelRegistry CR in `redhat-ods-applications`
3. Configure RBAC for ai-admin and ai-developer
4. Run seed job to register demo model (Granite-7b-Inference)

---

## Validation Commands

### 1. Check Model Registry

```bash
# Verify ModelRegistry CR (uses v1beta1 API)
oc get modelregistry.modelregistry.opendatahub.io -n rhoai-model-registries

# Expected output:
# NAME                  AGE
# private-ai-registry   5m

# Check registry pods
oc get pods -n rhoai-model-registries | grep private-ai-registry

# Check HTTPS route (authenticated via kube-rbac-proxy)
oc get route -n rhoai-model-registries | grep private-ai-registry
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

# Check logs
oc logs job/model-registry-seed -n rhoai-model-registries
```

### 4. Access Registry via Dashboard

The Model Registry uses kube-rbac-proxy for authentication, so direct API access requires OpenShift tokens.

**Recommended**: Access via RHOAI Dashboard:
1. Go to **Settings** → **Model registries**
2. Click **private-ai-registry**
3. View registered models and versions

---

## Demo Walkthrough

### 1. View Model Catalog

1. Login as `ai-developer` to RHOAI Dashboard
2. Go to **GenAI Studio** → **AI Available Assets**
3. See **Granite-7b-Inference** model (seeded by job)

### 2. Deploy Model from Registry

1. Click on **Granite-7b-Inference**
2. Click **Deploy** button
3. Select **Hardware Profile**: "NVIDIA L4 1GPU"
4. Select **Data Connection**: "MinIO Storage"
5. Click **Deploy**

### 3. View Registry Details (Admin)

1. Login as `ai-admin` to RHOAI Dashboard
2. Go to **Settings** → **Model registries**
3. Click on **private-ai-registry**
4. View model versions, metadata, and deployment history

---

## Model Lifecycle Management

### Registering a Model

```python
# From a Workbench using the Python SDK
from model_registry import ModelRegistry

registry = ModelRegistry(
    server_address="private-ai-registry-rest.redhat-ods-applications.svc:8080",
    author="ai-developer"
)

# Register model
registered_model = registry.register_model(
    name="my-custom-model",
    description="Fine-tuned model for specific task",
    owner="ai-developer"
)

# Create version
version = registry.register_model_version(
    registered_model=registered_model,
    name="v1.0",
    uri="s3://models/my-custom-model/v1.0/"
)
```

### Archiving a Model (Compliance)

For regulatory compliance, models can be archived (soft-delete):

```bash
# Archive a model version (admin only)
REGISTRY_URL="http://private-ai-registry-rest.redhat-ods-applications.svc:8080"

curl -X PATCH "${REGISTRY_URL}/api/model_registry/v1alpha3/model_versions/{VERSION_ID}" \
  -H "Content-Type: application/json" \
  -d '{"state": "ARCHIVED"}'
```

> **Note**: Archived models are hidden from the catalog but preserved for audit purposes.

---

## Deployment Handover

RHOAI 3.0 enables **one-click deployment** from registry to KServe:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Deployment Handover Flow                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   1. MODEL CATALOG            2. DEPLOY WIZARD           3. KSERVE         │
│   ─────────────────────────────────────────────────────────────────────     │
│                                                                             │
│   ┌─────────────────┐         ┌─────────────────┐         ┌─────────────┐  │
│   │ Granite-7b      │─────────│ Select:         │─────────│ Inference   │  │
│   │                 │  Click  │ • Hardware      │  Auto   │ Service     │  │
│   │ [Deploy]        │  ────▶  │   Profile       │  ────▶  │ Created     │  │
│   │                 │         │ • Data Conn     │         │             │  │
│   │                 │         │ • Serving RT    │         │ Status:     │  │
│   │                 │         │                 │         │ ✓ Running   │  │
│   └─────────────────┘         └─────────────────┘         └─────────────┘  │
│                                                                             │
│   Uses: Hardware Profiles from Step 02                                      │
│         Data Connections from Step 03                                       │
│         Kueue quotas for GPU allocation                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

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
│   │   ├── s3-credentials-secret.yaml
│   │   └── model-registry.yaml
│   │
│   ├── rbac/                        # Access control
│   │   ├── kustomization.yaml
│   │   ├── registry-user-rolebinding.yaml
│   │   └── registry-admin-rolebinding.yaml
│   │
│   └── seed-job.yaml                # Demo model registration
```

---

## Troubleshooting

### ModelRegistry Not Ready

```bash
# Check operator logs
oc logs -n redhat-ods-operator -l app=rhods-operator --tail=50

# Check ModelRegistry status (v1beta1 API)
oc describe modelregistry.modelregistry.opendatahub.io private-ai-registry -n rhoai-model-registries
```

### Database Connection Failed

```bash
# Test database connectivity
oc exec -n private-ai deployment/model-registry-db -- \
  mysql -u mlmd -pmlmd-secret-123 -e "SELECT 1"

# Check secret values match
oc get secret model-registry-db-creds -n private-ai -o yaml
oc get secret private-ai-registry-db-creds -n redhat-ods-applications -o yaml
```

### Seed Job Failed

```bash
# Check job logs
oc logs job/model-registry-seed -n rhoai-model-registries

# Re-run seed job
oc delete job model-registry-seed -n rhoai-model-registries
oc apply -f gitops/step-04-model-registry/base/seed-job.yaml
```

### RBAC Issues

```bash
# Verify role bindings
oc get rolebindings -n rhoai-model-registries | grep registry

# Check user permissions
oc auth can-i get modelregistries -n rhoai-model-registries --as=ai-developer
```

---

## Documentation Links

### Official Red Hat Documentation
- [Enabling Model Registry Component](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/enabling_the_model_registry_component/index)
- [Managing Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/managing_model_registries/index)
- [Working with Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/working_with_model_registries/index)
- [Managing Permissions](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/managing_model_registries/index#managing-model-registry-permissions_model-reg)

---

## Summary

| Component | Purpose | Managed By |
|-----------|---------|------------|
| **MariaDB** | Metadata storage | ArgoCD |
| **ModelRegistry CR** | Registry instance | RHOAI Operator |
| **Seed Job** | Demo model registration | ArgoCD Hook |
| **RBAC** | Access control | ArgoCD |

**The Model Registry Flow:**
1. **Train** → Export model from workbench to MinIO
2. **Register** → Add model metadata to registry
3. **Version** → Track iterations and lineage
4. **Deploy** → One-click to KServe via Hardware Profile
5. **Monitor** → Track deployments and usage
6. **Archive** → Soft-delete for compliance
