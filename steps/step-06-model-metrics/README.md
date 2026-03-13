# Step 06: Model Performance Metrics

**"The ROI of Quantization"** — Comprehensive observability and benchmarking to prove that Inference Efficiency is the most important metric for enterprise AI.

## The Business Story

In enterprise AI deployments, the question isn't just *"How fast is my model?"* but *"How much value per GPU-hour?"* This step demonstrates the **Economics of Precision**: a 1-GPU INT4 model at $0.85/hr vs a 4-GPU BF16 model at $3.40/hr. We use GuideLLM stress tests and Grafana dashboards to find each model's "Breaking Point" — the concurrency level where latency degrades beyond acceptable SLOs. The punchline: 4 INT4 instances cost the same as 1 BF16 instance but serve 60% more users.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│              Step 06: The "ROI of Quantization" Demo             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Grafana Dashboards          OpenShift Console (DCGM)           │
│        │                              │                          │
│        ▼                              ▼                          │
│   OpenShift User Workload Monitoring (Thanos + Prometheus)       │
│                          ▲                                       │
│                          │                                       │
│   GuideLLM Benchmark Jobs (CronJob + on-demand)                  │
│        │                              │                          │
│        ▼                              ▼                          │
│   mistral-3-int4 (1-GPU, $)    mistral-3-bf16 (4-GPU, $$$$)     │
│                                                                  │
│   ServiceMonitors auto-created by KServe per InferenceService    │
└──────────────────────────────────────────────────────────────────┘
```

## What Gets Deployed

| Component | Description | Official/Community |
|-----------|-------------|-------------------|
| **Grafana Operator** | Kubernetes-native Grafana management from OperatorHub | Community |
| **Grafana Instance** | Dashboard with anonymous access in `private-ai` | Community (OSS) |
| **GrafanaDatasource** | Prometheus datasource pointing to UWM Thanos Querier | — |
| **3 GrafanaDashboards** | vLLM metrics, GPU hardware, ROI comparison | — |
| **GuideLLM CronJob** | Daily parallel benchmarks at 2:00 AM UTC | Community (OSS) |
| **Job Templates** | On-demand benchmark Jobs per model (`oc create -f`) | Community (OSS) |

> **Community Tooling Disclaimer:** Grafana Operator and GuideLLM are community-driven tools and are NOT officially supported by Red Hat OpenShift AI 3.3. See [Red Hat's Third Party Software Support Policy](https://access.redhat.com/third-party-software-support).

## Prerequisites

| Requirement | How to Verify |
|-------------|---------------|
| **Step 01 Complete** | User Workload Monitoring enabled, DCGM Dashboard |
| **Step 05 Complete** | At least one vLLM InferenceService running |
| **Recommended** | Both `mistral-3-int4` and `mistral-3-bf16` for ROI comparison |

```bash
oc get cm cluster-monitoring-config -n openshift-monitoring -o yaml | grep enableUserWorkload
oc get inferenceservice -n private-ai | grep -E "mistral-3-int4|mistral-3-bf16"
oc get servicemonitor -n private-ai | grep metrics
```

## Deployment

### Option A: Direct Deploy (Recommended for Demo)

```bash
./steps/step-06-model-metrics/deploy.sh
```

### Option B: ArgoCD (GitOps)

```bash
oc apply -f gitops/argocd/app-of-apps/step-06-model-metrics.yaml
```

The deploy uses a **CronJob + Job template** pattern instead of Tekton Pipelines (Tekton's affinity assistants deadlock in Kueue-managed namespaces). The CronJob checks which models are running and creates a GuideLLM Job per active model. Metrics flow to Prometheus automatically via KServe ServiceMonitors.

## Validation

```bash
# 1. Grafana Operator installed
oc get csv -n grafana-operator | grep grafana
# Expected: grafana-operator.v5.x ... Succeeded

# 2. Grafana instance ready
oc get grafana -n private-ai
# Expected: grafana   12.x.x   complete   success

