# Step 05: GPU-as-a-Service Demo

**"Enterprise Model Portfolio"** - Demonstrating RHOAI 3.0's intelligent GPU allocation with Kueue and 5 Red Hat Validated models.

## The Business Story

In enterprise environments, GPU resources are expensive and shared. Teams can't hoard GPUs indefinitely. **GPU-as-a-Service** means:

1. **Fair Allocation**: Quotas prevent any single team from monopolizing resources
2. **Dynamic Handover**: When one workload finishes, another automatically starts
3. **Predictable Queuing**: Developers know exactly when their job will run
4. **Model Portfolio**: Multiple specialized models available on-demand

## Demo Overview

### Enterprise Model Portfolio (5 Red Hat Validated Models)

Our cluster has **5 GPUs** with a **5 GPU quota**, but access to **14 GPUs worth of models**:

| Model | GPUs | Status | Provider | Use Case |
|-------|------|--------|----------|----------|
| **mistral-3-bf16** | 4 | ✅ Active | Mistral AI | Primary Production |
| **mistral-3-int4** | 1 | ✅ Active | Neural Magic | Cost-efficient (75% savings) |
| **devstral-2** | 4 | ⏸️ Queued | Mistral AI | Agentic Tool-calling |
| **gpt-oss-20b** | 4 | ⏸️ Queued | RedHatAI | High-reasoning (Oct 2025) |
| **granite-8b-agent** | 1 | ⏸️ Queued | IBM/Red Hat | RAG/Tool-call (May 2025) |

**Total Potential:** 14 GPUs | **Quota Limit:** 5 GPUs

### Demo Scenarios

```
═══════════════════════════════════════════════════════════════
SCENARIO 1: RESOURCE HANDOVER
───────────────────────────────────────────────────────────────
Story: "Switch from general-purpose Mistral to specialized Devstral"

Before: BF16 (4) + INT4 (1) = 5 GPUs
Action: Enable Devstral → PENDING ⏳ (over quota)
Fix:    Disable BF16 → Devstral INSTANTLY starts! ⚡
After:  Devstral (4) + INT4 (1) = 5 GPUs

═══════════════════════════════════════════════════════════════
SCENARIO 2: EFFICIENCY STORY
───────────────────────────────────────────────────────────────
Story: "Trade 1x 4-GPU model for 4x 1-GPU specialists"

Before: BF16 (4) + INT4 (1) = 5 GPUs (2 models)
After:  Granite (1) + GPT-OSS (1) + INT4 (1) + ... = 4+ specialists

Message: "Same 5 GPUs, 4x more specialized workloads!"

═══════════════════════════════════════════════════════════════
SCENARIO 3: PRIORITY QUEUE
───────────────────────────────────────────────────────────────
Story: "Kueue ensures fair access - no GPU hoarding"

Action: Enable ALL 5 models (14 GPUs requested)
Result: Only 5 GPUs admitted, rest queued
Watch:  Disable one → Another AUTO-STARTS

═══════════════════════════════════════════════════════════════
THE KEY MESSAGE:
"This is GPU-as-a-Service. Model Registry provides governance,
Kueue provides resource arbitration. Organizations access a wide
range of Red Hat Validated models while controlling AWS GPU costs."
═══════════════════════════════════════════════════════════════
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     AWS OCP 4.20 Cluster                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────────┐  ┌────────────────────────────────────┐  │
│  │     MinIO (S3 Storage)   │  │    Red Hat Registry (OCI)          │  │
│  │  s3://models/mistral-24b │  │  registry.redhat.io/rhelai1/       │  │
│  │      (~48GB BF16)        │  │  modelcar-...-quantized-w4a16:1.5  │  │
│  │  For models > 20GB       │  │  (~13.5GB INT4) For models < 20GB  │  │
│  └──────────────────────────┘  └────────────────────────────────────┘  │
│              │                                    │                     │
│              ▼                                    ▼                     │
│  ┌─────────────────────────┐  ┌─────────────────────────┐              │
│  │   g6.12xlarge Node      │  │   g6.4xlarge Node       │              │
│  │   (4x NVIDIA L4)        │  │   (1x NVIDIA L4)        │              │
│  │                         │  │                         │              │
│  │  ┌───────────────────┐  │  │  ┌───────────────────┐  │              │
│  │  │ mistral-3-bf16    │  │  │  │ mistral-3-int4    │  │              │
│  │  │      OR           │  │  │  │ Always Running    │  │              │
│  │  │ devstral-2        │  │  │  │                   │  │              │
│  │  │ (swapped via Kueue)│ │  │  │                   │  │              │
│  │  └───────────────────┘  │  │  └───────────────────┘  │              │
│  └─────────────────────────┘  └─────────────────────────┘              │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        Kueue Controller                          │   │
│  │  ClusterQueue: rhoai-main-queue (quota: 5 GPUs)                 │   │
│  │  ResourceFlavors: nvidia-l4-1gpu, nvidia-l4-4gpu                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Model Portfolio

### Active Models (Baseline Saturation)

| Name | GPUs | Hardware | Storage | Provider | Description |
|------|------|----------|---------|----------|-------------|
| **mistral-3-bf16** | 4 | g6.12xlarge | S3 | Mistral AI | Primary 24B full precision |
| **mistral-3-int4** | 1 | g6.4xlarge | OCI | Neural Magic | 75% cost savings (INT4 W4A16) |

### Queued Models (Ready for Activation)

| Name | GPUs | Hardware | Storage | Provider | Description |
|------|------|----------|---------|----------|-------------|
| **devstral-2** | 4 | g6.12xlarge | S3 | Mistral AI | Agentic tool-calling |
| **gpt-oss-20b** | 4 | g6.12xlarge | S3 | RedHatAI | High-reasoning (Oct 2025) |
| **granite-8b-agent** | 1 | g6.4xlarge | S3 | IBM/Red Hat | RAG & tool-call (May 2025) |

### Model Highlights

#### 🏆 Granite 3.1 8B Agent: "Small but Mighty"

The flagship model for **agentic workflows**:
- **Tool-calling**: Native support via `--chat-template=granite`
- **Function-calling**: `--enable-auto-tool-choice` for Agent Playground
- **RAG-ready**: 16k context for long retrieval contexts
- **Efficient**: FP8 quantization fits on single L4 (~8GB VRAM)

> *"Granite 3.1 models are designed for high-performance agentic workflows, featuring native support for tool-calling and enhanced RAG capabilities."*

#### 🧠 GPT-OSS-20B: "The Reasoning Lead"

Enterprise-vetted reasoning model (October 2025 Collection):
- **Complex reasoning**: Multi-step instruction following
- **OpenAI-alternative**: Same API, enterprise-supported
- **Full precision**: BF16 on 4-GPU for maximum quality

### Storage Strategy

| Model Size | Storage | Why |
|------------|---------|-----|
| **< 20GB** | OCI ModelCar | Fits in CRI-O overlay |
| **> 20GB** | S3/MinIO | Avoids "no space left on device" |

## Prerequisites

### 1. Scale AWS MachineSets

```bash
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')

