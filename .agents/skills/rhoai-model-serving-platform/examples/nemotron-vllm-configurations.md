# Nemotron 3 Nano vLLM Configurations

Use these examples when reviewing or rebuilding the rhoai3-demo Nemotron 3
Nano serving path. They combine the Red Hat AI quickstart pattern with the
working `rhoai3-coding-demo` Nemotron deployment.

Sources:

- Red Hat AI MaaS code assistant quickstart:
  https://docs.redhat.com/en/learn/ai-quickstarts/rh-maas-code-assistant
- Source repository:
  https://github.com/rh-ai-quickstart/maas-code-assistant
- Local reference implementation:
  `rhoai3-coding-demo/gitops/stages/030-private-model-serving/base/models/nemotron-3-nano-30b.yaml`

Official RHOAI 3.4 documentation and live CRD schemas remain product authority.
Use these examples as implementation evidence and verify API versions before
committing long-lived GitOps.

## Model And Runtime Contract

| Field | Demo value |
|-------|------------|
| Model name | `nemotron-3-nano-30b-a3b` |
| Display name | `NVIDIA Nemotron 3 Nano 30B A3B FP8` |
| Model source | `oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0` |
| Accelerator | `nvidia.com/gpu` |
| GPU shape | one L40S-class GPU per replica |
| CPU request/limit | `2` / `4` |
| Memory request/limit | `16Gi` / `24Gi` |
| Stage 210 serving context | `8192` tokens by default |
| Shared memory volume | `emptyDir.medium: Memory`, `sizeLimit: 2Gi`, mounted at `/dev/shm` |

## Required Tool-Calling Arguments

These arguments are required for the demo's Nemotron tool-calling and reasoning
behavior:

```text
--enable-auto-tool-choice
--tool-call-parser=qwen3_coder
--trust-remote-code
--reasoning-parser-plugin=/mnt/models/nano_v3_reasoning_parser.py
--reasoning-parser=nano_v3
```

Review points:

- `--enable-auto-tool-choice` lets vLLM decide when to emit tool calls.
- `--tool-call-parser=qwen3_coder` matches the Nemotron parser behavior used by
  the working code-assistant deployment.
- The reasoning parser flags expose Nemotron reasoning metadata in compatible
  OpenAI-style responses.
- Keep `--trust-remote-code` limited to the trusted Red Hat registry modelcar.

## Direct InferenceService Profile

Stage 210 uses direct KServe `InferenceService` for baseline serving. The model
uses the RHOAI-provided vLLM ServingRuntime created from the active cluster
template, while the deployment owns the model-specific args and resources.

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: nvidia-nemotron-3-nano-30b-a3b
  namespace: demo-sandbox
  labels:
    opendatahub.io/dashboard: "true"
    networking.kserve.io/visibility: exposed
    kueue.x-k8s.io/queue-name: lq-gpu-reserved-demo
  annotations:
    openshift.io/display-name: NVIDIA-Nemotron-3-Nano-30B-A3B-FP8 - Version 1
    opendatahub.io/model-type: generative
    opendatahub.io/hardware-profile-name: gpu-reserved-demo
    opendatahub.io/hardware-profile-namespace: redhat-ods-applications
    modelFormat: vLLM
    serving.kserve.io/deploymentMode: Standard
    security.opendatahub.io/enable-auth: "false"
spec:
  predictor:
    deploymentStrategy:
      type: Recreate
    minReplicas: 1
    maxReplicas: 1
    model:
      args:
        - --enable-force-include-usage
        - --disable-uvicorn-access-log
        - --enable-prefix-caching
        - --max-model-len=8192
        - --max-num-batched-tokens=8192
        - --enable-auto-tool-choice
        - --tool-call-parser=qwen3_coder
        - --trust-remote-code
        - --reasoning-parser-plugin=/mnt/models/nano_v3_reasoning_parser.py
        - --reasoning-parser=nano_v3
      modelFormat:
        name: vLLM
      resources:
        requests:
          cpu: "2"
          memory: 16Gi
          nvidia.com/gpu: "1"
        limits:
          cpu: "4"
          memory: 24Gi
          nvidia.com/gpu: "1"
      runtime: <vllm-serving-runtime-name>
      storageUri: oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0
