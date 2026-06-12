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
  Do NOT use for deploying or re-deploying stages (use env-deploy-and-evaluate),
  troubleshooting failures (use env-troubleshoot), or chatbot changes
  (use rhoai-chatbot-customization).
---

# Manage Demo Resources

Scale model-serving resources and MachineSets (GPU nodes) without conflicting
with ArgoCD. Active reimplementation should support RHOAI `LLMInferenceService`
for the private Nemotron model; legacy `InferenceService` patterns are reference
material only.

## Reimplementation Status

Stage 120 owns GPU MachineSet scaling guidance. Stage 210 enables the model
serving platform through the shared Stage 110 RHOAI owner; it does not create a
separate Argo CD Application. Model endpoint scaling remains planned until
Stage 220 creates active MaaS/Nemotron resources.

Do not run scripts from `backup/legacy-implementation-2026-06-09/` unless the
user explicitly asks to restore or inspect the legacy implementation.

## Prerequisites

- Logged in with `oc` (cluster-admin)
- ArgoCD Applications for the GPU infrastructure and shared RHOAI owner have
  documented `selfHeal` behavior for intentional scale operations

## Resource Inventory

Discover the current state before making changes:

```bash
# Models
oc get llminferenceservice -n models-as-a-service
oc get isvc -n models-as-a-service

# GPU MachineSets
oc get machineset -n openshift-machine-api -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas'

# ArgoCD sync status
for app in stage-110-rhoai-base-platform stage-120-gpu-as-a-service; do
  echo "$app: $(oc get application $app -n openshift-gitops -o jsonpath='{.status.sync.status}/{.status.health.status}')"
done
```

## Scale Down a Model

For the current target architecture, first verify the active
`LLMInferenceService` schema and GitOps owner. The imported implementation uses
`spec.replicas` for `nemotron-3-nano-30b-a3b`; scale only through the supported
field or through GitOps.

```bash
oc explain llminferenceservice.spec.replicas
oc patch llminferenceservice nemotron-3-nano-30b-a3b -n models-as-a-service --type merge \
  -p '{"spec":{"replicas":0}}'
```

**Models in this demo:**

| Model | GPU | Purpose | Safe to stop? |
|-------|-----|---------|---------------|
| `nemotron-3-nano-30b-a3b` | 1× `g6e.2xlarge` per replica | Primary private MaaS GenAI model | Private GenAI, RAG, MCP, guardrails, Playground, and private evals stop |
| OpenAI `gpt-5.4-mini` external MaaS model | 0 cluster GPU | Approved external model path using MaaS resource alias `gpt-5-4-mini` | MaaS external calls fail only if the MaaS model, policy, or provider credentials are removed |
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

**Scale-down sequence for the private Nemotron GPU path:**
```bash
oc patch llminferenceservice nemotron-3-nano-30b-a3b -n models-as-a-service --type merge -p '{"spec":{"replicas":0}}'
sleep 60
oc scale machineset -n openshift-machine-api -l cluster-api/accelerator=nvidia-gpu --replicas=0
```

## Scale Back Up

Reverse order — start the MachineSet first, wait for the node, then start models.

```bash
# 1. Scale up MachineSet
oc scale machineset <MACHINESET_NAME> -n openshift-machine-api --replicas=1

# 2. Wait for node ready (~5 min for GPU nodes)
oc get nodes -l node-role.kubernetes.io/gpu --watch

# 3. Restore model
oc patch llminferenceservice nemotron-3-nano-30b-a3b -n models-as-a-service --type merge \
  -p '{"spec":{"replicas":1}}'
```

Stage 210 only enables the model-serving platform. Later model-serving and MaaS
stages must document their own model scale-up guard before this command path is
treated as active:

```bash
./stage-210-model-serving-foundation/deploy.sh
```

## Restore Full Git State

To bring everything back to the Git-declared state, sync via ArgoCD:

```bash
# Sync the shared RHOAI owner after Stage 210 platform changes
oc patch application stage-110-rhoai-base-platform -n openshift-gitops \
  --type merge -p '{"operation":{"sync":{}}}'

# Or sync both
for app in stage-110-rhoai-base-platform stage-120-gpu-as-a-service; do
  oc patch application "$app" -n openshift-gitops --type merge -p '{"operation":{"sync":{}}}'
done
```

Or click **Sync** in the ArgoCD UI on the OutOfSync application.

## Verification

After any scaling operation, verify the state:

```bash
# Check ArgoCD shows expected status
oc get application stage-110-rhoai-base-platform stage-120-gpu-as-a-service -n openshift-gitops \
  -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

# Check model readiness
oc get llminferenceservice -n models-as-a-service
oc get isvc -n models-as-a-service

# Check node availability
oc get nodes -l node-role.kubernetes.io/gpu
```

## ArgoCD Behavior Reference

| Action | ArgoCD Status | Auto-heal? |
|--------|---------------|------------|
| Manual scale down model | OutOfSync | No (selfHeal=false) |
| Manual scale down MachineSet | Synced or ignored diff | No; Stage 120 ignores `MachineSet.spec.replicas` |
| Push Git change to GPU stage or shared RHOAI owner | Auto-syncs | Yes (automated=true) |
| Click Sync in ArgoCD UI | Synced | Restores Git state |
