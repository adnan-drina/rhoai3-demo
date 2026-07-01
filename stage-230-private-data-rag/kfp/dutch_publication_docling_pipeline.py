"""KFP v2 pipeline for Stage 230 Dutch publication Docling preparation.

This pipeline adapts the Red Hat-documented
opendatahub-io/data-processing docling-standard pattern for the Stage 230
single-document Dutch government publication smoke corpus. It is intentionally
small: one Docling preparation task that produces RAG-ready JSONL chunks and
metrics, suitable for validating the contract before wiring a full DSPA
pipeline server and larger S3-backed corpus.
"""

import argparse
from pathlib import Path

from components.dutch_docling_components import prepare_dutch_publication_chunks
from kfp import compiler, dsl


ROOT = Path(__file__).resolve().parents[1]
METADATA_JSON = (ROOT / "data/dutch-government/metadata/stb-2022-14-metadata.json").read_text(
    encoding="utf-8"
)
DEFAULT_SOURCE_URL = "https://zoek.officielebekendmakingen.nl/stb-2022-14.pdf"
DEFAULT_SOURCE_FILENAME = "stb-2022-14.pdf"


@dsl.pipeline(
    name="stage-230-dutch-publication-docling",
    description="Prepare Dutch government publication chunks with Docling for Stage 230 RAG.",
)
def dutch_publication_docling_pipeline(
    source_url: str = DEFAULT_SOURCE_URL,
    source_filename: str = DEFAULT_SOURCE_FILENAME,
    metadata_json: str = METADATA_JSON,
    chunk_max_tokens: int = 512,
):
    prepare = prepare_dutch_publication_chunks(
        source_url=source_url,
        source_filename=source_filename,
        metadata_json=metadata_json,
        chunk_max_tokens=chunk_max_tokens,
    )
    prepare.set_caching_options(False)
    prepare.set_cpu_request("500m")
    prepare.set_cpu_limit("4")
    prepare.set_memory_request("1Gi")
    prepare.set_memory_limit("6Gi")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        default=str(ROOT / "kfp/compiled/stage-230-dutch-publication-docling.yaml"),
    )
    args = parser.parse_args()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    compiler.Compiler().compile(dutch_publication_docling_pipeline, str(output))
    print(f"compiled pipeline: {output}")


if __name__ == "__main__":
    main()
