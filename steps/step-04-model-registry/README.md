# Step 04: Model Registry

Establishes the **Model Registry** as a governance layer — the "Gatekeeper Pattern" — so only vetted models reach production.

---

## The Business Story

In enterprise environments, developers should **not** pull models directly from Hugging Face into production. The Model Registry acts as the organization's **Gatekeeper**:

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

**Key benefits:** governance (only admin-approved models appear), versioning (track updates without breaking consumers), discovery (developers find models in GenAI Studio, not external sources), and hardware alignment (models tagged with optimal GPU requirements).

---

## Architecture

All components live in the `rhoai-model-registries` namespace. The operator creates an OAuth-protected service on `:8443` for Dashboard/UI access. We add a second **internal** service on `:8080` (unauthenticated) so seed jobs and automation can register models without an OAuth token.

| Service | Port | Purpose |
|---------|------|---------|
| `private-ai-registry` | 8443 | OAuth-protected — Dashboard, external clients |
| `private-ai-registry-internal` | 8080 | Unauthenticated — seed jobs, automation |

MariaDB 10.5 provides metadata storage (5 Gi PVC, same namespace).

---

## What Gets Deployed

| Resource | Name | Purpose |
|----------|------|---------|
| Secret | `model-registry-db-creds` | MariaDB credentials |
| PVC | `model-registry-db-pvc` | 5 Gi persistent storage |
| Deployment | `model-registry-db` | MariaDB 10.5 |
| Service | `model-registry-db` | DB port 3306 |
| ModelRegistry | `private-ai-registry` | Registry CR (v1beta1) |
| Service | `private-ai-registry` | OAuth API (8443) |
| Service | `private-ai-registry-internal` | Internal API (8080) |
| NetworkPolicy | `private-ai-registry-internal-access` | Allow seed job traffic |
| RoleBinding | `ai-admin-registry-admin` | Full admin access |
| RoleBinding | `ai-developer-registry-user` | Read-only access |
| Job | `model-registry-seed` | Register Granite 3.1 8B |

**Seed job registers:** Granite 3.1 8B Instruct FP8 — owner `ai-admin`, artifact at `s3://rhoai-artifacts/granite-3.1-8b-instruct-FP8-dynamic/`, tagged for NVIDIA L4 (AWS G6).

> RHOAI 3.3 also ships a **Model Catalog** with 48+ pre-bundled validated models (IBM Granite, Meta Llama, Mistral, Qwen, phi-4, DeepSeek, Gemma). Browse them in **GenAI Studio → AI Available Assets**.

---

## Prerequisites

- Step 01 completed (GPU infrastructure)
- Step 02 completed (RHOAI 3.3 with ModelRegistry component enabled)
- Step 03 completed (MinIO for artifact storage)

---

## Deployment

### A) One-shot (recommended)

```bash
./steps/step-04-model-registry/deploy.sh
```

Deploys MariaDB, creates the ModelRegistry CR, configures RBAC for `ai-admin` / `ai-developer`, and runs the Granite seed job.

### B) Step-by-step

```bash
# Dry-run
kustomize build gitops/step-04-model-registry/base | oc apply --dry-run=server -f -

# Apply Argo CD Application
oc apply -f gitops/argocd/app-of-apps/step-04-model-registry.yaml

# Wait for MariaDB
oc rollout status deployment/model-registry-db -n rhoai-model-registries --timeout=120s

# Wait for ModelRegistry Available
until oc get modelregistry.modelregistry.opendatahub.io private-ai-registry \
      -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q True; do
    echo "Waiting for ModelRegistry..."; sleep 10
done

# Wait for seed job
oc wait --for=condition=complete job/model-registry-seed -n rhoai-model-registries --timeout=120s
```

> For self-signed clusters, add `--insecure-skip-tls-verify=true` to `oc` commands.

---

## Validation