# Scale for 5 total GPUs
oc scale machineset ${CLUSTER_ID}-gpu-g6-12xlarge-us-east-2b -n openshift-machine-api --replicas=1
oc scale machineset ${CLUSTER_ID}-gpu-g6-4xlarge-us-east-2b -n openshift-machine-api --replicas=1

# Verify nodes (3-5 minutes)
oc get nodes -l nvidia.com/gpu.product=NVIDIA-L4
```

### 2. Upload Models to MinIO

```bash
# Create HuggingFace token secret
oc create secret generic hf-token -n minio-storage --from-literal=token=hf_xxxYOURTOKENxxx

# Upload Mistral BF16 (required for baseline)
oc apply -f gitops/step-05-llm-on-vllm/base/model-upload/upload-mistral-bf16.yaml
oc logs -f job/upload-mistral-bf16 -n minio-storage  # ~30-60 min

# Optional: Upload extended portfolio models
oc apply -f gitops/step-05-llm-on-vllm/base/model-upload/upload-gpt-oss-20b.yaml
oc logs -f job/upload-gpt-oss-20b -n minio-storage  # ~30 min

oc apply -f gitops/step-05-llm-on-vllm/base/model-upload/upload-granite-8b.yaml
oc logs -f job/upload-granite-8b -n minio-storage  # ~10 min
```

### 3. Verify Kueue Quota

```bash
# ClusterQueue should show nominalQuota: 5 for nvidia.com/gpu
oc get clusterqueue rhoai-main-queue -o yaml | grep -A20 "resourceGroups"
```

## Deployment

### A) One-shot (recommended)

```bash
./steps/step-05-llm-on-vllm/deploy.sh
```

### B) Step-by-step (exact commands)

For manual deployment or debugging:

```bash
# 1. Validate manifests (dry-run)
kustomize build gitops/step-05-llm-on-vllm/base | oc apply --dry-run=server -f -

