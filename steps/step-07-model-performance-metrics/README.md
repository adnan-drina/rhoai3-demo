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
│  │  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐   │ │
│  │  │  Grafana Dashboard │  │ vLLM-Playground   │  │ OpenShift Console │   │ │
│  │  │  (KV Cache, TTFT)  │  │ (Interactive)     │  │ (DCGM GPU Metrics)│   │ │
│  │  └─────────┬─────────┘  └─────────┬─────────┘  └─────────┬─────────┘   │ │
│  └────────────┼──────────────────────┼──────────────────────┼─────────────┘ │
│               │                      │                      │               │
│               ▼                      │                      ▼               │
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
| **Grafana** | Visualization dashboard with anonymous access | Community (OSS) |
| **ServiceAccount** | `grafana-sa` with `cluster-monitoring-view` permissions | - |
| **Dashboard ConfigMaps** | Pre-configured vLLM metrics dashboard | - |
| **GuideLLM CronJob** | Daily Poisson stress tests at 2:00 AM UTC | Community (OSS) |
| **GuideLLM Scripts** | ROI comparison, efficiency analysis | - |
| **vLLM-Playground** | Interactive chat UI for demos | ⚠️ Community |

> **⚠️ Community Tooling Disclaimer:** vLLM-Playground and GuideLLM are community-driven tools and are NOT officially supported components of Red Hat OpenShift AI 3.0.

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

## Deployment

### Option A: Direct Deploy (Recommended for Demo)

```bash
./steps/step-07-model-performance-metrics/deploy.sh
```

### Option B: ArgoCD (GitOps)

```bash
oc apply -f gitops/argocd/app-of-apps/step-07-model-performance-metrics.yaml
```

## The "ROI of Quantization" Demo

### Step 1: Access Grafana Dashboard

```bash
# Get Grafana URL
GRAFANA_URL=$(oc get route grafana -n private-ai -o jsonpath='{.spec.host}')
echo "https://${GRAFANA_URL}"
```

**No login required** (anonymous access enabled). Default dashboard: **vLLM Model Performance**

### Step 2: Access vLLM-Playground (Interactive Demo)

```bash
# Get Playground URL
PLAYGROUND_URL=$(oc get route vllm-playground -n private-ai -o jsonpath='{.spec.host}')
echo "https://${PLAYGROUND_URL}"
```

Use this for live demos to show the "vibe check" - the qualitative feel of latency differences.

### Step 3: Run the Efficiency Comparison

```bash
# Trigger the ROI comparison benchmark
oc create job --from=cronjob/guidellm-daily roi-comparison-$(date +%H%M) -n private-ai

# Watch progress
oc logs -f job/roi-comparison-$(date +%H%M) -n private-ai
```

Alternatively, run the dedicated efficiency script:

```bash
# Create efficiency comparison job
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: roi-analysis
  namespace: private-ai
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: guidellm
          image: python:3.11-slim
          command:
            - /bin/bash
            - -c
            - |
              pip install --quiet guidellm
              chmod +x /scripts/efficiency-comparison.sh
              /scripts/efficiency-comparison.sh
          volumeMounts:
            - name: scripts
              mountPath: /scripts
            - name: results
              mountPath: /results
      volumes:
        - name: scripts
          configMap:
            name: guidellm-scripts
            defaultMode: 0755
        - name: results
          persistentVolumeClaim:
            claimName: guidellm-results
EOF

# Watch the comparison
oc logs -f job/roi-analysis -n private-ai
```

### Step 4: Interpret Results

After running the efficiency comparison, analyze:

1. **Break Point (INT4)**: At what req/s does TTFT exceed 1.0s?
2. **Break Point (BF16)**: At what req/s does TTFT exceed 1.0s?
3. **Efficiency Delta**: `BF16_breakpoint / INT4_breakpoint`
4. **Cost Analysis**: If INT4 breaks at 2 req/s and BF16 at 6 req/s, can 4x INT4 instances (4 × 2 = 8 req/s) outperform 1x BF16 at lower cost?

## GuideLLM Benchmarking

