"""
KFP v2 GuideLLM Benchmark Pipeline

Single-step pipeline: runs GuideLLM against a deployed model and
uploads results to S3 for dashboard viewing.

Components are in kfp/components/ following KFP modular best practices.
Reuses dspa-rag (step-07) for pipeline execution — no new DSPA needed.
Triggerable from the RHOAI Dashboard: Develop & train -> Pipelines.

Ref: https://developers.redhat.com/articles/2025/12/24/how-deploy-and-benchmark-vllm-guidellm-kubernetes
Ref: https://developers.redhat.com/articles/2026/03/03/practical-strategies-vllm-performance-tuning
"""

import kfp
from kfp import dsl, kubernetes
from kfp.dsl import PipelineTask
from pathlib import Path

from components.run_benchmark import run_benchmark

MINIO_SECRET = "minio-connection"


def _set_resources(
    task: PipelineTask,
    cpu_req: str = "500m", cpu_lim: str = "2",
    mem_req: str = "1Gi", mem_lim: str = "2Gi",
) -> None:
    task.set_cpu_request(cpu_req)
    task.set_cpu_limit(cpu_lim)
    task.set_memory_request(mem_req)
    task.set_memory_limit(mem_lim)


def _inject_minio(task: PipelineTask) -> None:
    kubernetes.use_secret_as_env(
        task,
        secret_name=MINIO_SECRET,
        secret_key_to_env={
            "AWS_S3_ENDPOINT": "AWS_S3_ENDPOINT",
            "AWS_ACCESS_KEY_ID": "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY": "AWS_SECRET_ACCESS_KEY",
            "AWS_S3_BUCKET": "AWS_S3_BUCKET",
            "AWS_DEFAULT_REGION": "AWS_DEFAULT_REGION",
        },
    )


@dsl.pipeline(
    name="bench-granite-8b",
    description=(
        "Granite 8B Agent benchmark (1x L4 FP8). "
        "Rates: 1,3,5,8,10 RPS. SLO: TTFT <=150ms, ITL <=45ms."
    ),
    pipeline_root="s3://pipelines/",
)
def granite_benchmark_pipeline(
    model_name: str = "granite-8b-agent",
    rates: str = "1,3,5,8,10",
    max_seconds: int = 60,
    max_requests: int = 50,
    run_id: str = "bench-granite",
):
    # --- Step 1: Run Benchmark ---
    bench = run_benchmark(
        model_name=model_name,
        rates=rates,
        max_seconds=max_seconds,
        max_requests=max_requests,
        run_id=run_id,
    )
    _inject_minio(bench)
    _set_resources(bench)
    bench.set_caching_options(False)


@dsl.pipeline(
    name="bench-mistral-bf16",
    description=(
        "Mistral Small 24B BF16 benchmark (4x L4 TP=4). "
        "Rates: 1,3,5,8,10,15 RPS. SLO: TTFT <=500ms, ITL <=55ms."
    ),
    pipeline_root="s3://pipelines/",
)
def mistral_benchmark_pipeline(
    model_name: str = "mistral-3-bf16",
    rates: str = "1,3,5,8,10,15",
    max_seconds: int = 60,
    max_requests: int = 50,
    run_id: str = "bench-mistral",
):
    # --- Step 1: Run Benchmark ---
    bench = run_benchmark(
        model_name=model_name,
        rates=rates,
        max_seconds=max_seconds,
        max_requests=max_requests,
        run_id=run_id,
    )
    _inject_minio(bench)
    _set_resources(bench)
    bench.set_caching_options(False)


if __name__ == "__main__":
    script_dir = Path(__file__).parent.resolve()
    step_dir = script_dir.parent
    repo_root = step_dir.parent.parent
    artifacts_dir = repo_root / "artifacts"
    artifacts_dir.mkdir(exist_ok=True)

    compiler = kfp.compiler.Compiler()

    for pipeline_func, filename in [
        (granite_benchmark_pipeline, "bench-granite-8b.yaml"),
        (mistral_benchmark_pipeline, "bench-mistral-bf16.yaml"),
    ]:
        out = artifacts_dir / filename
        compiler.compile(pipeline_func=pipeline_func, package_path=str(out))
        print(f"Pipeline compiled: {out}")
