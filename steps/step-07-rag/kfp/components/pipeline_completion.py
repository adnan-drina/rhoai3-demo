"""
Pipeline Completion Component — single terminal convergence node.

Ensures the pipeline DAG has one clear end-point for proper
completion detection when branches (ParallelFor) are used.
"""

from typing import NamedTuple, Dict, Any
from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
)
def pipeline_completion_component(
    vector_db_status: Dict[str, Any],
    file_count: int,
) -> NamedTuple("CompletionOutput", [("completion_status", str)]):
    """Terminal convergence node — summarizes pipeline outcome.

    Args:
        vector_db_status: Status dict from the register_vector_db step.
        file_count: Number of files processed by the download step.

    Returns:
        completion_status: Overall pipeline status (SUCCESS, PARTIAL_SUCCESS, or FAILED).
    """
    from collections import namedtuple

    print("Pipeline Completion")
    print("=" * 60)

    db_ok = vector_db_status.get("ready", False)
    db_id = vector_db_status.get("vector_db_id", "unknown")

    if db_ok and file_count > 0:
        status = "SUCCESS"
    elif db_ok:
        status = "PARTIAL_SUCCESS"
    else:
        status = "FAILED"

    print(f"  Vector DB:  {db_id} (ready={db_ok})")
    print(f"  Files:      {file_count}")
    print(f"  Status:     {status}")
    print("=" * 60)

    CompletionOutput = namedtuple("CompletionOutput", ["completion_status"])
    return CompletionOutput(completion_status=status)
