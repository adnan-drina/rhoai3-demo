"""
Benchmark Summary Component — parses GuideLLM results and logs metrics
to the RHOAI Dashboard for visibility.
"""

from kfp.dsl import component, Output, Metrics


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
)
def benchmark_summary(
    results_json: str,
    model_name: str,
    s3_uri: str,
    metrics: Output[Metrics],
) -> str:
    """Parse GuideLLM results and log metrics to the Dashboard.

    Args:
        results_json: Raw GuideLLM results as a JSON string.
        model_name: Name of the benchmarked model.
        s3_uri: S3 URI where results were uploaded.
        metrics: KFP Metrics artifact for Dashboard visibility.

    Returns:
        Human-readable summary of the benchmark.
    """
    import json

    data = json.loads(results_json)
    benchmarks = data.get("benchmarks", [])

    print("GuideLLM Benchmark Summary")
    print("=" * 60)
    print(f"  Model: {model_name}")
    print(f"  Rate levels: {len(benchmarks)}")
    print(f"  Results: {s3_uri}")

    metrics.log_metric("model", model_name)
    metrics.log_metric("rate_levels", len(benchmarks))

    total_completed = 0
    for i, bench in enumerate(benchmarks):
        totals = bench.get("request_totals", {})
        completed = totals.get("completed", 0)
        total_completed += completed
        print(f"  Rate {i+1}: {completed} completed requests")

    metrics.log_metric("total_completed_requests", total_completed)

    if benchmarks:
        last = benchmarks[-1]
        totals = last.get("request_totals", {})
        metrics.log_metric("peak_completed", totals.get("completed", 0))
        metrics.log_metric("peak_errored", totals.get("errored", 0))

    metrics.log_metric("s3_uri", s3_uri)

    summary = f"{model_name}: {len(benchmarks)} rate levels, {total_completed} total requests"
    print(f"\n  {summary}")
    print("=" * 60)

    return summary
