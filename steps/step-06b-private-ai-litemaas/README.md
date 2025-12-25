# Step 06B: LiteMaaS - Experimental MaaS Alternative

> ⚠️ **EXPERIMENTAL**: This step deploys a proof-of-concept MaaS platform.
> **NOT for production use.** See [Disclaimers](#disclaimers) below.

## Disclaimers

### ⚠️ Important Notices

| Aspect | Status |
|--------|--------|
| **Support Status** | ❌ NOT officially supported by Red Hat |
| **License** | MIT License - use at your own risk |
| **Intended Use** | Demo, learning, experimentation ONLY |
| **Production Ready** | ❌ NO - this is a proof-of-concept |
| **Data Persistence** | ⚠️ Data may be lost on cleanup |
| **Security** | ⚠️ Demo credentials - NOT production-grade |

### Why This Step Exists

The official **RHOAI MaaS** is currently **Developer Preview** and requires:
- Red Hat Connectivity Link 1.2 operator (not installed)
- LLM-D runtime (we use vLLM)
- InferenceGateway CRD (not available in RHOAI 3.0 GA)

**LiteMaaS** provides a simpler alternative for demonstrating MaaS concepts:
- Self-service API key management
- Usage tracking and budget controls
- Unified model endpoint (via LiteLLM)
- Works with existing vLLM InferenceServices

### When to Use This

✅ **Good for:**
- Learning MaaS concepts before RHOAI MaaS GA
- Demonstrating API key management workflows
- Testing unified model access patterns
- Quick experimentation with multiple models

❌ **NOT for:**
- Production workloads
- Customer-facing deployments
- Security-sensitive environments
- Long-term data storage

### Official Alternative

When RHOAI MaaS reaches **Technology Preview (TP)**, migrate to the official solution:
- [RHOAI MaaS Documentation](https://opendatahub-io.github.io/models-as-a-service/latest/)
- [Step 06 - GenAI Playground (GA)](../step-06-private-ai-playground-maas/README.md)

---

## The Business Story

**"Self-Service AI Platform"** - Developers get API keys, admins track usage.

| Persona | Capability |
|---------|------------|
| **Developer** | Request API keys, view personal usage |
| **Team Lead** | Manage team subscriptions, set budgets |
| **Platform Admin** | Approve subscriptions, view analytics |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        litemaas namespace (ISOLATED)                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌──────────────────────────────────────────────────────────────────────────┐  │
│   │                      LiteMaaS Frontend                                    │  │
│   │                  (PatternFly 6 React UI)                                 │  │
│   │   • Model Discovery    • API Key Management    • Usage Analytics         │  │
│   └──────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                             │
│                                    ▼                                             │
│   ┌──────────────────────────────────────────────────────────────────────────┐  │
│   │                      LiteMaaS Backend                                     │  │
│   │                    (Fastify API Server)                                  │  │
│   │   • Subscription Management    • API Key Validation    • Budget Control  │  │
│   └──────────────────────────────────────────────────────────────────────────┘  │
│         │                                              │                         │
│         ▼                                              ▼                         │
│   ┌────────────────┐                    ┌────────────────────────────────────┐  │
│   │   PostgreSQL   │                    │          LiteLLM Proxy             │  │
│   │  (Usage Data)  │                    │    (Unified Model Gateway)         │  │
│   └────────────────┘                    └────────────────────────────────────┘  │
│                                                        │                         │
└────────────────────────────────────────────────────────│─────────────────────────┘
                                                         │
                                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        private-ai namespace (Step-05)                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│   ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────┐       │
│   │mistral-3-int4 │ │mistral-3-bf16 │ │  devstral-2   │ │  gpt-oss-20b  │  ...  │
│   │   (1 GPU)     │ │   (4 GPU)     │ │   (4 GPU)     │ │   (4 GPU)     │       │
│   └───────────────┘ └───────────────┘ └───────────────┘ └───────────────┘       │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Steps 01-05 Completed

```bash
# Verify InferenceServices are deployed
oc get inferenceservice -n private-ai
```

### 2. At Least One Model Running

```bash
# Check for running model pods
oc get pods -n private-ai | grep predictor
```

## Deployment

### Quick Deploy

```bash
./steps/step-06b-litemaas/deploy.sh
```

### What Gets Deployed

| Component | Image | Purpose |
|-----------|-------|---------|
| **PostgreSQL** | `rhel9/postgresql-15` | Stores subscriptions, API keys, usage |
| **LiteLLM** | `ghcr.io/berriai/litellm:main-latest` | Unified model proxy |
| **LiteMaaS Backend** | `quay.io/rh-aiservices-bu/litemaas-backend:0.1.2` | API server |
| **LiteMaaS Frontend** | `quay.io/rh-aiservices-bu/litemaas-frontend:0.1.2` | React UI |

### Namespace Isolation

All resources are deployed in the **`litemaas`** namespace, completely isolated from:
- `private-ai` (production models)
- `redhat-ods-applications` (RHOAI)
- `openshift-*` (platform)

## Validation

### 1. Check Deployments

```bash
./steps/step-06b-litemaas/deploy.sh status
```

### 2. Test LiteLLM Directly

```bash
# Get LiteLLM URL
LITELLM_URL=$(oc get route litellm -n litemaas -o jsonpath='{.spec.host}')

# Health check
curl -k https://${LITELLM_URL}/health

# List models
curl -k https://${LITELLM_URL}/v1/models \
  -H "Authorization: Bearer sk-litemaas-demo-key-2024"

# Chat completion (if mistral-3-int4 is running)
curl -k https://${LITELLM_URL}/v1/chat/completions \
  -H "Authorization: Bearer sk-litemaas-demo-key-2024" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-3-int4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### 3. Access LiteMaaS UI

```bash
# Get UI URL
oc get route litemaas -n litemaas -o jsonpath='{.spec.host}'
```

> **Note:** LiteMaaS UI requires OAuth configuration for full functionality.
> For demo purposes, use LiteLLM directly with the master key.

## Cleanup

### Complete Removal

```bash
./steps/step-06b-litemaas/deploy.sh cleanup
```

This will:
1. ⚠️ Delete all data in PostgreSQL
2. Delete all PersistentVolumeClaims
3. Delete all Deployments, Services, Routes
4. Delete the `litemaas` namespace
5. Delete the ArgoCD Application (if exists)

### Partial Cleanup (Keep Namespace)

```bash
# Delete just the deployments
oc delete deployment --all -n litemaas

# Keep PostgreSQL data for debugging
oc delete deployment litellm litemaas-backend litemaas-frontend -n litemaas
```

## Demo Scenarios

### Scenario 1: Unified Model Access

**Story:** "Access all models through one endpoint."

```bash
LITELLM_URL=$(oc get route litellm -n litemaas -o jsonpath='{.spec.host}')
API_KEY="sk-litemaas-demo-key-2024"

# Same endpoint, different models
curl -k https://${LITELLM_URL}/v1/chat/completions \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{"model": "mistral-3-int4", "messages": [{"role": "user", "content": "Hello"}]}'

curl -k https://${LITELLM_URL}/v1/chat/completions \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{"model": "granite-8b-agent", "messages": [{"role": "user", "content": "Hello"}]}'
```

### Scenario 2: Model Fallback

**Story:** "LiteLLM handles model unavailability gracefully."

When a model is scaled to 0 (Kueue pending), LiteLLM returns an appropriate error:

```bash
# Try a model that's not running
curl -k https://${LITELLM_URL}/v1/chat/completions \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{"model": "gpt-oss-20b", "messages": [{"role": "user", "content": "Hello"}]}'

# LiteLLM returns: {"error": "Connection refused..."}
```

## Troubleshooting

### LiteLLM Can't Reach Models

**Symptom:** `Connection refused` or timeout errors.

**Cause:** Models in `private-ai` are not running.

**Solution:**
```bash
# Check which models are running
oc get pods -n private-ai | grep predictor

# Scale up a model
oc scale deployment mistral-3-int4-predictor -n private-ai --replicas=1
```

### PostgreSQL Not Starting

**Symptom:** Pod stuck in `Pending` or `CrashLoopBackOff`.

**Cause:** PVC not bound or image pull issues.

**Solution:**
```bash
# Check PVC status
oc get pvc -n litemaas

# Check events
oc get events -n litemaas --sort-by='.lastTimestamp'

# Check pod logs
oc logs deployment/postgres -n litemaas
```

### LiteMaaS UI Not Loading

**Symptom:** Blank page or 500 error.

**Cause:** Backend not reachable or OAuth not configured.

**Solution:**
```bash
# Check backend health
oc logs deployment/litemaas-backend -n litemaas

# For demo, use LiteLLM directly
curl -k https://$(oc get route litellm -n litemaas -o jsonpath='{.spec.host}')/health
```

## GitOps Structure

```
gitops/step-06b-litemaas/
├── base/
│   ├── kustomization.yaml          # Main kustomization
│   ├── namespace/
│   │   ├── kustomization.yaml
│   │   └── namespace.yaml          # litemaas namespace
│   ├── postgres/
│   │   ├── kustomization.yaml
│   │   └── postgres.yaml           # PostgreSQL deployment
│   ├── litellm/
│   │   ├── kustomization.yaml
│   │   └── litellm.yaml            # LiteLLM proxy + config
│   └── litemaas/
│       ├── kustomization.yaml
│       └── litemaas.yaml           # Backend + Frontend

steps/step-06b-litemaas/
├── deploy.sh                        # Deployment script
└── README.md                        # This file
```

## LiteLLM Configuration

Models are configured in `gitops/step-06b-litemaas/base/litellm/litellm.yaml`:

```yaml
model_list:
  - model_name: mistral-3-int4           # Friendly name for API
    litellm_params:
      model: openai/...                   # Pass-through model ID
      api_base: http://mistral-3-int4-predictor.private-ai.svc.cluster.local:8080/v1
      api_key: fake                       # vLLM doesn't require auth
```

### Adding New Models

1. Deploy InferenceService in `private-ai` (Step-05)
2. Add entry to LiteLLM config
3. Restart LiteLLM: `oc rollout restart deployment/litellm -n litemaas`

## Comparison: LiteMaaS vs RHOAI MaaS

| Feature | LiteMaaS (PoC) | RHOAI MaaS (DP) |
|---------|----------------|-----------------|
| **Status** | MIT PoC | Developer Preview |
| **Support** | Community | Red Hat (when GA) |
| **Runtime** | Any (via LiteLLM) | LLM-D only |
| **Dependencies** | PostgreSQL | Connectivity Link 1.2 |
| **Auth** | JWT + OAuth2 | Authorino |
| **Rate Limiting** | Budget-based | Limitador |
| **UI** | Standalone PatternFly | Dashboard integrated |

## Official References

- [LiteMaaS GitHub](https://github.com/rh-aiservices-bu/litemaas)
- [LiteLLM Documentation](https://docs.litellm.ai/)
- [RHOAI MaaS (when available)](https://opendatahub-io.github.io/models-as-a-service/latest/)
- [Step 06 - GenAI Playground (GA)](../step-06-private-ai-playground-maas/README.md)

## Next Steps

When RHOAI MaaS reaches Technology Preview:
1. Run `./steps/step-06b-litemaas/deploy.sh cleanup`
2. Follow Step-06 for official MaaS deployment
3. Migrate any learned patterns to production configuration

