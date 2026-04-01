# Step 06: Model Performance Metrics
**"Measure What Matters"** — Understand how your models perform under load with Grafana dashboards and GuideLLM benchmarks.

## Overview

Models are deployed. But how do they perform? *"Moving from proof-of-concept to production introduces new challenges around cost, latency, and scale. Optimization ensures your models perform efficiently under real-world conditions, where every millisecond of latency and every dollar of compute cost matters."* Before scaling to production, platform teams need data: latency distributions, throughput ceilings, GPU utilization, and KV cache pressure under real concurrency. Without observability, capacity planning is guesswork — and guessing at GPU scale costs money.

**Red Hat OpenShift AI 3.3** provides model observability through **OpenShift User Workload Monitoring**, which automatically scrapes vLLM's Prometheus metrics via KServe-managed ServiceMonitors. Grafana dashboards visualize latency, throughput, and KV cache utilization in real time, while **GuideLLM** stress tests reveal each model's capacity limits under graduated concurrency. **DCGM** (Data Center GPU Manager) exposes GPU hardware utilization for capacity planning.

This step demonstrates the **Operationalized AI** use case of the Red Hat AI platform: model observability and governance — tracking metrics including performance and capacity to right-size deployments and set SLO expectations.

> **Community Tooling:** Grafana Operator and GuideLLM are community-driven tools, not officially supported RHOAI 3.3 components.

### What Gets Deployed

```text
Model Performance Metrics
├── Grafana Operator        → Kubernetes-native Grafana (community)
├── 2 GrafanaDashboards     → vLLM Latency/Throughput/Cache + DCGM GPU Metrics
├── GuideLLM CronJob        → Daily benchmarks at 2:00 AM UTC
├── Job Templates           → On-demand per-model benchmarks (graduated concurrency)
├── Benchmarking Workbench  → Jupyter notebook for interactive analysis
└── GuideLLM KFP Pipeline   → Dashboard-triggerable benchmark (3-step: run → upload → summary)
```

| Component | Description | Namespace |
|-----------|-------------|-----------|
| **Grafana Operator** | Kubernetes-native Grafana from OperatorHub (community) | `grafana-operator` |
| **2 GrafanaDashboards** | vLLM metrics (latency/throughput/cache), GPU hardware (DCGM) | `private-ai` |
| **GuideLLM CronJob** | Daily benchmarks at 2:00 AM UTC | `private-ai` |
| **Job Templates** | On-demand: per-model benchmarks at 1,3,5,8,10 req/s | `private-ai` |
| **Model Benchmarking Workbench** | Jupyter notebook for interactive analysis | `private-ai` |
| **GuideLLM KFP Pipeline** | Dashboard-triggerable benchmark (requires step-07 DSPA) | `private-ai` |

Manifests: [`gitops/step-06-model-metrics/base/`](../../gitops/step-06-model-metrics/base/)

### Design Decisions

> **CronJob + Job templates instead of Tekton:** Tekton adds unnecessary complexity for simple benchmark jobs. Jobs with `nodeSelector` and GPU `tolerations` are simpler and more reliable.

> **Prometheus/Grafana metrics over file-based results:** vLLM automatically exposes production metrics via ServiceMonitors. Grafana dashboards visualize real-time performance without custom result parsing.

