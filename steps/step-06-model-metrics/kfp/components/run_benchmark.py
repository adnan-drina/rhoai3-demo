"""
Run Benchmark Component — executes GuideLLM against a deployed model
and uploads results to S3 for dashboard viewing.

Uses the GuideLLM container image directly as base_image.
"""

from kfp.dsl import component, Output, Metrics

GUIDELLM_IMAGE = "ghcr.io/vllm-project/guidellm:stable"


@component(
    base_image=GUIDELLM_IMAGE,
    packages_to_install=["boto3>=1.34.0"],
)
def run_benchmark(
    model_name: str,
    rates: str,
    max_seconds: int,
    max_requests: int,
    run_id: str,
    metrics: Output[Metrics] = None,
) -> str:
    """Run GuideLLM benchmark, print summary, upload results to S3.

    Args:
        model_name: Name of the deployed InferenceService to benchmark.
        rates: Comma-separated request rates (RPS) to test.
        max_seconds: Maximum seconds per rate level.
        max_requests: Maximum requests per rate level.
        run_id: Unique identifier for grouping results in S3.
        metrics: KFP Metrics artifact for Dashboard visibility.

    Returns:
        S3 URI of uploaded results, or a status message if upload was skipped.
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
        return f"ERROR: {results_path} not found — benchmark may have failed"

    with open(results_path) as f:
        data = json.load(f)

    benchmarks = data.get("benchmarks", [])
    print(f"\n{'=' * 60}")
    print(f"GuideLLM Summary: {model_name} ({len(benchmarks)} rate levels)")
    print(f"{'=' * 60}")
    total_completed = 0
    for i, bench in enumerate(benchmarks):
        completed = bench.get("request_totals", {}).get("completed", 0)
        total_completed += completed
        print(f"  Rate level {i+1}: {completed} completed requests")

    if metrics is not None:
        metrics.log_metric("model_name", model_name)
        metrics.log_metric("rate_levels", len(benchmarks))
        metrics.log_metric("total_completed_requests", total_completed)

    endpoint = os.environ.get("AWS_S3_ENDPOINT", "")
    if endpoint:
        import boto3

        s3 = boto3.client(
            "s3",
            endpoint_url=endpoint,
            aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID"),
            aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY"),
            region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        )
        bucket = os.environ.get("AWS_S3_BUCKET", "rhoai-storage")
        key = f"benchmark-results/{run_id}/{model_name}-results.json"
        s3.upload_file(results_path, bucket, key)
        msg = f"s3://{bucket}/{key}"
        print(f"Results uploaded: {msg}")
        return msg

    return "Results printed (no S3 credentials configured)"
