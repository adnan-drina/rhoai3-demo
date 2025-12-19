# Step 03: LLM Deployment

Deploys LLMs using vLLM serving runtime.

## Prerequisites

Set `HF_TOKEN` in `.env` if using gated models.

## Deploy

```bash
./deploy.sh [--wait] [--sync]
```

## Verify

```bash
oc get inferenceservice -n rhoai-models
```