> **Two focused dashboards:** vLLM Latency/Throughput/Cache (operational) and DCGM GPU Metrics (hardware). The vLLM dashboard (from [llm-d-deployer](https://github.com/llm-d/llm-d-deployer)) covers E2E latency, TTFT, TPOT, scheduler, and KV cache in one view.

> **CronJob uses 1,3,5,8,10 for both models:** The daily CronJob benchmarks all active models with 5 rate levels. Mistral's 15 RPS level is available only through the on-demand job template. This keeps daily runs shorter while still providing meaningful saturation data.

> **Model Benchmarking Workbench:** A Jupyter notebook (`Model-Benchmarking.ipynb`) is deployed as an RHOAI workbench for interactive result analysis. The notebook reads GuideLLM JSON output from S3 (uploaded by the KFP benchmark pipeline) or from on-demand Job results.

### Deploy

```bash
./steps/step-06-model-metrics/deploy.sh         # Deploy Grafana + GuideLLM via ArgoCD
./steps/step-06-model-metrics/validate.sh       # Verify Grafana health, dashboards, CronJob
```

Additional operations:

```bash
./steps/step-06-model-metrics/run-benchmark.sh  # CLI benchmark (Job template or CronJob)
./steps/step-06-model-metrics/run-pipeline.sh   # Dashboard benchmark (KFP pipeline via DSPA)
```

### What to Verify After Deployment

`validate.sh` runs 5 checks: Grafana health, dashboards, CronJob, and tuned vLLM config.

| Check | What It Tests | Pass Criteria |
|-------|--------------|---------------|
| Grafana instance | Grafana CR exists | 1 instance |
| GrafanaDashboards | vLLM + DCGM dashboards | 2 dashboards |
| Grafana health | API health endpoint | `database: ok` |
| GuideLLM CronJob | Daily benchmark schedule | `0 2 * * *`, not suspended |
| Granite KV cache | Tuned vLLM startup logs | 155,184 tokens (fp8, 0.92) |
| Mistral KV cache | Tuned vLLM startup logs | 426,160 tokens (fp8, 0.90) |

```bash
oc get grafana -n private-ai
oc get grafanadashboard -n private-ai

GRAFANA_HOST=$(oc get route grafana-route -n private-ai -o jsonpath='{.spec.host}')
curl -sk "https://$GRAFANA_HOST/api/health" | python3 -c "import sys,json; print(json.load(sys.stdin))"

oc get cronjob guidellm-daily -n private-ai

oc logs deploy/granite-8b-agent-predictor -n private-ai -c kserve-container \
  | grep 'KV cache size'
oc logs deploy/mistral-3-bf16-predictor -n private-ai -c kserve-container \
  | grep 'KV cache size'
```

## The Demo

> In this demo, we run real benchmarks against our deployed models, visualize the results in Grafana, and establish baseline performance metrics — latency, throughput, GPU utilization, and capacity limits — giving platform teams the data to right-size deployments and set SLO expectations.

### Run a Benchmark

> We start by stress-testing a model with GuideLLM, which sends graduated concurrency — 1, 3, 5, 8, 10 requests per second — while vLLM's built-in Prometheus metrics capture latency and throughput at each level.

1. Get the Grafana URL:

```bash
GRAFANA_URL=$(oc get route grafana-route -n private-ai -o jsonpath='{.spec.host}')
echo "https://${GRAFANA_URL}"
```

2. Benchmark granite-8b-agent (~5 min):

```bash
oc create -f gitops/step-06-model-metrics/base/guidellm/job-templates/granite-8b-agent.yaml
```

3. Or benchmark mistral-3-bf16 (~8 min):

```bash
oc create -f gitops/step-06-model-metrics/base/guidellm/job-templates/mistral-3-bf16.yaml
```

**Expect:** The GuideLLM Job runs graduated concurrency tests while vLLM metrics flow to Prometheus. KServe auto-creates the ServiceMonitors.

> GuideLLM generates real load at production-level concurrency. Combined with vLLM's native Prometheus metrics and KServe's automatic ServiceMonitor creation, we get end-to-end observability without custom instrumentation.

### vLLM Performance Dashboard

> With the benchmark running, we open Grafana to see real-time model performance — latency distributions, token throughput, and KV cache pressure across concurrency levels.

1. Open Grafana → select `namespace=private-ai`, `model_name=granite-8b-agent`
2. Observe key panels:
   - **E2E Request Latency** — P50/P95/P99 across concurrency levels
   - **Token Throughput** — output tokens/second
   - **KV Cache Utilization** — memory pressure indicator
   - **Time To First Token** — responsiveness metric
   - **Scheduler State** — running vs waiting requests

**Expect:** At 10 concurrent users, Granite's P95 inter-token latency stays at ~41ms and throughput holds at 130-170 tok/s. The KV cache is healthy — no memory pressure. Switch the model dropdown to compare Mistral BF16 on the same panels.

> Production-grade observability out of the box. vLLM exposes Prometheus metrics natively, KServe manages the ServiceMonitors, and Grafana visualizes the full picture — from token-level latency to KV cache pressure. Platform teams can set SLO targets backed by real data.

### GPU Hardware Dashboard

> Beyond model metrics, GPU hardware utilization tells us whether we're getting value from our GPU investment — or leaving capacity on the table.

1. Switch to the DCGM dashboard in Grafana

**Expect:** GPU utilization hits 95-100% during the benchmark — that's the capacity ceiling.

> When GPU utilization hits 100%, that's the wall. New pods remain Pending until a GPU node has available resources. DCGM metrics give platform teams the signal to scale GPU nodes before users experience queuing.

### Understanding Capacity Limits

> After both benchmarks complete, we compare the tuned results to establish capacity baselines for each model — the data platform teams need for procurement and scaling decisions.

After both benchmarks complete, compare the results (tuned configuration):

| Metric | granite-8b-agent (1 GPU) | mistral-3-bf16 (4 GPU) |
|--------|--------------------------|------------------------|
| **KV cache capacity** | 155K tokens (9.5x at 16K) | 426K tokens (26.0x at 16K) |
| **TTFT p95** | <90ms | <128ms |
| **ITL p95** | ~40ms (hardware-bound) | ~53ms (hardware-bound) |
| **Output throughput** | ~130-170 tok/s | ~120-135 tok/s |
| **Sweet spot** | 5-8 concurrent users | 10-15 concurrent users |

**Expect:** After tuning, Granite's KV cache doubled from 74K to 155K tokens — 9 concurrent requests at full 16K context, up from 4.5 before tuning. Mistral gained 16% more capacity. Both models' inter-token latency is hardware-bound on L4 GPUs.

> KV cache doubled through FP8 tuning. Throughput holds steady through realistic concurrency. But inter-token latency at 40ms and 53ms is the L4 memory bandwidth floor — not a tuning issue. Moving to A100 or H100 GPUs would reduce ITL significantly. These are the numbers platform teams need to make GPU procurement decisions with confidence.

> **Known Limitation (NVIDIA L4):** ITL is limited by memory bandwidth (~300 GB/s). An 8B FP8 model reads ~8 GB of weights per decode step, giving a theoretical minimum of ~27ms. Observed 40ms includes compute, KV cache attention, and CUDA overhead. This is near the hardware floor — not a tuning issue. See [Practical strategies for vLLM performance tuning](https://developers.redhat.com/articles/2026/03/03/practical-strategies-vllm-performance-tuning).

### Dashboard Pipeline

> CLI benchmarks work for automation, but platform teams need self-service. The same GuideLLM benchmark runs as a Kubeflow Pipeline, triggerable from the RHOAI Dashboard without CLI access.

1. Navigate to **Develop & train → Pipelines** in the RHOAI Dashboard
2. Select `bench-granite-8b` (or `bench-mistral-bf16`)
3. Click **Create run**
4. Review pre-filled parameters: `model_name`, `rates`, `max_seconds`, `max_requests`, `run_id`
5. Keep defaults, click **Start**
6. Watch the run in the **Runs** tab

**Expect:** A 3-step pipeline: `run_benchmark` → `upload_results` → `benchmark_summary`. Granite completes in ~5 minutes, Mistral in ~8 minutes. Results uploaded to S3 (`benchmark-results/<run_id>/`). The summary step logs TTFT, ITL, and throughput metrics to the Dashboard.

> The same GuideLLM benchmark — now a Kubeflow Pipeline that anyone can trigger from the RHOAI Dashboard. No `oc` access needed. The platform team sets it up once, developers run it whenever they want to validate model performance after a configuration change. Results are versioned in S3 and summarized directly in the Dashboard.

> **Prerequisite:** The KFP pipeline requires `dspa-rag` from Step 07. If Step 07 hasn't been deployed yet, this scene is not available — use the CLI approach from Run a Benchmark.

## Key Takeaways

**For business stakeholders:**

- Model observability transforms GPU investment from guesswork into data-driven capacity planning
- Performance baselines enable SLO commitments — P95 latency, throughput, and concurrency limits are measurable
- Self-service benchmarking via the RHOAI Dashboard puts performance validation in the hands of every team, not just platform operators

**For technical teams:**

- vLLM exposes Prometheus metrics natively; KServe auto-creates ServiceMonitors — zero custom instrumentation
- FP8 KV cache tuning doubles effective concurrency without additional GPUs
- GuideLLM graduated concurrency tests (1-10 req/s) reveal saturation points and hardware-bound limits

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
- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet)
- [Get started with AI for enterprise organizations — Red Hat](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)

## Next Steps

- **Step 07**: [RAG Pipeline](../step-07-rag/README.md) — Document ingestion and vector search with LlamaStack
