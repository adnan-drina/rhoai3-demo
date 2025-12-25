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
│   │             │     ║  │ ✓ Llama 3.3/4    │  ║         │             │   │
│   └─────────────┘     ║  │ ✓ Mistral 24B    │  ║         │  Discovers  │   │
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

## Architecture

All Model Registry components are deployed in the `rhoai-model-registries` namespace:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     rhoai-model-registries namespace                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                 ModelRegistry Pod (private-ai-registry)             │   │
│   │  ┌────────────────────┐    ┌────────────────────┐                   │   │
│   │  │   OAuth Proxy      │    │   REST API         │                   │   │
│   │  │   (kube-rbac)      │    │   (model-registry) │                   │   │
│   │  │   :8443            │    │   :8080            │                   │   │
│   │  └────────────────────┘    └────────────────────┘                   │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                ▲                            ▲                               │
│                │                            │                               │
│   ┌────────────┴────────────┐   ┌──────────┴──────────────────────┐        │
│   │ private-ai-registry     │   │ private-ai-registry-internal    │        │
│   │ :8443 (operator)        │   │ :8080 (GitOps)                  │        │
│   │ OAuth-protected         │   │ Internal automation             │        │
│   │ Dashboard/UI access     │   │ Seed job access                 │        │
│   └─────────────────────────┘   └─────────────────────────────────┘        │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         MariaDB                                     │   │
│   │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │   │
│   │  │ Deployment   │    │   Service    │    │     PVC      │          │   │
│   │  │ mariadb-105  │◀───│   :3306      │    │    5Gi       │          │   │
│   │  └──────────────┘    └──────────────┘    └──────────────┘          │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Service Architecture:**
| Service | Port | Purpose | Access |
|---------|------|---------|--------|
| `private-ai-registry` | 8443 | OAuth-protected API | Dashboard, external clients |
| `private-ai-registry-internal` | 8080 | Unauthenticated API | Seed jobs, automation |

---

## Model Catalog

RHOAI 3.0 includes a pre-bundled **Model Catalog** with 48+ validated models:

| Provider | Models |
|----------|--------|
| **IBM** | Granite 3.1 (8B variants, FP8, W4A16, W8A8) |
| **Meta** | Llama 3.1/3.3/4 (8B-70B, Maverick, Scout) |
| **Mistral** | Mistral Small 24B, Mixtral 8x7B |
| **Alibaba** | Qwen 2.5/3 (7B-8B variants) |
| **Microsoft** | phi-4 (all quantizations) |
| **DeepSeek** | DeepSeek-R1 |
| **Google** | Gemma 2/3n |

Access via: **GenAI Studio → AI Available Assets**

---

## Registered Model (Seed Job)

This step registers the **Granite 3.1 8B Instruct FP8** model:

| Property | Value |
|----------|-------|
| **Model** | `Granite-3.1-8b-Instruct-FP8` |
| **Version** | `3.1-May2025-Validated` |
| **Owner** | `ai-admin` |
| **Provider** | IBM |
| **License** | Apache 2.0 |
| **Quantization** | FP8-dynamic |
| **Hardware Target** | NVIDIA L4 (AWS G6) |
| **Tags** | `granite`, `fp8`, `validated`, `vllm` |
| **Artifact URI** | `s3://rhoai-artifacts/granite-3.1-8b-instruct-FP8-dynamic/` |

> **Note**: The seed job uses proper RHOAI metadata format with `metadataType: MetadataStringValue`.

---

## Demo Credentials

| Username | Password | Registry Access |
|----------|----------|-----------------|
| `ai-admin` | `redhat123` | Full access - register, archive, delete models |
| `ai-developer` | `redhat123` | Read-only - discover and deploy models |

---

## What Gets Installed

All resources in `rhoai-model-registries` namespace:

### Database (MariaDB)

| Resource | Name | Purpose |
|----------|------|---------|
| **Secret** | `model-registry-db-creds` | MariaDB credentials |
| **PVC** | `model-registry-db-pvc` | 5Gi persistent storage |
| **Deployment** | `model-registry-db` | MariaDB 10.5 |
| **Service** | `model-registry-db` | Port 3306 |

### Model Registry

| Resource | Name | Purpose |
|----------|------|---------|
| **ModelRegistry** | `private-ai-registry` | Registry instance (v1beta1) |
| **Service** | `private-ai-registry` | OAuth-protected API (8443) |
| **Service** | `private-ai-registry-internal` | Internal API (8080) |
| **NetworkPolicy** | `private-ai-registry-internal-access` | Allow seed job access |

