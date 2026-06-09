---
name: env-manage-resources
metadata:
  author: rhoai3-demo
  version: 1.1.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Demo Environment"
disable-model-invocation: true
description: >
  Scale models and GPU MachineSets up or down in the RHOAI demo environment
  once active GitOps Applications and resource-management scripts exist.
  During the reimplementation, use this skill to rebuild the resource workflow
  from legacy references.
  Use when the user wants to stop/start models, scale GPU nodes, save costs,
  manage cluster resources, reduce cloud spend overnight, prepare for demo
  shutdown, or recover from shutdown by bringing resources back up. Also use
  when the user asks "how do I shut down the demo?" or "which models can I stop
  safely?".
  Do NOT use for deploying or re-deploying steps (use env-deploy-and-evaluate),
  troubleshooting failures (use env-troubleshoot), or chatbot changes
  (use rhoai-chatbot-customization).
---

# Manage Demo Resources

Scale InferenceServices (models) and MachineSets (GPU nodes) without
conflicting with ArgoCD. Steps 01 and 05 have `selfHeal: false`, so manual
changes show OutOfSync but are not auto-reverted.

## Reimplementation Status

The active implementation is being rewritten. No active resource-management
scripts or current GitOps Applications exist yet. Treat the resource inventory,
step names, and legacy command references in this skill as reference material
for rebuilding the workflow, not as active-project instructions.

Do not run scripts from `backup/legacy-implementation-2026-06-09/` unless the
user explicitly asks to restore or inspect the legacy implementation.

## Prerequisites

- Logged in with `oc` (cluster-admin)
- ArgoCD Applications for step-01 and step-05 have `selfHeal: false`

## Resource Inventory

Discover the current state before making changes:

```bash
# Models
oc get isvc -n maas -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,MIN_REPLICAS:.spec.predictor.minReplicas'

# GPU MachineSets
oc get machineset -n openshift-machine-api -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas'

# ArgoCD sync status
for app in step-01-gpu-and-prereq step-05-maas-model-serving; do
  echo "$app: $(oc get application $app -n openshift-gitops -o jsonpath='{.status.sync.status}/{.status.health.status}')"
done
```

## Scale Down a Model

Set `minReplicas: 0` — KServe scales the predictor pod to zero after the
grace period (~60s). The ISVC resource remains; only the pod is removed.

```bash
oc patch isvc <MODEL_NAME> -n maas --type merge \
  -p '{"spec":{"predictor":{"minReplicas":0}}}'
```

**Models in this demo:**

| Model | GPU | Purpose | Safe to stop? |
|-------|-----|---------|---------------|
| `granite-8b-agent` | 1× g6.4xl | Primary MaaS agent model | Chatbot, RAG, MCP, and guardrails will stop |
| `mistral-3-bf16` | 4× g6.12xl | MaaS chat and judge model | Playground and eval pipelines will fail |
| `hap-detector` | 0 (CPU) | HAP guardrail | Guardrails degrade |
| `prompt-injection-detector` | 0 (CPU) | Prompt injection guardrail | Guardrails degrade |
| `face-recognition` | 0 (CPU) | YOLO face detection | Face recognition stops |

## Scale Down a GPU MachineSet

Scale the MachineSet to 0 replicas. The GPU node drains and terminates.
Pods on that node are evicted (models become unavailable).

```bash
# Scale down
oc scale machineset <MACHINESET_NAME> -n openshift-machine-api --replicas=0

# Monitor node drain
oc get nodes -l node-role.kubernetes.io/gpu --watch
```

**Dependency chain — scale down in this order:**

1. Stop models that use the GPU node first
2. Then scale down the MachineSet

**Scale-down sequence for 4-GPU node (Mistral):**
```bash
oc patch isvc mistral-3-bf16 -n maas --type merge -p '{"spec":{"predictor":{"minReplicas":0}}}'
sleep 60
oc scale machineset $(oc get machineset -n openshift-machine-api --no-headers | grep g6-12xlarge | awk '{print $1}') -n openshift-machine-api --replicas=0
```

**Scale-down sequence for 1-GPU node (Granite):**
```bash
oc patch isvc granite-8b-agent -n maas --type merge -p '{"spec":{"predictor":{"minReplicas":0}}}'
sleep 60
oc scale machineset $(oc get machineset -n openshift-machine-api --no-headers | grep g6-4xlarge | awk '{print $1}') -n openshift-machine-api --replicas=0
```

## Scale Back Up

Reverse order — start the MachineSet first, wait for the node, then start models.

```bash
# 1. Scale up MachineSet
oc scale machineset <MACHINESET_NAME> -n openshift-machine-api --replicas=1

# 2. Wait for node ready (~5 min for GPU nodes)
oc get nodes -l node-role.kubernetes.io/gpu --watch

# 3. Restore model
oc patch isvc <MODEL_NAME> -n maas --type merge \
  -p '{"spec":{"predictor":{"minReplicas":1}}}'
```

In the legacy implementation, Step 05 also performed this scale-up guard
automatically unless `RHOAI_SKIP_GPU_SCALE=true` was set. Recreate that behavior
before relying on this command path:

```bash
./steps/step-05-maas-model-serving/deploy.sh
```

## Restore Full Git State

To bring everything back to the Git-declared state, sync via ArgoCD:

```bash
# Sync a specific app
oc patch application step-05-maas-model-serving -n openshift-gitops \
  --type merge -p '{"operation":{"sync":{}}}'

# Or sync both
for app in step-01-gpu-and-prereq step-05-maas-model-serving; do
  oc patch application "$app" -n openshift-gitops --type merge -p '{"operation":{"sync":{}}}'
done
```

Or click **Sync** in the ArgoCD UI on the OutOfSync application.

## Verification

After any scaling operation, verify the state:

```bash
# Check ArgoCD shows expected status
oc get application step-01-gpu-and-prereq step-05-maas-model-serving -n openshift-gitops \
  -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

# Check model readiness
oc get isvc -n maas

# Check node availability
oc get nodes -l node-role.kubernetes.io/gpu
```

## ArgoCD Behavior Reference

| Action | ArgoCD Status | Auto-heal? |
|--------|---------------|------------|
| Manual scale down model | OutOfSync | No (selfHeal=false) |
| Manual scale down MachineSet | OutOfSync | No (selfHeal=false) |
| Push Git change to step-01/05 | Auto-syncs | Yes (automated=true) |
| Click Sync in ArgoCD UI | Synced | Restores Git state |
