# Step 06: Model Performance Metrics

**Understand how your models perform under load — latency, throughput, GPU utilization, and capacity limits.**

## The Business Story

Models are deployed. But how do they perform? Step-06 establishes observability: Grafana dashboards visualize vLLM metrics (latency, throughput, KV cache), DCGM exposes GPU hardware utilization, and GuideLLM stress tests reveal each model's capacity limits under graduated concurrency. This gives platform teams the data to right-size deployments and set SLO expectations.

## What It Does

```text
GuideLLM Benchmark Jobs
    │                          ┌─────────────────────────────────┐
    ├───► granite-8b-agent     │  Grafana Dashboards             │
    │     (1 GPU)              │  1. vLLM Latency/Throughput     │
    │                          │  2. NVIDIA DCGM GPU Metrics     │
    └───► mistral-3-bf16       │                                 │
          (4 GPU)              └────────────┬────────────────────┘
                                            │
                               OpenShift User Workload Monitoring
                               (Prometheus + Thanos)
```

| Component | Description |
|-----------|-------------|
| **Grafana Operator** | Kubernetes-native Grafana from OperatorHub (community) |
| **2 GrafanaDashboards** | vLLM metrics (latency/throughput/cache), GPU hardware (DCGM) |
| **GuideLLM CronJob** | Daily benchmarks at 2:00 AM UTC |
| **Job Templates** | On-demand: `granite-8b-agent` (1,3,5,8,10 req/s) and `mistral-3-bf16` (1,3,5,8,10,15 req/s) |
| **Model Benchmarking Workbench** | Jupyter notebook for interactive analysis |
| **GuideLLM KFP Pipeline** | Dashboard-triggerable benchmark (requires step-07 DSPA) |

> **Community Tooling:** Grafana Operator and GuideLLM are community-driven tools, not officially supported RHOAI 3.3 components.

Manifests: [`gitops/step-06-model-metrics/base/`](../../gitops/step-06-model-metrics/base/)

## Demo Walkthrough

### Scene 1: Run a Benchmark

```bash
GRAFANA_URL=$(oc get route grafana-route -n private-ai -o jsonpath='{.spec.host}')
echo "https://${GRAFANA_URL}"

# Benchmark granite-8b-agent (1 GPU, ~5 min)
oc create -f gitops/step-06-model-metrics/base/guidellm/job-templates/granite-8b-agent.yaml

# Or benchmark mistral-3-bf16 (4 GPU, ~8 min)
oc create -f gitops/step-06-model-metrics/base/guidellm/job-templates/mistral-3-bf16.yaml
```

*"GuideLLM sends graduated concurrency — 1, 3, 5, 8, 10 requests per second — while vLLM's built-in Prometheus metrics capture latency and throughput at each level. KServe auto-creates the ServiceMonitors."*

### Scene 2: vLLM Performance Dashboard

Open Grafana → select `namespace=private-ai`, `model_name=granite-8b-agent`.

**Key panels:**
- **E2E Request Latency** — P50/P95/P99 across concurrency levels
- **Token Throughput** — output tokens/second
- **KV Cache Utilization** — memory pressure indicator
- **Time To First Token** — responsiveness metric
- **Scheduler State** — running vs waiting requests

*"At 10 concurrent users, Granite's P95 inter-token latency stays at ~41ms and throughput holds at 130-170 tok/s. The KV cache is healthy — no memory pressure. Switch the model dropdown to compare Mistral BF16 on the same panels."*

### Scene 3: GPU Hardware Dashboard (DCGM)

Switch to the DCGM dashboard.

*"GPU utilization hits 95-100% during the benchmark — that's the capacity ceiling. When capacity is exhausted, new pods remain Pending until a GPU node has available resources."*

### Scene 4: Understanding Capacity Limits

After both benchmarks complete, compare the results (tuned configuration):

| Metric | granite-8b-agent (1 GPU) | mistral-3-bf16 (4 GPU) |
|--------|--------------------------|------------------------|
| **KV cache capacity** | 155K tokens (9.5x at 16K) | 426K tokens (26.0x at 16K) |
| **TTFT p95** | <90ms | <128ms |
| **ITL p95** | ~40ms (hardware-bound) | ~53ms (hardware-bound) |
| **Output throughput** | ~130-170 tok/s | ~120-135 tok/s |
| **Sweet spot** | 5-8 concurrent users | 10-15 concurrent users |

*"After tuning, Granite's KV cache doubled from 74K to 155K tokens — that's 9 concurrent requests at full 16K context, up from 4.5 before tuning. Mistral gained 16% more capacity. Both models' inter-token latency is hardware-bound on L4 GPUs at 40ms and 53ms respectively — that's the memory bandwidth floor. Moving to A100 or H100 GPUs would reduce ITL significantly."*

