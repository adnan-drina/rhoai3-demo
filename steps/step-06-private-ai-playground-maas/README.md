# Step 06: GenAI Playground

**"Prompt Engineering Sandbox"** - Interactive model experimentation before code integration.

## The Business Story

Before developers write integration code, they need to:

1. **Experiment with Prompts**: Test different phrasings to get optimal responses
2. **Compare Models**: See how different models handle the same query
3. **Validate Behavior**: Ensure the model fits the use case before committing

The GenAI Playground provides this sandbox environment within the RHOAI Dashboard.

| Component | Purpose | Persona |
|-----------|---------|---------|
| **GenAI Playground** | Interactive prompt testing UI | AI Developer, Data Scientist |
| **LlamaStack** | Backend orchestration (UI ↔ vLLM) | Platform (invisible) |
| **AI Asset Endpoints** | Model catalog for Playground | Platform Admin |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          RHOAI Dashboard                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                   GenAI Studio > Playground                           │  │
│   │                                                                       │  │
│   │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │  │
│   │   │   Model     │  │   Prompt    │  │  Response   │                  │  │
│   │   │  Selector   │  │   Editor    │  │   Viewer    │                  │  │
│   │   │  (5 models) │  │             │  │             │                  │  │
│   │   └─────────────┘  └─────────────┘  └─────────────┘                  │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                    LlamaStackDistribution                             │  │
│   │              (lsd-genai-playground - port 8321)                      │  │
│   │                                                                       │  │
│   │   Providers:                                                          │  │
│   │   ├── vllm-mistral-int4  → mistral-3-int4-predictor:8080            │  │
│   │   ├── vllm-mistral-bf16  → mistral-3-bf16-predictor:8080            │  │
│   │   ├── vllm-devstral      → devstral-2-predictor:8080                │  │
│   │   ├── vllm-gpt-oss       → gpt-oss-20b-predictor:8080               │  │
│   │   └── vllm-granite-agent → granite-8b-agent-predictor:8080          │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                   InferenceServices (Step-05)                         │  │
│   │                                                                       │  │
│   │   ┌───────────────┐ ┌───────────────┐ ┌───────────────┐              │  │
│   │   │mistral-3-bf16 │ │mistral-3-int4 │ │  devstral-2   │              │  │
│   │   │   (4 GPU)     │ │   (1 GPU)     │ │   (4 GPU)     │              │  │
│   │   └───────────────┘ └───────────────┘ └───────────────┘              │  │
│   │                                                                       │  │
│   │   ┌───────────────┐ ┌───────────────┐                                │  │
│   │   │  gpt-oss-20b  │ │granite-8b-agt │                                │  │
│   │   │   (4 GPU)     │ │   (1 GPU)     │                                │  │
│   │   └───────────────┘ └───────────────┘                                │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Support Status

| Component | Status | Notes |
|-----------|--------|-------|
| **GenAI Studio UI** | GA | Enabled via `genAiStudio: true` |
| **LlamaStack Operator** | Technology Preview (TP) | API may change between versions |
| **AI Asset Endpoints** | GA | Label-based model discovery |

> **Ref:** [RHOAI 3.0 Experimenting with Models in the GenAI Playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/experimenting_with_models_in_the_gen_ai_playground/index)

## Prerequisites

### 1. Steps 01-05 Completed

```bash
# Verify InferenceServices are deployed
oc get inferenceservice -n private-ai

# Expected: 5 models with AI Asset labels
oc get inferenceservice -n private-ai -l 'opendatahub.io/genai-asset=true'
```

### 2. Dashboard Flags Enabled

Verify in `gitops/step-02-rhoai/base/rhoai-operator/dashboard-config.yaml`:

```yaml
spec:
  dashboardConfig:
    genAiStudio: true      # ✅ Required for Playground
```

### 3. LlamaStack Operator Managed

Verify in DataScienceCluster:

```bash
oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.llamastackoperator.managementState}'
# Expected: Managed
```

## Deployment

### A) One-shot (recommended)

```bash
./steps/step-06-private-ai-playground-maas/deploy.sh
```

### B) Step-by-step (manual)

