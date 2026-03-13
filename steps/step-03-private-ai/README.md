# Step 03: Private AI - GPU as a Service

**"From Static Platform to GPU-as-a-Service"** — Dynamic GPU allocation, quota enforcement, S3 storage, and role-based access control.

## The Business Story

Step-02 installed the RHOAI platform, but without guardrails every user can consume every GPU. Step-03 transforms RHOAI into a **GPU-as-a-Service** model: MinIO provides shared S3 storage, Kueue enforces GPU quotas with fair-share scheduling, and two demo personas (`ai-admin`, `ai-developer`) demonstrate the Service Governor / Service Consumer split.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     Private AI - GPU as a Service                        │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐           │
│   │  ai-admin    │     │ ai-developer │     │    MinIO     │           │
│   │  (Governor)  │     │  (Consumer)  │     │  (S3 Data)  │           │
│   └──────┬───────┘     └──────┬───────┘     └──────┬───────┘           │
│          │                    │                    │                    │
│          ▼                    ▼                    ▼                    │
│   ┌─────────────────────────────────────────────────────────────┐      │
│   │                  RHOAI Dashboard (3.3)                       │      │
│   │  Hardware Profiles · Distributed Workloads · Data Connections│      │
│   └──────────────────────────────┬──────────────────────────────┘      │
│                                  ▼                                      │
│   ┌─────────────────────────────────────────────────────────────┐      │
│   │                  Kueue (Queue Management)                    │      │
│   │  LocalQueue (default) ────► ClusterQueue (rhoai-main-queue) │      │
│   └──────────────────────────────┬──────────────────────────────┘      │
│                                  ▼                                      │
│   ┌─────────────────────────────────────────────────────────────┐      │
│   │             GPU Nodes (g6.4xlarge / g6.12xlarge)             │      │
│   │  NVIDIA L4 GPUs · Automatic Admission · Fair Queuing         │      │
│   └─────────────────────────────────────────────────────────────┘      │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## What Gets Deployed

| Component | Resources | Purpose |
|-----------|-----------|---------|
| **MinIO** | Namespace, Deployment, Service, Route, Init Job, PVC (10Gi) | S3-compatible storage for all RHOAI workloads |
| **Data Connection** | Secret `minio-connection` in `private-ai` | Auto-appears in Dashboard dropdowns |
| **Authentication** | HTPasswd Secret, OAuth config | Demo users: `ai-admin`/`ai-developer` (password: `redhat123`) |
| **RBAC** | RoleBindings | `ai-admin` → admin, `ai-developer` → edit in `private-ai` |
| **Kueue** | 2 ResourceFlavors, 2 ClusterQueues, 2 LocalQueues | GPU quota: 5 GPUs (main) + 2 GPUs (llm-d reserve) |
| **Namespace** | `private-ai` with Kueue labels | GPU-managed project |

### Kueue Queue Architecture

| Resource | Name | Purpose |
|----------|------|---------|
| ResourceFlavor | `nvidia-l4-1gpu` | Targets g6.4xlarge (1x L4) |
| ResourceFlavor | `nvidia-l4-4gpu` | Targets g6.12xlarge (4x L4) |
| ClusterQueue | `rhoai-main-queue` | Main GPU pool (5 GPUs) for vLLM |
| ClusterQueue | `rhoai-llmd-queue` | Reserved pool (2 GPUs) for llm-d |
| LocalQueue | `default` | Standard name → `rhoai-main-queue` |
| LocalQueue | `llmd` | llm-d workloads → `rhoai-llmd-queue` |

### Demo Credentials

| Username | Password | Role | RHOAI Persona |
|----------|----------|------|---------------|
| `ai-admin` | `redhat123` | Service Governor | RHOAI Admin |
| `ai-developer` | `redhat123` | Service Consumer | RHOAI User |

## Prerequisites

- Step 01 completed (GPU infrastructure, MachineSets, Kueue Operator)
- Step 02 completed (RHOAI 3.3 with Hardware Profiles)
- GPU nodes available with labels

## Deployment

### A) One-shot (recommended)

```bash
./steps/step-03-private-ai/deploy.sh
```

### B) Step-by-step

```bash
# 1. Apply ArgoCD Application
oc apply -f gitops/argocd/app-of-apps/step-03-private-ai.yaml

# 2. Wait for MinIO
oc rollout status deployment/minio -n minio-storage --timeout=120s
oc wait --for=condition=complete job/minio-init -n minio-storage --timeout=120s

# 3. Create OpenShift Groups (cannot be managed by ArgoCD)
oc adm groups new rhoai-admins ai-admin 2>/dev/null || oc adm groups add-users rhoai-admins ai-admin
oc adm groups new rhoai-users ai-developer 2>/dev/null || oc adm groups add-users rhoai-users ai-developer

# 4. Verify core resources
oc get secret minio-connection -n private-ai
oc get clusterqueue rhoai-main-queue
oc get localqueue default -n private-ai
```

## Validation

```bash
./steps/step-03-private-ai/validate.sh
```

### Manual checks