# 2. Apply Argo CD Application (or apply directly)
oc apply -f gitops/argocd/app-of-apps/step-05-llm-on-vllm.yaml

# Or apply directly without ArgoCD:
oc apply -k gitops/step-05-llm-on-vllm/base/

# 3. Wait for ServingRuntime to be created
until oc get servingruntime vllm-runtime -n private-ai &>/dev/null; do sleep 5; done

# 4. Wait for InferenceServices to be created
oc get inferenceservice -n private-ai -w

# 5. Check which InferenceServices are admitted by Kueue
oc get workloads -n private-ai

# 6. Wait for active models to be ready (this may take 5-10 minutes for model download)
oc get inferenceservice -n private-ai -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status,URL:.status.url
```

> **Note**: For self-signed clusters, add `--insecure-skip-tls-verify=true` to `oc` commands if needed.

---

## Running the Demo

### CLI-as-SOP Pattern

This demo uses a **"CLI-First Guide"** approach, demonstrating Platform Engineering reality:
the notebook serves as the **Standard Operating Procedure (SOP)**, using native `oc` commands.

This makes it clear to the audience that RHOAI is **standard Kubernetes/OpenShift** under the hood.

### Option 1: GPU Orchestrator Notebook (Recommended)

1. Open the RHOAI Dashboard
2. Navigate to **Data Science Projects** → **private-ai**
3. Launch the **gpu-switchboard** workbench
4. Open `GPU-Orchestrator.ipynb`
5. Follow the step-by-step CLI commands with explanations

The notebook covers three scenarios:
- **Scenario 1:** Resource Conflict (request more GPUs than available)
- **Scenario 2:** Dynamic Handover (release GPUs to unblock queue)
- **Scenario 3:** Efficiency Portfolio (trade 1 big model for specialists)

### Option 2: Direct CLI Commands

```bash
# Step 0: Verify baseline (5/5 GPUs used)
oc get inferenceservice -n private-ai
oc get workloads -n private-ai

# Step 1: Scale up Devstral-2 (will be PENDING - over quota)
oc scale inferenceservice devstral-2 -n private-ai --replicas=1
oc get workloads -n private-ai  # Shows PENDING

# Step 2: Scale down BF16 to trigger handover
oc scale inferenceservice mistral-3-bf16 -n private-ai --replicas=0
# Watch Devstral-2 start INSTANTLY!
oc get pods -n private-ai -l serving.kserve.io/inferenceservice

# Step 3: Reset to baseline
oc scale inferenceservice mistral-3-bf16 -n private-ai --replicas=1
oc scale inferenceservice devstral-2 -n private-ai --replicas=0
```

### Why `oc scale` Works

KServe implements the Kubernetes **scale subresource**, allowing standard commands:
```bash
# These are equivalent:
oc scale inferenceservice devstral-2 --replicas=1
oc patch inferenceservice devstral-2 --type=merge -p '{"spec":{"predictor":{"minReplicas":1}}}'
```

## Validation

### Test the Models

```bash
# Mistral-3-BF16 (4-GPU)
curl -s -k https://mistral-3-bf16-private-ai.apps.<cluster>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "mistral-3-bf16", "messages": [{"role": "user", "content": "Hello!"}]}' | jq .

# Mistral-3-INT4 (1-GPU)
curl -s -k https://mistral-3-int4-private-ai.apps.<cluster>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "mistral-3-int4", "messages": [{"role": "user", "content": "Hello!"}]}' | jq .
```

### Check Kueue Status

```bash
# Workloads in the queue
oc get workload -n private-ai

# ClusterQueue admission status
oc describe clusterqueue rhoai-main-queue
```

## Troubleshooting

### Workload Stuck in Pending

```bash
# Check why workload isn't admitted
oc describe workload -n private-ai <workload-name>