```bash
# 1. Apply InferenceService AI Asset labels (if not already done)
for model in mistral-3-int4 mistral-3-bf16 devstral-2 gpt-oss-20b granite-8b-agent; do
  oc label inferenceservice $model -n private-ai opendatahub.io/genai-asset=true --overwrite
done

# 2. Apply LlamaStackDistribution and ConfigMap
oc apply -f gitops/step-06-private-ai-playground-maas/base/playground/llamastack.yaml

# 3. Wait for LlamaStack to be ready
oc wait llamastackdistribution/lsd-genai-playground -n private-ai \
  --for=jsonpath='{.status.phase}'=Ready --timeout=300s

# 4. Verify all providers are registered
oc get llamastackdistribution lsd-genai-playground -n private-ai \
  -o jsonpath='{.status.distributionConfig.providers}' | jq '[.[] | select(.api=="inference") | .provider_id]'
```

## Validation

### 1. LlamaStack Backend

```bash
# Check LlamaStackDistribution status
oc get llamastackdistribution -n private-ai
# Expected: lsd-genai-playground  Ready

# Verify all 5 vLLM providers are registered
oc get llamastackdistribution lsd-genai-playground -n private-ai \
  -o jsonpath='{.status.distributionConfig.providers}' | \
  jq '[.[] | select(.provider_type=="remote::vllm") | {id: .provider_id, url: .config.url}]'
```

### 2. AI Asset Endpoints

```bash
# All 5 models should have the genai-asset label
oc get inferenceservice -n private-ai \
  -l 'opendatahub.io/genai-asset=true' \
  -o custom-columns='NAME:.metadata.name,USE-CASE:.metadata.annotations.opendatahub\.io/genai-use-case,READY:.status.conditions[?(@.type=="Ready")].status'
```

Expected output:
```
NAME               USE-CASE                    READY
devstral-2         agentic coding assistant    True
gpt-oss-20b        complex reasoning           True
granite-8b-agent   agentic tool-calling        True
mistral-3-bf16     enterprise chat assistant   True
mistral-3-int4     chat assistant              True
```

### 3. GenAI Playground UI

1. Open RHOAI Dashboard
2. Navigate to **GenAI Studio** → **Playground**
3. Select a **running** model from the dropdown (e.g., `mistral-3-int4`)
4. Enter a test prompt: `"Explain Kubernetes in one sentence."`
5. Verify response is generated

> **Note:** Models with `minReplicas: 0` (not running) will show errors in Playground. Scale them up first or select a running model.

## Demo Scenarios

### Scenario 1: Prompt Engineering

**Story:** "Data scientists experiment with prompts before writing code."

1. Open **GenAI Studio > Playground**
2. Select **mistral-3-int4** (1-GPU, always running)
3. Test prompt: `"You are a helpful assistant. Summarize the benefits of containerization."`
4. Adjust **System Instructions** and observe response changes
5. **Key Message:** "Iterate on prompts visually before coding."

### Scenario 2: Model Comparison

**Story:** "Compare different model sizes on the same prompt."

1. In Playground, select **mistral-3-int4** (1-GPU quantized)
2. Send: `"Write a Python function to calculate Fibonacci numbers."`
3. Note the response quality and speed
4. Switch to **mistral-3-bf16** (4-GPU full precision) - same prompt
5. Compare response quality
6. **Key Message:** "Trade-off between efficiency and capability."

### Scenario 3: Kueue-Aware Model Selection

**Story:** "Understanding which models are available based on GPU allocation."

1. Check current GPU usage: `oc get pods -n private-ai | grep predictor`
2. In Playground, try selecting a **queued** model (e.g., `gpt-oss-20b`)
3. Observe error: "Model not available"
4. Use GPU Orchestrator notebook to scale models
5. **Key Message:** "Playground reflects real-time GPU availability."

## Troubleshooting

### Playground Shows No Models

**Symptom:** GenAI Playground model dropdown is empty.

**Root Cause:** No models have the `opendatahub.io/genai-asset: "true"` label.

**Solution:**
```bash
# Add AI Asset label to all InferenceServices
oc label inferenceservice --all -n private-ai opendatahub.io/genai-asset=true

# Verify
oc get inferenceservice -n private-ai -l 'opendatahub.io/genai-asset=true'
```

