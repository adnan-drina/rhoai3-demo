# Step 03: Private AI - GPU as a Service

**"From Static Platform to GPU-as-a-Service"** — Dynamic GPU allocation, quota enforcement, S3 storage, and role-based access control.

## The Business Story

Without guardrails, every user consumes every GPU. Step-03 transforms RHOAI into a **GPU-as-a-Service** model: MinIO provides shared S3 storage, Hardware Profiles with `nodeSelector` + `tolerations` direct workloads to the right GPU nodes, and two demo personas demonstrate the Service Governor / Service Consumer split.

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
│  Hardware Profiles: nodeSelector ──► GPU Nodes (5 GPUs)       │
└──────────────────────────────┬──────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────┐
│       GPU Nodes (g6.4xlarge / g6.12xlarge) · NVIDIA L4      │
└─────────────────────────────────────────────────────────────┘
```

| Component | Purpose |
|-----------|---------|
| **MinIO** | S3-compatible storage (models, pipelines, workbench data) |
| **Auth** | HTPasswd: `ai-admin` / `ai-developer` (password: `redhat123`) |
| **RBAC** | `ai-admin` → admin role, `ai-developer` → edit role in `private-ai` |
| **Data Connection** | Auto-appears in Dashboard dropdowns for workbenches and model serving |

## Demo Walkthrough

### Scene 1: The Service Consumer Experience

Login as `ai-developer` (`redhat123`) in the RHOAI Dashboard.

1. Go to **Data Science Projects** → **private-ai**
2. Create a **Workbench** → select Hardware Profile **"NVIDIA L4 1GPU"**
3. Under Data Connection, **"MinIO Storage"** appears automatically
4. Click **Create** → workbench starts, scheduled to GPU node

**What to say:** *"The developer selects a GPU profile from a curated list. The Hardware Profile's nodeSelector targets the right GPU node type. The S3 storage is pre-configured — no credentials to hunt for."*

### Scene 2: The Service Governor View

Login as `ai-admin` (`redhat123`) in the RHOAI Dashboard.

1. Go to **Observe & monitor** → **Workload metrics**
2. Select project **private-ai**
3. View GPU utilization via the Grafana dashboards deployed in step-07
4. Check node capacity: `oc describe node -l nvidia.com/gpu.present=true`

**What to say:** *"The platform admin monitors GPU utilization through Grafana dashboards and node metrics. Hardware Profiles ensure workloads land on the correct GPU node type."*

### Scene 3: GPU Scheduling in Action

This is the key demo moment — showing what happens when demand exceeds supply.

```bash
# Deploy two workbenches competing for 1 GPU
oc apply -k gitops/step-03-private-ai/gpu-as-a-service-demo/

# Watch the scheduling
oc get pods -n private-ai -w
# demo-workbench-1 → Running (GPU available)
# demo-workbench-2 → Pending (no GPU node capacity)

# Release GPU
oc delete notebook demo-workbench-1 -n private-ai
# Watch demo-workbench-2 automatically start!

# Cleanup
oc delete -k gitops/step-03-private-ai/gpu-as-a-service-demo/
```

**What to say:** *"When the first workbench takes the last GPU, the second one doesn't fail — it stays Pending. The moment the GPU is released, Kubernetes schedules the next workload automatically. Hardware Profiles ensure every workload targets the correct GPU node type. And with idle culling set to 15 minutes, forgotten notebooks release GPUs back to the pool."*

### Scene 4: MinIO Storage Console

```bash
MINIO_URL=$(oc get route minio-console -n minio-storage -o jsonpath='{.spec.host}')
echo "https://${MINIO_URL}"
# Login: minio-admin / minio-secret-123
```

Show the buckets: `rhoai-storage`, `models`, `pipelines`. These are where all subsequent steps store their data.

## Design Decisions

> **Direct GPU scheduling (no Kueue):** Kueue was evaluated and removed because its SchedulingGate mechanism gates ALL pods in managed namespaces — including build pods, DSPA pipeline executors, and chatbot Deployments — not just GPU workloads. GPU scheduling uses direct `nodeSelector` + `tolerations` defined in Hardware Profiles and InferenceService manifests. This provides reliable GPU placement without the SchedulingGate side effects.

> **Design Decision:** OpenShift Groups are created by `deploy.sh` (not ArgoCD) because ArgoCD cannot parse the `user.openshift.io/v1 Group` schema.

> **No `opendatahub.io/managed` label on `storage-config`:** The ODH model controller watches for secrets with `opendatahub.io/managed: "true"` and deletes any it did not create. Since ArgoCD creates `storage-config`, the controller deletes it within seconds, causing an infinite create-delete loop. This label is only needed on `minio-connection` (the Data Connection that appears in Dashboard dropdowns), not on `storage-config` (the KServe credential used by storage-initializer). See also: `.cursor/rules/30-secrets-and-certs.mdc`.

## References

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
