# Step 06: Model Performance Metrics

**"The ROI of Quantization"** — Prove that a $0.85/hr INT4 model beats a $3.40/hr BF16 model on cost-per-token.

## The Business Story

In enterprise AI, the question isn't *"How fast is my model?"* but *"How much value per GPU-hour?"* This step puts two models head-to-head: a 1-GPU INT4 deployment at $0.85/hr vs a 4-GPU BF16 deployment at $3.40/hr. GuideLLM stress tests generate load while three Grafana dashboards visualize latency, throughput, GPU saturation, and cost efficiency in real time. The punchline: 4 INT4 instances cost the same as 1 BF16 instance but serve **60% more users**.

## What It Does

```
GuideLLM Benchmark Jobs
    │                          ┌─────────────────────────────────┐
    ├───► mistral-3-int4       │  Grafana Dashboards             │
    │     (1 GPU, $0.85/hr)    │  1. vLLM Latency/Throughput     │
    │                          │  2. NVIDIA DCGM GPU Metrics     │
    └───► mistral-3-bf16       │  3. Mistral ROI Comparison      │
          (4 GPU, $3.40/hr)    └────────────┬────────────────────┘
                                            │
                               OpenShift User Workload Monitoring
                               (Prometheus + Thanos)
```

| Component | Description |
|-----------|-------------|
| **Grafana Operator** | Kubernetes-native Grafana from OperatorHub (community) |
| **Grafana Instance** | Anonymous-access dashboards in `private-ai` |
| **3 GrafanaDashboards** | vLLM metrics, GPU hardware, ROI comparison |
| **GuideLLM CronJob** | Daily parallel benchmarks at 2:00 AM UTC |
| **Job Templates** | On-demand benchmark per model via `oc create -f` |