### Playground Returns Errors for a Model

**Symptom:** Selecting a model shows "Connection error" or timeout.

**Root Cause:** Model is not running (minReplicas: 0) or still loading.

**Solution:**
```bash
# Check which models are actually running
oc get pods -n private-ai | grep predictor

# Scale up the desired model
oc scale deployment <model>-predictor -n private-ai --replicas=1
```

### LlamaStack Pod CrashLoopBackOff

**Symptom:** `lsd-genai-playground` pod keeps restarting.

**Root Cause:** ConfigMap syntax error or invalid model URLs.

**Solution:**
```bash
# Check LlamaStack logs
oc logs deployment/lsd-genai-playground -n private-ai --tail=100

# Verify ConfigMap run.yaml syntax
oc get configmap llama-stack-config -n private-ai -o yaml
```

### Model Works Directly but Not in Playground

**Symptom:** `curl` to model URL works, but Playground fails.

**Root Cause:** LlamaStack `VLLM_MAX_TOKENS` exceeds model's `--max-model-len`.

**Solution:**
```bash
# Check model context length
oc get inferenceservice <model> -n private-ai -o jsonpath='{.spec.predictor.model.args}' | tr ',' '\n' | grep max-model-len

# LlamaStack sends max_tokens=4096 by default
# Model must have --max-model-len > 4096 + input_tokens
# Recommended: --max-model-len=16384 or higher
```

## GitOps Structure

```
gitops/step-06-private-ai-playground-maas/
├── base/
│   ├── kustomization.yaml              # Main kustomization
│   └── playground/
│       ├── kustomization.yaml
│       └── llamastack.yaml             # LlamaStackDistribution + ConfigMap

steps/step-06-private-ai-playground-maas/
├── deploy.sh                           # Deployment script
└── README.md                           # This file
```

## Key Configuration Patterns

### AI Asset Label (on InferenceService)

```yaml
metadata:
  labels:
    opendatahub.io/genai-asset: "true"  # Enables AI Asset Endpoints
  annotations:
    opendatahub.io/model-type: generative
    opendatahub.io/genai-use-case: "chat assistant"
```

### LlamaStack Model Registration (in ConfigMap)

```yaml
models:
- provider_id: vllm-mistral-int4      # Must match provider in providers.inference
  model_id: mistral-3-int4            # Model name for Playground
  model_type: llm
  metadata:
    display_name: "Mistral-3 INT4 (1-GPU)"
```

### vLLM Provider Configuration

```yaml
providers:
  inference:
  - provider_id: vllm-mistral-int4
    provider_type: remote::vllm
    config:
      url: http://mistral-3-int4-predictor.private-ai.svc.cluster.local:8080/v1
      max_tokens: ${env.VLLM_MAX_TOKENS:=4096}
      tls_verify: false  # Internal cluster communication
```

## Rollback / Cleanup

```bash
# 1. Delete LlamaStackDistribution (operator cleans up deployment/service)
oc delete llamastackdistribution lsd-genai-playground -n private-ai

# 2. Delete ConfigMap
oc delete configmap llama-stack-config -n private-ai

# 3. Remove AI Asset labels (optional - models still work without them)
oc label inferenceservice --all -n private-ai opendatahub.io/genai-asset-

# 4. Delete Argo CD Application (if using GitOps)
oc delete application step-06-private-ai-playground-maas -n openshift-gitops
```

## Official Documentation

