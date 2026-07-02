"""Split imported PDFs into batches for KFP ParallelFor conversion."""

from typing import List

from kfp import dsl

from .constants import PYTHON_BASE_IMAGE


@dsl.component(base_image=PYTHON_BASE_IMAGE)
def create_pdf_splits(
    input_path: dsl.Input[dsl.Artifact],
    num_splits: int,
) -> List[List[str]]:
    """Create non-empty PDF filename batches from an imported PDF directory."""

    from pathlib import Path  # pylint: disable=import-outside-toplevel

    if num_splits < 1:
        raise ValueError("num_splits must be at least 1")

    input_dir = Path(input_path.path)
    all_pdfs = sorted(path.name for path in input_dir.glob("*.pdf"))
    if not all_pdfs:
        raise RuntimeError(f"no PDF files found under {input_dir}")

    all_splits = [all_pdfs[index::num_splits] for index in range(num_splits)]
    filled_splits = [split for split in all_splits if split]
    print(f"create-pdf-splits: created {len(filled_splits)} split(s) for {len(all_pdfs)} PDF file(s)", flush=True)
    return filled_splits