> **Known Limitation (NVIDIA L4):** ITL is limited by memory bandwidth (~300 GB/s). An 8B FP8 model reads ~8 GB of weights per decode step, giving a theoretical minimum of ~27ms. Observed 40ms includes compute, KV cache attention, and CUDA overhead. This is near the hardware floor — not a tuning issue. See [Practical strategies for vLLM performance tuning](https://developers.redhat.com/articles/2026/03/03/practical-strategies-vllm-performance-tuning).

### Scene 5: Dashboard Pipeline (no CLI needed)

**Do:** Navigate to **Develop & train -> Pipelines** in the RHOAI Dashboard. Select `bench-granite-8b` (or `bench-mistral-bf16`). Click **Create run**.

**Expect:** A form with pre-filled parameters: `model_name`, `rates`, `max_seconds`, `max_requests`, `run_id` — each pipeline has model-specific defaults.

**Do:** Keep defaults, click **Start**. Watch the run in the **Runs** tab.

**Expect:** Granite completes in ~5 minutes, Mistral in ~8 minutes. Results uploaded to S3 (`benchmark-results/<run_id>/`).

*"This is the same GuideLLM benchmark we ran from the CLI, but now it's a Kubeflow Pipeline that anyone can trigger from the dashboard. No `oc` access needed — the platform team sets it up once, and developers run it whenever they want to validate model performance after a config change."*

> **Prerequisite:** The KFP pipeline requires `dspa-rag` from Step 07. If Step 07 hasn't been deployed yet, Scene 5 is not available — use the CLI approach from Scene 1.

## What to Verify After Deployment

```bash
# Grafana health
oc get grafana -n private-ai
# Expected: 1 instance

oc get grafanadashboard -n private-ai
# Expected: 2 dashboards (vllm-latency-throughput-cache, dcgm-gpu-metrics)

GRAFANA_HOST=$(oc get route grafana-route -n private-ai -o jsonpath='{.spec.host}')
curl -sk "https://$GRAFANA_HOST/api/health" | python3 -c "import sys,json; print(json.load(sys.stdin))"
# Expected: {"commit":"...","database":"ok","version":"..."}

# GuideLLM CronJob
oc get cronjob guidellm-daily -n private-ai
# Expected: SCHEDULE "0 2 * * *", not suspended

# Tuned vLLM config (KV cache from pod startup logs)
oc logs deploy/granite-8b-agent-predictor -n private-ai -c kserve-container \
  | grep 'KV cache size'
# Expected: 155,184 tokens (kv-cache-dtype=fp8, gpu-memory-utilization=0.92)

oc logs deploy/mistral-3-bf16-predictor -n private-ai -c kserve-container \
  | grep 'KV cache size'
# Expected: 426,160 tokens (kv-cache-dtype=fp8, gpu-memory-utilization=0.90)
```

Or run the validation script:

```bash
./steps/step-06-model-metrics/validate.sh
# Expected: 5 passed, 0 failed
```

## Design Decisions

> **CronJob + Job templates instead of Tekton:** Tekton adds unnecessary complexity for simple benchmark jobs. Jobs with `nodeSelector` and GPU `tolerations` are simpler and more reliable.

> **Prometheus/Grafana metrics over file-based results:** vLLM automatically exposes production metrics via ServiceMonitors. Grafana dashboards visualize real-time performance without custom result parsing.

> **Two focused dashboards:** vLLM Latency/Throughput/Cache (operational) and DCGM GPU Metrics (hardware). The vLLM dashboard (from [llm-d-deployer](https://github.com/llm-d/llm-d-deployer)) covers E2E latency, TTFT, TPOT, scheduler, and KV cache in one view.

> **CronJob uses 1,3,5,8,10 for both models:** The daily CronJob benchmarks all active models with 5 rate levels. Mistral's 15 RPS level is available only through the on-demand job template. This keeps daily runs shorter while still providing meaningful saturation data.

> **Model Benchmarking Workbench:** A Jupyter notebook (`Model-Benchmarking.ipynb`) is deployed as an RHOAI workbench for interactive result analysis. The notebook parses GuideLLM JSON output from the CronJob results PVC.

## Troubleshooting

### Grafana dashboard shows "No data"

**Symptom:** Grafana panels show "No data" even though models are running.

**Root Cause:** ServiceMonitors may not be targeting the correct namespace, or Prometheus User Workload Monitoring is not enabled.

**Solution:**
```bash
# Verify User Workload Monitoring
oc get pods -n openshift-user-workload-monitoring
# Expected: prometheus-user-workload pods Running

# Verify vLLM metrics are scraped
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -- \
  curl -s http://localhost:9090/api/v1/targets | python3 -c \
  "import json,sys; [print(t['labels']['job']) for t in json.load(sys.stdin)['data']['activeTargets'] if 'vllm' in t['labels'].get('job','')]"
```

### GuideLLM job fails with "connection refused"

**Symptom:** GuideLLM benchmark job exits with connection error to the model endpoint.

**Root Cause:** InferenceService is not Ready or the internal service DNS is wrong.

**Solution:**
```bash
oc get inferenceservice -n private-ai
# Both models must show READY=True
```

### Grafana Operator OperatorGroup health empty

**Symptom:** ArgoCD shows Grafana OperatorGroup as "Unknown" health.

**Root Cause:** Multiple OperatorGroups in the namespace (e.g., from another operator). OLM only allows one OperatorGroup per namespace.

**Solution:**
```bash
oc get operatorgroup -n private-ai
# Should have exactly 1 OperatorGroup
```

## References

- [RHOAI 3.3 — Managing and Monitoring Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_and_monitoring_models/index)
- [OpenShift User Workload Monitoring (4.20)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/monitoring/enabling-monitoring-for-user-defined-projects)
- [GuideLLM — Evaluate LLM Deployments (Red Hat Developers)](https://developers.redhat.com/articles/2025/06/20/guidellm-evaluate-llm-deployments-real-world-inference)
- [vLLM Production Metrics](https://docs.vllm.ai/en/latest/usage/metrics/)
- [Grafana Operator](https://github.com/grafana/grafana-operator)

## Operations

```bash
./steps/step-06-model-metrics/deploy.sh         # Deploy Grafana + GuideLLM via ArgoCD
./steps/step-06-model-metrics/run-benchmark.sh  # CLI benchmark (Job template or CronJob)
./steps/step-06-model-metrics/run-pipeline.sh   # Dashboard benchmark (KFP pipeline via DSPA)
./steps/step-06-model-metrics/validate.sh       # Verify Grafana health, dashboards, CronJob
```

## Next Steps

- [Step 07: RAG Pipeline](../step-07-rag/README.md) — Document ingestion and vector search with LlamaStack
