# Step 08: Distributed Inference with llm-d

**"Elastic Scale-Out on a Budget"** — Demonstrating horizontal scaling of LLM inference across multiple GPU nodes using RHOAI 3.0's llm-d (Distributed Inference) capability.

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
- We can benchmark it using the existing GuideLLM + vLLM metrics and compare to the single-node INT4 baseline

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
║  g6.4xlarge  ×2   │ 2× L4 │ Mistral-3 INT4 (llm-d) ⭐  │ rhoai-llmd-queue   ║
║                                                                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  TOTAL: 1× g6.12xlarge + 3× g6.4xlarge = 7 GPUs                             ║
║                                                                              ║
║  Cost: $3.40/hr (g6.12xlarge) + $2.55/hr (3× g6.4xlarge) = ~$5.95/hr        ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

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

# Verify Gateway exists (note: our cluster uses data-science-gateway, not openshift-ai-inference)
oc get gateway -n openshift-ingress

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
│   └── benchmark/                       # Benchmarking (sync-wave: 5)
│       ├── kustomization.yaml
│       ├── pvc.yaml                     # Results storage
│       └── cronjob.yaml                 # llmd-benchmark
```

> **Note:** The Connectivity Link instance (resource kind `Kuadrant`) is deployed by Step 08 (not Step 01) because:
> 1. Step 01 installs the **RHCL operator** (provides CRDs)
> 2. Step 08 creates the **instance** (in `private-ai` namespace)
> 3. This pattern separates operator installation from workload configuration

### Comparison with Step 05/07 Baseline

| Metric | INT4 Single-Node (Step 05) | Distributed llm-d (Step 08) |
|--------|---------------------------|------------------------------|
| **GPUs** | 1× L4 | 2× L4 (tensor parallel) |
| **Instance** | g6.4xlarge | 2× g6.4xlarge |
| **Cost** | $0.85/hr | $1.70/hr |
| **Throughput** | ~85 tok/s | TBD (expected: 1.5-2x) |
| **Breaking Point** | ~8 concurrent | TBD (expected: ~15-20) |

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
spec:
  model:
    name: mistral-3-distributed
    uri: oci://registry.redhat.io/rhelai1/modelcar-mistral-small-24b-instruct-2501-quantized-w4a16:1.5
  
  # Distribute across 2 GPUs using tensor parallelism
  parallelism:
    tensor: 2
  
  # Number of replicas (each replica spans tensor GPUs)
  replicas: 1
  
  # Pod template for GPU scheduling
  template:
    nodeSelector:
      node.kubernetes.io/instance-type: g6.4xlarge
    tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
    # NOTE: The llm-d controller injects a container named "main".
    # We must use spec.template.containers with name: "main" to set GPU
    # resources on the correct container (not a custom name like "vllm").
    containers:
      - name: main
        resources:
          limits:
            nvidia.com/gpu: "1"
          requests:
            nvidia.com/gpu: "1"
  
  # Router configuration
  router:
    route: {}
    scheduler: {}
    gateway:
      refs:
        - name: data-science-gateway
          namespace: openshift-ingress
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

```bash
# Get the endpoint URL
ENDPOINT=$(oc get llminferenceservice mistral-3-distributed -n private-ai -o jsonpath='{.status.url}')

# Test inference
curl -sk "$ENDPOINT/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-3-distributed",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'
```

---

## Validate

### Expected Outcomes

1. **Pods on separate nodes**: Each worker scheduled on different g6.4xlarge
2. **Router pod running**: Handles request scheduling
3. **Endpoint accessible**: Gateway routes traffic to router

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
└── cronjob.yaml             # llmd-benchmark CronJob (daily 3:00 AM UTC)
```

### Run GuideLLM Benchmark

```bash
# Discover what Services/Routes the llm-d controller created
oc get svc -n private-ai | grep -i mistral || true
oc get route -n private-ai | grep -i mistral || true

# Trigger the dedicated llm-d benchmark
oc create job --from=cronjob/llmd-benchmark manual-llmd-$(date +%H%M) -n private-ai

# Monitor the benchmark
oc logs -f job/manual-llmd-$(date +%H%M) -n private-ai
```

### Benchmark Configuration

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Profile** | `constant` | Graduated concurrency |
| **Rates** | `1,3,5,8,10,15,20,30,40,50` | Extended range for distributed capacity |
| **Input Tokens** | 256 | Same as Step 07 for comparison |
| **Output Tokens** | 256 | Same as Step 07 for comparison |
| **Duration** | 60s per rate | 10 levels × 60s = ~10 min total |

### Metrics to Compare

| Metric | INT4 Single (Step 07) | Distributed (Step 08) | Notes |
|--------|----------------------|----------------------|-------|
| TTFT (p95) | TBD (measure) | TBD (measure) | Expect similar or slightly higher |
| TPOT (p95) | TBD (measure) | TBD (measure) | Expect similar |
| Max Throughput | TBD (measure) | TBD (measure) | Hypothesis: higher with tensor=2 |
| Breaking Point | TBD (measure) | TBD (measure) | Hypothesis: higher with tensor=2 |
| KV Cache Usage | `vllm:kv_cache_usage_perc` | TBD | Key saturation indicator |
| Queue Depth | `vllm:num_requests_waiting` | TBD | Saturation indicator |

### View Results

```bash
# Results are stored in the llmd-benchmark-results PVC
# Create a debug pod
oc run results-viewer --rm -it --image=busybox \
  --overrides='{"spec":{"containers":[{"name":"viewer","image":"busybox","command":["sh"],"volumeMounts":[{"name":"results","mountPath":"/results"}]}],"volumes":[{"name":"results","persistentVolumeClaim":{"claimName":"llmd-benchmark-results"}}]}}' \
  -n private-ai
```

---

## Technical Notes

### Gateway Naming

Official RHOAI 3.0 documentation references a Gateway named `openshift-ai-inference`.
Our cluster uses `data-science-gateway` in `openshift-ingress` namespace.

**If llm-d controller fails to bind:**
```bash
# Check for gateway binding errors
oc describe llminferenceservice mistral-3-distributed -n private-ai

# Verify available gateways
oc get gateway -n openshift-ingress

# Update the manifest if needed
# gitops/step-08-llm-d/base/llm-d/llminferenceservice.yaml → spec.router.gateway.refs
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

### Gateway Connection Issues

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

## Advanced Topics (Optional)

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