```bash
# ModelRegistry CR ready?
oc get modelregistry.modelregistry.opendatahub.io -n rhoai-model-registries
# NAME                  AVAILABLE   AGE
# private-ai-registry   True        5m

# MariaDB running?
oc get pods -n rhoai-model-registries -l app=model-registry-db

# Seed job completed?
oc get job model-registry-seed -n rhoai-model-registries
oc logs job/model-registry-seed -n rhoai-model-registries

# Query the registry API
oc run test-api --rm -i --restart=Never \
  --image=curlimages/curl -n rhoai-model-registries -- \
  curl -sf http://private-ai-registry-internal:8080/api/model_registry/v1alpha3/registered_models
```

**Dashboard check (ai-admin):** Settings → Model registries → `private-ai-registry` → verify Granite model appears.

**Dashboard check (ai-developer):** GenAI Studio → AI Available Assets → browse validated models.

| Username | Password | Access |
|----------|----------|--------|
| `ai-admin` | `redhat123` | Register, archive, delete |
| `ai-developer` | `redhat123` | Read-only discovery |

---

## Demo Walkthrough

1. **Login as `ai-admin`** — navigate to Settings → Model registries. Show `private-ai-registry` with the Granite model registered by the seed job.
2. **Switch to `ai-developer`** — navigate to GenAI Studio → AI Available Assets. Show the 48+ pre-bundled catalog models and explain that the registry gates what reaches production.
3. **Highlight the Gatekeeper** — `ai-admin` controls what enters the registry; `ai-developer` consumes only vetted models. No "Shadow AI."

---

## Troubleshooting

### ModelRegistry not becoming Available

```bash
oc describe modelregistry.modelregistry.opendatahub.io private-ai-registry -n rhoai-model-registries
oc logs -n redhat-ods-operator -l app=rhods-operator --tail=50
```

### Database connection failed

```bash
oc exec -n rhoai-model-registries deployment/model-registry-db -- \
  mysql -u mlmd -pmlmd-secret-123 -e "SELECT 1"
```

### Seed job failed

```bash
oc logs job/model-registry-seed -n rhoai-model-registries
# Re-run:
oc delete job model-registry-seed -n rhoai-model-registries
oc apply -f gitops/step-04-model-registry/base/seed-job.yaml
```

### Internal service unreachable

```bash
oc get svc private-ai-registry-internal -n rhoai-model-registries
oc get networkpolicy -n rhoai-model-registries
```

---

## GitOps Structure

```
gitops/step-04-model-registry/
├── base/
│   ├── kustomization.yaml
│   ├── database/                    # MariaDB for metadata
│   │   ├── kustomization.yaml
│   │   ├── credentials-secret.yaml
│   │   ├── pvc.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── registry/                    # ModelRegistry CR + services
│   │   ├── kustomization.yaml
│   │   ├── model-registry.yaml
│   │   ├── internal-service.yaml
│   │   └── internal-networkpolicy.yaml
│   ├── rbac/                        # Access control
│   │   ├── kustomization.yaml
│   │   ├── registry-user-rolebinding.yaml
│   │   └── registry-admin-rolebinding.yaml
│   └── seed-job.yaml                # Register Granite 3.1 model
```

---

## Design Decisions

> **External MariaDB instead of embedded:** The ModelRegistry CR supports an embedded database, but an external MariaDB gives us explicit PVC control and simpler backup/restore for the demo.

> **Internal service on port 8080:** The operator-managed service requires OAuth. A second headless service bypasses auth so Kubernetes Jobs can seed models without token negotiation.

> **Registry vs. Catalog:** The Model Registry stores custom metadata (our registered models). The Model Catalog is a pre-bundled read-only UI of 48+ Red Hat-validated models — no external sync required.

> **Seed job uses `metadataType: MetadataStringValue`:** This is the format expected by the RHOAI 3.3 registry API. Omitting the type wrapper causes silent metadata loss.

---

## References

- [Enabling Model Registry Component](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/enabling_the_model_registry_component/index)
- [Managing Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/managing_model_registries/index)
- [Working with Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/working_with_model_registries/index)
- [Granite 3.1 8B Instruct FP8](https://huggingface.co/RedHatAI/granite-3.1-8b-instruct-FP8-dynamic)

---

## Next Steps

Proceed to **[Step 05: LLM on vLLM](../step-05-llm-on-vllm/README.md)** to deploy the registered Granite model as a live inference endpoint using KServe + vLLM.
