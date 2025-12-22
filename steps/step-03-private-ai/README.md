# Step 03: Private AI

Deploy private LLM models using RHOAI 3.0 model serving capabilities.

## Prerequisites

- [x] Step 02 completed (RHOAI 3.0 platform)
- [x] GPU nodes available
- [ ] Set `HF_TOKEN` in `.env` if using gated models (e.g., Llama)

## Deploy

```bash
./steps/step-03-private-ai/deploy.sh
```

## Verify

```bash
# Check InferenceServices
oc get inferenceservice -n rhoai-models

# Check model pods
oc get pods -n rhoai-models
```