- [RHOAI 3.0 Experimenting with Models in the GenAI Playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/experimenting_with_models_in_the_gen_ai_playground/index)
- [RHOAI 3.0 Configuring a Playground for Your Project](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/experimenting_with_models_in_the_gen_ai_playground/index#configuring-a-playground-for-your-project_rhoai-user)
- [RHOAI 3.0 Support Matrix](https://access.redhat.com/articles/7019198)

---

## Future Enhancement: Models-as-a-Service (MaaS)

> **Status:** Developer Preview (DP) as of RHOAI 3.0  
> **Target:** Implement when MaaS reaches Technology Preview (TP)

### What is MaaS?

Models-as-a-Service provides a **unified API gateway** for all deployed models with:
- **Centralized endpoint**: `https://maas.apps.cluster.../llm/{model}/v1/...`
- **API Key authentication** via Authorino
- **Rate limiting** via Limitador (per-user, per-tier)
- **Usage tracking** for billing/chargeback
- **Tiered access** (free, premium, enterprise)

### Current State vs MaaS

| Feature | Current (Step-05/06) | With MaaS |
|---------|---------------------|-----------|
| **Endpoint** | Per-model URLs | Unified `/llm/{model}/` |
| **Auth** | None (internal) | API Keys |
| **Rate Limits** | None | Configurable tiers |
| **Billing** | None | Token tracking |
| **Runtime** | vLLM | LLM-D (Distributed) |

### Why Not Now?

1. **Developer Preview** - Not production-ready, API may change
2. **Missing dependency** - Requires **Red Hat Connectivity Link 1.2** operator
3. **Runtime migration** - Requires LLM-D, not compatible with current vLLM deployments
4. **Demo scope** - Our focus is Kueue GPU scheduling, not API management

### Prerequisites for MaaS (When TP Available)

| Component | Required Version | Purpose |
|-----------|------------------|---------|
| OpenShift | ≥ 4.19.9 | Cluster platform |
| RHOAI Operator | 3.x | AI platform |
| **Connectivity Link** | 1.2+ | Gateway policies, rate limiting |
| **LLM-D Runtime** | Latest | Distributed inference (not vLLM) |

### Placeholder GitOps Structure

```
gitops/step-06-private-ai-playground-maas/
├── base/
│   ├── kustomization.yaml          # Excludes maas/ for now
│   ├── playground/                 # ✅ Active
│   │   └── llamastack.yaml
│   └── maas/                       # ⏸️ Placeholder (not applied)
│       ├── inference-gateway.yaml  # InferenceGateway CR (when CRD available)
│       ├── api-key-secret.yaml     # Demo API keys
│       └── gateway-api-alternative.yaml  # Manual Gateway+HTTPRoute option
```

### Implementation Steps (Future)

When MaaS reaches Technology Preview:

```bash
# 1. Install Connectivity Link Operator
oc apply -f connectivity-link-subscription.yaml

# 2. Deploy MaaS infrastructure (official script)
curl -sSLo deploy-rhoai-stable.sh \
  https://raw.githubusercontent.com/opendatahub-io/maas-billing/refs/tags/0.0.1/deployment/scripts/deploy-rhoai-stable.sh
MAAS_REF="0.0.1" ./deploy-rhoai-stable.sh

# 3. Verify maas-default-gateway
oc get gateway maas-default-gateway -n openshift-ingress

# 4. Migrate models to LLM-D runtime
# (Re-deploy InferenceServices with Distributed Inference Server)

# 5. Enroll models in MaaS
oc label inferenceservice <model> -n private-ai maas.opendatahub.io/enabled=true
```

### Current Access Pattern (Without MaaS)

Direct InferenceService URLs work for development/demo:

```bash
# List available model endpoints
oc get inferenceservice -n private-ai -o custom-columns="MODEL:.metadata.name,URL:.status.url"

# Call model directly (no auth required for internal access)
curl -k https://mistral-3-int4-private-ai.apps.cluster.../v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "RedHatAI/Mistral-Small-24B-Instruct-2501-quantized.w4a16",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Official References

- [Introducing Models-as-a-Service in OpenShift AI](https://developers.redhat.com/articles/2025/11/25/introducing-models-service-openshift-ai) (Developer Preview announcement)
- [MaaS Community Documentation](https://opendatahub-io.github.io/models-as-a-service/latest/)
- [MaaS GitHub Repository](https://github.com/opendatahub-io/maas-billing)
- [RHOAI 3.0 Support Matrix](https://access.redhat.com/articles/7019198) - Check MaaS support status

---

## Next Steps

- **RAG Integration**: Upload documents to Playground for context-aware responses
- **MCP Servers**: Configure tool-calling capabilities  
- **Step 07**: Production RAG Pipeline with LangChain
- **MaaS**: Implement when it reaches Technology Preview