# Common causes:
# 1. Insufficient quota → Check nominalQuota in ClusterQueue
# 2. No matching ResourceFlavor → Check nodeLabels match actual nodes
# 3. Missing tolerations → Check ResourceFlavor has tolerations
```

### OCI Image Pull Fails: "No Space Left"

```bash
# OCI images > 20GB exceed CRI-O overlay limits
# Solution: Use S3 storage instead (see mistral-3-bf16.yaml)
```

### CUDA Driver Error 803

See [Red Hat KB 7134740](https://access.redhat.com/solutions/7134740) for driver downgrade instructions.

### Workbench: "cluster_not_found" or 500 Errors

**Root Cause:** RHOAI 3.0 Notebook Controller creates HTTPRoutes targeting port 8888, but the controller-managed Service exposes port 80. This port mismatch causes Istio to fail with `cluster_not_found`.

**Solution:** Create a GitOps-managed Service with port 8888:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gpu-switchboard
  namespace: private-ai
  labels:
    notebook-name: gpu-switchboard  # Required for controller discovery
spec:
  ports:
    - name: http-gpu-switchboard    # 'http-' prefix required for Envoy
      port: 8888                     # Must match HTTPRoute target
      targetPort: 8888
  selector:
    statefulset: gpu-switchboard
```

### Workbench: "Connection Timeout" Errors

**Root Cause:** The Notebook Controller creates NetworkPolicies that only allow traffic from `redhat-ods-applications` namespace, but the Gateway (Envoy) runs in `openshift-ingress`. Additionally, if you have an oauth-proxy sidecar, the NetworkPolicy must allow **both** ports:

| Port | Path | Purpose |
|------|------|---------|
| **8888** | Gateway API (Dashboard URL) | Direct to notebook container |
| **8443** | Custom Route (oauth-proxy) | Through oauth-proxy sidecar |

**Solution:** Add a NetworkPolicy allowing Gateway ingress on **both ports**:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gpu-switchboard-gateway-ingress
  namespace: private-ai
spec:
  podSelector:
    matchLabels:
      notebook-name: gpu-switchboard
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openshift-ingress
      ports:
        - port: 8888    # Gateway API path
          protocol: TCP
        - port: 8443    # oauth-proxy path (if using sidecar)
          protocol: TCP
```

> **Key Insight:** If your NetworkPolicy only allows port 8443 (for oauth-proxy) but the Gateway connects to port 8888 (notebook directly), you'll get "connection timeout" errors on the Dashboard URL.

## GPU Orchestrator Workbench

The GPU Orchestrator is a pre-configured Jupyter workbench that provides a **CLI-First SOP** for demonstrating GPU quota management.

### Why CLI-First?

| Approach | Benefit |
|----------|---------|
| **Transparency** | Shows OpenShift AI uses standard Kubernetes commands |
| **Realism** | This is how real Platform Engineers manage model capacity |
| **Simplicity** | No widget debugging—`oc scale` just works |
| **Portability** | Commands work in any terminal, not just Jupyter |

### Accessing the Workbench

**URL:** `https://data-science-gateway.apps.<cluster>/notebook/private-ai/gpu-switchboard`

Or via RHOAI Dashboard:
1. Navigate to **Data Science Projects** → **private-ai**
2. Open the **gpu-switchboard** workbench
3. Run the `GPU-Orchestrator.ipynb` notebook

### RHOAI 3.0 Native Ingress Pattern

The workbench uses RHOAI 3.0's Native Ingress Controller pattern with Gateway API:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Dashboard URL (Gateway API Path)                                       │
│  https://data-science-gateway.apps.../notebook/private-ai/gpu-switchboard/
│                                                                         │
│  Browser → Gateway → kube-auth-proxy (OAuth) → HTTPRoute                │
│                                                    ↓                    │
│                                              Service:8888               │
│                                                    ↓                    │
│                                           NetworkPolicy ✓               │
│                                                    ↓                    │
│                                              Pod:8888 (Jupyter)         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key Configuration Points:**

| Component | Configuration | Why |
|-----------|---------------|-----|
| **Service Port** | 8888 | Matches controller-generated HTTPRoute |
| **Port Name** | `http-gpu-switchboard` | `http-` prefix required for Envoy protocol detection |
| **NetworkPolicy** | Allow `openshift-ingress` on **port 8888** | Gateway namespace must reach notebook container |
| **OAuth** | `inject-oauth: "true"` annotation | Centralized auth at Gateway level |

### Common Configuration Mistakes

| Symptom | Root Cause | Fix |
|---------|------------|-----|
| **503 Service Unavailable** | HTTPRoute targets 8888, Service exposes 80 | Patch Service to port 8888 |
| **Connection Timeout** | NetworkPolicy blocks Gateway | Allow port 8888 from `openshift-ingress` |
| **cluster_not_found** | Service selector doesn't match pod labels | Use `statefulset: gpu-switchboard` selector |

