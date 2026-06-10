# Model Management And Monitoring Patterns

These examples are review patterns. Verify active CRDs, runtime support, model
storage, metrics, and dashboard state before copying patterns into GitOps.

## KServe Progress Deadline

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: <model-name>
spec:
  predictor:
    annotations:
      serving.knative.dev/progress-deadline: 30m
```

Review points:

- Annotation must be under `spec.predictor.annotations`.
- Use when large model pulls or node autoscaling exceed the default deployment
  progress deadline.

## Kueue Queue Label

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: <model-name>
  namespace: <project-namespace>
  labels:
    kueue.x-k8s.io/queue-name: <local-queue-name>
```

Verification:

```bash
oc describe localqueue <local-queue-name> -n <project-namespace>
```

## Multi-Node vLLM Shape

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: <model-name>
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
    serving.kserve.io/autoscalerClass: external
spec:
  predictor:
    model:
      modelFormat:
        name: vLLM
      runtime: vllm-multinode-runtime
      storageUri: oci://<registry>/<org>/<model-image>:<tag-or-digest>
    workerSpec:
      tensorParallelSize: 1
      pipelineParallelSize: 2
```

Review points:

- Technology Preview in the captured guide.
- Current demo default is one GPU worker node, so this is not the default path.
- Do not set extra head pod replicas.

## Metrics-Based Autoscaling Signals

```text
Latency objective, variable sequence lengths:
- TTFT
- ITL
- 1-2 minute window

Uniform sequence lengths:
- end-to-end latency
- 4-5 minute window

Throughput objective:
- vllm:num_requests_waiting > 0.1
```

Review points:

- Start conservatively.
- Tune from realistic load tests.
- Review KEDA `ScaledObject` scale-down behavior for cold start versus cost.

## Monitoring Resources

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: user-workload-monitoring-config
  namespace: openshift-user-workload-monitoring
data:
  config.yaml: |
    prometheus:
      retention: 15d
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
```

Review points:

- Use `rhoai-observability` for the broader observability stack.
- Apply Service Mesh `ServiceMonitor` and `PodMonitor` resources only when
  Service Mesh and Knative/KServe prerequisites exist.

## Grafana Dashboard Inputs

```text
NAMESPACE=<namespace>
MODEL_NAME=<model-name>
```

Review points:

- `MODEL_NAME` must match the model name in the `InferenceService`.
- NVIDIA GPU metrics require the NVIDIA GPU monitoring dashboard.
- vLLM dashboards require the deployed runtime to expose vLLM metrics.

## NIM Model Selection ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-nim-enabled-models
data:
  models: |-
    [
      "<ngc-model-id>"
    ]
```

Patch target:

```yaml
spec:
  modelListConfig:
    name: nvidia-nim-enabled-models
```

Review points:

- ConfigMap must be in the same namespace as the NIM `Account` CR.
- Model IDs must come from NGC Catalog or NGC CLI.

## Existing NIM Metrics Annotations

Graph generation:

```yaml
metadata:
  annotations:
    runtimes.opendatahub.io/nvidia-nim: "true"
```

Metrics collection:

```yaml
spec:
  predictor:
    annotations:
      prometheus.io/path: /metrics
      prometheus.io/port: "8000"
```

Review points:

- These are for existing upgraded NIM deployments that need metrics enabled.
- Newer NIM deployments may already enable metrics and graphs automatically.
