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
| **OpenShift Pipelines Operator** | Red Hat Tekton for CI/CD pipelines (v1.20.2) | Red Hat Official |
| **Grafana Operator** | Kubernetes-native Grafana management from OperatorHub | Community |
| **Grafana Instance** | Dashboard with anonymous access in `private-ai` | Community (OSS) |
| **GrafanaDatasource** | Prometheus datasource pointing to UWM Thanos Querier | - |
| **6 GrafanaDashboard CRs** | Official vLLM + RHOAI + custom dashboards | - |
| **ServiceAccount** | `grafana-sa` with `cluster-monitoring-view` permissions | - |
| **GuideLLM CronJob** | Daily parallel benchmarks at 2:00 AM UTC (dispatcher pattern) | Community (OSS) |
| **GuideLLM Pipeline** | Tekton Pipeline for self-service benchmarks | Community (OSS) |
| **5 PipelineRun Templates** | Pre-configured runs for each model | - |
| **GuideLLM Workbench** | Streamlit UI with pre-configured model endpoints | Community (OSS) |

> **⚠️ Community Tooling Disclaimer:** Grafana Operator and GuideLLM are community-driven tools and are NOT officially supported components of Red Hat OpenShift AI 3.0. See [Red Hat's Third Party Software Support Policy](https://access.redhat.com/third-party-software-support).

> **Note:** For interactive benchmark UI, see [Step 07B: vLLM-Playground](../step-07b-guidellm-vllm-playground/README.md) (future enhancement).

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

## The "ROI of Quantization" Demo

### Step 1: Access Grafana Dashboard

```bash
# Get Grafana URL
GRAFANA_URL=$(oc get route grafana -n private-ai -o jsonpath='{.spec.host}')
echo "https://${GRAFANA_URL}"
```

**No login required** (anonymous access enabled). Default dashboard: **vLLM Model Performance**

### Step 2: Run the Efficiency Comparison

```bash
# Trigger the ROI comparison benchmark
oc create job --from=cronjob/guidellm-daily roi-comparison-$(date +%H%M) -n private-ai

# Watch progress
oc logs -f job/roi-comparison-$(date +%H%M) -n private-ai
```

Alternatively, use the Tekton Pipeline for a structured efficiency comparison:

```bash
# Run INT4 benchmark via Pipeline
oc create -f gitops/step-07-model-performance-metrics/base/guidellm-pipeline/pipelineruns/mistral-3-int4.yaml

# Run BF16 benchmark via Pipeline (in parallel)
oc create -f gitops/step-07-model-performance-metrics/base/guidellm-pipeline/pipelineruns/mistral-3-bf16.yaml

# Watch pipeline progress
tkn pipelinerun list -n private-ai
tkn pipelinerun logs -f -n private-ai
```

### Step 4: Interpret Results

After running the efficiency comparison, analyze:

1. **Break Point (INT4)**: At what req/s does TTFT exceed 1.0s?
2. **Break Point (BF16)**: At what req/s does TTFT exceed 1.0s?
3. **Efficiency Delta**: `BF16_breakpoint / INT4_breakpoint`
4. **Cost Analysis**: If INT4 breaks at 2 req/s and BF16 at 6 req/s, can 4x INT4 instances (4 × 2 = 8 req/s) outperform 1x BF16 at lower cost?

## Self-Service Benchmarking with OpenShift Pipelines

This step deploys [Red Hat OpenShift Pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20) (Tekton) for self-service benchmark execution. Each model has a pre-configured PipelineRun template.

### Available Pipeline Runs

| Model | GPU Config | PipelineRun Template |
|-------|------------|---------------------|
| `mistral-3-bf16` | 4 x L4 | `pipelineruns/mistral-3-bf16.yaml` |
| `mistral-3-int4` | 1 x L4 | `pipelineruns/mistral-3-int4.yaml` |
| `granite-8b-agent` | 1 x L4 | `pipelineruns/granite-8b-agent.yaml` |
| `devstral-2` | 4 x L4 | `pipelineruns/devstral-2.yaml` |
| `gpt-oss-20b` | 4 x L4 | `pipelineruns/gpt-oss-20b.yaml` |

Reference: [rh-aiservices-bu/guidellm-pipeline](https://github.com/rh-aiservices-bu/guidellm-pipeline)

### Run Benchmark via Pipeline

**Option 1: Using Templates (Recommended)**

```bash
# Benchmark Mistral-3 INT4 (1-GPU)
oc create -f gitops/step-07-model-performance-metrics/base/guidellm-pipeline/pipelineruns/mistral-3-int4.yaml

# Benchmark Mistral-3 BF16 (4-GPU)
oc create -f gitops/step-07-model-performance-metrics/base/guidellm-pipeline/pipelineruns/mistral-3-bf16.yaml

# Watch pipeline progress
tkn pipelinerun logs -f -n private-ai
```

**Option 2: Using Tekton CLI**

```bash
# Install tkn CLI (if not installed)
# brew install tektoncd-cli  # macOS

# Run benchmark with custom parameters
tkn pipeline start guidellm-benchmark -n private-ai \
  --param model-name=mistral-3-int4 \
  --param profile=sweep \
  --param max-seconds=60 \
  --param max-requests=50 \
  --workspace name=results,claimName=guidellm-pipeline-results
```

**Option 3: OpenShift Console**

1. Navigate to **Pipelines → Pipelines** in `private-ai` namespace
2. Click on **guidellm-benchmark** pipeline
3. Click **Start** and fill in parameters
4. Monitor execution in **PipelineRuns** tab

### View Pipeline Results

```bash
# List completed runs
tkn pipelinerun list -n private-ai

# View specific run logs
tkn pipelinerun logs <run-name> -n private-ai

# Access results PVC
oc run results-viewer --rm -it --restart=Never \
  --image=registry.access.redhat.com/ubi9/ubi-minimal \
  --overrides='{"spec":{"containers":[{"name":"viewer","image":"registry.access.redhat.com/ubi9/ubi-minimal","command":["sh","-c","ls -la /results/*"],"volumeMounts":[{"name":"results","mountPath":"/results"}]}],"volumes":[{"name":"results","persistentVolumeClaim":{"claimName":"guidellm-pipeline-results"}}]}}' \
  -n private-ai
```

## GuideLLM Workbench (Interactive UI)

The [GuideLLM Workbench](https://github.com/rh-aiservices-bu/guidellm-pipeline) provides a Streamlit-based web interface for running benchmarks interactively.

### Features

- **Pre-populated Configuration**: UI fields auto-filled with environment-specific endpoints
- **Interactive Configuration**: Easy-to-use forms for endpoint, authentication, and benchmark parameters
- **Real-time Monitoring**: Live metrics parsing during benchmark execution
- **Quick Stats**: Sidebar with key performance indicators (requests/sec, tokens/sec, latency, TTFT)
- **Results History**: Session-based storage with detailed result viewing
- **Download Results**: Export benchmark results as YAML files

### Access the Workbench

```bash
# Get the Workbench URL
oc get route guidellm-workbench -n private-ai -o jsonpath='https://{.spec.host}{"\n"}'
```

### Pre-configured Endpoints

The workbench is automatically configured via the `guidellm-workbench-config` ConfigMap. The UI opens with the default model (`mistral-3-int4`) pre-selected.

| Default Setting | Value |
|----------------|-------|
| **Target Endpoint** | `http://mistral-3-int4-predictor.private-ai.svc.cluster.local:8080/v1` |
| **Model Name** | `mistral-3-int4` |
| **Processor** | `mistralai/Mistral-Small-24B-Instruct-2501` |
| **Max Duration** | 60 seconds |
| **Max Requests** | 100 |
| **Max Concurrency** | 10 |

All 5 model presets are available in the ConfigMap's `MODEL_PRESETS` JSON for future dropdown implementation.

### Environment Configuration (GitOps)

The workbench configuration is defined in:

```
gitops/step-07-model-performance-metrics/base/guidellm-workbench/configmap.yaml
```

The ConfigMap includes:
- **Default values** for UI fields (`DEFAULT_TARGET`, `DEFAULT_MODEL_NAME`, etc.)
- **Model presets** JSON array for all 5 models
- **Startup script** that patches `app.py` to read environment variables

> **Design Decision:** We use a startup script to patch the Streamlit app at runtime because the upstream image has hardcoded defaults. This allows GitOps configuration without modifying the container image.

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

### Trigger Manual Benchmark (Parallel Execution)

The CronJob uses a dispatcher pattern to spawn parallel Jobs for each model:

```bash
# Trigger parallel benchmarks for all available models
oc create job --from=cronjob/guidellm-daily benchmark-$(date +%H%M%S) -n private-ai

# Watch the dispatcher create Jobs
oc logs -f job/benchmark-$(date +%H%M%S) -n private-ai

# Monitor parallel benchmark Jobs (spawned by dispatcher)
oc get jobs -n private-ai -l app=guidellm

# Watch both models running in parallel
oc get pods -n private-ai -l app=guidellm -w
```

**Architecture:**
- The CronJob is a "dispatcher" that creates individual Jobs for each model
- Each model benchmark runs in its own container for true parallelism
- Jobs are labeled with `benchmark-run=<timestamp>` for tracking
- Jobs auto-delete after 24 hours (`ttlSecondsAfterFinished: 86400`)

### Run Single Model Benchmark

**Option 1: Using Tekton Pipeline (Recommended)**

```bash
# Use the pre-configured PipelineRun template
oc create -f gitops/step-07-model-performance-metrics/base/guidellm-pipeline/pipelineruns/mistral-3-int4.yaml

# Monitor the pipeline
tkn pipelinerun logs -f -n private-ai
```

**Option 2: Using GuideLLM Workbench (Interactive)**

```bash
# Open the workbench UI
oc get route guidellm-workbench -n private-ai -o jsonpath='https://{.spec.host}{"\n"}'
# The UI opens with mistral-3-int4 pre-configured - just click "Run Benchmark"
```

**Option 3: Ad-hoc Job (Advanced)**

```bash
# Create an ad-hoc benchmark job
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: benchmark-int4-$(date +%H%M%S)
  namespace: private-ai
  labels:
    app: guidellm
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      securityContext:
        fsGroup: 0
      containers:
        - name: benchmark
          image: ghcr.io/vllm-project/guidellm:stable
          env:
            - name: HOME
              value: /tmp
            - name: HF_HOME
              value: /tmp/.cache/huggingface
          command:
            - /bin/bash
            - -c
            - |
              cat > /tmp/prompts.json << 'PROMPTS'
              [{"prompt": "What is the capital of France?"},{"prompt": "Explain quantum computing."}]
              PROMPTS
              
              guidellm benchmark run \
                --target "http://mistral-3-int4-predictor.private-ai.svc.cluster.local:8080/v1" \
                --data /tmp/prompts.json \
                --profile sweep \
                --max-seconds 60 \
                --max-requests 50 \
                --output-dir /results \
                --outputs "mistral-3-int4-adhoc.json" \
                --disable-console-interactive
          volumeMounts:
            - name: results
              mountPath: /results
            - name: cache
              mountPath: /tmp/.cache
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 2Gi
      volumes:
        - name: results
          persistentVolumeClaim:
            claimName: guidellm-results
        - name: cache
          emptyDir: {}
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
│   ├── pipelines-operator/                # Red Hat OpenShift Pipelines (Tekton)
│   │   ├── kustomization.yaml
│   │   └── subscription.yaml              # latest channel, v1.20.2
│   ├── grafana-operator/
│   │   ├── kustomization.yaml
│   │   ├── operator/                      # Grafana Operator from OperatorHub
│   │   │   ├── kustomization.yaml
│   │   │   ├── namespace.yaml             # grafana-operator namespace
│   │   │   ├── operatorgroup.yaml         # AllNamespaces mode
│   │   │   └── subscription.yaml          # community-operators, v5 channel
│   │   ├── instance/                      # Grafana instance in private-ai
│   │   │   ├── kustomization.yaml
│   │   │   ├── grafana.yaml               # Grafana CR (anonymous access)
│   │   │   └── datasource.yaml            # GrafanaDatasource + RBAC
│   │   └── dashboards/                    # GrafanaDashboard CRs (6 total)
│   │       ├── kustomization.yaml
│   │       ├── vllm-performance-statistics.yaml  # Official (from GitHub URL)
│   │       ├── vllm-query-statistics.yaml        # Official (from GitHub URL)
│   │       ├── rhoai-vllm-model-metrics.yaml     # Custom per-model metrics
│   │       ├── dcgm-gpu-metrics.yaml             # Custom NVIDIA DCGM
│   │       └── mistral-roi-comparison.yaml       # Custom (BF16 vs INT4)
│   ├── guidellm/                          # Automated benchmarking (CronJob)
│   │   ├── kustomization.yaml
│   │   ├── rbac.yaml                      # ServiceAccount + Role for dispatcher
│   │   ├── pvc.yaml                       # Results storage
│   │   ├── cronjob.yaml                   # Daily dispatcher (creates parallel Jobs)
│   │   └── job-template.yaml              # On-demand template (reference only)
│   ├── guidellm-pipeline/                 # Self-service pipelines (Tekton)
│   │   ├── kustomization.yaml
│   │   ├── pvc.yaml                       # Pipeline results storage
│   │   ├── task.yaml                      # GuideLLM Tekton Task
│   │   ├── pipeline.yaml                  # GuideLLM Benchmark Pipeline
│   │   └── pipelineruns/                  # Pre-configured templates
│   │       ├── kustomization.yaml
│   │       ├── mistral-3-bf16.yaml        # 4-GPU full precision
│   │       ├── mistral-3-int4.yaml        # 1-GPU quantized
│   │       ├── granite-8b-agent.yaml      # 1-GPU agent model
│   │       ├── devstral-2.yaml            # 4-GPU coding model
│   │       └── gpt-oss-20b.yaml           # 4-GPU foundation model
│   └── guidellm-workbench/                # Interactive Streamlit UI
│       ├── kustomization.yaml
│       ├── rbac.yaml                      # ServiceAccount with anyuid SCC
│       ├── configmap.yaml                 # Pre-configured endpoints + startup script
│       ├── deployment.yaml                # Workbench deployment (patched at startup)
│       ├── service.yaml
│       └── route.yaml
└── kustomization.yaml
```

### Dashboards (GrafanaDashboard CRs)

| Dashboard | Source | Features |
|-----------|--------|----------|
| **vLLM Performance Statistics** | Official vLLM GitHub (URL) | E2E Latency, TTFT, ITL, TPS (auto-updated) |
| **vLLM Query Statistics** | Official vLLM GitHub (URL) | Request Rate, Success/Error, Token Distribution |
| **RHOAI vLLM Model Metrics** | Custom (embedded) | Per-model performance, KV Cache, Queue depth |
| **NVIDIA DCGM GPU Metrics** | Custom (embedded) | Temperature, Power, Utilization, Memory |
| **Mistral ROI Comparison** | Custom (embedded) | BF16 vs INT4 head-to-head, Efficiency curves |

## Validation

```bash
# 1. Verify Grafana Operator is installed
oc get csv -n grafana-operator | grep grafana
# Expected: grafana-operator.v5.21.x ... Succeeded

# 2. Verify OpenShift Pipelines Operator is installed
oc get csv -n openshift-operators | grep pipelines
# Expected: openshift-pipelines-operator-rh.v1.20.x ... Succeeded

# 3. Verify Grafana instance is ready
oc get grafana -n private-ai
# Expected: grafana   12.x.x   complete   success   <age>

# 4. Verify all 5 GrafanaDashboards are synced
oc get grafanadashboard -n private-ai
# Expected: 5 dashboards (vllm-performance-statistics, vllm-query-statistics, 
#           rhoai-vllm-model-metrics, dcgm-gpu-metrics, mistral-roi-comparison)

# 5. Verify GrafanaDatasource is ready
oc get grafanadatasource -n private-ai
# Expected: prometheus-uwm

# 6. Verify Grafana Route is accessible
curl -k -s -o /dev/null -w "%{http_code}" https://$(oc get route grafana-route -n private-ai -o jsonpath='{.spec.host}')/api/health
# Expected: 200

# 7. Verify GuideLLM CronJob exists
oc get cronjob guidellm-daily -n private-ai
# Expected: guidellm-daily   0 2 * * *   ...

# 8. Verify GuideLLM PVCs are bound
oc get pvc -n private-ai | grep guidellm
# Expected: guidellm-results and guidellm-pipeline-results both Bound

# 9. Verify Tekton Pipeline and Task exist
oc get pipeline,task -n private-ai
# Expected: guidellm-benchmark (Pipeline and Task)

# 10. Verify GuideLLM Workbench is running
oc get deployment guidellm-workbench -n private-ai
# Expected: 1/1 READY

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
- [RHOAI 3.0 Monitoring Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/managing_and_monitoring_models/index)
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
- [GuideLLM GitHub Repository](https://github.com/neuralmagic/guidellm)
- [GuideLLM Pipeline (rh-aiservices-bu)](https://github.com/rh-aiservices-bu/guidellm-pipeline)
- [AI on OpenShift - KServe UWM Dashboard](https://ai-on-openshift.io/odh-rhoai/kserve-uwm-dashboard-metrics/)
- [RHOAI GenAIOps Patterns](https://github.com/rhoai-genaiops)

### Related Steps
- [Step 07B: vLLM-Playground](../step-07b-guidellm-vllm-playground/README.md) - Interactive benchmark UI (future)
