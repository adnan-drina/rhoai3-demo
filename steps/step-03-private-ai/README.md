# Step 03: Private AI - GPU as a Service

**"From Static Platform to GPU-as-a-Service"** — Dynamic GPU allocation, quota enforcement, S3 storage, and role-based access control.

## The Business Story

Without guardrails, every user consumes every GPU. Step-03 transforms RHOAI into a **GPU-as-a-Service** model: MinIO provides shared S3 storage, Kueue enforces fair-share GPU quotas, and two demo personas demonstrate the Service Governor / Service Consumer split. When demand exceeds capacity, workloads queue — no GPU hoarding, no manual intervention.

## What It Does

```
ai-admin (Governor)     ai-developer (Consumer)     MinIO (S3)
       │                       │                       │
       ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   RHOAI Dashboard (3.3)                      │
│  Hardware Profiles · Distributed Workloads · Data Connections│
└──────────────────────────────┬──────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  Kueue: LocalQueue (default) ──► ClusterQueue (5 GPUs)      │
└──────────────────────────────┬──────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────┐
│       GPU Nodes (g6.4xlarge / g6.12xlarge) · NVIDIA L4      │
└─────────────────────────────────────────────────────────────┘
```

| Component | Purpose |
|-----------|---------|
| **MinIO** | S3-compatible storage (models, pipelines, workbench data) |
| **Kueue** | GPU quota: 5 GPUs (main) + 2 reserved (llm-d), fair-share scheduling |
| **Auth** | HTPasswd: `ai-admin` / `ai-developer` (password: `redhat123`) |
| **RBAC** | `ai-admin` → admin role, `ai-developer` → edit role in `private-ai` |
| **Data Connection** | Auto-appears in Dashboard dropdowns for workbenches and model serving |

## Demo Walkthrough

### Scene 1: The Service Consumer Experience

Login as `ai-developer` (`redhat123`) in the RHOAI Dashboard.

1. Go to **Data Science Projects** → **private-ai**
2. Create a **Workbench** → select Hardware Profile **"NVIDIA L4 1GPU"**
3. Under Data Connection, **"MinIO Storage"** appears automatically
4. Click **Create** → workbench starts, Kueue admits it

**What to say:** *"The developer selects a GPU profile from a curated list. Behind the scenes, Kueue checks the quota pool — if GPUs are available, it admits immediately. The S3 storage is pre-configured — no credentials to hunt for."*

### Scene 2: The Service Governor View

Login as `ai-admin` (`redhat123`) in the RHOAI Dashboard.

1. Go to **Observe & monitor** → **Workload metrics**
2. Select project **private-ai**
3. Click **Distributed workload status** — see Admitted vs Pending workloads
4. Click **Project metrics** — see GPU/CPU usage per queue

**What to say:** *"The platform admin sees every workload — who's using GPUs, who's waiting, how much capacity remains. No manual allocation, no tickets."*

### Scene 3: GPU Queuing in Action

This is the key demo moment — showing what happens when demand exceeds supply.

```bash
# Deploy two workbenches competing for 1 GPU
oc apply -k gitops/step-03-private-ai/gpu-as-a-service-demo/

# Watch the queuing
oc get workloads -n private-ai -w
# demo-workbench-1 → Admitted (Running)
# demo-workbench-2 → Pending (Queued — not enough GPUs)

# Release GPU
oc delete notebook demo-workbench-1 -n private-ai
# Watch demo-workbench-2 automatically start!

# Cleanup
oc delete -k gitops/step-03-private-ai/gpu-as-a-service-demo/
```

**What to say:** *"When the first workbench takes the last GPU, the second one doesn't fail — it queues. The moment the GPU is released, Kueue admits the next workload automatically. This is fair-share scheduling with zero manual intervention. And with idle culling set to 15 minutes, forgotten notebooks release GPUs back to the pool."*

### Scene 4: MinIO Storage Console

```bash
MINIO_URL=$(oc get route minio-console -n minio-storage -o jsonpath='{.spec.host}')
echo "https://${MINIO_URL}"
# Login: minio-admin / minio-secret-123
```

Show the buckets: `rhoai-storage`, `models`, `pipelines`. These are where all subsequent steps store their data.

## Design Decisions

