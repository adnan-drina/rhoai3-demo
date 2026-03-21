"""
Split PDF List Component — divides a list of PDF paths into balanced groups
for parallel processing via dsl.ParallelFor.
"""

from typing import NamedTuple, List
from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
)
def split_pdf_list_component(
    downloaded_files: List[str],
    num_splits: int,
) -> NamedTuple("SplitOutput", [("file_groups", List[List[str]])]):
    """Divide a list of PDF paths into balanced groups for parallel processing.

    Args:
        downloaded_files: List of local file paths from the download step.
        num_splits: Number of parallel groups to create.

    Returns:
        file_groups: Nested list of file paths, one sub-list per group.
    """
    from collections import namedtuple

    n = max(1, num_splits)
    file_groups: list[list[str]] = [[] for _ in range(n)]

    for i, fp in enumerate(downloaded_files):
        file_groups[i % n].append(fp)

    for g_idx, group in enumerate(file_groups):
        print(f"  Group {g_idx}: {len(group)} files")

    SplitOutput = namedtuple("SplitOutput", ["file_groups"])
    return SplitOutput(file_groups=file_groups)
