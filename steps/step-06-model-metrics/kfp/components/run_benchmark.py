"""
Run Benchmark Component — executes GuideLLM against a deployed model.

Uses the GuideLLM container image directly as base_image. This step only
runs the benchmark binary and returns the raw results JSON. Upload and
summary are handled by downstream atomic steps.
"""

from kfp.dsl import component

GUIDELLM_IMAGE = "ghcr.io/vllm-project/guidellm:stable"


@component(
    base_image=GUIDELLM_IMAGE,
)
def run_benchmark(
    model_name: str,
    rates: str,
    max_seconds: int,
    max_requests: int,
) -> str:
    """Run GuideLLM benchmark and return raw results JSON.

    Args:
        model_name: Name of the deployed InferenceService to benchmark.
        rates: Comma-separated request rates (RPS) to test.
        max_seconds: Maximum seconds per rate level.
        max_requests: Maximum requests per rate level.

    Returns:
        Raw GuideLLM results as a JSON string.
    """
    import json
    import os

    os.environ.setdefault("HOME", "/tmp")
    os.environ.setdefault("HF_HOME", "/tmp/.cache/huggingface")

    target = f"http://{model_name}-predictor.private-ai.svc.cluster.local:8080/v1"
    results_path = "/tmp/results.json"

    prompts_json = json.dumps([
        {"prompt": "Explain the difference between containers and virtual machines in detail."},
        {"prompt": "Write a Python function that implements a binary search tree with insert, delete, and search."},
        {"prompt": "What are the key benefits of using Kubernetes for microservices architecture?"},
        {"prompt": "Describe the CAP theorem and its implications for distributed databases."},
        {"prompt": "Write a bash script that monitors CPU usage and sends alerts when usage exceeds 80%."},
        {"prompt": "Explain how the TLS 1.3 handshake works step by step."},
        {"prompt": "What is GitOps and how does ArgoCD implement the GitOps pattern on OpenShift?"},
        {"prompt": "Describe the SOLID principles in software engineering with practical examples."},
        {"prompt": "How does the KV cache work in transformer-based language models during inference?"},
        {"prompt": "Explain the Red Hat OpenShift AI platform architecture and its key components."},
    ], indent=2)

    script = f"""#!/bin/bash
cat > /tmp/prompts.json << 'PROMPTEOF'
{prompts_json}
PROMPTEOF
guidellm benchmark run \
  --target "{target}" \
  --model "{model_name}" \
  --data /tmp/prompts.json \
  --rate "{rates}" \
  --rate-type constant \
  --max-seconds {max_seconds} \
  --max-requests {max_requests} \
  --output-path "{results_path}" \
  --disable-console-interactive || true
echo "Benchmark complete for {model_name}"
"""
    with open("/tmp/run_benchmark.sh", "w") as f:
        f.write(script)
    os.chmod("/tmp/run_benchmark.sh", 0o755)
    exit_code = os.system("/bin/bash /tmp/run_benchmark.sh")
    if exit_code != 0:
        print(f"Benchmark script exited with code {exit_code}")

    if not os.path.exists(results_path):
        raise RuntimeError(f"{results_path} not found — GuideLLM benchmark failed")

    with open(results_path) as f:
        return f.read()
