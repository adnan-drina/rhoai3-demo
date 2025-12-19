# Step 01: GPU Infrastructure

Deploys NVIDIA GPU Operator for GPU node enablement.

## Deploy

```bash
./deploy.sh [--wait] [--sync]
```

## Verify

```bash
oc get csv -n nvidia-gpu-operator
oc get clusterpolicy
```