### RBAC

| Resource | Name | Purpose |
|----------|------|---------|
| **RoleBinding** | `ai-admin-registry-admin` | Full admin access |
| **RoleBinding** | `ai-developer-registry-user` | Read-only access |

### Seed Job

| Resource | Name | Purpose |
|----------|------|---------|
| **Job** | `model-registry-seed` | Register Granite 3.1 model |

---

## Prerequisites

- [x] Step 01 completed (GPU infrastructure)
- [x] Step 02 completed (RHOAI 3.0 with ModelRegistry component)
- [x] Step 03 completed (MinIO for artifact storage)

---

## Deploy

### A) One-shot (recommended)

```bash
./steps/step-04-model-registry/deploy.sh
```

The script will:
1. Deploy MariaDB database in `rhoai-model-registries`
2. Create ModelRegistry CR `private-ai-registry`
3. Create internal service for API access
4. Configure RBAC for ai-admin and ai-developer
5. Register the Granite 3.1 FP8 model (metadata only)

### B) Step-by-step (exact commands)

For manual deployment or debugging:

```bash
# 1. Validate manifests (dry-run)
kustomize build gitops/step-04-model-registry/base | oc apply --dry-run=server -f -

# 2. Apply Argo CD Application
oc apply -f gitops/argocd/app-of-apps/step-04-model-registry.yaml

# 3. Wait for namespace
until oc get namespace rhoai-model-registries &>/dev/null; do sleep 5; done

# 4. Wait for MariaDB deployment
oc rollout status deployment/model-registry-db -n rhoai-model-registries --timeout=120s

# 5. Wait for ModelRegistry to be available
until oc get modelregistry.modelregistry.opendatahub.io private-ai-registry \
      -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q True; do
    echo "Waiting for ModelRegistry to become available..."
    sleep 10
done
echo "ModelRegistry is available"

# 6. Wait for seed job to complete
oc wait --for=condition=complete job/model-registry-seed -n rhoai-model-registries --timeout=120s

# 7. Verify model was registered
oc run test-api --rm -i --restart=Never \
  --image=curlimages/curl -n rhoai-model-registries -- \
  curl -sf http://private-ai-registry-internal:8080/api/model_registry/v1alpha3/registered_models
```

> **Note**: For self-signed clusters, add `--insecure-skip-tls-verify=true` to `oc` commands if needed.

---

## Validation Commands

### 1. Check Model Registry

```bash
# Verify ModelRegistry CR
oc get modelregistry.modelregistry.opendatahub.io -n rhoai-model-registries

# Expected output:
# NAME                  AVAILABLE   AGE
# private-ai-registry   True        5m

# Check registry pods
oc get pods -n rhoai-model-registries -l app=private-ai-registry
```

### 2. Check Database

```bash
# Verify MariaDB is running
oc get pods -n rhoai-model-registries -l app=model-registry-db

# Check database connectivity
oc exec -n rhoai-model-registries deployment/model-registry-db -- \
  mysql -u mlmd -pmlmd-secret-123 -e "SHOW DATABASES;"
```

### 3. Check Seed Job

```bash
# Verify seed job completed
oc get job model-registry-seed -n rhoai-model-registries

# Check logs
oc logs job/model-registry-seed -n rhoai-model-registries
```

### 4. Query Registry API

```bash
# List registered models via internal service
oc run test-api --rm -i --restart=Never \
  --image=curlimages/curl -n rhoai-model-registries -- \
  curl -sf http://private-ai-registry-internal:8080/api/model_registry/v1alpha3/registered_models
```

### 5. Verify in Dashboard

**As ai-admin (Registry View):**
1. Login to RHOAI Dashboard
2. Go to **Settings** → **Model registries**
3. Click **private-ai-registry**
4. Verify **Granite-3.1-8b-Instruct-FP8** appears

