# Step 07: Model Performance Metrics

**"The ROI of Quantization"** - Comprehensive observability and benchmarking to demonstrate that **Inference Efficiency** is the most important metric for enterprise AI.

## The Business Story

In enterprise AI deployments, the question isn't just *"How fast is my model?"* but *"How much value per GPU-hour?"*

This step demonstrates the **Economics of Precision**:

| Model | GPUs | Cost | Capacity | Use Case |
|-------|------|------|----------|----------|
| **Mistral-3-BF16** | 4 | $$$$ | High concurrency | Enterprise workloads |
| **Mistral-3-INT4** | 1 | $ | Moderate concurrency | Cost-optimized |

**The Key Question:** At what point does the 1-GPU model saturate, and how many 1-GPU specialists can we run for the cost of one 4-GPU powerhouse?

### Strategic Insights

1. **Define Performance Limits**: Find each model's "Breaking Point" (Concurrency vs. Latency)
2. **Quantify Efficiency**: Calculate Tokens-per-GPU across quantization levels
3. **ROI Analysis**: 4x INT4 instances vs 1x BF16 - which delivers more value?

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│               Step 07: The "ROI of Quantization" Demo                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                    Visualization Layer                                   │ │
│  │  ┌───────────────────────────────┐      ┌───────────────────────────┐   │ │
│  │  │     Grafana Dashboard         │      │     OpenShift Console     │   │ │
│  │  │  (KV Cache, TTFT, Throughput) │      │    (DCGM GPU Metrics)     │   │ │
│  │  └─────────────┬─────────────────┘      └─────────────┬─────────────┘   │ │
│  └────────────────┼──────────────────────────────────────┼─────────────────┘ │
│                   │                                      │                   │
│                   ▼                                      ▼                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │              OpenShift User Workload Monitoring                          │ │
│  │                     (Thanos Querier + Prometheus)                        │ │
│  └───────────────────────────────────┬─────────────────────────────────────┘ │
│                                      │                                       │
│                                      ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        GuideLLM Benchmark Jobs                           │ │
│  │  ┌───────────────────────────────────────────────────────────────────┐  │ │
│  │  │  Poisson Stress Test (simulates realistic human traffic)          │  │ │
│  │  │  Rate Sweep: 0.1 → 5.0 req/s | Find the "Breaking Point"          │  │ │
│  │  └───────────────────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────┬─────────────────────────────────────┘ │
│                                      │                                       │
│               ┌──────────────────────┴──────────────────────┐               │
│               ▼                                              ▼               │
│  ┌───────────────────────────┐              ┌───────────────────────────┐   │
│  │   mistral-3-int4 (1-GPU)  │              │   mistral-3-bf16 (4-GPU)  │   │
│  │   Cost: $                 │              │   Cost: $$$$              │   │
│  │   Break Point: X req/s    │              │   Break Point: Y req/s    │   │
│  └───────────────────────────┘              └───────────────────────────┘   │
│                                                                              │
│  ServiceMonitors AUTO-CREATED by KServe for each InferenceService           │
└─────────────────────────────────────────────────────────────────────────────┘
```

## What Gets Deployed

| Component | Description | Official/Community |
|-----------|-------------|-------------------|
| **Grafana Operator** | Kubernetes-native Grafana management from OperatorHub | Community |
| **Grafana Instance** | Dashboard with anonymous access in `private-ai` | Community (OSS) |
| **GrafanaDatasource** | Prometheus datasource pointing to UWM Thanos Querier | - |
| **3 GrafanaDashboards** | vLLM metrics + GPU hardware + ROI comparison | - |
| **GuideLLM CronJob** | Daily parallel benchmarks at 2:00 AM UTC | Community (OSS) |
| **Job Templates** | On-demand benchmark Jobs per model (`oc create -f`) | Community (OSS) |

> **⚠️ Community Tooling Disclaimer:** Grafana Operator and GuideLLM are community-driven tools and are NOT officially supported components of Red Hat OpenShift AI 3.3. See [Red Hat's Third Party Software Support Policy](https://access.redhat.com/third-party-software-support).

## Benchmarking Approach

We use a **simplified CronJob + Job template** pattern instead of Tekton Pipelines:

```
CronJob (daily, 2 AM UTC)
├── Checks which models are running (curl /models)
├── Creates a GuideLLM Job per active model
└── Each Job: benchmark → metrics flow to Prometheus → visible in Grafana

