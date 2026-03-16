# Step 06: Model Performance Metrics

**Understand how your models perform under load — latency, throughput, GPU utilization, and capacity limits.**

## The Business Story

Models are deployed. But how do they perform? Step-06 establishes observability: Grafana dashboards visualize vLLM metrics (latency, throughput, KV cache), DCGM exposes GPU hardware utilization, and GuideLLM stress tests reveal each model's capacity limits under graduated concurrency. This gives platform teams the data to right-size deployments and set SLO expectations.

## What It Does

```
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

> **Community Tooling:** Grafana Operator and GuideLLM are community-driven tools, not officially supported RHOAI 3.3 components.

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

*"At 10 concurrent users, Granite's P95 latency stays under 100ms per token and throughput holds at 80-120 tok/s. The KV cache is healthy — no memory pressure. Switch the model dropdown to compare Mistral BF16 on the same panels."*

### Scene 3: GPU Hardware Dashboard (DCGM)

Switch to the DCGM dashboard.

*"GPU utilization hits 95-100% during the benchmark — that's the capacity ceiling. When it stays here, Kueue's quota management from Step 03 ensures new models queue instead of crashing."*

### Scene 4: Understanding Capacity Limits

After both benchmarks complete, compare the results:

| Metric | granite-8b-agent (1 GPU) | mistral-3-bf16 (4 GPU) |
|--------|--------------------------|------------------------|
| **Sweet spot** | 3-5 concurrent users | 10-15 concurrent users |
| **Breaking point** | 8-10 users (TTFT > 2s) | 20 users (TTFT > 2s) |
| **Max throughput** | ~300 tok/s | ~700 tok/s |
| **TTFT at sweet spot** | 874ms (p95) | 594ms (p95) |

*"Granite handles 5 concurrent users comfortably on a single L4 GPU. Mistral BF16 scales to 15 users across four GPUs. Beyond these sweet spots, latency degrades — that's when you either scale up or optimize with quantization."*

## Design Decisions

> **CronJob + Job templates instead of Tekton:** Tekton's affinity assistants create Kueue admission deadlocks in GPU-managed namespaces. Simple Jobs with `kueue.x-k8s.io/queue-name: default` work reliably.

> **Prometheus/Grafana metrics over file-based results:** vLLM automatically exposes production metrics via ServiceMonitors. Grafana dashboards visualize real-time performance without custom result parsing.

> **Two focused dashboards:** vLLM Latency/Throughput/Cache (operational) and DCGM GPU Metrics (hardware). The vLLM dashboard (from [llm-d-deployer](https://github.com/llm-d/llm-d-deployer)) covers E2E latency, TTFT, TPOT, scheduler, and KV cache in one view.

## References

- [RHOAI 3.3 — Managing and Monitoring Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_and_monitoring_models/index)
- [OpenShift User Workload Monitoring (4.20)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/monitoring/enabling-monitoring-for-user-defined-projects)
- [GuideLLM — Evaluate LLM Deployments (Red Hat Developers)](https://developers.redhat.com/articles/2025/06/20/guidellm-evaluate-llm-deployments-real-world-inference)
- [vLLM Production Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html)
- [Grafana Operator](https://github.com/grafana/grafana-operator)

## Operations

```bash
./steps/step-06-model-metrics/deploy.sh        # Deploy Grafana + GuideLLM via ArgoCD
./steps/step-06-model-metrics/run-benchmark.sh  # Trigger benchmark (all models or specific)
./steps/step-06-model-metrics/validate.sh      # Verify Grafana health, dashboards, CronJob
```

## Next Steps

- [Step 07: RAG Pipeline](../step-07-rag/README.md) — Document ingestion and vector search with LlamaStack
