"""
Split PDF List Component — divides a list of PDF URIs into balanced groups
for parallel processing via dsl.ParallelFor.
"""

from typing import NamedTuple, List
from kfp.dsl import component


@component(
    base_image="python:3.11",
)
def split_pdf_list_component(
    downloaded_files: List[str],
    original_keys: List[str],
    num_splits: int,
) -> NamedTuple("SplitOutput", [("file_groups", List[List[str]]), ("key_groups", List[List[str]])]):
    from collections import namedtuple

    n = max(1, num_splits)
    file_groups: list[list[str]] = [[] for _ in range(n)]
    key_groups: list[list[str]] = [[] for _ in range(n)]

    for i, (fp, key) in enumerate(zip(downloaded_files, original_keys)):
        idx = i % n
        file_groups[idx].append(fp)
        key_groups[idx].append(key)

    for g_idx, group in enumerate(file_groups):
        print(f"  Group {g_idx}: {len(group)} files")

    SplitOutput = namedtuple("SplitOutput", ["file_groups", "key_groups"])
    return SplitOutput(file_groups=file_groups, key_groups=key_groups)