> **Lesson Learned:** The Notebook Controller creates HTTPRoute targeting port 8888, but creates Service exposing port 80. A PostSync hook patches the Service to align ports. The NetworkPolicy must also allow port 8888 for the Gateway API path.

### Workbench GitOps Components

The workbench manifest (`workbench.yaml`) includes:

1. **ServiceAccount** - Identity for RBAC
2. **PVC** - 20Gi storage for notebooks
3. **Service** - Port 8888 aligned with controller HTTPRoute
4. **NetworkPolicy** - Allow Gateway ingress
5. **Notebook CR** - With Hardware Profile delegation
6. **RBAC** - Permissions to manage InferenceServices

## GitOps Structure

```
gitops/step-05-llm-on-vllm/base/
├── kustomization.yaml
├── serving-runtime/
│   └── vllm-runtime.yaml              # Thin vLLM runtime
├── inference/
│   ├── kustomization.yaml
│   ├── mistral-3-bf16.yaml            # 4-GPU, S3, minReplicas: 1 (Active)
│   ├── mistral-3-int4.yaml            # 1-GPU, OCI, minReplicas: 1 (Active)
│   ├── devstral-2.yaml                # 4-GPU, S3, minReplicas: 0 (Queued)
│   ├── gpt-oss-20b.yaml               # 4-GPU, S3, minReplicas: 0 (Queued)
│   └── granite-8b-agent.yaml          # 1-GPU, S3, minReplicas: 0 (Queued)
├── model-registration/
│   └── seed-job.yaml                  # Register 5 models in Registry
├── model-upload/
│   ├── kustomization.yaml
│   ├── upload-mistral-bf16.yaml       # Mistral BF16 (~48GB)
│   ├── upload-gpt-oss-20b.yaml        # GPT-OSS (~44GB)
│   └── upload-granite-8b.yaml         # Granite (~8GB)
└── controller/
    ├── workbench.yaml                 # GPU Orchestrator workbench
    └── GPU-Orchestrator.ipynb         # CLI-First SOP notebook
```

## Key RHOAI 3.0 Design Patterns

### Dynamic Admission (Kueue)

> *"Kueue allows for the declarative management of resource quotas. By submitting more work than the quota allows, administrators can demonstrate the deterministic queueing behavior required for shared enterprise GPU clusters."*

### KServe Replica Management

> *"Setting minReplicas to 1 ensures immediate availability, while minReplicas 0 allows for cost-optimization. Managing these fields via API allows for higher-level orchestration of inference capacity."*

---

## Rollback / Cleanup

### Remove LLM Deployments

```bash
# 1. Scale down all InferenceServices (releases GPUs immediately)
oc scale inferenceservice --all -n private-ai --replicas=0

# 2. Delete InferenceServices
oc delete inferenceservice --all -n private-ai

# 3. Delete ServingRuntime
oc delete servingruntime vllm-runtime -n private-ai

# 4. Delete GPU Orchestrator workbench (if deployed)
oc delete notebook gpu-switchboard -n private-ai

# 5. Delete Argo CD Application
oc delete application step-05-llm-on-vllm -n openshift-gitops
```

### Remove Model Artifacts from MinIO

```bash
# Connect to MinIO and delete model files
MINIO_POD=$(oc get pod -n minio-storage -l app=minio -o jsonpath='{.items[0].metadata.name}')
oc exec -n minio-storage $MINIO_POD -- mc rm -r --force local/models/
```

### GitOps Revert (alternative)

```bash
# Remove from Git and let Argo CD prune
git revert <commit-with-step-05>
git push

# Or delete Argo CD Application with cascade
oc delete application step-05-llm-on-vllm -n openshift-gitops --cascade=foreground
```

---

## Official Documentation

- [RHOAI 3.0 Distributed Workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/working_with_distributed_workloads/index)
- [Kueue Integration](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/working_with_distributed_workloads/index#configuring-quota-management-for-distributed-workloads_distributed-workloads)
- [KServe Storage Configuration](https://kserve.github.io/website/latest/modelserving/storage/)
- [Red Hat KB: NVIDIA Driver 580.x Compatibility](https://access.redhat.com/solutions/7134740)

## Next Steps

- **Step 06**: RAG Pipeline with LangChain
- **Step 07**: Agent Playground with Bee Framework
