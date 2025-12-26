# Plan: Step 07 - Model Performance Metrics

## 1. Introduction & Objectives

This step focuses on **Observability** and **Benchmarking** for LLMs running on RHOAI 3.0. We will move beyond simple deployment ("it runs") to production-grade monitoring ("how well does it run?").

**Primary Goals:**
1.  **Enable Observability**: Implement comprehensive monitoring for LLM inference (vLLM) and infrastructure (GPUs).
2.  **Understand Performance**: Explain and visualize key metrics like Time To First Token (TTFT) and Token generation capability.
3.  **Evaluate Optimization**: Quantify the impact of model quantization (Mistral 3 24B FP vs INT4).
4.  **Standardize Benchmarking**: Introduce **GuideLLM** as the tool for capacity planning and performance testing.
5.  **Performance Bottlenecks**: Identify limitations in the current single-replica setup (e.g., KV cache exhaustion, queue latency) and establish the case for the next demo step: **LLM-d and Distributed Inference**.

---

## 2. Metrics Strategy

We will adhere to the "USE Method" (Utilization, Saturation, Errors) adapted for LLMs.

### 2.1 Essential LLM Metrics (vLLM)
RHOAI 3.0's vLLM runtime exposes metrics at `/metrics`. We must scrape these to track:

| Metric | Description | Why it matters |
|--------|-------------|----------------|
| **Time To First Token (TTFT)** | Latency from request to first visible output. | Critical for user perceived latency (chatbots). |
| **Time Per Output Token (TPOT)** | Time to generate subsequent tokens. | Determines "reading speed" for the user. |
| **Request Throughput** | Requests served per second. | System capacity sizing. |
| **KV Cache Usage** | GPU memory used for context handling. | Saturation indicator; high usage = upcoming queueing. |
| **Queue Length** | Pending requests. | Immediate saturation signal. |

