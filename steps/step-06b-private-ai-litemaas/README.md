# Step 06B: LiteMaaS - Model as a Service (Experimental)

> ⚠️ **EXPERIMENTAL**: This step deploys [LiteMaaS](https://github.com/rh-aiservices-bu/litemaas), 
> a proof-of-concept MaaS platform. It is not production-ready and is included for 
> demonstration purposes only.

## Overview

LiteMaaS provides a self-service portal for LLM access management:

- **User Subscriptions**: Users can subscribe to available models
- **API Key Management**: Generate and manage API keys
- **Usage Tracking**: Monitor token usage per user/key
- **OpenShift OAuth**: Authentication via OpenShift identity

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LiteMaaS Architecture                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Users                                                                     │
│     │                                                                       │
│     ▼                                                                       │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                     litemaas namespace                               │  │
│   │                                                                      │  │
│   │   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐     │  │
│   │   │   Frontend   │─────▶│   Backend    │─────▶│   LiteLLM    │     │  │
│   │   │   (nginx)    │      │  (Node.js)   │      │   (Proxy)    │     │  │
│   │   └──────────────┘      └──────────────┘      └──────────────┘     │  │
│   │          │                     │                     │              │  │
│   │          │                     ▼                     │              │  │
│   │          │              ┌──────────────┐             │              │  │
│   │          │              │  PostgreSQL  │             │              │  │
│   │          │              │  (StatefulSet)│            │              │  │
│   │          │              └──────────────┘             │              │  │
│   └──────────│───────────────────────────────────────────│──────────────┘  │
│              │                                           │                  │
│              ▼                                           ▼                  │
│   ┌──────────────────┐                      ┌─────────────────────────────┐│
│   │ OpenShift OAuth  │                      │     private-ai namespace    ││
│   │ (Authentication) │                      │                             ││
│   └──────────────────┘                      │  ┌─────────┐ ┌─────────┐   ││
│                                              │  │mistral-3│ │granite-8│   ││
│                                              │  │  int4   │ │  agent  │   ││
│                                              │  └─────────┘ └─────────┘   ││
│                                              │  ┌─────────┐ ┌─────────┐   ││
│                                              │  │devstral │ │gpt-oss  │   ││
│                                              │  │   -2    │ │  -20b   │   ││
│                                              │  └─────────┘ └─────────┘   ││
│                                              └─────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites (Cluster-Admin Required)

Before deploying LiteMaaS, the following cluster-level resources must exist:

### 1. OAuthClient

```yaml
kind: OAuthClient
apiVersion: oauth.openshift.io/v1
metadata:
  name: litemaas-oauth-client
secret: <your-oauth-secret>
redirectURIs:
  - 'https://litemaas-litemaas.<cluster-domain>/api/auth/callback'
grantMethod: auto
```

### 2. OpenShift Groups

```bash
# Create groups (as cluster-admin)
oc adm groups new litemaas-admins
oc adm groups new litemaas-readonly
oc adm groups new litemaas-users

# Add users to admin group
oc adm groups add-users litemaas-admins <username>
```

## Deployment

### Option A: Via ArgoCD (Recommended)

```bash
# Apply the ArgoCD Application
oc apply -f gitops/argocd/app-of-apps/step-06b-private-ai-litemaas.yaml

# Monitor sync status
oc get application step-06b-private-ai-litemaas -n openshift-gitops -w
```

### Option B: Direct Apply

```bash
# Apply all resources
oc apply -k gitops/step-06b-private-ai-litemaas/base
```

## Verification

```bash
# Check all pods are running
oc get pods -n litemaas

# Expected output:
# NAME                        READY   STATUS    RESTARTS   AGE
# postgres-0                  1/1     Running   0          5m
# litellm-xxx                 1/1     Running   0          4m
# backend-xxx                 1/1     Running   0          3m
# frontend-xxx                1/1     Running   0          2m

# Get the LiteMaaS URL
oc get route litemaas -n litemaas -o jsonpath='{.spec.host}'
```

## Access

| Application | URL | Purpose |
|-------------|-----|---------|
| LiteMaaS UI | `https://litemaas-litemaas.<domain>` | User portal |
| LiteLLM Proxy | `https://litellm-litemaas.<domain>` | API endpoint |
| Backend API | `https://litemaas-api-litemaas.<domain>` | Direct API |

## Demo Workflow

1. **Login**: Navigate to LiteMaaS UI and click "Login with OpenShift"
2. **Subscribe**: Select models you want to use
3. **Generate Key**: Create an API key for your subscriptions
4. **Use API**: Make requests to LiteLLM proxy with your key

### Example API Call

```bash
# Get your API key from LiteMaaS UI, then:
curl -sk https://litellm-litemaas.<domain>/v1/chat/completions \
  -H "Authorization: Bearer <your-api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-3-int4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Cleanup

```bash
# Remove LiteMaaS deployment
oc delete application step-06b-private-ai-litemaas -n openshift-gitops
oc delete namespace litemaas

# Remove cluster-level resources
oc delete oauthclient litemaas-oauth-client
oc delete group litemaas-admins litemaas-readonly litemaas-users
```

## Known Limitations

1. **No Production PKI**: Uses edge TLS termination
2. **Single Replica**: All components run as single replicas
3. **No Backup**: PostgreSQL data is not backed up
4. **Group Management**: Users must be manually added to groups

## References

- [LiteMaaS Repository](https://github.com/rh-aiservices-bu/litemaas)
- [OpenShift Deployment Guide](https://github.com/rh-aiservices-bu/litemaas/blob/main/docs/deployment/openshift-deployment.md)
- [LiteLLM Documentation](https://docs.litellm.ai/)