# 3. Three dashboards exist
oc get grafanadashboard -n private-ai
# Expected: vllm-latency-throughput-cache, dcgm-gpu-metrics, mistral-roi-comparison

# 4. Datasource configured
oc get grafanadatasource -n private-ai
# Expected: prometheus-uwm

# 5. Grafana route healthy
curl -k -s -o /dev/null -w "%{http_code}" \
  https://$(oc get route grafana-route -n private-ai -o jsonpath='{.spec.host}')/api/health
# Expected: 200

# 6. CronJob scheduled
oc get cronjob guidellm-daily -n private-ai
# Expected: guidellm-daily   0 2 * * *
```

## Demo Walkthrough

### Before the Demo (~5 min)

```bash
GRAFANA_URL=$(oc get route grafana-route -n private-ai -o jsonpath='{.spec.host}')
echo "https://${GRAFANA_URL}"

oc create -f gitops/step-06-model-metrics/base/guidellm/job-templates/granite-8b-agent.yaml
oc create -f gitops/step-06-model-metrics/base/guidellm/job-templates/mistral-3-bf16.yaml
oc get pods -n private-ai -l app=guidellm -w
```

### During the Demo (3-Dashboard Narrative)

**Dashboard 1: vLLM Latency, Throughput & Cache** (primary — show live)

Open Grafana, select `namespace=private-ai` and `model_name=granite-8b-agent`. Walk through: E2E Request Latency ("P99 stays under 40s at 10 concurrent users"), Token Throughput ("80-120 tok/s on a single $0.85/hr GPU"), Scheduler State ("zero queue backlog"), Cache Utilization ("healthy, no memory pressure"), and Time To First Token ("P95 under 95ms"). Then switch to `mistral-3-bf16` and compare the same panels.

**Dashboard 2: NVIDIA DCGM GPU Metrics** (hardware story)

Show GPU utilization hitting 100% during benchmarks — "This is the capacity ceiling; when we need more, Kueue queues the request."

**Dashboard 3: Mistral ROI Comparison** (closing — business story)

Side-by-side BF16 vs INT4 metrics. Key message: *"The 1-GPU model delivers 60% of the 4-GPU throughput at 25% of the cost."*

### Demo Talking Points

> *"On a single $0.85/hr L4 GPU, granite-8b-agent handles 10 concurrent users with sub-100ms TTFT and zero queue backlog. The 4-GPU BF16 model costs 4x more but only delivers 2x the throughput. For cost-sensitive workloads, running 4 instances of the 1-GPU model gives you more total capacity at the same price."*

> *"When the GPU hits 100% utilization, Kueue's quota management kicks in — new models queue until resources free up. This is exactly the GPU-as-a-Service pattern we demonstrated in Step 03."*

## Benchmark Results

Based on GuideLLM graduated concurrency testing (256 input, 256 output tokens). Both models tuned with `--kv-cache-dtype=fp8` and `--enable-chunked-prefill` per Red Hat AI Field Engineering recommendations.

### Summary Comparison

| Metric | INT4 (1-GPU) | BF16 (4-GPU) | Ratio |
|--------|--------------|--------------|-------|
| **Hardware Cost** | $0.85/hr | $3.40/hr | 4x |
| **Sweet Spot Capacity** | 3-5 users | 10-15 users | 3x |
| **Breaking Point** | 8-10 users | 20 users | 2-2.5x |
| **Max Throughput** | ~300 tok/s | ~700 tok/s | 2.3x |
| **Efficiency (tok/s/$)** | 353 tok/s/$ | 206 tok/s/$ | **INT4 1.7x better** |
| **TTFT at Sweet Spot** | 874ms (p95) | 594ms (p95) | BF16 faster |

> **INT4 Sweet Spot:** 3-5 concurrent users (TTFT < 1.5s) | **Breaking Point:** 8-10 users (TTFT > 2s)
>
> **BF16 Sweet Spot:** 5-15 concurrent users (TTFT < 1.7s) | **Breaking Point:** 20 users (TTFT > 2s)

### Key Findings

1. **FP8 KV Cache is Critical for INT4**: Without FP8 cache, INT4 broke at 5 users. With optimization, it handles 8+ users (60% improvement).

2. **INT4 is More Cost-Efficient**: At $0.85/hr vs $3.40/hr, INT4 delivers 1.7x more tokens per dollar.

3. **BF16 Scales Better**: For high-concurrency workloads (15+ users), BF16's 4-GPU parallelism provides more stable latency.

4. **The "4x INT4" Strategy**: Running 4 INT4 instances (4 x 8 = 32 concurrent users) costs the same as 1 BF16 instance (20 concurrent users), providing 60% more capacity.

### Demo Storyline

> *"With Red Hat AI memory optimizations, a single $0.85/hr L4 GPU running INT4 quantization handles 8 concurrent users with sub-100ms per-token latency. For the cost of one 4-GPU BF16 deployment, you can run 4 INT4 instances serving 60% more users with 98.9% accuracy recovery."*

## Troubleshooting

### GuideLLM Job Failing

**Symptom:** Benchmark job exits with error

```bash
oc logs job/<job-name> -n private-ai
```

Check that the target InferenceService is ready. If the rate is too high, lower `MAX_RATE` in the job template.

### No Data in Grafana

**Symptom:** Dashboard shows "No data"

```bash
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -- \
  curl -s 'localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job | contains("metrics")) | {job: .labels.job, health: .health}'
