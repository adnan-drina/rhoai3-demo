# Step 06B: LiteMaaS - Model as a Service (Experimental)

> ⚠️ **EXPERIMENTAL**: This step deploys [LiteMaaS](https://github.com/rh-aiservices-bu/litemaas), 
> a proof-of-concept MaaS platform. It is not production-ready and is included for 
> demonstration purposes only.

## Goal

Demonstrate a self-service Model-as-a-Service (MaaS) platform that provides:
- **User Subscriptions**: Users subscribe to available LLM models
- **API Key Management**: Generate and manage API keys for programmatic access
- **Usage Tracking**: Monitor token usage per user/model
- **Unified API**: Single endpoint for all models via LiteLLM proxy
- **OpenShift OAuth**: Native authentication with OpenShift identity

## Prerequisites

| Requirement | Details |
|-------------|---------|
| RHOCP | 4.20 |
| RHOAI | 3.0 (Step 02 completed) |
| vLLM Models | At least one model running in `private-ai` (Step 05) |
| Cluster Admin | Required for OAuthClient creation |

### Cluster-Admin Setup (One-Time)

Before deploying, create these cluster-level resources:

```bash
# 1. Create OAuthClient
cat <<EOF | oc apply -f -
apiVersion: oauth.openshift.io/v1
kind: OAuthClient
metadata:
  name: litemaas-oauth-client
secret: 277e639bb4ebed8e0e5dd9517dc947cf
redirectURIs:
  - 'https://litemaas-litemaas.apps.<cluster-domain>/api/auth/callback'
grantMethod: auto
EOF

# 2. Create OpenShift Groups
oc adm groups new litemaas-admins
oc adm groups new litemaas-users
oc adm groups add-users litemaas-admins $(oc whoami)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LiteMaaS Architecture                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Users ────▶ https://litemaas-litemaas.apps.cluster/                      │
│                           │                                                 │
│   ┌───────────────────────│─────────────────────────────────────────────┐  │
│   │                   litemaas namespace                                │  │
│   │                       │                                             │  │
│   │   ┌──────────────┐    │    ┌──────────────┐    ┌──────────────┐    │  │
│   │   │   Frontend   │◀───┴───▶│   Backend    │───▶│   LiteLLM    │    │  │
│   │   │  (React/Nginx)│        │  (Node.js)   │    │   (Proxy)    │    │  │
│   │   └──────────────┘         └──────────────┘    └──────────────┘    │  │
│   │                                   │                   │             │  │
│   │                                   ▼                   │             │  │
│   │                           ┌──────────────┐            │             │  │
│   │                           │  PostgreSQL  │            │             │  │
│   │                           │ (StatefulSet)│            │             │  │
│   │                           └──────────────┘            │             │  │
│   └───────────────────────────────────────────────────────│─────────────┘  │
│                                                           │                 │
│                                                           ▼                 │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                      private-ai namespace                            │  │
│   │                                                                      │  │
│   │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │  │
│   │   │mistral-3-int4│  │granite-8b-  │  │ devstral-2  │  + more...     │  │
│   │   │   (1-GPU)    │  │   agent     │  │   (4-GPU)   │                 │  │
│   │   └─────────────┘  └─────────────┘  └─────────────┘                 │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## What Gets Deployed

| Component | Resource Type | Purpose |
|-----------|---------------|---------|
| `litemaas` | Namespace | Isolated environment |
| `postgres` | StatefulSet | User/subscription database |
| `litellm` | Deployment | LLM proxy with DB support |
| `backend` | Deployment | API server (Node.js) |
| `frontend` | Deployment | Web UI (React/Nginx) |
| `postgres-secret` | Secret | Database credentials |
| `backend-secret` | Secret | OAuth, JWT, API keys |
| `litellm-secret` | Secret | LiteLLM master key |

**GitOps Location**: `gitops/step-06b-private-ai-litemaas/base/`

## Deployment

### Option A: One-Shot Deploy

```bash
cd steps/step-06b-private-ai-litemaas
./deploy.sh
```

### Option B: Step-by-Step

```bash
# 1. Apply ArgoCD Application
oc apply -f gitops/argocd/app-of-apps/step-06b-private-ai-litemaas.yaml

# 2. Wait for sync
oc get application step-06b-private-ai-litemaas -n openshift-gitops -w

# 3. Wait for all pods
oc wait --for=condition=Ready pod -l app.kubernetes.io/part-of=litemaas -n litemaas --timeout=300s
```

## Post-Deployment Setup

After ArgoCD syncs, run these one-time setup commands:

```bash
# 1. Fix OpenShift OAuth compatibility (oauth_id nullable)
oc exec -n litemaas postgres-0 -- psql -U litemaas_admin -d litemaas_db -c \
  "ALTER TABLE users ALTER COLUMN oauth_id DROP NOT NULL;"

# 2. Register models in backend database
oc exec -n litemaas postgres-0 -- psql -U litemaas_admin -d litemaas_db -c "
INSERT INTO models (id, name, provider, description, category, context_length, supports_streaming, availability, api_base) VALUES
('mistral-3-int4', 'Mistral-3 INT4', 'vLLM', 'Mistral-3 INT4 (1-GPU)', 'chat', 16384, true, 'available', 'http://mistral-3-int4-predictor.private-ai.svc.cluster.local:8080/v1'),
('granite-8b-agent', 'Granite-8B Agent', 'vLLM', 'Granite-3.1-8B Agent', 'agent', 16384, true, 'available', 'http://granite-8b-agent-predictor.private-ai.svc.cluster.local:8080/v1'),
('mistral-3-bf16', 'Mistral-3 BF16', 'vLLM', 'Mistral-3 BF16 (4-GPU)', 'chat', 32768, true, 'available', 'http://mistral-3-bf16-predictor.private-ai.svc.cluster.local:8080/v1'),
('devstral-2', 'Devstral-2', 'vLLM', 'Devstral-2 Agentic Coder (4-GPU)', 'coding', 131072, true, 'available', 'http://devstral-2-predictor.private-ai.svc.cluster.local:8080/v1'),
('gpt-oss-20b', 'GPT-OSS-20B', 'vLLM', 'GPT-OSS-20B (4-GPU)', 'reasoning', 32768, true, 'available', 'http://gpt-oss-20b-predictor.private-ai.svc.cluster.local:8080/v1')
ON CONFLICT (id) DO NOTHING;"

# 3. Register models in LiteLLM (for routing)
MASTER_KEY="sk-1b4f0a05549af06f80db6cd51b37fd01"
for model in mistral-3-int4 granite-8b-agent mistral-3-bf16 devstral-2 gpt-oss-20b; do
  oc exec deployment/backend -n litemaas -- curl -s -X POST http://litellm:4000/model/new \
    -H "Authorization: Bearer $MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model_name\": \"$model\", \"litellm_params\": {\"model\": \"openai/$model\", \"api_base\": \"http://${model}-predictor.private-ai.svc.cluster.local:8080/v1\", \"api_key\": \"none\"}}"
done
```

## Verification

```bash
# Check all pods running
oc get pods -n litemaas
# Expected:
# postgres-0                  1/1     Running
# litellm-xxx                 1/1     Running  
# backend-xxx                 1/1     Running
# frontend-xxx                1/1     Running

# Verify models in LiteLLM
oc exec deployment/backend -n litemaas -- curl -s http://litellm:4000/model/info \
  -H "Authorization: Bearer sk-1b4f0a05549af06f80db6cd51b37fd01" | jq '.data | length'
# Expected: 5

# Verify models in backend DB
oc exec -n litemaas postgres-0 -- psql -U litemaas_admin -d litemaas_db -c "SELECT id, name FROM models;"
# Expected: 5 rows
```

## Access URLs

| Application | URL | Purpose |
|-------------|-----|---------|
| **LiteMaaS UI** | `https://litemaas-litemaas.<domain>` | User portal, subscriptions |
| **LiteLLM Proxy** | `https://litellm-litemaas.<domain>` | API endpoint for models |
| **Backend API** | `https://litemaas-api-litemaas.<domain>` | Direct backend access |

## Demo Workflow

### 1. Login
Navigate to LiteMaaS UI → Click "Login with OpenShift" → Authorize

### 2. Subscribe to Models
Go to "Models" → Click on a model → Click "Subscribe"

### 3. Create API Key
Go to "API Keys" → Create new key → Copy the key

### 4. Test via Chatbot Playground
Go to "Chatbot" → Select model and API key → Chat!

### 5. Test via API

```bash
# Replace with your actual API key from LiteMaaS
API_KEY="sk-your-api-key"
LITELLM_URL="https://litellm-litemaas.apps.<cluster-domain>"

# Test Mistral-3 INT4
curl -sk "$LITELLM_URL/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-3-int4",
    "messages": [{"role": "user", "content": "What is OpenShift?"}],
    "max_tokens": 100
  }'

# Test Devstral-2 (coding)
curl -sk "$LITELLM_URL/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "devstral-2",
    "messages": [{"role": "user", "content": "Write a Python hello world"}],
    "max_tokens": 100
  }'
```

## Troubleshooting

### OAuth "Authentication failed"

**Symptom**: `null value in column "oauth_id" violates not-null constraint`

**Cause**: OpenShift OAuth doesn't provide standard OIDC `sub` claim

**Fix**:
```bash
oc exec -n litemaas postgres-0 -- psql -U litemaas_admin -d litemaas_db -c \
  "ALTER TABLE users ALTER COLUMN oauth_id DROP NOT NULL;"
```

### Subscription "Failed to subscribe"

**Symptom**: `Key (model_id)=(...) is not present in table "models"`

**Cause**: Models not registered in backend database

**Fix**: Run the model registration SQL commands from Post-Deployment Setup

### Chatbot "Network Error"

**Symptom**: Chatbot playground shows network error

**Cause**: Backend returning internal LiteLLM URL instead of public URL

**Fix**: Ensure `LITELLM_API_URL` in backend-secret is the **public** route URL:
```bash
# Should be: https://litellm-litemaas.apps.<domain>
# NOT: http://litellm:4000
```

### LiteLLM "Database not connected"

**Symptom**: `500 - Database not connected`

**Cause**: Using wrong LiteLLM image or missing DATABASE_URL

**Fix**: Use `ghcr.io/berriai/litellm-non_root:main-v1.74.7-stable` image with `DATABASE_URL` env var

## Cleanup

```bash
# Remove ArgoCD application
oc delete application step-06b-private-ai-litemaas -n openshift-gitops

# Delete namespace (removes all resources)
oc delete namespace litemaas

# Remove cluster-level resources
oc delete oauthclient litemaas-oauth-client
oc delete group litemaas-admins litemaas-users 2>/dev/null || true
```

## Known Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| No production PKI | Self-signed certs | Use `NODE_TLS_REJECT_UNAUTHORIZED=0` |
| Single replicas | No HA | Scale manually if needed |
| No DB backup | Data loss risk | Export data periodically |
| Manual model registration | Setup overhead | Use PostSync jobs |
| OpenShift OAuth only | No other IdPs | N/A for this demo |

## References

- [LiteMaaS Repository](https://github.com/rh-aiservices-bu/litemaas)
- [LiteMaaS OpenShift Deployment](https://github.com/rh-aiservices-bu/litemaas/tree/main/deployment/openshift)
- [LiteLLM Documentation](https://docs.litellm.ai/)
- [LiteLLM Database Setup](https://docs.litellm.ai/docs/simple_proxy#managing-auth---virtual-keys)
