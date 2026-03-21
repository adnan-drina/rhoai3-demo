"""
Benchmark Summary Component — parses GuideLLM results and logs
performance metrics to the RHOAI Dashboard.

Extracts TTFT, ITL, throughput, and request counts from the GuideLLM
JSON output. These are the key metrics for evaluating model serving
performance under load.
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
    """Parse GuideLLM results and log serving performance metrics.

    Args:
        results_json: Raw GuideLLM results as a JSON string.
        model_name: Name of the benchmarked model.
        s3_uri: S3 URI where results were uploaded.
        metrics: KFP Metrics artifact for Dashboard visibility.

    Returns:
        Human-readable summary of the benchmark.
    """
    import json

    def safe_get(d, *keys, default=None):
        for k in keys:
            if isinstance(d, dict):
                d = d.get(k)
            else:
                return default
            if d is None:
                return default
        return d

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
        errored = totals.get("errored", 0)
        total_completed += completed

        sched = bench.get("scheduler", {})
        rate = sched.get("rate", sched.get("args", {}).get("rate", "?"))

        m = bench.get("metrics", {})
        successful = m.get("successful", m)

        ttft = safe_get(successful, "time_to_first_token_ms", default={})
        itl = safe_get(successful, "inter_token_latency_ms", default={})
        tpot = safe_get(successful, "time_per_output_token_ms", default={})
        out_tok = safe_get(successful, "output_tokens_per_second", default={})
        req_lat = safe_get(successful, "request_latency_seconds", default={})

        ttft_med = ttft.get("median") or ttft.get("p50")
        ttft_p99 = ttft.get("p99")
        itl_med = itl.get("median") or itl.get("p50")
        itl_p99 = itl.get("p99")
        throughput = out_tok.get("mean") if isinstance(out_tok, dict) else out_tok

        label = f"rate_{i+1}"
        print(f"\n  [{label}] rate={rate} RPS, {completed} completed, {errored} errored")

        if ttft_med is not None:
            print(f"    TTFT:       median={ttft_med:.0f}ms  p99={ttft_p99:.0f}ms" if ttft_p99 else f"    TTFT:       median={ttft_med:.0f}ms")
        if itl_med is not None:
            print(f"    ITL:        median={itl_med:.1f}ms  p99={itl_p99:.1f}ms" if itl_p99 else f"    ITL:        median={itl_med:.1f}ms")
        if throughput is not None:
            print(f"    Throughput: {throughput:.0f} tok/s")

    metrics.log_metric("total_completed", total_completed)

    if benchmarks:
        last = benchmarks[-1]
        m = last.get("metrics", {})
        successful = m.get("successful", m)

        ttft = safe_get(successful, "time_to_first_token_ms", default={})
        itl = safe_get(successful, "inter_token_latency_ms", default={})
        out_tok = safe_get(successful, "output_tokens_per_second", default={})

        if isinstance(ttft, dict) and (ttft.get("median") or ttft.get("p50")):
            val = ttft.get("median") or ttft.get("p50")
            metrics.log_metric("ttft_median_ms", round(val, 1))
        if isinstance(ttft, dict) and ttft.get("p99"):
            metrics.log_metric("ttft_p99_ms", round(ttft["p99"], 1))
        if isinstance(itl, dict) and (itl.get("median") or itl.get("p50")):
            val = itl.get("median") or itl.get("p50")
            metrics.log_metric("itl_median_ms", round(val, 1))
        if isinstance(itl, dict) and itl.get("p99"):
            metrics.log_metric("itl_p99_ms", round(itl["p99"], 1))
        if isinstance(out_tok, dict) and out_tok.get("mean"):
            metrics.log_metric("throughput_tok_s", round(out_tok["mean"], 1))
        elif isinstance(out_tok, (int, float)):
            metrics.log_metric("throughput_tok_s", round(out_tok, 1))

    print(f"\n  Total: {total_completed} completed requests across {len(benchmarks)} rate levels")
    print("=" * 60)

    return f"{model_name}: {len(benchmarks)} rates, {total_completed} requests"
