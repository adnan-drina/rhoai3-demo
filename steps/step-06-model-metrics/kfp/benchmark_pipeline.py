"""
KFP v2 GuideLLM Benchmark Pipeline

Single-step pipeline: runs GuideLLM against a deployed model and
uploads results to S3 for dashboard viewing.

Reuses dspa-rag (step-07) for pipeline execution — no new DSPA needed.
Triggerable from the RHOAI Dashboard: Develop & train -> Pipelines.

Ref: https://developers.redhat.com/articles/2025/12/24/how-deploy-and-benchmark-vllm-guidellm-kubernetes
Ref: https://developers.redhat.com/articles/2026/03/03/practical-strategies-vllm-performance-tuning
"""

import kfp
from kfp import dsl, kubernetes
from pathlib import Path

GUIDELLM_IMAGE = "ghcr.io/vllm-project/guidellm:stable"


@dsl.component(
    base_image=GUIDELLM_IMAGE,
    packages_to_install=["boto3"],
)
def run_benchmark(
    model_name: str,
    rates: str,
    max_seconds: int,
    max_requests: int,
    run_id: str,
) -> str:
    """Run GuideLLM benchmark, print summary, upload results to S3."""
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
    for i, bench in enumerate(benchmarks):
        completed = bench.get("request_totals", {}).get("completed", 0)
        print(f"  Rate level {i+1}: {completed} completed requests")

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


@dsl.pipeline(
    name="guidellm-benchmark",
    description=(
        "GuideLLM model benchmark: graduated concurrency stress test "
        "with TTFT, ITL, throughput metrics. "
        "SLO targets: Granite ITL <=45ms, Mistral ITL <=55ms (L4 hardware floor)."
    ),
    pipeline_root="s3://pipelines/",
)
def guidellm_benchmark_pipeline(
    model_name: str = "granite-8b-agent",
    rates: str = "1,3,5,8,10",
    max_seconds: int = 60,
    max_requests: int = 50,
    run_id: str = "bench",
    s3_report_secret: str = "minio-connection",
):
    bench = run_benchmark(
        model_name=model_name,
        rates=rates,
        max_seconds=max_seconds,
        max_requests=max_requests,
        run_id=run_id,
    )
    bench.set_caching_options(False)
    bench.set_cpu_request("500m")
    bench.set_cpu_limit("2")
    bench.set_memory_request("1Gi")
    bench.set_memory_limit("2Gi")

    kubernetes.use_secret_as_env(
        bench,
        secret_name=s3_report_secret,
        secret_key_to_env={
            "AWS_S3_ENDPOINT": "AWS_S3_ENDPOINT",
            "AWS_ACCESS_KEY_ID": "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY": "AWS_SECRET_ACCESS_KEY",
            "AWS_S3_BUCKET": "AWS_S3_BUCKET",
            "AWS_DEFAULT_REGION": "AWS_DEFAULT_REGION",
        },
    )


if __name__ == "__main__":
    script_dir = Path(__file__).parent.resolve()
    step_dir = script_dir.parent
    repo_root = step_dir.parent.parent
    artifacts_dir = repo_root / "artifacts"
    artifacts_dir.mkdir(exist_ok=True)

    out = artifacts_dir / "guidellm-benchmark.yaml"
    kfp.compiler.Compiler().compile(
        pipeline_func=guidellm_benchmark_pipeline,
        package_path=str(out),
    )
    print(f"Pipeline compiled: {out}")
