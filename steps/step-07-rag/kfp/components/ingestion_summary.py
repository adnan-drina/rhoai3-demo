"""
Ingestion Summary Component — waits for all parallel inserts to write
their results to /shared-data/ingestion-log.jsonl, then reports
final document counts and names.

Workaround for RHOAI 3.3 not supporting dsl.Collected: the component
polls the PVC log file until expected_count entries are present.
"""

from kfp.dsl import component, Output, Metrics


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    pip_index_urls=["https://pypi.org/simple"],
)
def ingestion_summary_component(
    expected_count: int,
    vector_db_id: str,
    metrics: Output[Metrics],
) -> str:
    """Wait for all documents to be processed, then report results.

    Args:
        expected_count: Number of documents expected (from download step).
        vector_db_id: Target vector store collection name.
        metrics: KFP Metrics artifact for Dashboard visibility.

    Returns:
        Human-readable summary of the ingestion run.
    """
    import json
    import time
    import os

    log_path = "/shared-data/ingestion-log.jsonl"
    timeout = 900
    poll_interval = 10
    elapsed = 0

    print(f"Waiting for {expected_count} documents to complete...")

    while elapsed < timeout:
        if os.path.exists(log_path):
            with open(log_path) as f:
                lines = [l.strip() for l in f if l.strip()]
            if len(lines) >= expected_count:
                break
            print(f"  {len(lines)}/{expected_count} done ({elapsed}s)")
        time.sleep(poll_interval)
        elapsed += poll_interval

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

    print("\nRAG Ingestion Summary")
    print("=" * 60)
    print(f"  Vector DB:  {vector_db_id}")
    print(f"  Expected:   {expected_count}")
    print(f"  Processed:  {len(results)}")
    print(f"  Succeeded:  {len(succeeded)}")
    print(f"  Skipped:    {len(skipped)}")
    print(f"  Errored:    {len(errored)}")

    if succeeded:
        print(f"\n  Ingested documents:")
        for r in succeeded:
            print(f"    - {r['document']}")

    print("=" * 60)

    metrics.log_metric("vector_db_id", vector_db_id)
    metrics.log_metric("documents_expected", expected_count)
    metrics.log_metric("documents_ingested", len(succeeded))
    metrics.log_metric("documents_skipped", len(skipped))
    metrics.log_metric("documents_errored", len(errored))
    for i, r in enumerate(succeeded):
        metrics.log_metric(f"doc_{i+1}", r["document"])

    # Clean up log for next run
    if os.path.exists(log_path):
        os.remove(log_path)

    return f"{len(succeeded)}/{expected_count} documents ingested into {vector_db_id}"
