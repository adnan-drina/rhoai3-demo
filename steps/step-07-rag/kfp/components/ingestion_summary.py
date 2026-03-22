"""
Ingestion Summary Component — receives collected results from the
ParallelFor loop and reports ingestion metrics to the Dashboard.
"""

from typing import List
from kfp.dsl import component, Output, Metrics


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    pip_index_urls=["https://pypi.org/simple"],
)
def ingestion_summary_component(
    insert_statuses: List[str],
    vector_db_id: str,
    metrics: Output[Metrics],
) -> str:
    """Aggregate parallel ingestion results and log metrics.

    Args:
        insert_statuses: Collected status strings from each insert iteration.
        vector_db_id: Target vector store collection name.
        metrics: KFP Metrics artifact for Dashboard visibility.

    Returns:
        Human-readable summary of the ingestion run.
    """
    total = len(insert_statuses)
    succeeded = sum(1 for s in insert_statuses if s == "success")
    skipped = sum(1 for s in insert_statuses if s == "skipped")
    errored = sum(1 for s in insert_statuses if s == "error")

    print("RAG Ingestion Summary")
    print("=" * 60)
    print(f"  Vector DB:  {vector_db_id}")
    print(f"  Total:      {total}")
    print(f"  Succeeded:  {succeeded}")
    print(f"  Skipped:    {skipped}")
    print(f"  Errored:    {errored}")
    print("=" * 60)

    metrics.log_metric("vector_db_id", vector_db_id)
    metrics.log_metric("documents_total", total)
    metrics.log_metric("documents_ingested", succeeded)
    metrics.log_metric("documents_skipped", skipped)
    metrics.log_metric("documents_errored", errored)

    return f"{succeeded}/{total} documents ingested into {vector_db_id}"