**Source**: [vLLM Metrics Documentation](https://docs.vllm.ai/en/latest/serving/metrics.html)

### 2.2 Infrastructure Metrics (NVIDIA DCGM)
We will leverage the **NVIDIA DCGM Exporter** (already installed by the GPU Operator in Step 01) to track:
- GPU Utilization (%)
- GPU Memory Used (Framebuffer)
- GPU Temperature & Power Draw

**Source**: [Red Hat OpenShift AI - Monitoring GPU Health](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.13/html/monitoring_data_science_models/monitoring-gpu-health)

---

## 3. Implementation Plan

### 3.1 Observability Stack
We will use the **OpenShift User Workload Monitoring** stack (enabled in Step 01) to scrape metrics, but we may deploy a user-managed **Grafana** instance for advanced dashboarding if the built-in Console Dashboards are insufficient for custom queries (e.g., comparing two models).

**Tasks:**
1.  **ServiceMonitor**: Define a `ServiceMonitor` to scrape the vLLM pods.
    *   *Note*: vLLM pods in Step 05 already expose port `8080` with `prometheus.io/scrape` annotations, but a `ServiceMonitor` is the OCP-native way to ingest this into the user-workload Prometheus.
2.  **Grafana Deployment**: Deploy a lightweight Grafana instance in the `private-ai` namespace (or reuse RHOAI dashboard if possible, but a custom Grafana is usually required for custom dashbaords).
    *   *Decision*: We will deploy a dedicated Grafana instance using the community operator or a simple Deployment to have full control over dashboards.

### 3.2 Dashboards
We will provision three Grafana dashboards via ConfigMaps (GitOps):

1.  **Infrastructure (NVIDIA DCGM)**:
    *   Based on the official NVIDIA DCGM dashboard.
    *   Focus: "Are my GPUs healthy and utilized?"
2.  **LLM Performance (vLLM Official)**:
    *   Based on the official vLLM Grafana dashboard.
    *   Focus: "Is the model responsive?"
3.  **Model Comparison (Mistral 3 Showcase)**:
    *   **Custom Dashboard**: Side-by-side view of `mistral-3-bf16` vs `mistral-3-int4`.
    *   Panels:
        *   Latency (TTFT) Comparison.
        *   Throughput Comparison.
        *   GPU Memory Footprint Comparison (~45GB vs ~14GB).

### 3.3 Benchmarking with GuideLLM
We will introduce **GuideLLM** (by Neural Magic) to automate performance testing.

**Why GuideLLM?**
*   It helps determine the "optimal" concurrency for a given hardware/model.
*   It generates traffic simulation (Poisson arrival, etc.) rather than just static requests.
*   *Note*: Neural Magic is a Red Hat partner and GuideLLM is becoming a standard tool for sizing RHOAI deployments.

**Tasks:**
1.  Create a `Job` or `Pod` definition for GuideLLM.
2.  Define a "Benchmark Suite" script that:
    *   Runs a baseline test against `mistral-3-bf16`.
    *   Runs a baseline test against `mistral-3-int4`.
    *   Exports results for analysis.

**Ref**: [GuideLLM GitHub Repository](https://github.com/neuralmagic/guidellm)

---

## 4. Impact of Quantization (Hypothesis to Verify)

We expect to demonstrate:
*   **Memory**: Significant reduction (approx 50-60% less VRAM for INT4 vs BF16).
*   **Throughput**: Higher maximum batch size possible on INT4 due to KV cache headroom.
*   **Latency**: Potential improvement in memory-bound scenarios, though compute-bound kernels (AWQ/Marlin) vary.

---

## 5. Analyzing Performance Bottlenecks

As we benchmark the single-replica models (Step 05 architecture), we will explicitly look for these bottlenecks to motivate **Step 08 (LLM-d & Distributed Inference)**:

### 5.1 The "KV Cache" Wall
*   **Symptom**: `vllm:gpu_cache_usage_perc` hits 100% despite GPU Compute Utilization being < 50%.
*   **Effect**: New requests are queued (`vllm:num_requests_waiting` > 0). TTFT spikes massively for queued requests.
*   **Conclusion**: Single GPU memory is the bottleneck for **concurrency**, not compute.
*   **Solution**: **Tensor Parallelism (Distributed Inference)** to pool memory from multiple GPUs, allowing larger batch sizes and KV caches.

### 5.2 The "Compute" Wall
*   **Symptom**: GPU Compute Utilization is > 95%, but Token Generation (TPOT) slows down linearly with batch size.
*   **Effect**: The model generates text slowly for everyone.
*   **Conclusion**: The model is too large or the batch is too big for a single GPU's FP capability.
*   **Solution**: **Sharding (LLM-d)** to distribute matrix multiplications across GPUs.

### 5.3 The "Latency" Floor
*   **Symptom**: Even with 1 user, TTFT is high for large models (e.g., Llama 3 70B on 1 GPU).
*   **Effect**: Bad user experience despite low utilization.
*   **Conclusion**: Serial processing time is too high.
*   **Solution**: **Tensor Parallelism** to parallelize the single-request computation.

---

## 6. References & Resources

*   **RHOAI 3.0 Documentation**: [Monitoring Data Science Models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/managing_and_monitoring_models/index)
*   **OCP 4.20 Monitoring**: [Enabling monitoring for user-defined projects](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/monitoring/enabling-monitoring-for-user-defined-projects)
*   **vLLM Metrics**: [vLLM Production Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html)
*   **GuideLLM**: [Neural Magic GuideLLM](https://github.com/neuralmagic/guidellm)

## 7. Design Decisions (Confirmed)

1.  **Grafana Strategy**: **Hybrid Approach**.
    *   We will demonstrate the **Built-in RHOCP/RHOAI Console Dashboards** first to show out-of-the-box value.
    *   We will then deploy **User-Managed Grafana** for the advanced/custom dashboards (Comparison View), which will be the primary focus of the demo.

2.  **Load Generation (GuideLLM)**: **CronJob + Manual Job**.
    *   We will implement a `CronJob` scheduled for midnight daily.
    *   We will provide a `Job` template for manual execution (GitOps-able).

## 8. Appendix: Benchmark as a Service (Deep Dive & Architecture Analysis)

We analyzed advanced patterns for "Benchmark as a Service" using **Red Hat OpenShift Pipelines (Tekton)**, referenced from `rh-aiservices-bu/guidellm-pipeline` and `rhoai-genaiops`.

### 8.1 The "Benchmark as a Service" Pattern
In a production GenAIOps platform, benchmarking should not just be a "check once" activity, but a continuous pipeline triggered by:
*   **Model Updates**: New model version pushed to registry.
*   **Runtime Updates**: Change in vLLM version or config.
*   **Schedule**: Daily regression testing.

**Architecture Reference (`rh-aiservices-bu/guidellm-pipeline`):**
1.  **Tekton Task**: Wraps the GuideLLM Docker image.
    *   *Inputs*: Model Endpoint, Rate Limit, Duration, Shape (Poisson/Static).
    *   *Outputs*: Results JSON/CSV stored in a PVC or Object Store.
2.  **Tekton Pipeline**:
    *   Step 1: Provision ephemeral Environment (optional).
    *   Step 2: Run GuideLLM Task.
    *   Step 3: Parse results and push to a Metrics Store (Prometheus pushgateway) or create a Report (S3).
3.  **Visualization**:
    *   **GuideLLM Workbench**: A Streamlit app (from the repo) that reads the artifacts and presents a UI for "What-if" analysis (e.g., "What if I double my request rate?").

### 8.2 Comparison: Job (Demo) vs. Pipeline (Prod)

| Feature | Kubernetes Job / CronJob (Our Demo) | Tekton Pipeline (Advanced) |
| :--- | :--- | :--- |
| **Triggering** | Time-based (Cron) or Manual (kubectl) | Event-based (Git commit, Image push, Webhook) |
| **Artifacts** | Logs (ephemeral), requires sidecar to push results | First-class `Workspaces` (PVC/S3) for reports |
| **Parametrization** | Hardcoded in YAML or ConfigMap | Dynamic params (UI/CLI/Trigger) per run |
| **Visual History** | Hard to see history of runs in Console | Native "PipelineRuns" view in OCP Console |
| **Complexity** | Low (Single YAML) | Medium (Tasks, Pipelines, Triggers, SA) |

### 8.3 Design Decision for Demo
We will stick to the **CronJob/Job** approach for **Step 07** to keep the dependency list low (no need to install OpenShift Pipelines Operator yet). However, we will structure the `Job` command to mimic the Tekton Task logic, making it easy to "lift and shift" into a Pipeline later if we decide to add a "GenAIOps CI/CD" step.

---
*Drafted by Cursor Agent for RHOAI 3.0 Demo Project*