On-demand (any time):
  oc create -f gitops/.../guidellm/job-templates/granite-8b-agent.yaml
  oc create -f gitops/.../guidellm/job-templates/mistral-3-bf16.yaml
```

**Why not Tekton Pipelines?** In Kueue-managed namespaces, Tekton's affinity assistants and topology scheduling gates create deadlocks. Simple Jobs with `kueue.x-k8s.io/queue-name: default` work reliably.

**Why no results PVC?** The real value is in Prometheus/Grafana metrics, not JSON files. vLLM automatically exposes metrics via ServiceMonitors — every benchmark request lights up the dashboards.

## Traffic Profiles (aligned with NeuralNav/GuideLLM standards)

| Profile | Tokens (in→out) | Use Case | Model | SLO Class |
|---------|----------------|----------|-------|-----------|
| **Chatbot/Q&A** | 512→256 | Interactive chat, tool-calling | `granite-8b-agent` | Conversational |
| **Enterprise Chat** | 1024→1024 | Content generation, translation | `mistral-3-bf16` | Interactive |
| **RAG/Summarization** | 4096→512 | Document analysis, long-context Q&A | `granite-8b-agent` (RAG) | Interactive |

> **Ref:** [NeuralNav Traffic Profile Framework](https://github.com/redhat-et/neuralnav/blob/main/docs/traffic_and_slos.md)

## SLO Targets (Experience-Driven)

| Experience Class | TTFT P95 | ITL P95 | E2E P95 | Our Model | Status |
|-----------------|---------|---------|---------|-----------|--------|
| **Conversational** | ≤150ms | ≤25ms | ≤7s | granite-8b: 60-95ms TTFT, 40ms TPOT | ✅ Meets SLO |
| **Interactive** | ≤500ms | ≤35ms | ≤25s | mistral-bf16: 70-115ms TTFT, 53ms TPOT | ⚠️ TPOT exceeds |
| **Deferred** | ≤1s | ≤40ms | ≤35s | mistral-bf16 at high concurrency | ✅ Meets SLO |

> **Ref:** [NeuralNav Experience-Driven SLOs](https://github.com/redhat-et/neuralnav/blob/main/docs/traffic_and_slos.md#3-experience-classes-and-user-expectations)

### Grafana Operator Benefits

The [Grafana Operator](https://github.com/grafana/grafana-operator) provides Kubernetes-native management of Grafana:

- **GrafanaDashboard CRs**: Dashboards as code, auto-synced without restart
- **External URL References**: Official vLLM dashboards auto-updated from GitHub
- **GitOps Friendly**: Full ArgoCD integration with declarative resources
- **Multi-Instance Support**: Can manage multiple Grafana deployments

Reference: [redhat-cop/gitops-catalog](https://github.com/redhat-cop/gitops-catalog/tree/main/grafana-operator)

## Prerequisites

| Requirement | How to Verify |
|-------------|---------------|
| **Step 01 Complete** | User Workload Monitoring enabled, DCGM Dashboard |
| **Step 05 Complete** | At least one vLLM InferenceService running |
| **Recommended** | Both `mistral-3-int4` and `mistral-3-bf16` for comparison |

```bash
# Verify User Workload Monitoring
oc get cm cluster-monitoring-config -n openshift-monitoring -o yaml | grep enableUserWorkload

# Verify models are running (for ROI comparison, need both)
oc get inferenceservice -n private-ai | grep -E "mistral-3-int4|mistral-3-bf16"

