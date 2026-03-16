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

> **Kueue Pod integration (not Deployment):** The namespace has `kueue.openshift.io/managed: "true"` for Dashboard workload visibility, but the Kueue instance (step-01) excludes the `Deployment` framework. With `Deployment` enabled, Kueue SchedulingGates **all** Deployments in managed namespaces — including non-GPU pods (chatbot, Docling, DSPA, MCP servers). Instead, we use the `Pod` integration: only pods with `kueue.x-k8s.io/queue-name` label get Workload objects and quota tracking. Non-labeled pods bypass Kueue entirely. Ref: [Managing workloads with Kueue](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_openshift_ai/managing-workloads-with-kueue).

> **ResourceFlavor tolerations omitted:** ResourceFlavors define `nodeLabels` (for flavor matching) and `nodeTaints` (for admission topology) but intentionally omit `tolerations`. With the Pod integration, Kueue injects tolerations from the ResourceFlavor when unsuspending. If the pod already has a toleration with the same key+effect but a different operator (e.g. `Equal` vs `Exists`), Kubernetes rejects: *"existing toleration can not be modified"*. InferenceService manifests (step-05) define GPU tolerations directly. Kueue merges `nodeLabels` into the pod's `nodeSelector` via `MutablePodSchedulingDirectives` (OCP 4.20 / K8s 1.31+).

> **Queue separation:** `default` for vLLM workloads (5 GPUs) and `llmd` for llm-d distributed inference (2 GPUs reserved). This follows the RHOAI pattern of hardware-specific quota separation — llm-d always has guaranteed capacity even when vLLM saturates the main queue.

> **Design Decision:** OpenShift Groups are created by `deploy.sh` (not ArgoCD) because ArgoCD cannot parse the `user.openshift.io/v1 Group` schema.

> **No `opendatahub.io/managed` label on `storage-config`:** The ODH model controller watches for secrets with `opendatahub.io/managed: "true"` and deletes any it did not create. Since ArgoCD creates `storage-config`, the controller deletes it within seconds, causing an infinite create-delete loop. This label is only needed on `minio-connection` (the Data Connection that appears in Dashboard dropdowns), not on `storage-config` (the KServe credential used by storage-initializer). See also: `.cursor/rules/30-secrets-and-certs.mdc`.

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