```

Verify the ServiceMonitors exist (`oc get servicemonitor -n private-ai`) and that User Workload Monitoring is enabled.

### vLLM Metrics Use Colon Separator

vLLM metrics use `:` not `_` (e.g., `vllm:num_requests_running`). If PromQL queries return empty, check the separator. See [vLLM Production Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html) for the full metric reference.

## GitOps Structure

```
gitops/step-06-model-metrics/
├── base/
│   ├── kustomization.yaml
│   ├── pipelines-operator/                # Red Hat OpenShift Pipelines (for step-07)
│   │   ├── kustomization.yaml
│   │   └── subscription.yaml
│   ├── grafana-operator/
│   │   ├── kustomization.yaml
│   │   ├── operator/                      # Grafana Operator from OperatorHub
│   │   │   ├── kustomization.yaml
│   │   │   ├── namespace.yaml
│   │   │   ├── operatorgroup.yaml
│   │   │   └── subscription.yaml
│   │   ├── instance/                      # Grafana instance in private-ai
│   │   │   ├── kustomization.yaml
│   │   │   ├── grafana.yaml
│   │   │   └── datasource.yaml
│   │   └── dashboards/                    # 3 GrafanaDashboard CRs
│   │       ├── kustomization.yaml
│   │       ├── vllm-latency-throughput-cache.yaml
│   │       ├── vllm-ltc-configmap.yaml
│   │       ├── dcgm-gpu-metrics.yaml
│   │       └── mistral-roi-comparison.yaml
│   ├── guidellm/                          # Benchmarking
│   │   ├── kustomization.yaml
│   │   ├── rbac.yaml
│   │   ├── cronjob.yaml
│   │   └── job-templates/
│   │       ├── granite-8b-agent.yaml
│   │       └── mistral-3-bf16.yaml
└── kustomization.yaml
```

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
- [vLLM Production Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html) (includes PromQL examples)
- [Grafana Operator](https://github.com/grafana/grafana-operator) | [Docs](https://grafana.github.io/grafana-operator/docs/)
- [GuideLLM (vllm-project)](https://github.com/vllm-project/guidellm)
- [NeuralNav — SLO-Driven Capacity Planning](https://github.com/redhat-et/neuralnav) (traffic profiles + experience-driven SLOs)
- [llm-d-deployer vLLM Dashboard](https://github.com/llm-d/llm-d-deployer/tree/main/quickstart/grafana/dashboards)

## Next Steps

- [Step 07: RAG Pipeline](../step-07-rag/README.md) — Document ingestion and vector search