# Verify auto-created ServiceMonitors
oc get servicemonitor -n private-ai | grep metrics
```

## SLA Targets & Thresholds

Based on [vLLM Production Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html) and industry best practices:

| Metric | Excellent | Acceptable (SLA) | Degraded | Breaking Point |
|--------|-----------|------------------|----------|----------------|
| **TTFT** | < 500ms | < 1.0s | 1.0-2.0s | > 2.0s |
| **TPOT** | > 50 tok/s | > 20 tok/s | 10-20 tok/s | < 10 tok/s |
| **KV Cache** | < 70% | 70-85% | 85-95% | > 95% |
| **Queue Depth** | 0 | 0-1 | 2-5 | > 5 |

> **Breaking Point Definition**: System is saturated when **TTFT > 1.0s** consistently OR **Queue Depth > 0** under steady load.

## Benchmark Results (Validated)

Based on GuideLLM graduated concurrency testing with synthetic data (256 input, 256 output tokens).

### Memory Optimizations Applied

Both models have been tuned using Red Hat AI Field Engineering recommendations:

| Optimization | INT4 (1-GPU) | BF16 (4-GPU) | Purpose |
|--------------|--------------|--------------|---------|
| `--kv-cache-dtype=fp8` | ✅ Applied | ✅ Applied | Doubles KV cache capacity |
| `--enable-chunked-prefill` | ✅ Applied | ✅ Applied | Prevents prefill blocking |
| `--max-model-len` | 8192 | 32768 | Right-sized for hardware |
| `--gpu-memory-utilization` | 0.85 | 0.9 | Driver breathing room |

### INT4 (1-GPU) Performance Profile

**Hardware:** g6.4xlarge (1x NVIDIA L4, 24GB VRAM)

| Concurrent Users | TTFT (p95) | TPOT (p95) | Throughput | Status |
|------------------|------------|------------|------------|--------|
| 1 | 1,105ms | 56ms | 51 tok/s | ✅ Baseline |
| 3 | 874ms | 56ms | 135 tok/s | ✅ **Healthy** |
| 5 | 1,489ms | 60ms | 207 tok/s | ⚠️ SLA borderline |
| **8** | **2,185ms** | **63ms** | **281 tok/s** | ⚠️ **Target capacity** |
| 10 | 2,822ms | 68ms | 313 tok/s | 🔴 Breaking |
| 15 | 4,277ms | 75ms | 438 tok/s | 🔴 Severe degradation |

> **INT4 Sweet Spot:** 3-5 concurrent users with TTFT < 1.5s
> **INT4 Breaking Point:** 8-10 concurrent users (TTFT > 2s)

### BF16 (4-GPU) Performance Profile

**Hardware:** g6.12xlarge (4x NVIDIA L4, 96GB total VRAM)

| Concurrent Users | TTFT (p95) | TPOT (p95) | Throughput | Status |
|------------------|------------|------------|------------|--------|
| 1 | 574ms | 54ms | 35 tok/s | ✅ Baseline |
| 5 | 594ms | 58ms | 160 tok/s | ✅ Healthy |
| **10** | **1,167ms** | **64ms** | **312 tok/s** | ✅ **Sweet spot** |
| 15 | 1,695ms | 67ms | 438 tok/s | ⚠️ SLA borderline |
| **20** | **2,084ms** | **78ms** | **593 tok/s** | 🔴 **Breaking point** |
| 30 | 2,993ms | 86ms | 694 tok/s | 🔴 Severe degradation |

> **BF16 Sweet Spot:** 5-15 concurrent users with TTFT < 1.7s
> **BF16 Breaking Point:** 20 concurrent users (TTFT > 2s)

### ROI Analysis: The Economics of Precision

| Metric | INT4 (1-GPU) | BF16 (4-GPU) | Ratio |
|--------|--------------|--------------|-------|
| **Hardware Cost** | $0.85/hr | $3.40/hr | 4x |
| **Sweet Spot Capacity** | 3-5 users | 10-15 users | 3x |
| **Breaking Point** | 8-10 users | 20 users | 2-2.5x |
| **Max Throughput** | ~300 tok/s | ~700 tok/s | 2.3x |
| **Efficiency (tok/s/$)** | 353 tok/s/$ | 206 tok/s/$ | **INT4 1.7x better** |

### Key Findings

1. **FP8 KV Cache is Critical for INT4**: Without FP8 cache, INT4 broke at 5 users. With optimization, it handles 8+ users (60% improvement).

2. **INT4 is More Cost-Efficient**: At $0.85/hr vs $3.40/hr, INT4 delivers 1.7x more tokens per dollar.

3. **BF16 Scales Better**: For high-concurrency workloads (15+ users), BF16's 4-GPU parallelism provides more stable latency.

4. **The "4x INT4" Strategy**: Running 4 INT4 instances (4 × 8 = 32 concurrent users) would cost the same as 1 BF16 instance (20 concurrent users), providing 60% more capacity.

### Demo Storyline

> *"With Red Hat AI memory optimizations, a single $0.85/hr L4 GPU running INT4 quantization handles 8 concurrent users with sub-100ms per-token latency. For the cost of one 4-GPU BF16 deployment, you can run 4 INT4 instances serving 60% more users with 98.9% accuracy recovery."*

## Deployment

### Option A: Direct Deploy (Recommended for Demo)

```bash
./steps/step-07-model-performance-metrics/deploy.sh
```

### Option B: ArgoCD (GitOps)

```bash
oc apply -f gitops/argocd/app-of-apps/step-07-model-performance-metrics.yaml
```

## Demo Walkthrough

### Before the Demo (~5 min)

```bash
# 1. Get Grafana URL
GRAFANA_URL=$(oc get route grafana-route -n private-ai -o jsonpath='{.spec.host}')
echo "https://${GRAFANA_URL}"

