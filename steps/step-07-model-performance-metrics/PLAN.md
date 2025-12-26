# Plan: Step 07 - Model Performance Metrics (Saturation & Sizing)

## 1. Conceptual Foundation (Platform-to-Business)

This step transforms raw monitoring into a **Strategic Sizing Tool**. We are implementing a **"Stress Test" methodology** to answer the most critical question in GenAI Ops: *"Exactly how many concurrent users can I support on this AWS instance before the user experience degrades?"*

Instead of static graphs, we introduce **Performance Limit Testing**. This mimics the "breaking point" analysis used in traditional performance engineering but specialized for LLM architectures (KV Cache and Compute bounds).

**Primary Goals:**
1.  **Define Performance Limits**: Determine the "Breaking Point" (Concurrency vs. Latency) for our models.
2.  **Quantify "Economic Throughput"**: Measure Tokens-per-second-per-GPU to demonstrate the ROI of quantization.
3.  **Establish Enterprise SLAs**: Set clear thresholds for TTFT, TPOT, and Success Rate based on community standards (Mistral AI, HuggingFace).

---

## 2. Layered Architecture Analysis

| Layer | Component | Metric Strategy | Why it matters |
| :--- | :--- | :--- | :--- |
| **Layer 1: Infrastructure** | **NVIDIA DCGM** | Power Draw (Watts), Framebuffer Memory | Correlate energy cost (4-GPU vs 1-GPU) to model output. |
| **Layer 2: Platform** | **OpenShift Monitoring** | `ServiceMonitor` | Ingest vLLM metrics into the user-workload Prometheus stack. |
| **Layer 3: Application** | **vLLM Runtime** | TTFT, TPOT, Queue Length, KV Cache Usage | The primary signals for User Experience and System Saturation. |
| **Layer 4: Testing** | **GuideLLM** | Synthetic Load (Stress Test) | Generate consistent traffic to find the "Breaking Point". |

---

## 3. Metrics Strategy & SLAs

We define the following "Enterprise SLAs" for this demo, derived from **Mistral AI**, **HuggingFace**, and **vLLM** best practices.

### 3.1 The "Breaking Point" Definition
The system is considered "broken" (saturated) when **TTFT > 2.0s** OR **Queue Length > 0** consistently.

### 3.2 Key Performance Indicators (KPIs)

| Metric | Target (Excellent) | Acceptable (SLA) | Degraded (Break Point) | Description |
| :--- | :--- | :--- | :--- | :--- |
| **TTFT** | < 200ms | < 800ms | > 2.0s | **Time To First Token**. Critical for chat "flow". |
| **TPOT** | > 50 tok/s | > 20 tok/s | < 10 tok/s | **Time Per Output Token**. Reading speed. |
| **KV Cache** | < 70% | 70-90% | > 95% | Memory pressure. >95% means queueing is imminent. |
| **Success** | 100% | 99% | < 95% | Error rate (HTTP 500/429). |