**As ai-developer (Catalog View):**
1. Login to RHOAI Dashboard
2. Go to **GenAI Studio** → **AI Available Assets**
3. Find models under "Red Hat AI validated" filter
4. Browse 48+ validated models

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
│   ├── registry/                    # ModelRegistry CR + services
│   │   ├── kustomization.yaml
│   │   ├── model-registry.yaml      # v1beta1 CR
│   │   ├── internal-service.yaml    # Port 8080 for automation
│   │   └── internal-networkpolicy.yaml
│   │
│   ├── rbac/                        # Access control
│   │   ├── kustomization.yaml
│   │   ├── registry-user-rolebinding.yaml
│   │   └── registry-admin-rolebinding.yaml
│   │
│   └── seed-job.yaml                # Register Granite 3.1 model
```

---

## Registry vs. Catalog

| Component | Purpose | Location | Access |
|-----------|---------|----------|--------|
| **Model Registry** | Backend storage for metadata | Settings → Model registries | ai-admin |
| **Model Catalog** | Discovery UI (48+ pre-bundled models) | GenAI Studio → AI Available Assets | ai-developer |

The **Model Catalog** uses pre-bundled YAML files from Red Hat - no external sync required.

---

## Model Lifecycle Management

### Archiving Models (Compliance)

When a model version is superseded or deprecated:

```bash
# Archive a model via internal API
oc run archive-model --rm -i --restart=Never \
  --image=curlimages/curl -n rhoai-model-registries -- \
  curl -sf -X PATCH "http://private-ai-registry-internal:8080/api/model_registry/v1alpha3/registered_models/{MODEL_ID}" \
  -H "Content-Type: application/json" \
  -d '{"state": "ARCHIVED"}'
```

> **Note**: Archived models are hidden from the catalog but preserved for regulatory audit.

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
oc exec -n rhoai-model-registries deployment/model-registry-db -- \
  mysql -u mlmd -pmlmd-secret-123 -e "SELECT 1"

# Check credentials secret
oc get secret model-registry-db-creds -n rhoai-model-registries -o yaml
```

### Seed Job Failed

```bash
# Check job logs
oc logs job/model-registry-seed -n rhoai-model-registries

# Re-run seed job
oc delete job model-registry-seed -n rhoai-model-registries
oc apply -f gitops/step-04-model-registry/base/seed-job.yaml
```

### Internal Service Not Accessible

```bash
# Check internal service exists
oc get svc private-ai-registry-internal -n rhoai-model-registries

# Check network policy
oc get networkpolicy -n rhoai-model-registries

# Test from debug pod
oc run debug --rm -i --restart=Never --image=curlimages/curl -n rhoai-model-registries -- \
  curl -sf http://private-ai-registry-internal:8080/api/model_registry/v1alpha3/registered_models
```

---

## Rollback / Cleanup

### Remove Model Registry Infrastructure

> **⚠️ Warning**: This will delete all registered models, versions, and metadata. The Model Catalog (pre-bundled models) is not affected.

```bash
# 1. Delete Argo CD Application (cascades to managed resources)
oc delete application step-04-model-registry -n openshift-gitops

# 2. Wait for resources to be removed
oc get pods -n rhoai-model-registries -w

# 3. Optional: Delete namespace manually if not cleaned up
oc delete namespace rhoai-model-registries
```

### GitOps Revert (alternative)

```bash
# Remove from Git and let Argo CD prune
git revert <commit-with-step-04>
git push

# Or delete Argo CD Application with cascade
oc delete application step-04-model-registry -n openshift-gitops --cascade=foreground
```

---

## Documentation Links

### Official Red Hat Documentation
- [Enabling Model Registry Component](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/enabling_the_model_registry_component/index)
- [Managing Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/managing_model_registries/index)
- [Working with Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/working_with_model_registries/index)

### Model Reference
- [Red Hat AI Validated Models](https://huggingface.co/collections/RedHatAI)
- [Granite 3.1 8B Instruct FP8](https://huggingface.co/RedHatAI/granite-3.1-8b-instruct-FP8-dynamic)

---

## Summary

| Component | Purpose | Status |
|-----------|---------|--------|
| **MariaDB** | Metadata storage | ✅ Deployed |
| **ModelRegistry** | Registry instance | ✅ Deployed |
| **Internal Service** | API access for automation | ✅ Deployed |
| **Granite 3.1 FP8** | Validated model | ✅ Registered |
| **Model Catalog** | 48+ pre-bundled models | ✅ Available |
| **KServe Deployment** | Inference endpoint | ⏳ Step 05 |

**This step establishes the "Model Warehouse":**
- ✅ Registry infrastructure deployed
- ✅ Database connected (same namespace)
- ✅ Granite model registered with proper metadata
- ✅ Model Catalog with 48+ validated models
- ⏳ Ready for Step 05: Deploy to inference endpoint