# 2. Run benchmarks to generate live Grafana data
oc create -f gitops/step-07-model-performance-metrics/base/guidellm/job-templates/granite-8b-agent.yaml
oc create -f gitops/step-07-model-performance-metrics/base/guidellm/job-templates/mistral-3-bf16.yaml

# 3. Monitor progress
oc get pods -n private-ai -l app=guidellm -w
```

### During the Demo

**Dashboard 1: vLLM Latency, Throughput & Cache** (primary — show live)

Open Grafana → select "vLLM Latency, Throughput & Cache" dashboard. Ensure `namespace=private-ai` and `model_name=granite-8b-agent`.

Walk through these panels:

1. **E2E Request Latency** — "P99 latency stays under 40s even at 10 concurrent users"
2. **Token Throughput** — "We're generating 80-120 tokens/second on a single $0.85/hr GPU"
3. **Scheduler State** — "Green line shows concurrent requests; yellow would show queuing — we have zero queue backlog"
4. **Cache Utilization** — "KV cache usage stays healthy, no memory pressure"
5. **Time To First Token** — "TTFT P95 under 95ms — users see the first token almost instantly"

Switch `model_name` to `mistral-3-bf16` and compare the same panels.

**Dashboard 2: NVIDIA DCGM GPU Metrics** (optional — hardware story)

- Show GPU utilization hitting 100% during benchmarks
- Point out: "This is the capacity ceiling — when we need more, Kueue queues the request"

**Dashboard 3: Mistral ROI Comparison** (closing — business story)

- Side-by-side BF16 vs INT4 metrics
- Key message: *"The 1-GPU model delivers 60% of the 4-GPU model's throughput at 25% of the cost"*

### Demo Talking Points

> *"On a single $0.85/hr L4 GPU, granite-8b-agent handles 10 concurrent users with sub-100ms TTFT and zero queue backlog. The 4-GPU BF16 model costs 4x more but only delivers 2x the throughput. For cost-sensitive workloads, running 4 instances of the 1-GPU model gives you more total capacity at the same price."*

> *"When the GPU hits 100% utilization, Kueue's quota management kicks in — new models queue until resources free up. This is exactly the GPU-as-a-Service pattern we demonstrated in Step 05."*

## Running Benchmarks

### On-Demand (Job Templates)

```bash
# Benchmark granite-8b-agent (1-GPU, ~5 min)
oc create -f gitops/step-07-model-performance-metrics/base/guidellm/job-templates/granite-8b-agent.yaml

# Benchmark mistral-3-bf16 (4-GPU, ~8 min)
oc create -f gitops/step-07-model-performance-metrics/base/guidellm/job-templates/mistral-3-bf16.yaml

# Monitor
oc get pods -n private-ai -l app=guidellm -w

# View results
oc logs job/<job-name> -n private-ai | grep -A12 "Request Latency Statistics"
```

### Automated (CronJob)

```bash
# Runs daily at 2:00 AM UTC — benchmarks all active models
oc get cronjob guidellm-daily -n private-ai

# Trigger manually
oc create job --from=cronjob/guidellm-daily bench-$(date +%H%M) -n private-ai
```

## vLLM Metrics Reference

> **Important**: vLLM metrics use `:` separator, not `_` (e.g., `vllm:num_requests_running`)

| Metric | Type | Description | Saturation Indicator |
|--------|------|-------------|---------------------|
| `vllm:num_requests_running` | Gauge | Active requests | > 10 = heavy load |
| `vllm:num_requests_waiting` | Gauge | Queued requests | > 0 = saturating |
| `vllm:kv_cache_usage_perc` | Gauge | KV Cache utilization | > 85% = memory pressure |
| `vllm:time_to_first_token_seconds` | Histogram | TTFT latency | P95 > 1s = degraded |
| `vllm:generation_tokens_total` | Counter | Total output tokens | Rate = throughput |

### PromQL Queries for Grafana

```promql
# The "Breaking Point" Query - Queue building up
vllm:num_requests_waiting{namespace="private-ai"} > 0

# KV Cache Wall - Memory saturation
vllm:kv_cache_usage_perc{namespace="private-ai"} > 0.85