> **Community Tooling Disclaimer:** Grafana Operator and GuideLLM are community-driven tools and are NOT officially supported by Red Hat OpenShift AI 3.3. See [Red Hat's Third Party Software Support Policy](https://access.redhat.com/third-party-software-support).

## Demo Walkthrough

### Scene 1: Fire a Benchmark

Kick off a GuideLLM stress test against a running model so the dashboards have live data.

```bash
GRAFANA_URL=$(oc get route grafana-route -n private-ai -o jsonpath='{.spec.host}')
echo "https://${GRAFANA_URL}"

oc create -f gitops/step-06-model-metrics/base/guidellm/job-templates/mistral-3-bf16.yaml
oc get pods -n private-ai -l app=guidellm -w
```

**What to expect:** A GuideLLM pod starts and ramps concurrency from 1 to 32 users against the model endpoint. Runs for 5-10 minutes.

*What to say: "GuideLLM is an open-source tool from the vLLM project. It sends graduated concurrency — 1, 2, 4, 8, 16, 32 users — while measuring latency and throughput at each level. Every request flows through KServe's metrics endpoint straight into Prometheus."*

---

### Scene 2: Grafana — vLLM Latency, Throughput & Cache

Open Grafana and select `namespace=private-ai`. Walk through the panels while the benchmark runs.

**What to expect:** Five live panel groups — E2E Request Latency, Token Throughput, Scheduler State, KV Cache Utilization, and Time To First Token — all updating in real time as GuideLLM increases load.

*What to say: "This single dashboard replaces three separate vLLM dashboards. Notice the P99 latency stays under 40 seconds at 10 concurrent users, throughput holds at 80-120 tokens per second, and the cache shows zero memory pressure. These metrics come directly from vLLM's built-in Prometheus endpoint — KServe auto-creates the ServiceMonitors."*

Switch the `model_name` dropdown from one model to the other and compare the same panels.

*What to say: "Same dashboard, different model. You can instantly compare any model deployed through KServe — no config changes needed."*

---

### Scene 3: NVIDIA DCGM GPU Dashboard

Switch to the DCGM dashboard to show the hardware layer.

**What to expect:** GPU utilization hitting 95-100% during the active benchmark, with memory utilization and temperature alongside it.

*What to say: "This is the capacity ceiling. When GPU utilization hits 100%, that's when Kueue's quota management from Step 03 kicks in — new model requests queue until resources free up. This is exactly the GPU-as-a-Service pattern we built earlier."*

---

### Scene 4: Mistral ROI Comparison — The Business Case

Open the ROI Comparison dashboard. This is the closer — the business story.

**What to expect:** Side-by-side panels showing INT4 vs BF16 latency, throughput, and cost metrics.

*What to say: "Here's the business case. The 1-GPU INT4 model delivers 60% of the 4-GPU throughput at 25% of the cost. For the price of one BF16 deployment, you can run four INT4 instances and serve 60% more total users."*

### ROI Summary

| Metric | INT4 (1-GPU) | BF16 (4-GPU) | Ratio |
|--------|--------------|--------------|-------|
| **Hardware Cost** | $0.85/hr | $3.40/hr | 4x |
| **Sweet Spot Capacity** | 3-5 users | 10-15 users | 3x |
| **Breaking Point** | 8-10 users | 20 users | 2-2.5x |
| **Max Throughput** | ~300 tok/s | ~700 tok/s | 2.3x |
| **Efficiency (tok/s/$)** | 353 tok/s/$ | 206 tok/s/$ | **INT4 1.7x better** |
| **TTFT at Sweet Spot** | 874ms (p95) | 594ms (p95) | BF16 faster |

### Key Findings

1. **FP8 KV Cache is Critical for INT4**: Without FP8 cache, INT4 broke at 5 users. With optimization, it handles 8+ users (60% improvement).

2. **INT4 is More Cost-Efficient**: At $0.85/hr vs $3.40/hr, INT4 delivers 1.7x more tokens per dollar.

3. **BF16 Scales Better**: For high-concurrency workloads (15+ users), BF16's 4-GPU parallelism provides more stable latency.

4. **The "4x INT4" Strategy**: Running 4 INT4 instances costs the same as 1 BF16 instance but serves 60% more users with 98.9% accuracy recovery.

*What to say: "With Red Hat AI memory optimizations, a single $0.85/hr L4 GPU running INT4 handles 8 concurrent users with sub-100ms per-token latency. For the cost of one 4-GPU BF16 deployment, you can run 4 INT4 instances serving 60% more users."*

## Design Decisions

> **Why CronJob + Job templates instead of Tekton?** In Kueue-managed namespaces, Tekton's affinity assistants and topology scheduling gates create deadlocks. Simple Jobs with `kueue.x-k8s.io/queue-name: default` work reliably.

> **Why no results PVC?** The real value is in Prometheus/Grafana metrics, not JSON files. vLLM automatically exposes metrics via ServiceMonitors — every benchmark request lights up the dashboards.

> **Why 3 dashboards instead of 6?** The vLLM Latency, Throughput & Cache dashboard (from [llm-d-deployer](https://github.com/llm-d/llm-d-deployer)) replaces 3 separate vLLM dashboards — it covers E2E latency, TTFT, TPOT, scheduler state, KV cache, and queue time in one view.

## References

### Red Hat Official
- [RHOAI 3.3 Monitoring Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_and_monitoring_models/index)
- [OpenShift User Workload Monitoring (4.20)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/monitoring/enabling-monitoring-for-user-defined-projects)
- [GuideLLM — Evaluate LLM Deployments (Red Hat Developers)](https://developers.redhat.com/articles/2025/06/20/guidellm-evaluate-llm-deployments-real-world-inference)
- [How to Deploy and Benchmark vLLM with GuideLLM (Red Hat Developers)](https://developers.redhat.com/articles/2025/12/24/how-deploy-and-benchmark-vllm-guidellm-kubernetes)

### Community / Open Source
- [vLLM Production Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html)
- [Grafana Operator](https://github.com/grafana/grafana-operator) | [Docs](https://grafana.github.io/grafana-operator/docs/)
- [GuideLLM (vllm-project)](https://github.com/vllm-project/guidellm)
- [llm-d-deployer vLLM Dashboard](https://github.com/llm-d/llm-d-deployer/tree/main/quickstart/grafana/dashboards)

## Operations

```bash
./steps/step-06-model-metrics/deploy.sh     # Deploy Grafana + GuideLLM + dashboards
./steps/step-06-model-metrics/validate.sh   # Verify Grafana health, dashboards, datasource
```

## Next Steps

- [Step 07: RAG Pipeline](../step-07-rag/README.md) — Document ingestion and vector search
