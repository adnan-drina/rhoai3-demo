# Step 08: Distributed Inference with llm-d

**"Elastic Scale-Out on a Budget"** — Demonstrating horizontal scaling of LLM inference across multiple GPU nodes using RHOAI 3.0's llm-d (Distributed Inference) capability.

> **Reference Implementation**: This step is aligned with the Red Hat AI Services reference repo:
> https://github.com/rh-aiservices-bu/rhaoi3-llm-d

> ⚠️ **DEMO-ONLY**: This step deploys llm-d without authentication for simplicity.
> For production deployments, configure authentication using **Red Hat Connectivity Link (RHCL)**:
> - [RHOAI 3.0: Configuring authentication for Distributed Inference with llm-d using RHCL](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#configuring-authentication-for-llmd_rhoai-user)

---

## Goal

Demonstrate that enterprises can **increase inference capacity without upgrading to expensive multi-GPU instances** by horizontally scaling a single model across multiple smaller GPU nodes.

**Demo narrative (building on Step 07):**
- Step 07 framed the economics story ("ROI of quantization") with measured breakpoints
- Step 08 extends that story by introducing llm-d as the "scale-out" option

**Success criteria:**
- A distributed model deployment is created using the **RHOAI 3.0 GA supported flow**
- The endpoint is reachable and returns valid inference responses
- Step 08 deploys the **llm-d benchmarks + observability add-ons** (ServiceMonitors + Grafana dashboard) so the llm-d story is self-contained in Step 08 GitOps

---

## The Business Story

Enterprise AI teams face a common challenge: **how to increase inference capacity without upgrading to expensive multi-GPU instances?**

llm-d solves this by enabling **horizontal scaling** — distributing a model across multiple smaller GPU nodes:

| Approach | Cost | Capacity | Use Case |
|----------|------|----------|----------|
| **Vertical Scale** (1× g6.12xlarge) | $3.40/hr | Single large instance | Simple, limited by instance size |
| **Horizontal Scale** (2× g6.4xlarge) | $1.70/hr | Distributed across nodes | Elastic, pay-as-you-grow |

**Key insight**: Same total GPU memory, but horizontal scaling offers:
- **Elasticity**: Add/remove nodes based on demand
- **Resilience**: No single point of failure
- **Cost optimization**: Use spot instances for workers

### llm-d vs vLLM: Engine vs Platform

| Layer | Component | Role |
|-------|-----------|------|
| **Engine** | vLLM | High-performance inference engine |
| **Platform** | llm-d | Orchestration layer enabling disaggregation, cache-aware routing, fleet-scale elasticity |

> **Official explanation:** [RHOAI 3.0: Deploying models by using Distributed Inference with llm-d](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#deploying-models-using-distributed-inference_rhoai-user)

---

## Deployment Mode Design Decision

### Two Distributed Inference Modes

llm-d supports two distinct deployment modes, each solving different problems:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Distributed Inference Modes                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  REPLICAS MODE (Current Demo)         TENSOR PARALLELISM                    │
│  "Intelligent Fleet Routing"          "Model Sharding"                      │
│  tensor: 1, replicas: 2               tensor: 2, replicas: 1                │
│                                                                             │
│  ┌─────────┐    ┌─────────────┐      ┌─────────────────────────────────┐   │
│  │ Request │───▶│ llm-d Router│      │      LeaderWorkerSet            │   │
│  └─────────┘    │ (KV-cache   │      │  ┌─────────┐    ┌─────────┐     │   │
│                 │  scoring)   │      │  │ Leader  │◄──▶│ Worker  │     │   │
│                 └──────┬──────┘      │  │(Shard 0)│Ray │(Shard 1)│     │   │
│                        │             │  └─────────┘    └─────────┘     │   │
│          ┌─────────────┼───────────┐ │                                 │   │
│          ▼             ▼           │ └─────────────────────────────────┘   │
│    ┌──────────┐  ┌──────────┐      │                                       │
│    │ Replica 1│  │ Replica 2│      │  Problem: Model too big for 1 GPU     │
│    │(Full Mod)│  │(Full Mod)│      │  Solution: Split model weights        │
│    └──────────┘  └──────────┘      │                                       │
│                                    │                                       │
│  Problem: Cache misses with RR     │                                       │
│  Solution: Route to cached replica │                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Mode Comparison

| Aspect | Replicas Mode (`tensor:1, replicas:N`) | Tensor Parallelism (`tensor:N, replicas:1`) |
|--------|----------------------------------------|---------------------------------------------|
| **What it creates** | Kubernetes Deployment | LeaderWorkerSet (LWS) |
| **Model instances** | N independent full copies | 1 model sharded across N pods |
| **GPU utilization** | Each replica runs full model | Model weights split across GPUs |
| **Communication** | None between replicas | Ray/NCCL between Leader-Worker |
| **Best for** | Multi-turn conversations, cache reuse | Models too large for single GPU |
| **Benchmark story** | Routing efficiency, tail latency | Memory capacity, large models |

### Why We Chose Replicas Mode

For this demo's **Step 07 → Step 08 benchmark continuation**, Replicas Mode is the correct choice:

| Reason | Explanation |
|--------|-------------|
| **Same model, different routing** | Shows llm-d's intelligent routing vs vLLM's round-robin |
| **Measurable improvement** | Reference repo shows ~63% faster P95 TTFT |
| **Apples-to-apples comparison** | Same Mistral INT4 model, same GPU resources |
| **Model fits on 1 GPU** | Mistral INT4 (~12GB) doesn't need sharding |
| **Real-world use case** | Multi-turn chat benefits from KV-cache reuse |

### Expected Benchmark Improvement (vs Step 07 Baseline)

Based on [Red Hat reference implementation](https://github.com/rh-aiservices-bu/rhaoi3-llm-d):

| Metric | vLLM (Step 07) | llm-d Replicas (Step 08) | Improvement |
|--------|----------------|--------------------------|-------------|
| **P50 TTFT** | ~123 ms | ~92 ms | **25% faster** |
| **P95 TTFT** | ~745 ms | ~272 ms | **63% faster** |
| **P99 TTFT** | ~841 ms | ~674 ms | 20% faster |
| **Cache speedup** | 1.79x | 3.84x | **2.1x better** |

> **Key insight**: The biggest improvement is for the most frustrated users (P95/P99).
> This is the enterprise value proposition of llm-d's intelligent routing.

### When to Use Tensor Parallelism Instead

Use `tensor: N, replicas: 1` when:
- Model doesn't fit on a single GPU (>24GB for L4)
- Serving massive models like Llama 3 70B or Granite 3.0 108B
- Latency is less important than capability

Example for 70B model across 2 nodes:
```yaml
spec:
  parallelism:
    tensor: 2  # Shard across 2 pods
  replicas: 1  # Single sharded instance
```

This creates a LeaderWorkerSet with atomic startup and fate-sharing guarantees.

---

## Dashboard Visibility

> **Important**: `LLMInferenceService` does **NOT** appear in the RHOAI Dashboard.

| Resource Type | API Version | Dashboard Visibility | Management |
|--------------|-------------|---------------------|------------|
| `InferenceService` | `serving.kserve.io/v1beta1` | ✅ Visible | UI + CLI |
| `LLMInferenceService` | `serving.kserve.io/v1alpha1` | ❌ Not visible | CLI only |

This is **expected behavior** per RHOAI 3.0 — llm-d uses the alpha API and is managed exclusively via CLI/GitOps.

### Monitoring llm-d

```bash
# Check status
oc get llminferenceservice -n private-ai

# View detailed conditions
oc describe llminferenceservice mistral-3-distributed -n private-ai

# View pods
oc get pods -n private-ai -l app.kubernetes.io/name=mistral-3-distributed

# Get endpoint URL
oc get llminferenceservice mistral-3-distributed -n private-ai -o jsonpath='{.status.url}'
```

---

## Prerequisites

### Cluster Requirements

| Requirement | Status | Provided By |
|-------------|--------|-------------|
| RHOAI 3.0 installed | ✅ | Step 02 |
| GPU nodes with NVIDIA L4 GPUs | ✅ | Step 01 |
| LeaderWorkerSet operator installed | ✅ | Step 01 (operator CRD only; workload CRD not exposed) |
| **Red Hat Connectivity Link (RHCL)** operator | ✅ | Step 01 (`rhcl-operator` v1.2.1) |
| Gateway API configured | ✅ | RHOAI 3.0 (automatic) |
| Kueue configured for GPU scheduling | ✅ | Step 03 |
| **2× g6.4xlarge nodes** available | 🔲 | Scale MachineSet |
| **llm-d reserved queue** (`rhoai-llmd-queue` + `LocalQueue/llmd`) | 🔲 | Step 03 |

> **Important: Red Hat Connectivity Link (RHCL)**
>
> The llm-d controller requires the `AuthPolicy` CRD (`authpolicies.kuadrant.io`) for Gateway validation.
> Install the **RHCL operator** (`rhcl-operator`) from `redhat-operators` (Step 01).
>
> After installing RHCL, **restart the RHOAI controllers** per [RHOAI 3.0 docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#deploying-models-using-distributed-inference_rhoai-user):
> ```bash
> oc delete pod -n redhat-ods-applications -l app=odh-model-controller
> oc delete pod -n redhat-ods-applications -l control-plane=kserve-controller-manager
> ```
>
> **Ref:** [RHOAI 3.0: Configuring authentication for llm-d using RHCL](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#configuring-authentication-for-llmd_rhoai-user)

---

## GPU Allocation Design

### Design Decision: Dedicated GPU Reservation for llm-d

To ensure llm-d can **always start** even when vLLM workloads are consuming GPUs, we use a **hard reservation** via a dedicated Kueue ClusterQueue.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  GPU Node Allocation - Full Demo (Step 05/07 + Step 08)                      ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  INSTANCE         │ GPUS  │ WORKLOAD                   │ QUEUE              ║
║  ─────────────────┼───────┼────────────────────────────┼──────────────────  ║
║  g6.12xlarge ×1   │ 4× L4 │ Mistral-3 BF16 (vLLM)      │ rhoai-main-queue   ║
║  g6.4xlarge  ×1   │ 1× L4 │ Mistral-3 INT4 (vLLM)      │ rhoai-main-queue   ║
║  g6.4xlarge  ×2   │ 2× L4 │ Mistral-3 INT4 (llm-d) ⭐  │ default queue      ║
║                   │       │ (2 replicas, 1 GPU each)   │                    ║
║                                                                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  TOTAL: 1× g6.12xlarge + 3× g6.4xlarge = 7 GPUs                             ║
║                                                                              ║
║  Cost: $3.40/hr (g6.12xlarge) + $2.55/hr (3× g6.4xlarge) = ~$5.95/hr        ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

> **Note:** The llm-d controller assigns pods to the `default` LocalQueue (not `llmd`).
> This is expected behavior — the controller manages queue assignment internally.

### Kueue Queue Separation

| Queue | ClusterQueue | Capacity | Workloads |
|-------|--------------|----------|-----------|
| `default` | `rhoai-main-queue` | 5 GPUs (1+4) | vLLM InferenceServices (Step 05/07) |
| `llmd` | `rhoai-llmd-queue` | 2 GPUs (reserved) | llm-d LLMInferenceService (Step 08) |

> **Why separate queues?**
> - **Guaranteed capacity**: llm-d workloads won't be blocked by vLLM saturation
> - **Isolation**: Benchmarking one doesn't starve the other
> - **Elasticity**: Can scale llm-d reservation independently

### Scale Up GPU Nodes

To run **Step 05/07 (vLLM) + Step 08 (llm-d) simultaneously**, scale to **3× g6.4xlarge**:

```bash
# Check current g6.4xlarge node count
oc get nodes -l node.kubernetes.io/instance-type=g6.4xlarge

# Scale MachineSet to 3 replicas
oc get machinesets -n openshift-machine-api | grep g6.4xlarge
oc scale machineset <g6-4xlarge-machineset-name> --replicas=3 -n openshift-machine-api

# Wait for nodes to be ready (~5-10 minutes for new node)
oc get nodes -l node.kubernetes.io/instance-type=g6.4xlarge -w
```

### Verify Reserved Queue

```bash
# Check ClusterQueues
oc get clusterqueue rhoai-main-queue rhoai-llmd-queue

# Check LocalQueues in private-ai
oc get localqueue -n private-ai

# Verify llmd queue has capacity
oc describe clusterqueue rhoai-llmd-queue | grep -A5 "Flavors Usage"
```

### Verify Prerequisites

```bash
# Verify LLMInferenceService CRD is available
oc api-resources | grep llminferenceservice
# Expected: llminferenceservices  llmisvc  serving.kserve.io/v1alpha1  true  LLMInferenceService

# Verify LeaderWorkerSet operator is installed (operator CRD, not workload CRD)
oc api-resources | grep leaderworkersetoperator

# Verify RHCL operator is installed and AuthPolicy CRD is available
oc get csv -n rhcl-operator | grep rhcl
# Expected: rhcl-operator.v1.2.1 ... Succeeded

oc get crd authpolicies.kuadrant.io
# Expected: authpolicies.kuadrant.io ... <date>

# Verify Gateway API resources exist (RHOAI enables Gateway API automatically)
oc api-resources | grep -E 'gatewayclasses|gateways|httproutes'

# Optional: external Gateway exposure (Step 08 overlay only)
# Step 08 base does NOT create any additional Gateways/LBs by default.
# If you apply `gitops/step-08-llm-d/overlays/external-gateway/`, validate:
oc get gatewayclass openshift-default
oc get gateway openshift-ai-inference -n openshift-ingress

# Verify Kueue resources
oc get clusterqueue rhoai-main-queue
oc get clusterqueue rhoai-llmd-queue
oc get localqueue default -n private-ai
oc get localqueue llmd -n private-ai

# Verify GPU nodes available (need 2 for tensor=2)
oc get nodes -l node.kubernetes.io/instance-type=g6.4xlarge
```

---

## Architecture

### Distributed Inference Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Distributed Inference Architecture                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│    ┌──────────────┐                                                         │
│    │   Client     │                                                         │
│    └──────┬───────┘                                                         │
│           │                                                                  │
│           ▼                                                                  │
│    ┌──────────────┐     ┌──────────────────────────────────────────────┐   │
│    │   Gateway    │────▶│              llm-d Router                     │   │
│    │  (Ingress)   │     │  • Request scheduling                        │   │
│    └──────────────┘     │  • KV-cache aware routing                    │   │
│                         │  • Load balancing                             │   │
│                         └──────────────┬───────────────────────────────┘   │
│                                        │                                    │
│                    ┌───────────────────┼───────────────────┐               │
│                    │                   │                   │               │
│                    ▼                   ▼                   ▼               │
│           ┌────────────────┐  ┌────────────────┐  ┌────────────────┐      │
│           │  Worker Pod 0  │  │  Worker Pod 1  │  │  Worker Pod N  │      │
│           │  (g6.4xlarge)  │  │  (g6.4xlarge)  │  │  (g6.4xlarge)  │      │
│           │  1× NVIDIA L4  │  │  1× NVIDIA L4  │  │  1× NVIDIA L4  │      │
│           └────────────────┘  └────────────────┘  └────────────────┘      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

> **KV-cache routing (official example):**
> [RHOAI 3.0: Intelligent inference scheduler with KV cache routing](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#intelligent_inference_scheduler_with_kv_cache_routing)

### llm-d Components

| Component | Description | Created By |
|-----------|-------------|------------|
| **LLMInferenceService** | Primary CR defining the distributed model | User (GitOps) |
| **Router Pod** | Request scheduling and load balancing | llm-d controller |
| **Worker Pods** | vLLM inference engines (one per GPU node) | llm-d controller |
| **Gateway/HTTPRoute** | External traffic ingress | RHOAI Gateway controller |

### GitOps Structure

```
gitops/step-08-llm-d/
├── base/
│   ├── kustomization.yaml
│   ├── rhcl/                            # Connectivity Link instance (sync-wave: 0)
│   │   ├── kustomization.yaml
│   │   └── rhcl-instance.yaml           # Required for llm-d Gateway integration
│   ├── llm-d/                           # Distributed Inference (sync-wave: 1)
│   │   ├── kustomization.yaml
│   │   └── llminferenceservice.yaml     # Primary CR
│   ├── observability/                   # ServiceMonitors + GrafanaDashboard (sync-wave: 10-12)
│   │   ├── kustomization.yaml
│   │   ├── servicemonitor-llmd-router.yaml
│   │   ├── servicemonitor-llmd-workload.yaml
│   │   └── llm-tail-latency-and-cache.yaml
│   └── benchmark/                       # Benchmarks (sync-wave: 5-6)
│       ├── kustomization.yaml
│       ├── pvc.yaml                     # llmd-benchmark-results (5Gi)
│       ├── cronjob.yaml                 # GuideLLM benchmark (suspended by default)
│       ├── cronjob-multi-turn-benchmark-llmd.yaml        # multi-turn (suspended)
│       └── cronjob-multi-turn-benchmark-vllm-int4.yaml   # baseline (suspended)
```

> **Note:** The Connectivity Link instance (resource kind `Kuadrant`) is deployed by Step 08 (not Step 01) because:
> 1. Step 01 installs the **RHCL operator** (provides CRDs)
> 2. Step 08 creates the **instance** (in `private-ai` namespace)
> 3. This pattern separates operator installation from workload configuration

### Current Configuration

> **Configuration aligned with [Red Hat reference implementation](https://github.com/rh-aiservices-bu/rhaoi3-llm-d)**

| Setting | Value | Purpose |
|---------|-------|---------|
| **Mode** | **Replicas** | Intelligent routing demonstration |
| **Parallelism** | `tensor: 1` | Full model per replica (no sharding) |
| **Replicas** | `2` | 2 independent instances for KV-cache routing |
| **Queue** | `llmd` → `rhoai-llmd-queue` | Dedicated GPU reservation |

> **Design Decision**: We chose `tensor:1, replicas:2` (Replicas Mode) instead of `tensor:2, replicas:1` (Tensor Parallelism) to:
> 1. **Continue the Step 07 benchmark story** — demonstrate routing efficiency vs round-robin
> 2. **Show llm-d's unique value** — KV-cache aware request scheduling
> 3. **Match the reference repo** — comparable benchmark results
> 4. **Maximize improvement visibility** — P95 TTFT improves ~63%
>
> See [Deployment Mode Design Decision](#deployment-mode-design-decision) for detailed comparison.

### Comparison with Step 05/07 Baseline

| Metric | INT4 Single-Node (Step 05/07) | Distributed llm-d (Step 08) |
|--------|-------------------------------|------------------------------|
| **GPUs** | 1× L4 | 2× L4 (2 replicas) |
| **Instance** | g6.4xlarge | 2× g6.4xlarge |
| **Cost** | $0.85/hr | $1.70/hr |
| **Routing** | Round-robin / random | **KV-cache aware** |
| **Throughput** | ~85 tok/s | ~170 tok/s (2× capacity) |
| **P95 TTFT** | ~745 ms | **~272 ms (63% faster)** |
| **Cache Hit Rate** | ~25% (round-robin) | **~90%** (intelligent routing) |

> **The benchmark story**: With the same model and double the GPUs, llm-d doesn't just double throughput —
> it **dramatically reduces tail latency** through intelligent request routing to replicas with cached KV prefixes.

---

## Reproduce

### Option A: One-Shot (Recommended)

```bash
./steps/step-08-llm-d/deploy.sh
```

**What to watch for:**
- Prerequisites check passes
- ArgoCD Application syncs successfully
- LLMInferenceService reports `Ready` status

### Option B: GitOps via ArgoCD

```bash
# Apply via ArgoCD
oc apply -f gitops/argocd/app-of-apps/step-08-llm-d.yaml

# Wait for sync
oc get application step-08-llm-d -n openshift-gitops -w
```

### Option C: Direct Apply

```bash
# Apply manifests directly
oc apply -k gitops/step-08-llm-d/base/

# Wait for deployment
oc get llminferenceservice -n private-ai -w
```

> **Doc-aligned example:** This step follows the official multi-node pattern:
> [RHOAI 3.0: Example usage — Multi-node deployment](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#multi_node_deployment)

---

## Step-by-Step Deployment

### 1. Create the LLMInferenceService

> **Note (Kueue integration):** Some clusters enforce a Kueue admission label on llm-d resources.
> If your cluster rejects the CR with a “missing required label `kueue.x-k8s.io/queue-name`” error, add the label shown below.
> Otherwise, you can omit it (we validated server-side dry-run without this label on our cluster).

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: mistral-3-distributed
  namespace: private-ai
  labels:
    # Use the reserved llm-d LocalQueue (created in Step 03)
    kueue.x-k8s.io/queue-name: llmd
  annotations:
    # Disable authentication for demo simplicity
    security.opendatahub.io/enable-auth: "false"
spec:
  model:
    name: mistral-3-distributed
    uri: oci://registry.redhat.io/rhelai1/modelcar-mistral-small-24b-instruct-2501-quantized-w4a16:1.5
  
  # Routing Demo Configuration (matching reference repo pattern)
  # - tensor: 1 = single GPU per replica (no sharding)
  # - replicas: 2 = enables intelligent routing between instances
  parallelism:
    tensor: 1
  
  # 2 replicas for routing demonstration
  # llm-d router can route to replica with cached KV prefix
  replicas: 2
  
  # Pod template for GPU scheduling
  template:
    nodeSelector:
      node.kubernetes.io/instance-type: g6.4xlarge
    tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
    # NOTE: The llm-d controller injects a container named "main".
    containers:
      - name: main
        resources:
          limits:
            cpu: "16"
            memory: 60Gi
            nvidia.com/gpu: "1"
          requests:
            cpu: "8"
            memory: 32Gi
            nvidia.com/gpu: "1"
  
  # Router configuration (no external Gateway by default)
  router:
    route: {}
    scheduler: {}
```

### 2. Verify Deployment

```bash
# Check LLMInferenceService status
oc get llminferenceservice mistral-3-distributed -n private-ai

# Check pods are distributed across nodes
oc get pods -n private-ai -o wide | grep mistral-3-distributed || true

# Check for gateway binding issues
oc describe llminferenceservice mistral-3-distributed -n private-ai | grep -A10 "Conditions:" || true
```

### 3. Test the Endpoint

**Option A: Via OpenShift Route (recommended)**

Step 08 creates a passthrough Route for direct external access:

```bash
# Get the Route URL
ROUTE_URL=$(oc get route mistral-3-distributed -n private-ai -o jsonpath='https://{.spec.host}')

# Test inference
curl -sk "$ROUTE_URL/v1/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-3-distributed",
    "prompt": "Hello!",
    "max_tokens": 50
  }'
```

**Option B: Via Gateway (if configured)**

```bash
# Get the Gateway endpoint URL
GATEWAY_URL=$(oc get llminferenceservice mistral-3-distributed -n private-ai -o jsonpath='{.status.url}')

# Test inference (may return 500 due to TLS origination issues)
curl -sk "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-3-distributed",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'
```

> **Note:** The OpenShift Route uses passthrough TLS termination (at the pod),
> which avoids the TLS re-encryption complexity between Gateway and backend.

---

## Validate

### Expected Outcomes

1. **2 workload pods running**: Each on a separate g6.4xlarge node
2. **Router pod running**: Handles KV-cache aware request scheduling
3. **Endpoint accessible**: Via OpenShift Route or Gateway
4. **Metrics flowing**: Visible in Grafana "LLM Tail Latency + Cache Health" dashboard

### Validation Commands

```bash
# 1. Verify LLMInferenceService is ready
oc get llminferenceservice -n private-ai
# Expected: STATUS = Ready

# 2. Verify pods are distributed
oc get pods -n private-ai -o wide | grep mistral-3-distributed
# Expected: Pods on different nodes

# 3. Test inference endpoint
curl -sk "$(oc get llminferenceservice mistral-3-distributed -n private-ai -o jsonpath='{.status.url}')/v1/models"
```

---

## Benchmarking

Step 08 includes a dedicated benchmark setup for the distributed endpoint.

### Benchmark Resources

```
gitops/step-08-llm-d/base/benchmark/
├── kustomization.yaml
├── pvc.yaml                 # llmd-benchmark-results (5Gi)
├── cronjob.yaml             # GuideLLM benchmark (suspended by default)
├── cronjob-multi-turn-benchmark-llmd.yaml        # multi-turn (suspended)
└── cronjob-multi-turn-benchmark-vllm-int4.yaml   # baseline (suspended)
```

### Run GuideLLM Benchmark

```bash
# Trigger the dedicated llm-d benchmark (CronJob is suspended by default)
oc create job --from=cronjob/llmd-benchmark manual-llmd-$(date +%H%M) -n private-ai

# Monitor the benchmark
oc logs -f job/manual-llmd-$(date +%H%M) -n private-ai
```

### Run Multi-turn Benchmarks (Cache Story)

```bash
# llm-d multi-turn (CronJob is suspended by default)
oc create job --from=cronjob/multi-turn-benchmark-llmd mtb-llmd-$(date +%H%M) -n private-ai

# vLLM baseline multi-turn (CronJob is suspended by default)
oc create job --from=cronjob/multi-turn-benchmark-vllm-int4 mtb-vllm-$(date +%H%M) -n private-ai
```

### Benchmark Configuration

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Profile** | `constant` | Graduated concurrency |
| **Rates** | `1,3,5,8,10,15,20,30,40,50` | Extended range for distributed capacity |
| **Input Tokens** | 256 | Same as Step 07 for comparison |
| **Output Tokens** | 256 | Same as Step 07 for comparison |
| **Duration** | 60s per rate | 10 levels × 60s = ~10 min total |

### Benchmark Results (Multi-Turn Conversations)

> **Test:** 20 conversations × 6 turns each = 120 requests, 4 parallel workers

| Metric | vLLM INT4 (1 replica) | llm-d (1 replica) | llm-d (2 replicas) |
|--------|----------------------|-------------------|-------------------|
| **TTFT P50** | 10,980 ms | 12,507 ms | **9,448 ms** ✅ |
| **TTFT P95** | 23,107 ms | 29,215 ms | 28,839 ms |
| **TTFT P99** | 24,358 ms | 31,684 ms | 42,591 ms |
| **TTFT Mean** | 12,160 ms | 13,611 ms | **11,704 ms** ✅ |
| **Total Time** | 764s | 1,285s | **896s** ✅ |
| **Requests/sec** | 0.16 | 0.09 | 0.13 |
| **Speedup Ratio** | 1.18x | 1.17x | 0.88x |

**Key Observations:**
- ✅ **TTFT P50 improved 14%** vs vLLM baseline (9.4s vs 11.0s)
- ✅ **Total time reduced 30%** vs single-replica llm-d (896s vs 1285s)
- ✅ **Mean TTFT improved 4%** vs vLLM baseline
- ⚠️ P95/P99 variance higher due to cache distribution across replicas

**For full routing demo** (per [reference repo](https://github.com/rh-aiservices-bu/rhaoi3-llm-d)):
- Scale to **4 replicas** to demonstrate 90%+ KV cache hit rate
- Requires 4× g6.4xlarge nodes

### Metrics to Compare

| Metric | Source | Notes |
|--------|--------|-------|
| TTFT (p50/p95/p99) | `vllm:time_to_first_token_seconds_bucket` | User-perceived latency |
| ITL/TPOT | `vllm:time_per_output_token_seconds_bucket` | Decode speed |
| KV Cache Usage | `vllm:gpu_cache_usage_perc` | Saturation indicator |
| Queue Depth | `vllm:num_requests_waiting` | Backpressure indicator |

### View Results

```bash
# Results are stored in the llmd-benchmark-results PVC
# Create a debug pod
oc run results-viewer --rm -it --image=busybox \
  --overrides='{"spec":{"containers":[{"name":"viewer","image":"busybox","command":["sh"],"volumeMounts":[{"name":"results","mountPath":"/results"}]}],"volumes":[{"name":"results","persistentVolumeClaim":{"claimName":"llmd-benchmark-results"}}]}}' \
  -n private-ai
```

---

## Observability

Step 08 deploys llm-d observability resources into the `private-ai` namespace:
- **ServiceMonitors** for router metrics and workload `/metrics`
- A **GrafanaDashboard** for tail-latency and cache health

> **Dependency:** Grafana Operator + Grafana instance are deployed by Step 07.

**GitOps location:** `gitops/step-08-llm-d/base/observability/`

### Access the Dashboard

```bash
# Get Grafana URL
GRAFANA_URL=$(oc get route grafana-route -n private-ai -o jsonpath='https://{.spec.host}')
echo "Grafana: $GRAFANA_URL"

# Dashboard: Dashboards → private-ai → LLM Tail Latency + Cache Health
# Set model dropdown to: mistral-3-distributed
```

### Key Metrics to Monitor

| Panel | Metric | What to Watch |
|-------|--------|---------------|
| **Time to First Token (TTFT)** | P50/P95/P99 | User-perceived latency |
| **Inter-Token Latency (ITL)** | P50/P95 | Decode speed consistency |
| **Token Throughput** | prompt/gen tok/s | Overall performance |
| **KV Cache Usage** | % | Saturation indicator (>80% = pressure) |
| **Queue Health** | running vs waiting | Backpressure indicator |

---

## Technical Notes

### Gateway Naming

RHOAI 3.0 documentation references (and llm-d validates) a Gateway named `openshift-ai-inference` in the `openshift-ingress` namespace.

This demo follows the Red Hat reference implementation, but **ships Gateway exposure as an optional overlay** to avoid provisioning extra cloud load balancers/DNS records by default:

- **Base (default):** no additional Gateway is created
- **Overlay:** `gitops/step-08-llm-d/overlays/external-gateway/`

**If llm-d controller reports a Gateway error:**

```bash
oc get gatewayclass openshift-default
oc get gateway openshift-ai-inference -n openshift-ingress
oc get httproute -n private-ai
oc describe llminferenceservice mistral-3-distributed -n private-ai
```

### Kueue Integration

Some environments enforce Kueue admission on llm-d resources via an admission webhook.

**If you see an error like:**

- `missing required label "kueue.x-k8s.io/queue-name"`

**Then add:**

- `metadata.labels.kueue.x-k8s.io/queue-name: default`

And re-apply.

### vLLM Environment Variables

The following env vars are used in Step 05 and should be preserved:
- `VLLM_USE_V1: "1"` — Required for RHOAI 3.0
- `VLLM_NO_HW_METRICS: "1"` — Avoids DCGM dependency issues
- `LD_LIBRARY_PATH: "/usr/local/nvidia/lib64"` — NVIDIA library path

---

## Troubleshooting

### Pods Not Scheduling

**Symptom**: Worker pods stuck in `Pending`

**Check**:
```bash
oc get pods -n private-ai -o wide | grep mistral-3-distributed
oc describe pod -n private-ai <pod-name> | grep -A10 "Events:"
```

**Common causes**:
- Insufficient GPU nodes (need 2× g6.4xlarge for tensor=2)
- Kueue quota exceeded
- Missing tolerations for GPU taint

### Router Not Ready

**Symptom**: LLMInferenceService shows `RouterNotReady`

**Check**:
```bash
oc get pods -n private-ai | grep router
oc logs -n private-ai -l component=router
```

### OpenShift Console / Routes Unavailable After Creating `openshift-ai-inference` Gateway

**Symptom**:
- OpenShift web console is unavailable (browser can’t load).
- Cluster operators show route/DNS errors:
  - `oc get co console authentication ingress`
- `*.apps.<cluster_domain>` (and/or `console-openshift-console.apps...`) returns `NXDOMAIN`.

**Root Cause (only if you created an additional Gateway/LB):**
Using a Gateway listener hostname like `*.apps.<cluster_domain>` for the `openshift-ai-inference` Gateway can cause the OpenShift Gateway controller to create a **wildcard** `DNSRecord` and (temporarily) overwrite or remove the default `*.apps` record.

That breaks *all* OpenShift Routes, including the console and OAuth routes.

**Solution (cluster admin):**

```bash
# 1) Identify DNSRecords
oc get dnsrecord -A

# 2) Ensure the ingress wildcard is still owned by the default ingress controller
oc get dnsrecord default-wildcard -n openshift-ingress-operator -o yaml | grep -A5 dnsName

# 3) Remove any stale openshift-ai-inference gateway stack created with the old class
# (these are generated resources; safe to delete if the Gateway is no longer using that class)
oc delete svc openshift-ai-inference-data-science-gateway-class -n openshift-ingress --ignore-not-found=true
oc delete deploy openshift-ai-inference-data-science-gateway-class -n openshift-ingress --ignore-not-found=true

# 4) Force a re-publish of the *.apps DNSRecord (bumps generation/reconcile)
oc patch dnsrecord default-wildcard -n openshift-ingress-operator --type=merge -p '{"spec":{"recordTTL":31}}'
oc patch dnsrecord default-wildcard -n openshift-ingress-operator --type=merge -p '{"spec":{"recordTTL":30}}'

# 5) Validate operators recover
oc get co console authentication ingress
```

> **Note (client-side DNS caching):** your workstation DNS resolver may cache `NXDOMAIN` for several minutes.
> If the console is still not reachable after the record is restored, flush local DNS caches and retry.

### Gateway TLS Origination Issues (Known Limitation)

**Symptom**: Gateway endpoint returns "Internal Server Error" (HTTP 500)

**Root Cause**: The Gateway API HTTPRoute routes to an HTTPS backend (vLLM serving on port 8000 with TLS). The TLS origination from the Gateway Envoy proxy to the backend fails despite configured `DestinationRules`.

**Context from [rh-aiservices-bu/rhaoi3-llm-d](https://github.com/rh-aiservices-bu/rhaoi3-llm-d) reference repo**:
- The reference repo uses internal cluster URLs for benchmarks
- Different cluster/Istio configurations may work
- The Gateway TLS origination behavior appears to be environment-specific

**Workaround**: Use the **OpenShift Route** (passthrough TLS) instead of the Gateway endpoint:

```bash
# ✅ WORKS: OpenShift Route (passthrough TLS)
ROUTE_URL=$(oc get route mistral-3-distributed -n private-ai -o jsonpath='https://{.spec.host}')
curl -sk "$ROUTE_URL/v1/models"

# ❌ MAY NOT WORK: Gateway endpoint (TLS origination issue)
GATEWAY_URL=$(oc get llminferenceservice mistral-3-distributed -n private-ai -o jsonpath='{.status.url}')
curl -sk "$GATEWAY_URL/v1/models"  # Returns 500
```

**Why Route works but Gateway doesn't**:
| Access Method | TLS Handling | Status |
|---------------|--------------|--------|
| OpenShift Route (passthrough) | TLS terminated at pod | ✅ Works |
| Gateway API → HTTPRoute | TLS origination from Envoy to HTTPS backend | ❌ 500 Error |

> **Design Decision**: For this demo, we use the OpenShift Route for external access.
> The Gateway endpoint URL shown in the dashboard may not be functional.

### Gateway Connection Issues (General)

**Symptom**: External endpoint not accessible

**Check**:
```bash
oc get gateway -n openshift-ingress
oc get httproute -n private-ai
oc describe llminferenceservice mistral-3-distributed -n private-ai
```

### Missing Kueue Label

**Symptom**: CR rejected by admission webhook

**Error**: `missing required label "kueue.x-k8s.io/queue-name"`

**Fix**: Add `kueue.x-k8s.io/queue-name: default` to metadata.labels

---

## Cleanup

```bash
# Remove distributed inference resources
oc delete llminferenceservice mistral-3-distributed -n private-ai

# Or remove via ArgoCD
oc delete application step-08-llm-d -n openshift-gitops
```

---

## References

### Official Documentation

- **Deploying models (llm-d)**:
  - [RHOAI 3.0: Deploying models by using Distributed Inference with llm-d](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#deploying-models-using-distributed-inference_rhoai-user)
  - [RHOAI 3.0: Configuring authentication for llm-d using Red Hat Connectivity Link](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#configuring-authentication-for-llmd_rhoai-user)
  - [RHOAI 3.0: Enabling Distributed Inference with llm-d](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#enabling-distributed-inference_rhoai-user)
  - [RHOAI 3.0: Example usage — Single-node GPU deployment](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#single_node_gpu_deployment)
  - [RHOAI 3.0: Example usage — Multi-node deployment](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#multi_node_deployment)
  - [RHOAI 3.0: Example usage — Intelligent inference scheduler with KV cache routing](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index#intelligent_inference_scheduler_with_kv_cache_routing)
- **Release notes**:
  - [RHOAI 3.0: New features and enhancements](https://docs.redhat.com/documentation/red_hat_openshift_ai_self-managed/3.0/html/release_notes/new-features-and-enhancements_relnotes)
  - [RHOAI 3.0: Release notes (index)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/release_notes/index)

### Additional Reading

- [Introduction to Distributed Inference with llm-d](https://developers.redhat.com/articles/2025/11/21/introduction-distributed-inference-llm-d)
- [Demystifying llm-d and vLLM: The race to production](https://www.redhat.com/en/blog/demystifying-llm-d-and-vllm-race-production)
- [Autoscaling vLLM on OpenShift AI](https://developers.redhat.com/articles/2025/11/26/autoscaling-vllm-openshift-ai-model-serving)

### Repo References

- [Step 01: GPU Prerequisites](../step-01-gpu-and-prereq/README.md) — LeaderWorkerSet operator, GPU nodes
- [Step 05: vLLM Baseline](../step-05-llm-on-vllm/README.md) — INT4 model configuration
- [Step 07: Benchmarking](../step-07-model-performance-metrics/README.md) — GuideLLM, performance measurement

---

## RHOAI 3.0 llm-d Architecture

Understanding the four-layer architecture helps explain Gateway behavior:

| Layer | Component | Role | Status in Demo |
|-------|-----------|------|----------------|
| **Orchestration** | LeaderWorkerSet (LWS) | Multi-pod coordination for tensor parallelism | N/A (using replicas) |
| **Engine** | vLLM | High-performance inference runtime | ✅ Running in workload pods |
| **Gateway** | InferenceGateway (MaaS) | Auth, rate limiting, unified endpoint | ❌ CRD not available |
| **Network** | Service Mesh/Istio | Pod-to-pod TLS, ingress | ✅ Partial (see limitations) |

> **Key insight**: The `InferenceGateway` (`maas.opendatahub.io/v1alpha1`) is the proper MaaS endpoint.
> This CRD is **Developer Preview** and not available in RHOAI 3.0 GA installations.

### Why Gateway API TLS Fails

The Gateway API → HTTPRoute → InferencePool path requires TLS origination to the backend:
1. Gateway receives HTTP:80
2. HTTPRoute routes to InferencePool (port 8000)
3. InferencePool → EPP → Workload pods (HTTPS:8000)

**Issue**: The Gateway Envoy's TLS origination to the HTTPS backend fails despite:
- DestinationRules with `mode: SIMPLE` and `insecureSkipVerify: true`
- Service `appProtocol: https` annotation
- Correct Envoy cluster configuration

**Workaround**: Use OpenShift Route with passthrough TLS (TLS terminated at pod).

### Accessing llm-d in This Demo

| Method | URL | Status |
|--------|-----|--------|
| **OpenShift Route** (recommended) | `https://mistral-3-distributed-private-ai.apps.cluster-78cqq.78cqq.sandbox3352.opentlc.com` | ✅ Works |
| **Gateway API** (dashboard URL) | `http://...elb.amazonaws.com/private-ai/mistral-3-distributed` | ❌ 500 Error |
| **Internal cluster** | `http://openshift-ai-inference-openshift-default.openshift-ingress.svc.cluster.local/...` | ❌ 500 Error |

---

## Future Enhancements

### Model-as-a-Service (MaaS) Integration

> **Status:** Developer Preview in RHOAI 3.0 GA
> **Dependency:** `InferenceGateway` CRD (`maas.opendatahub.io/v1alpha1`) - **Not available in this cluster**

MaaS provides a centralized "Enterprise AI API" pattern using four layers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          MaaS Architecture                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────┐     ┌──────────────────┐     ┌──────────────┐     ┌─────────┐ │
│  │ Client  │────▶│ InferenceGateway │────▶│ llm-d Router │────▶│ Workload│ │
│  │ + API   │     │ (Authorino auth) │     │ (EPP/KV-cache│     │ (vLLM)  │ │
│  │   Key   │     │ (Limitador rate) │     │  scheduling) │     │         │ │
│  └─────────┘     └──────────────────┘     └──────────────┘     └─────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### MaaS Configuration Layers

| Layer | Component | Purpose | Status |
|-------|-----------|---------|--------|
| **1. Platform** | `OdhDashboardConfig.modelAsService: true` | Enable MaaS controllers | ✅ Enabled |
| **2. Identity** | AuthConfig + API Key Secret | Request authentication | ✅ CRD available |
| **3. Rate Limit** | Limitador | Token/request quotas | ✅ CRD available |
| **4. Routing** | InferenceGateway | Unified endpoint | ❌ CRD not installed |

#### Example MaaS Configuration (For Future Use)

When `InferenceGateway` CRD becomes available, configure MaaS as follows:

**API Key Secret:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: demo-api-key
  namespace: private-ai
  labels:
    authorino.kuadrant.io/managed-by: authorino
stringData:
  api_key: "rhoai-demo-secret-2025"
```

**AuthConfig:**
```yaml
apiVersion: authorino.kuadrant.io/v1beta1
kind: AuthConfig
metadata:
  name: maas-auth
  namespace: private-ai
spec:
  hosts:
    - "*"
  authentication:
    "api-key-auth":
      apiKey:
        selector:
          matchLabels:
            authorino.kuadrant.io/managed-by: authorino
      header:
        name: Authorization
```

**InferenceGateway:**
```yaml
apiVersion: maas.opendatahub.io/v1alpha1
kind: InferenceGateway
metadata:
  name: enterprise-ai-gateway
  namespace: private-ai
spec:
  auth:
    type: authorino
  rateLimit:
    type: limitador
  gatewayRef:
    name: data-science-gateway
    namespace: openshift-ingress
  models:
    - name: mistral-3-bf16
      serviceName: mistral-3-bf16-predictor
    - name: mistral-3-int4
      serviceName: mistral-3-int4-predictor
    - name: mistral-3-distributed
      serviceName: mistral-3-distributed-api  # llm-d Leader
```

**Testing (when available):**
```bash
# Get MaaS endpoint
MAAS_URL=$(oc get inferencegateway enterprise-ai-gateway -n private-ai -o jsonpath='{.status.url}')

# Test with API key
curl -k -X POST "$MAAS_URL/v1/chat/completions" \
  -H "Authorization: Bearer rhoai-demo-secret-2025" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-3-distributed",
    "messages": [{"role": "user", "content": "Explain llm-d."}]
  }'
```

#### Current Verification

```bash
# Check if InferenceGateway CRD exists (currently NOT available)
oc api-resources | grep -i inferencegateway

# Check MaaS controller (currently NOT running)
oc get pods -n redhat-ods-applications | grep maas

# Confirm modelAsService is enabled (✅ TRUE)
oc get odhdashboardconfig -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.modelAsService}'
```

**References:**
- [RHOAI 3.0 Release Notes - Developer Preview Features](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/release_notes/index)
- [Red Hat Developer: Introducing MaaS on OpenShift AI](https://developers.redhat.com/articles/2025/11/25/introducing-models-service-openshift-ai)
- [OpenDataHub MaaS Documentation](https://opendatahub-io.github.io/models-as-a-service/)
- [GitHub: opendatahub-io/models-as-a-service](https://github.com/opendatahub-io/models-as-a-service)

---

## Advanced Topics (Optional)

### LeaderWorkerSet (LWS) and Tensor Parallelism

> See [Deployment Mode Design Decision](#deployment-mode-design-decision) for a detailed comparison of the two modes.

**Our demo uses `tensor: 1, replicas: 2`** (Replicas Mode), which creates a standard Kubernetes Deployment.
For models requiring tensor parallelism, llm-d uses **LeaderWorkerSet (LWS)**.

#### Why LWS Matters

Standard Deployments treat pods independently. LWS provides:

1. **Atomic Startup**: Both Leader and Worker must start together — Kueue won't admit workload until all GPUs are available
2. **Fate Sharing**: If Leader crashes, Workers restart together
3. **Stable DNS**: Headless Service provides predictable addresses for Ray/NCCL communication

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      LeaderWorkerSet Architecture                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                    LeaderWorkerSet (size: 2)                          │  │
│  │  ┌─────────────────────────┐  ┌─────────────────────────┐            │  │
│  │  │       Pod 0 (Leader)    │  │       Pod 1 (Worker)    │            │  │
│  │  │  ┌───────────────────┐  │  │  ┌───────────────────┐  │            │  │
│  │  │  │   vLLM + Ray Head │  │  │  │   vLLM + Ray Worker│  │            │  │
│  │  │  │   Model Shard 0   │◄─┼──┼─▶│   Model Shard 1   │  │            │  │
│  │  │  │   nvidia.com/gpu:1│  │  │  │   nvidia.com/gpu:1│  │            │  │
│  │  │  └───────────────────┘  │  │  └───────────────────┘  │            │  │
│  │  └─────────────────────────┘  └─────────────────────────┘            │  │
│  │                              Ray/NCCL                                 │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Headless Service: mistral-70b-sharded-headless                            │
│  DNS: pod-0.mistral-70b-sharded-headless, pod-1.mistral-70b-sharded-headless│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### LWS Configuration Example

For true tensor parallelism (model too large for single GPU):

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: mistral-70b-sharded
  namespace: private-ai
spec:
  model:
    uri: oci://registry.redhat.io/rhelai1/modelcar-mistral-large:latest
  parallelism:
    tensor: 2  # Shard model across 2 pods (creates LWS)
  replicas: 1  # Single sharded instance
  template:
    containers:
      - name: main
        resources:
          limits:
            nvidia.com/gpu: "1"  # 1 GPU per pod × 2 pods = 2 GPUs total
```

This creates a `LeaderWorkerSet` with:
- Pod 0: Leader (Ray Head, Model Shard 0)
- Pod 1: Worker (Ray Worker, Model Shard 1)

#### Verification

```bash
# Check if LWS CRD is available
oc get crd | grep leaderworkerset

# Check if LWS was created (only for tensor > 1)
oc get leaderworkerset -n private-ai

# Our demo uses Deployment (replicas mode)
oc get deployment -n private-ai | grep mistral-3-distributed
```

### Disaggregated Prefill/Decode

llm-d supports separating prefill and decode workers for independent scaling:

```bash
# Check if prefill/decode fields are available
oc explain llminferenceservice.spec.prefill
oc explain llminferenceservice.spec.worker
```

> **Note**: This is an advanced feature. Keep Step 08 baseline simple;
> add disaggregation as an optional appendix if cluster CRDs support it.

### Autoscaling

Compare scaling mechanisms:
- **Kueue**: Workload admission and quota management
- **HPA/KPA**: Pod autoscaling based on metrics

```bash
oc get hpa -n private-ai
oc get knativepodautoscaler -n private-ai 2>/dev/null || true
```

> **Recommendation**: Do not mix autoscaling into Step 08 initially to avoid compounding variables.

---

> **Note**: This step is part of the RHOAI 3.0 demo series. The distributed inference feature requires RHOAI 3.0 GA and proper Gateway API configuration.
