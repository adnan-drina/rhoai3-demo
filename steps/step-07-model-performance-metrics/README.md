# Step 07: Model Performance Metrics

This step transforms the RHOAI platform from a simple runtime into a measured, observable production system. We introduce specific tools to measure the "Economic Throughput" of our models and define "Breaking Point" limits.

## 🎯 Objectives
*   **Deploy Observability Stack**: User-Managed Grafana + Prometheus for high-resolution metrics.
*   **Establish Baselines**: Measure TTFT (Time To First Token) and TPOT (Time Per Output Token).
*   **Benchmark Saturation**: Use **GuideLLM** to stress-test the system until it breaks (Queue > 0).
*   **Compare Quantization**: Prove that the INT4 model (1 GPU) delivers higher tokens-per-dollar than BF16 (4 GPUs).

## 🏗️ Architecture
We use a **Layered Monitoring Approach**:
1.  **Infrastructure**: NVIDIA DCGM (Power, Temp, Memory).
2.  **Platform**: OpenShift Monitoring (ServiceMonitor).
3.  **Application**: vLLM Metrics (Request Queue, KV Cache).
4.  **Testing**: GuideLLM (Synthetic Load Generator).

For deep architectural details, see [PLAN.md](./PLAN.md).

## 🚀 Deployment

### 1. Prerequisites
*   **Step 05 Completed**: You must have vLLM models deployed (`mistral-3-bf16` or `mistral-3-int4`).
*   **Cluster Admin**: Required to create RBAC for Prometheus scraping.

### 2. Run Deployment
```bash
./deploy.sh
```
This script will:
*   Create the `step-07-model-performance-metrics` ArgoCD application.
*   Deploy Grafana and Prometheus to `private-ai`.
*   Configure Dashboards and Datasources.

### 3. Verification

**Access Grafana:**
```bash
# Get the URL
oc get route grafana -n private-ai
```
*   **Username/Password**: Anonymous access enabled (Admin role).

**Dashboards to Check:**
1.  **vLLM Production Metrics**: Main view of system health.
2.  **GPU Health (DCGM)**: Power draw and fan speeds.

## 🧪 Benchmarking (GuideLLM)

We include a `CronJob` that runs a daily "Sweep" to test performance limits.

### Trigger a Manual Run
```bash
oc create job --from=cronjob/guidellm-daily manual-benchmark-01 -n private-ai
```

### View Results
Results are stored in the `guidellm-results` PVC.
```bash
# Create a viewer pod to inspect results
oc run result-viewer --image=ubi9 --restart=Never --overrides='
{
  "spec": {
    "containers": [{
      "name": "viewer",
      "image": "registry.access.redhat.com/ubi9/ubi",
      "command": ["sleep", "3600"],
      "volumeMounts": [{
        "mountPath": "/results",
        "name": "data"
      }]
    }],
    "volumes": [{
      "name": "data",
      "persistentVolumeClaim": {
        "claimName": "guidellm-results"
      }
    }]
  }
}' -n private-ai

# List files
oc exec result-viewer -n private-ai -- ls -l /results
```

## 📚 References
*   [GuideLLM Repository](https://github.com/neuralmagic/guidellm)
*   [vLLM Metrics Guide](https://docs.vllm.ai/en/latest/serving/metrics.html)
*   [RHOAI Monitoring Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/managing_and_monitoring_models/index)