# TTFT by Model - Find the slow one
histogram_quantile(0.95, sum(rate(vllm:time_to_first_token_seconds_bucket{namespace="private-ai"}[5m])) by (le, model_name))

# Throughput Comparison
rate(vllm:generation_tokens_total{namespace="private-ai"}[1m])
```

## GitOps Structure

```
gitops/step-07-model-performance-metrics/
├── base/
│   ├── kustomization.yaml
│   ├── pipelines-operator/                # Red Hat OpenShift Pipelines (for step-09)
│   │   ├── kustomization.yaml
│   │   └── subscription.yaml
│   ├── grafana-operator/
│   │   ├── kustomization.yaml
│   │   ├── operator/                      # Grafana Operator from OperatorHub
│   │   │   ├── kustomization.yaml
│   │   │   ├── namespace.yaml
│   │   │   ├── operatorgroup.yaml
│   │   │   └── subscription.yaml          # community-operators, v5 channel
│   │   ├── instance/                      # Grafana instance in private-ai
│   │   │   ├── kustomization.yaml
│   │   │   ├── grafana.yaml               # Grafana CR (anonymous access)
│   │   │   └── datasource.yaml            # GrafanaDatasource + RBAC
│   │   └── dashboards/                    # 3 focused GrafanaDashboard CRs
│   │       ├── kustomization.yaml
│   │       ├── vllm-latency-throughput-cache.yaml # PRIMARY: 12-panel vLLM metrics
│   │       ├── vllm-ltc-configmap.yaml           # Dashboard JSON (ConfigMap)
│   │       ├── dcgm-gpu-metrics.yaml             # GPU hardware metrics
│   │       └── mistral-roi-comparison.yaml       # BF16 vs INT4 ROI story
│   ├── guidellm/                          # Benchmarking (CronJob + Job templates)
│   │   ├── kustomization.yaml
│   │   ├── rbac.yaml                      # SA + Role for dispatcher
│   │   ├── cronjob.yaml                   # Daily dispatcher
│   │   └── job-templates/                 # On-demand benchmarks (oc create -f)
│   │       ├── granite-8b-agent.yaml      # 512→256 Chatbot profile
│   │       └── mistral-3-bf16.yaml        # 1024→1024 Enterprise profile
└── kustomization.yaml
```

### Dashboards (3 Focused Views)

| # | Dashboard | Purpose | Demo Use |
|---|-----------|---------|----------|
| 1 | **vLLM Latency, Throughput & Cache** | 12-panel comprehensive vLLM metrics | **Primary** — show during live benchmark |
| 2 | **NVIDIA DCGM GPU Metrics** | GPU hardware: temp, power, utilization | Show GPU saturation at breaking point |
| 3 | **Mistral ROI Comparison** | BF16 vs INT4 side-by-side | Close with the ROI story |

> Consolidated from 6 dashboards to 3. The vLLM Latency, Throughput & Cache dashboard (from [llm-d-deployer](https://github.com/llm-d/llm-d-deployer)) replaces the 3 separate vLLM dashboards — it covers E2E latency P50/P95/P99, TTFT, TPOT, scheduler state, KV cache utilization, queue time, and prefill/decode time in one view.

## Validation

```bash
# 1. Verify Grafana Operator
oc get csv -n grafana-operator | grep grafana
# Expected: grafana-operator.v5.x ... Succeeded

# 2. Verify Grafana instance
oc get grafana -n private-ai
# Expected: grafana   12.x.x   complete   success

# 3. Verify 3 dashboards
oc get grafanadashboard -n private-ai
# Expected: vllm-latency-throughput-cache, dcgm-gpu-metrics, mistral-roi-comparison

# 4. Verify datasource
oc get grafanadatasource -n private-ai
# Expected: prometheus-uwm

# 5. Verify Grafana route
curl -k -s -o /dev/null -w "%{http_code}" \
  https://$(oc get route grafana-route -n private-ai -o jsonpath='{.spec.host}')/api/health
# Expected: 200

# 6. Verify CronJob
oc get cronjob guidellm-daily -n private-ai
# Expected: guidellm-daily   0 2 * * *

# 7. Verify ServiceMonitors (auto-created by KServe)
oc get servicemonitor -n private-ai
# Expected: one per model (*-metrics)

# 11. Verify Workbench Route is accessible
curl -k -s -o /dev/null -w "%{http_code}" https://$(oc get route guidellm-workbench -n private-ai -o jsonpath='{.spec.host}')/_stcore/health
# Expected: 200