**Ref**: [HuggingFace LLM Performance Optimization Guide](https://huggingface.co/docs/transformers/llm_tutorial_optimization)

---

## 4. Implementation Plan

### 4.1 Wave 1: Observability Stack
*   **Deploy `ServiceMonitor`**: Enable Prometheus scraping of vLLM `/metrics`.
*   **Deploy User-Managed Grafana**: A dedicated instance in `private-ai` for custom A/B comparison dashboards.

### 4.2 Wave 2: The "GuideLLM-Sweep" Job
We will implement an **Incremental Load Sweep** job using GuideLLM.

*   **Logic**:
    1.  **Baseline**: 1 concurrent user (Ideal Latency).
    2.  **Increment**: Double concurrency (2, 4, 8, 16...) until saturation.
    3.  **Workload Shapes**:
        *   *Scenario A (Support)*: Short Input / Short Output (Focus: TTFT).
        *   *Scenario B (Summary)*: Long Input / Short Output (Focus: KV Cache).
        *   *Scenario C (Coding)*: Short Input / Long Output (Focus: TPOT).
*   **Connectivity**: Run inside `private-ai` namespace (ClusterIP) to measure *Model Performance* excluding external Ingress latency.
*   **Persistence**: Mount a dedicated `guidellm-results` PVC to save results.

### 4.3 Wave 3: The "Sizing & Saturation" Dashboard
A custom Grafana dashboard titled **"Mistral Scale Comparison"**:
1.  **Breaking Point Chart**: Line graph (X=Concurrency, Y=TTFT) comparing 4-GPU BF16 vs. 1-GPU INT4.
2.  **Efficiency Gauge**: Calculated **Tokens-per-second-per-GPU** (Economic Throughput).
3.  **KV Cache Wall**: Visualizing `vllm_gpu_cache_usage_perc` to show memory-bound saturation.
4.  **Power Usage**: Real-time Watts (DCGM) to contrast energy footprint (~800W vs ~150W).

---

## 5. Design Decisions (Explicit)

### Decision 1: Internal "ClusterIP" Testing
*   **Context**: We need to isolate the model engine performance.
*   **Decision**: Run GuideLLM inside the cluster targeting the Service ClusterIP directly.
*   **Reason**: Bypassing the Ingress/Router eliminates network variable jitter, giving us pure "Engine Capacity" metrics.

### Decision 2: Standalone Grafana
*   **Context**: The default Console Dashboards are excellent for single metrics but poor for complex A/B math (e.g., "Diff between Model A and Model B").
*   **Decision**: Deploy a lightweight Grafana instance.
*   **Reason**: Required for the "Comparison Dashboard" to overlay two different data sources (Prometheus queries) on the same chart.

### Decision 3: Quantization Narrative
*   **Context**: INT4 is often seen as "lower quality."
*   **Decision**: Frame INT4 as **"High Economic Throughput."**
*   **Reason**: We will demonstrate that while it may saturate earlier on *total* concurrency, it handles significantly more users *per dollar* (per GPU) than the BF16 model.

---

## 6. Implementation Checklist / Coding Hand-off

### Task 1: Grafana & Prometheus ✅ COMPLETE
- [x] Create `gitops/step-07-model-performance-metrics/base/grafana/`
- [x] Define `Deployment` (grafana), `Service`, and `Route`.
- [x] Define `ServiceMonitor` for vLLM pods.
- [x] Configure `datasource-cm.yaml` for Prometheus connectivity.
- [x] Configure `local-prometheus.yaml` for high-resolution scraping.

### Task 2: Dashboards (ConfigMaps) ✅ COMPLETE
- [x] `dashboard-provider.yaml` (Dashboard provisioning config).
- [x] `dashboard-vllm.yaml` (vLLM Production Metrics).
- [ ] `dashboard-dcgm.json` (Infrastructure) - Phase 2.
- [ ] `dashboard-mistral-comparison.json` (Custom A/B view) - Phase 2.

### Task 3: GuideLLM Job 🔲 PENDING (Phase 2)
- [x] Create `gitops/step-07-model-performance-metrics/base/guidellm/` (placeholder)
- [ ] Define `PVC` for results storage.
- [ ] Define `CronJob` for daily scheduled benchmarks.
- [ ] Define `Job` template for on-demand runs.
- [ ] Script the `entrypoint.sh` to run the sweep:
    ```bash
    # Pseudo-code for agent
    for concurrency in 1 2 4 8 16 32; do
       guidellm --target http://mistral-3-bf16:8080 --concurrency $concurrency ...
       guidellm --target http://mistral-3-int4:8080 --concurrency $concurrency ...
    done
    ```

### Task 4: Supporting Resources 🔲 PENDING
- [ ] ArgoCD Application for Step 07.
- [ ] README and deploy.sh scripts.
- [ ] Integration testing with live models.

---

## 7. References & Resources
*   **vLLM Metrics**: [https://docs.vllm.ai/en/latest/serving/metrics.html](https://docs.vllm.ai/en/latest/serving/metrics.html)
*   **GuideLLM**: [https://github.com/neuralmagic/guidellm](https://github.com/neuralmagic/guidellm)
*   **HuggingFace Performance Guide**: [https://huggingface.co/docs/transformers/llm_tutorial_optimization](https://huggingface.co/docs/transformers/llm_tutorial_optimization)
*   **RHOAI Monitoring**: [https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/managing_and_monitoring_models/index](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/managing_and_monitoring_models/index)

---
*Drafted by Cursor Agent for RHOAI 3.0 Demo Project*