```bash
# S3 storage
oc get pods -n minio-storage
oc get route minio-console -n minio-storage -o jsonpath='{.spec.host}'

# Data Connection
oc get secret -n private-ai -l opendatahub.io/connection-type=s3

# Kueue
oc get localqueue default -n private-ai
oc get clusterqueue rhoai-main-queue

# Authentication
oc login -u ai-admin -p redhat123
oc login -u ai-developer -p redhat123
oc get groups | grep rhoai
```

## Demo Walkthrough

### 1. Login as `ai-developer` (Service Consumer)

In the RHOAI Dashboard:
1. Go to **Data Science Projects** → **private-ai**
2. Create a **Workbench** with Hardware Profile "NVIDIA L4 1GPU"
3. Select Data Connection "MinIO Storage" (appears automatically)

### 2. Login as `ai-admin` (Service Governor)

In the RHOAI Dashboard:
1. Go to **Observe & monitor** → **Workload metrics**
2. Select project **private-ai**
3. View **Distributed workload status**: Admitted vs Pending vs Running

### 3. GPU Queuing Demo

Demonstrates what happens when demand exceeds GPU quota:

```bash
# Deploy two workbenches competing for 1 GPU
oc apply -k gitops/step-03-private-ai/gpu-as-a-service-demo/

# Watch queuing behavior
oc get workloads -n private-ai -w
# demo-workbench-1 → Admitted (Running)
# demo-workbench-2 → Pending (Queued)

# Release GPU by deleting workbench-1
oc delete notebook demo-workbench-1 -n private-ai
# Watch workbench-2 automatically start

# Cleanup
oc delete -k gitops/step-03-private-ai/gpu-as-a-service-demo/
```

**Key messages:**
- No GPU hoarding — unused GPUs return to the pool
- Fair queuing — first-come-first-served
- Idle culling — inactive notebooks auto-stop after 15 minutes

## Troubleshooting

### MinIO Not Starting

```bash
oc get pods -n minio-storage
oc describe pod -n minio-storage -l app=minio
oc get pvc -n minio-storage
```

### Data Connection Not Appearing in Dashboard

Verify the secret has required labels:
```bash
oc get secret minio-connection -n private-ai -o yaml | grep -A5 labels
# Needs: opendatahub.io/dashboard: "true", opendatahub.io/managed: "true"
```

### Login Fails

```bash
oc get pods -n openshift-authentication
oc get secret htpass-secret -n openshift-config
```

### Workbench FailedScheduling

GPU nodes have taints. Workbenches need tolerations for `nvidia.com/gpu`:
```bash
oc get nodes -l nvidia.com/gpu.present=true -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

### ArgoCD: "unable to resolve parseableType for Group"

OpenShift Groups can't be managed by ArgoCD. They are created by `deploy.sh` instead:
```bash
oc adm groups new rhoai-admins ai-admin
oc adm groups new rhoai-users ai-developer
```

## GitOps Structure

```
gitops/step-03-private-ai/
├── base/
│   ├── kustomization.yaml
│   ├── minio/                    # S3 storage (namespace, deployment, init job)
│   ├── auth/                     # HTPasswd + OAuth
│   ├── rbac/                     # Project role bindings
│   ├── namespace.yaml            # private-ai (Kueue labels)
│   ├── data-connection.yaml      # MinIO S3 connection
│   ├── resource-flavors.yaml     # GPU node flavors
│   ├── cluster-queue.yaml        # GPU quota pools
│   └── local-queue.yaml          # LocalQueues (default + llmd)
└── gpu-as-a-service-demo/        # Manual apply for queuing demo
    ├── workbench-1.yaml
    └── workbench-2.yaml
```

## Design Decisions

> **Design Decision:** We do **not** set `kueue.openshift.io/managed: "true"` on the `private-ai` namespace. Only workloads with `kueue.x-k8s.io/queue-name: default` are managed by Kueue. Namespace-wide management gates all pods — including builds, chatbot deployments, and pipeline executors.

> **Design Decision:** OpenShift Groups are created by `deploy.sh` instead of ArgoCD because ArgoCD cannot parse the `user.openshift.io/v1 Group` schema for diff calculation.

> **Design Decision:** Idle culling is set to 15 minutes for the demo to quickly release GPUs. Production deployments should use longer timeouts.

> **Design Decision:** Queue separation — `default` for vLLM workloads (5 GPUs) and `llmd` for llm-d distributed inference (2 GPUs reserved). This ensures llm-d can always start even when vLLM saturates the main queue.

## References

- [RHOAI 3.3 — Managing Workloads with Kueue](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_openshift_ai/managing-workloads-with-kueue)
- [RHOAI 3.3 — Managing Resources](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/managing_resources/index)
- [RHOAI 3.3 — User Management](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_users/index)
- [OpenShift — Configuring HTPasswd](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/configuring-identity-providers#configuring-htpasswd-identity-provider)

## Next Steps

- **Step 04**: [Model Registry](../step-04-model-registry/README.md) — Enterprise model governance
- **Step 05**: [LLM on vLLM](../step-05-llm-on-vllm/README.md) — Deploy models with GPU-as-a-Service queuing