> **Known Limitation (RHOAI 3.3): No Kueue Dashboard workload visibility in mixed-workload namespaces.** The `private-ai` namespace does **not** have `kueue.openshift.io/managed: "true"`. Without this label, the Dashboard's "Distributed workload status" page is empty (no Workload objects created). However, adding the label causes ALL pods in the namespace to be SchedulingGated — not just GPU pods. This is because RHOAI 3.3 auto-injects `kueue.x-k8s.io/queue-name: default` on every pod in managed namespaces via two mechanisms: (1) the `defaultLocalQueueName: "default"` in the DataScienceCluster Kueue config, and (2) the `kueue.x-k8s.io/default-queue: "true"` annotation on the LocalQueue. Neither can be disabled without breaking Dashboard integration. Tested 4 times with different configurations (`Pod`-only frameworks, `Deployment`-only, `labelPolicy: QueueName`, default-queue annotation removal) — all result in non-GPU pods being gated (build pods, DSPA pipelines, chatbot, MCP servers). The `kueue.x-k8s.io/topology` SchedulingGate never clears on pods without node affinity. **Workaround:** GPU tolerations are defined directly in InferenceService manifests (step-05). The `kueue.x-k8s.io/queue-name: default` label on ISVCs still enables CLI tracking. **Future fix:** Separate GPU workloads into a dedicated namespace with the managed label, keeping non-GPU workloads in `private-ai`. Ref: [Managing workloads with Kueue](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_openshift_ai/managing-workloads-with-kueue).

> **Queue separation:** `default` for vLLM workloads (5 GPUs) and `llmd` for llm-d distributed inference (2 GPUs reserved). This follows the RHOAI pattern of hardware-specific quota separation — llm-d always has guaranteed capacity even when vLLM saturates the main queue.

> **Design Decision:** OpenShift Groups are created by `deploy.sh` (not ArgoCD) because ArgoCD cannot parse the `user.openshift.io/v1 Group` schema.

> **No `opendatahub.io/managed` label on `storage-config`:** The ODH model controller watches for secrets with `opendatahub.io/managed: "true"` and deletes any it did not create. Since ArgoCD creates `storage-config`, the controller deletes it within seconds, causing an infinite create-delete loop. This label is only needed on `minio-connection` (the Data Connection that appears in Dashboard dropdowns), not on `storage-config` (the KServe credential used by storage-initializer). See also: `.cursor/rules/30-secrets-and-certs.mdc`.

## Troubleshooting

### Dashboard "Distributed workload status" is empty

**Symptom:** Observe & monitor > Distributed workload status shows no workloads, even though GPU models are running.

**Root Cause:** The `private-ai` namespace does not have `kueue.openshift.io/managed: "true"`. Without this label, Kueue creates no Workload objects.

**Why we can't add the label:** RHOAI 3.3 auto-injects `kueue.x-k8s.io/queue-name: default` on ALL pods in managed namespaces (via DSC `defaultLocalQueueName` and LocalQueue `default-queue` annotation). This gates every pod — including build pods, DSPA pipeline executors, chatbot, Docling, MCP servers, and Grafana. The `kueue.x-k8s.io/topology` SchedulingGate never clears on pods without GPU node affinity, permanently blocking them.

**Tested configurations (all failed):**

| Attempt | Configuration | Result |
|---------|--------------|--------|
| 1 | Namespace label + Deployment framework | All Deployments gated |
| 2 | Namespace label + Pod framework only | All pods gated, build pods stuck permanently |
| 3 | Namespace label + `labelPolicy: QueueName` | Webhook still auto-labels all pods via default-queue |
| 4 | Namespace label + default-queue annotation removed | DSC `defaultLocalQueueName` still auto-labels all pods |

**Workaround:** GPU workloads function correctly without Dashboard visibility. Use CLI: `oc get inferenceservice -n private-ai` and `oc get pods -l kueue.x-k8s.io/queue-name -n private-ai`.

**Future fix:** Separate GPU InferenceServices into a dedicated `gpu-workloads` namespace with the managed label. Keep non-GPU workloads (DSPA, chatbot, MCP, etc.) in `private-ai` without it.

## References

- [RHOAI 3.3 — Managing Workloads with Kueue](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_openshift_ai/managing-workloads-with-kueue)
- [RHOAI 3.3 — Managing Resources](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/managing_resources/index)
- [RHOAI 3.3 — User Management](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_users/index)

## Operations

```bash
./steps/step-03-private-ai/deploy.sh     # Deploy via ArgoCD
./steps/step-03-private-ai/validate.sh   # Verify all components
```

## Next Steps

- **Step 04**: [Model Registry](../step-04-model-registry/README.md) — Enterprise model governance
- **Step 05**: [LLM on vLLM](../step-05-llm-on-vllm/README.md) — Deploy models with GPU-as-a-Service
