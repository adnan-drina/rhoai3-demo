"""
Eval Summary Component — terminal step that summarizes RAG evaluation results.

Receives per-scenario summaries from run_and_score_tests, logs metrics to the
Dashboard, and highlights the quality delta between pre-RAG and post-RAG scenarios.

This is a RAG quality evaluation, not a benchmark pass/fail gate. The key insight
is the improvement when document context is available (post-RAG) vs without (pre-RAG).
"""

from typing import List, Dict, Any
from kfp.dsl import component, Output, Metrics


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    pip_index_urls=["https://pypi.org/simple"],
)
def eval_summary_component(
    summary: List[Dict[str, Any]],
    run_id: str,
    minio_console_url: str,
    metrics: Output[Metrics],
) -> str:
    """Summarize RAG evaluation results and log metrics to the Dashboard.

    Args:
        summary: Per-scenario results from run_and_score_tests.
        run_id: Evaluation run identifier.
        minio_console_url: External MinIO console URL for report links.
        metrics: KFP Metrics artifact for Dashboard visibility.

    Returns:
        Human-readable summary of the evaluation results.
    """
    print("RAG Evaluation Summary")
    print("=" * 60)
    print(f"  Run ID: {run_id}")
    print(f"  Scenarios: {len(summary)}")

    metrics.log_metric("run_id", run_id)
    metrics.log_metric("scenarios", len(summary))

    pre_rag_good = 0
    pre_rag_total = 0
    post_rag_good = 0
    post_rag_total = 0
    lines = []

    for s in summary:
        scenario = s.get("scenario", "unknown")
        mode = s.get("mode", "unknown")
        tests = s.get("tests", 0)
        pass_rate = s.get("pass_rate", "?")
        scores = s.get("scores", {})

        good = sum(scores.get(l, 0) for l in ("A", "B"))

        if mode == "pre-rag":
            pre_rag_good += good
            pre_rag_total += tests
        else:
            post_rag_good += good
            post_rag_total += tests

        label = f"{scenario} ({mode})"
        print(f"  {label}: {pass_rate}")
        lines.append(f"{label}: {pass_rate}")

    if pre_rag_total > 0:
        pre_pct = round(100 * pre_rag_good / pre_rag_total)
        metrics.log_metric("pre_rag_quality", f"{pre_rag_good}/{pre_rag_total} ({pre_pct}%)")
        print(f"\n  Pre-RAG quality:  {pre_rag_good}/{pre_rag_total} ({pre_pct}% A/B)")

    if post_rag_total > 0:
        post_pct = round(100 * post_rag_good / post_rag_total)
        metrics.log_metric("post_rag_quality", f"{post_rag_good}/{post_rag_total} ({post_pct}%)")
        print(f"  Post-RAG quality: {post_rag_good}/{post_rag_total} ({post_pct}% A/B)")

    if pre_rag_total > 0 and post_rag_total > 0:
        delta = round(100 * post_rag_good / post_rag_total) - round(100 * pre_rag_good / pre_rag_total)
        sign = "+" if delta >= 0 else ""
        metrics.log_metric("rag_improvement", f"{sign}{delta}pp")
        print(f"  RAG improvement:  {sign}{delta} percentage points")

    report_url = f"{minio_console_url}/browser/rhoai-storage/eval-results/{run_id}/"
    metrics.log_metric("reports", report_url)
    print(f"\n  Reports: {report_url}")
    print("=" * 60)

    return " | ".join(lines)