```

Review points:

- Use this path for Stage 210 baseline serving and GuideLLM/Grafana evidence.
- Keep endpoint auth disabled only for the controlled Stage 210 baseline path.
  Governed shared access belongs behind MaaS.
- Recreate strategy avoids two large model replicas competing for one GPU
  during config changes.

## MaaS LLMInferenceService Profile

Stage 220 should use `LLMInferenceService` when publishing Nemotron through
MaaS. This shape is copied from the working code-assistant deployment and must
be verified against the installed RHOAI 3.4 CRD before committing.

```yaml
apiVersion: serving.kserve.io/v1alpha2
kind: LLMInferenceService
metadata:
  name: nemotron-3-nano-30b-a3b
  namespace: models-as-a-service
  annotations:
    openshift.io/display-name: NVIDIA Nemotron 3 Nano 30B A3B FP8
    opendatahub.io/model-type: generative
    security.opendatahub.io/enable-auth: "true"
  labels:
    inference.optimization/acceleratorName: L40S
    kueue.x-k8s.io/queue-name: lq-gpu-reserved-demo
    llm-d.ai/deployment-mode: single-gpu-per-replica
    opendatahub.io/dashboard: "true"
    opendatahub.io/genai-asset: "true"
spec:
  model:
    name: nemotron-3-nano-30b-a3b
    uri: oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0
  replicas: 1
  router:
    gateway:
      refs:
        - name: maas-default-gateway
          namespace: openshift-ingress
    route: {}
    scheduler:
      pool:
        spec:
          endpointPickerRef:
            failureMode: FailOpen
            group: ""
            kind: Service
            name: nemotron-3-nano-30b-a3b-epp-service
            port:
              number: 9002
          selector:
            matchLabels:
              app.kubernetes.io/name: nemotron-3-nano-30b-a3b
              app.kubernetes.io/part-of: llminferenceservice
              kserve.io/component: workload
          targetPorts:
            - number: 8000
  template:
    containers:
      - name: main
        image: registry.redhat.io/rhaii/vllm-cuda-rhel9@sha256:ad06abf3bb5235ebb5b2df84cd1b9fd09e823f0ff2eebfc82bb4590275ccfe0b
        command:
          - python
          - -m
          - vllm.entrypoints.openai.api_server
        args:
          - "--served-model-name={{.Name}}"
          - --model=/mnt/models
          - --enable-ssl-refresh
          - --ssl-certfile=/var/run/kserve/tls/tls.crt
          - --ssl-keyfile=/var/run/kserve/tls/tls.key
          - --enable-force-include-usage
          - --disable-uvicorn-access-log
          - --enable-prefix-caching
          - --max-model-len=8192
          - --max-num-batched-tokens=8192
          - --enable-auto-tool-choice
          - --tool-call-parser=qwen3_coder
          - --trust-remote-code
          - --reasoning-parser-plugin=/mnt/models/nano_v3_reasoning_parser.py
          - --reasoning-parser=nano_v3
        resources:
          requests:
            cpu: "2"
            memory: 16Gi
            nvidia.com/gpu: "1"
          limits:
            cpu: "4"
            memory: 24Gi
            nvidia.com/gpu: "1"
```

Review points:

- Confirm whether the active cluster serves `LLMInferenceService` as
  `v1alpha1`, `v1alpha2`, or another version before authoring GitOps.
- Verify the active RHOAI 3.4 vLLM image or installed template before pinning an
  image digest.
- Keep the Gateway, scheduler, MaaSModelRef, subscription, and auth-policy
  resources together in the Stage 220 plan.
- For this repo, Stage 220 owns the local Nemotron backend in
  `models-as-a-service` and removes stale direct `demo-sandbox` serving
  resources before reconciling the MaaS-owned `LLMInferenceService`.
- Use the Stage 210 `8192` token default as the initial MaaS serving envelope
  until RAG-specific benchmarks justify a larger context.

## Validation

For direct Stage 210 serving:

```bash
oc get inferenceservice nvidia-nemotron-3-nano-30b-a3b -n demo-sandbox \
  -o json | jq '.spec.predictor.model | {args, resources}'
```

The response must include `--enable-auto-tool-choice`,
`--tool-call-parser=qwen3_coder`, and `--reasoning-parser=nano_v3`.

For endpoint smoke testing, use a chat completion request that asks for a tool
call and includes a tool schema. A compliant response should include
`choices[0].message.tool_calls` rather than plain text only.