# 12. Verify ServiceMonitors exist (auto-created by KServe)
oc get servicemonitor -n private-ai | grep metrics
# Expected: One per model (mistral-3-int4-metrics, mistral-3-bf16-metrics, etc.)
```

## Troubleshooting

### GuideLLM Job Failing

**Symptom:** Benchmark job exits with error

```bash
# Check job logs
oc logs job/<job-name> -n private-ai

# Common issues:
# - Model not responding: Check InferenceService is ready
# - Rate too high: Lower MAX_RATE in single-model-benchmark.sh
```

### No Data in Grafana

**Symptom:** Dashboard shows "No data"

```bash
# Verify Prometheus targets
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -- \
  curl -s 'localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job | contains("metrics")) | {job: .labels.job, health: .health}'
```

## Additional Monitoring

### GPU Metrics (DCGM)

Access GPU-level metrics in OpenShift Console:
1. Navigate to: **Observe → Dashboards**
2. Select: **NVIDIA DCGM Exporter Dashboard**

This was deployed in Step 01 via `dcgm-dashboard-configmap.yaml`.

### OpenShift Console Metrics

Direct PromQL queries in OpenShift Console:
1. Navigate to: **Observe → Metrics**
2. Query: `vllm:num_requests_running{namespace="private-ai"}`

## Official Documentation & References

### Red Hat Official
- [RHOAI 3.3 Monitoring Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_and_monitoring_models/index)
- [OpenShift User Workload Monitoring (4.20)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/monitoring/enabling-monitoring-for-user-defined-projects)
- [Red Hat OpenShift Pipelines 1.20](https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20)
- [GuideLLM - Evaluate LLM Deployments (Red Hat Developers)](https://developers.redhat.com/articles/2025/06/20/guidellm-evaluate-llm-deployments-real-world-inference)
- [How to Deploy and Benchmark vLLM with GuideLLM (Red Hat Developers)](https://developers.redhat.com/articles/2025/12/24/how-deploy-and-benchmark-vllm-guidellm-kubernetes)

### Community / Open Source
- [vLLM Production Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html)
- [vLLM Grafana Dashboards (GitHub)](https://github.com/vllm-project/vllm/tree/main/examples/online_serving/dashboards/grafana)
- [Grafana Operator (GitHub)](https://github.com/grafana/grafana-operator)
- [Grafana Operator Documentation](https://grafana.github.io/grafana-operator/docs/)
- [redhat-cop/gitops-catalog - OpenShift Pipelines](https://github.com/redhat-cop/gitops-catalog/tree/main/openshift-pipelines-operator)
- [redhat-cop/gitops-catalog - Grafana Operator](https://github.com/redhat-cop/gitops-catalog/tree/main/grafana-operator)
- [GuideLLM (vllm-project)](https://github.com/vllm-project/guidellm) — SLO-aware benchmarking platform
- [NeuralNav - SLO-Driven Capacity Planning](https://github.com/redhat-et/neuralnav) — Traffic profiles + experience-driven SLOs
- [llm-d Observability on OpenShift AI](https://medium.com/@jajodia.nirjhar/how-we-built-an-observability-stack-for-llm-d-on-openshift-ai-d46e6365a362) — Grafana + Thanos pattern
- [llm-d-deployer vLLM Dashboard](https://github.com/llm-d/llm-d-deployer/tree/main/quickstart/grafana/dashboards)
- [RHOAI GenAIOps Patterns](https://github.com/rhoai-genaiops)

### Future Enhancement: Metrics-Based Autoscaling (RHOAI 3.3 TP)

RHOAI 3.3 introduces **metrics-based autoscaling** (Technology Preview) using KEDA with vLLM metrics. This enables autoscaling InferenceServices based on latency and throughput SLOs instead of traditional request concurrency.

```yaml
# Example: Scale based on vLLM queue depth
spec:
  predictor:
    minReplicas: 1
    maxReplicas: 5
    autoscaling:
      metrics:
        - type: External
          external:
            metric:
              backend: "prometheus"
              query: vllm:num_requests_waiting
            target:
              type: Value
              value: 2
```

> **Ref:** [RHOAI 3.3 — Configuring metrics-based autoscaling](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_and_monitoring_models/managing_and_monitoring_models#configuring-metrics-based-autoscaling_monitor-model)

### Related Steps
- [Step 09: RAG Pipeline](../step-09-rag-pipeline/README.md) — Document ingestion and vector search
- [llm-d Workshop](https://rhpds.github.io/llm-d-showroom/) — Distributed inference with intelligent routing (separate demo)
