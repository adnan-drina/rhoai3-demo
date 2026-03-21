"""
Benchmark Summary Component — reads GuideLLM results from the shared PVC
and logs serving performance metrics (TTFT, ITL, throughput) to the Dashboard.

GuideLLM JSON structure:
  benchmarks[].metrics.request_totals = {successful, errored, incomplete, total}
  benchmarks[].metrics.time_to_first_token_ms.successful = {mean, median, p99, ...}
  benchmarks[].metrics.inter_token_latency_ms.successful = {mean, median, p99, ...}
  benchmarks[].metrics.output_tokens_per_second.successful = {mean, median, ...}
"""

from kfp.dsl import component, Output, Metrics


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
)
def benchmark_summary(
    results_path: str,
    model_name: str,
    s3_uri: str,
    metrics: Output[Metrics],
) -> str:
    """Parse GuideLLM results and log serving performance metrics.

    Args:
        results_path: Path to results JSON on the shared PVC.
        model_name: Name of the benchmarked model.
        s3_uri: S3 URI where results were uploaded.
        metrics: KFP Metrics artifact for Dashboard visibility.

    Returns:
        Human-readable summary of the benchmark.
    """
    import json
    import os

    def safe_get(d, *keys, default=None):
        for k in keys:
            if isinstance(d, dict):
                d = d.get(k)
            else:
                return default
            if d is None:
                return default
        return d

    if not os.path.exists(results_path):
        metrics.log_metric("error", "results file not found")
        return "ERROR: results not found"

    with open(results_path) as f:
        data = json.load(f)

    benchmarks = data.get("benchmarks", [])

    print("GuideLLM Benchmark Summary")
    print("=" * 60)
    print(f"  Model: {model_name}")
    print(f"  Rate levels: {len(benchmarks)}")
    print(f"  Results: {s3_uri}")

    metrics.log_metric("model", model_name)
    metrics.log_metric("rate_levels", len(benchmarks))

    total_successful = 0

    for i, bench in enumerate(benchmarks):
        m = bench.get("metrics", {})

        rt = m.get("request_totals", {})
        successful = rt.get("successful", 0)
        errored = rt.get("errored", 0)
        total_successful += successful

        ttft_stats = safe_get(m, "time_to_first_token_ms", "successful", default={})
        itl_stats = safe_get(m, "inter_token_latency_ms", "successful", default={})
        out_tok_stats = safe_get(m, "output_tokens_per_second", "successful", default={})

        ttft_med = ttft_stats.get("median") if isinstance(ttft_stats, dict) else None
        itl_med = itl_stats.get("median") if isinstance(itl_stats, dict) else None
        throughput = out_tok_stats.get("mean") if isinstance(out_tok_stats, dict) else None

        print(f"\n  [rate_{i+1}] {successful} successful, {errored} errored")
        if ttft_med is not None:
            p99 = ttft_stats.get("percentiles", {}).get("99") or ttft_stats.get("max")
            print(f"    TTFT:       median={ttft_med:.0f}ms" + (f"  p99={p99:.0f}ms" if p99 else ""))
        if itl_med is not None:
            p99 = itl_stats.get("percentiles", {}).get("99") or itl_stats.get("max")
            print(f"    ITL:        median={itl_med:.1f}ms" + (f"  p99={p99:.1f}ms" if p99 else ""))
        if throughput is not None:
            print(f"    Throughput: {throughput:.0f} tok/s")

    metrics.log_metric("total_successful", total_successful)

    if benchmarks:
        last_m = benchmarks[-1].get("metrics", {})

        ttft = safe_get(last_m, "time_to_first_token_ms", "successful", default={})
        itl = safe_get(last_m, "inter_token_latency_ms", "successful", default={})
        out_tok = safe_get(last_m, "output_tokens_per_second", "successful", default={})

        if isinstance(ttft, dict) and ttft.get("median"):
            metrics.log_metric("ttft_median_ms", round(ttft["median"], 1))
        if isinstance(ttft, dict) and ttft.get("percentiles", {}).get("99"):
            metrics.log_metric("ttft_p99_ms", round(ttft["percentiles"]["99"], 1))
        if isinstance(itl, dict) and itl.get("median"):
            metrics.log_metric("itl_median_ms", round(itl["median"], 1))
        if isinstance(itl, dict) and itl.get("percentiles", {}).get("99"):
            metrics.log_metric("itl_p99_ms", round(itl["percentiles"]["99"], 1))
        if isinstance(out_tok, dict) and out_tok.get("mean"):
            metrics.log_metric("throughput_tok_s", round(out_tok["mean"], 1))

    print(f"\n  Total: {total_successful} successful requests across {len(benchmarks)} rate levels")
    print("=" * 60)

    return f"{model_name}: {len(benchmarks)} rates, {total_successful} requests"
