"""
Ingestion Summary Component — reads the ingestion log from the shared PVC
and reports final document counts and names.

Runs after all ParallelFor inserts complete via .after(insert).
"""

from kfp.dsl import component, Output, Metrics


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    pip_index_urls=["https://pypi.org/simple"],
)
def ingestion_summary_component(
    vector_db_id: str,
    metrics: Output[Metrics],
) -> str:
    """Read ingestion results from PVC log and report metrics.

    Args:
        vector_db_id: Target vector store collection name.
        metrics: KFP Metrics artifact for Dashboard visibility.

    Returns:
        Human-readable summary of the ingestion run.
    """
    import json
    import os

    log_path = "/shared-data/ingestion-log.jsonl"

    results = []
    if os.path.exists(log_path):
        with open(log_path) as f:
            for line in f:
                line = line.strip()
                if line:
                    results.append(json.loads(line))

    succeeded = [r for r in results if r.get("status") == "success"]
    skipped = [r for r in results if r.get("status") == "skipped"]
    errored = [r for r in results if r.get("status") == "error"]

    print("RAG Ingestion Summary")
    print("=" * 60)
    print(f"  Vector DB:  {vector_db_id}")
    print(f"  Total:      {len(results)}")
    print(f"  Succeeded:  {len(succeeded)}")
    print(f"  Skipped:    {len(skipped)}")
    print(f"  Errored:    {len(errored)}")

    if succeeded:
        print(f"\n  Ingested documents:")
        for r in succeeded:
            print(f"    - {r['document']}")

    print("=" * 60)

    metrics.log_metric("vector_db_id", vector_db_id)
    metrics.log_metric("documents_total", len(results))
    metrics.log_metric("documents_ingested", len(succeeded))
    metrics.log_metric("documents_skipped", len(skipped))
    metrics.log_metric("documents_errored", len(errored))
    for i, r in enumerate(succeeded):
        metrics.log_metric(f"doc_{i+1}", r["document"])

    return f"{len(succeeded)}/{len(results)} documents ingested into {vector_db_id}"