[GuideLLM](https://github.com/neuralmagic/guidellm) is an open-source tool from Neural Magic for evaluating LLM deployments by simulating real-world inference workloads.

### Poisson Stress Test Methodology

We use **Poisson distribution** to simulate realistic human arrival patterns, not synthetic constant load:

```
λ (lambda) = average requests per second
Actual arrivals follow Poisson distribution (natural variability)
```

This answers: *"How does my model behave when real users arrive randomly?"*

### Benchmark Scenarios

| Scenario | Prompt | Output | Focus | Simulates |
|----------|--------|--------|-------|-----------|
| **Chat** | 64 tok | 64 tok | TTFT | Interactive conversation |
| **Summarization** | 512 tok | 128 tok | KV Cache | Document processing |
| **Code Gen** | 128 tok | 256 tok | TPOT | Long-form generation |
| **Stress** | 256 tok | 256 tok | Overall | High I/O workload |

### Trigger Manual Benchmark

```bash
# Full sweep on all available models
oc create job --from=cronjob/guidellm-daily manual-$(date +%H%M) -n private-ai

# Watch progress
oc logs -f job/manual-$(date +%H%M) -n private-ai
```

### Run Single Model Benchmark

```bash
# Quick benchmark on specific model
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: benchmark-int4
  namespace: private-ai
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: guidellm
          image: python:3.11-slim
          env:
            - name: MODEL_NAME
              value: "mistral-3-int4"
            - name: SCENARIO
              value: "chat"
            - name: MAX_RATE
              value: "3.0"
          command:
            - /bin/bash
            - -c
            - |
              pip install --quiet guidellm
              chmod +x /scripts/single-model-benchmark.sh
              /scripts/single-model-benchmark.sh "\${MODEL_NAME}" "\${SCENARIO}" "\${MAX_RATE}"
          volumeMounts:
            - name: scripts
              mountPath: /scripts
            - name: results
              mountPath: /results
      volumes:
        - name: scripts
          configMap:
            name: guidellm-scripts
            defaultMode: 0755
        - name: results
          persistentVolumeClaim:
            claimName: guidellm-results
EOF
```

### View Benchmark Results

```bash
# Create a debug pod to view results
oc run results-viewer --rm -it --restart=Never \
  --image=registry.access.redhat.com/ubi9/ubi-minimal \
  --overrides='{"spec":{"containers":[{"name":"viewer","image":"registry.access.redhat.com/ubi9/ubi-minimal","command":["sh","-c","find /results -name *.json | head -20"],"volumeMounts":[{"name":"results","mountPath":"/results"}]}],"volumes":[{"name":"results","persistentVolumeClaim":{"claimName":"guidellm-results"}}]}}' \
  -n private-ai
```

## vLLM-Playground (Interactive UI)

> **⚠️ Community Tool Disclaimer:** [vLLM-Playground](https://github.com/micytao/vllm-playground) is a community-driven tool and is NOT an officially supported component of Red Hat OpenShift AI 3.0.

### Purpose

While GuideLLM gives us hard data, vLLM-Playground provides the **"Vibe Check"**:
- Side-by-side chat windows comparing INT4 vs BF16
- See latency differences in real-time
- Perfect for stakeholder presentations

### Access

```bash
PLAYGROUND_URL=$(oc get route vllm-playground -n private-ai -o jsonpath='{.spec.host}')
echo "https://${PLAYGROUND_URL}"
```

### Demo Scenario

1. Open two browser tabs pointing to the playground
2. Configure one tab to use `mistral-3-int4` endpoint
3. Configure the other to use `mistral-3-bf16` endpoint
4. Ask the same question in both
5. Observe the latency difference visually

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
│   ├── grafana/
│   │   ├── kustomization.yaml
│   │   ├── rbac.yaml              # ServiceAccount + ClusterRoleBinding
│   │   ├── datasource.yaml        # Prometheus UWM datasource
│   │   ├── dashboard-provisioner.yaml
│   │   ├── deployment.yaml        # Grafana with token injection
│   │   ├── service.yaml
│   │   └── route.yaml
│   ├── dashboards/
│   │   ├── kustomization.yaml
│   │   └── vllm-overview.yaml     # vLLM metrics dashboard
│   ├── guidellm/
│   │   ├── kustomization.yaml
│   │   ├── pvc.yaml               # Results storage
│   │   ├── configmap.yaml         # Poisson benchmark scripts
│   │   ├── cronjob.yaml           # Daily scheduled benchmarks
│   │   └── job-template.yaml      # On-demand template
│   └── vllm-playground/           # ⚠️ Community tool
│       ├── kustomization.yaml
│       └── deployment.yaml        # Interactive UI
└── kustomization.yaml
```

## Validation

```bash
# 1. Verify Grafana is running
oc get pods -n private-ai -l app=grafana

# 2. Verify Route is accessible
curl -k -s -o /dev/null -w "%{http_code}" https://$(oc get route grafana -n private-ai -o jsonpath='{.spec.host}')/api/health
# Expected: 200

# 3. Verify GuideLLM CronJob exists
oc get cronjob guidellm-daily -n private-ai

# 4. Verify GuideLLM PVC is bound
oc get pvc guidellm-results -n private-ai

# 5. Verify vLLM-Playground is running
oc get pods -n private-ai -l app=vllm-playground

# 6. Verify all Routes
oc get routes -n private-ai | grep -E "grafana|vllm-playground"
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

### vLLM-Playground Not Connecting

**Symptom:** Chat shows connection errors

```bash
# Check pod logs
oc logs -n private-ai deployment/vllm-playground

# Verify internal connectivity
oc exec deployment/vllm-playground -n private-ai -- curl -s http://mistral-3-int4-predictor.private-ai.svc.cluster.local:80/v1/models
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
- [RHOAI 3.0 Monitoring Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/managing_and_monitoring_models/index)
- [OpenShift User Workload Monitoring (4.20)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/monitoring/enabling-monitoring-for-user-defined-projects)
- [GuideLLM - Evaluate LLM Deployments (Red Hat Developers)](https://developers.redhat.com/articles/2025/06/20/guidellm-evaluate-llm-deployments-real-world-inference)
- [How to Deploy and Benchmark vLLM with GuideLLM (Red Hat Developers)](https://developers.redhat.com/articles/2025/12/24/how-deploy-and-benchmark-vllm-guidellm-kubernetes)

### Community / Open Source
- [vLLM Production Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html)
- [GuideLLM GitHub Repository](https://github.com/neuralmagic/guidellm)
- [vLLM-Playground GitHub](https://github.com/micytao/vllm-playground) ⚠️ Community Tool
- [Grafana Dashboard Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [AI on OpenShift - KServe UWM Dashboard](https://ai-on-openshift.io/odh-rhoai/kserve-uwm-dashboard-metrics/)
- [RHOAI GenAIOps Patterns](https://github.com/rhoai-genaiops)
