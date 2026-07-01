"""KFP v2 pipeline for Stage 230 Dutch publication Docling preparation.

This pipeline adapts the Red Hat-documented
opendatahub-io/data-processing docling-standard pattern for the Stage 230
single-document Dutch government publication corpus. The notebook path
validates each processing step interactively; this pipeline automates the same
contract through DSPA/KFP:

1. read the source PDF from the project S3 bucket
2. convert it with Docling standard conversion
3. build validated RAG chunk JSONL
4. write the prepared chunks back to the project S3 bucket

Product authority: RHOAI 3.4 "Working with AI pipelines" and "Prepare your
data for AI consumption".
"""

import argparse
import json
from pathlib import Path

from components.dutch_docling_components import (
    build_dutch_publication_chunks,
    convert_pdf_with_docling,
    download_pdf_from_s3,
)
from kfp import compiler, dsl, kubernetes


ROOT = Path(__file__).resolve().parents[1]
METADATA_JSON = json.dumps(
    json.loads((ROOT / "data/dutch-government/metadata/stb-2022-14-metadata.json").read_text(encoding="utf-8")),
    ensure_ascii=False,
    separators=(",", ":"),
)
DEFAULT_SOURCE_FILENAME = "stb-2022-14.pdf"
DEFAULT_INPUT_S3_KEY = "raw/dutch-government/stb-2022-14.pdf"
DEFAULT_OUTPUT_S3_KEY = "processed/dutch-government/stb-2022-14-docling-kfp-chunks.jsonl"
DEFAULT_PIPELINE_S3_SECRET = "data-processing-docling-pipeline"
PIPELINE_ROOT = "s3://enterprise-rag/pipelines/stage-230"
S3_SECRET_ENV = {
    "S3_ENDPOINT_URL": "S3_ENDPOINT_URL",
    "S3_ACCESS_KEY": "S3_ACCESS_KEY",
    "S3_SECRET_KEY": "S3_SECRET_KEY",
    "S3_BUCKET": "S3_BUCKET",
    "AWS_DEFAULT_REGION": "AWS_DEFAULT_REGION",
}


def _with_s3_secret(task: dsl.PipelineTask, secret_name: str) -> dsl.PipelineTask:
    return kubernetes.use_secret_as_env(
        task=task,
        secret_name=secret_name,
        secret_key_to_env=S3_SECRET_ENV,
    )


def _resources(
    task: dsl.PipelineTask,
    *,
    cpu_request: str,
    cpu_limit: str,
    memory_request: str,
    memory_limit: str,
) -> dsl.PipelineTask:
    task.set_caching_options(False)
    task.set_cpu_request(cpu_request)
    task.set_cpu_limit(cpu_limit)
    task.set_memory_request(memory_request)
    task.set_memory_limit(memory_limit)
    return task


@dsl.pipeline(
    name="stage-230-dutch-publication-docling",
    description="Prepare Dutch government publication chunks with Docling for Stage 230 RAG.",
    pipeline_root=PIPELINE_ROOT,
)
def dutch_publication_docling_pipeline(
    s3_pdf_key: str = DEFAULT_INPUT_S3_KEY,
    output_s3_key: str = DEFAULT_OUTPUT_S3_KEY,
    source_filename: str = DEFAULT_SOURCE_FILENAME,
    pipeline_s3_secret_name: str = DEFAULT_PIPELINE_S3_SECRET,
    metadata_json: str = METADATA_JSON,
    chunk_max_tokens: int = 512,
):
    download = download_pdf_from_s3(
        s3_pdf_key=s3_pdf_key,
        source_filename=source_filename,
    )
    _with_s3_secret(download, pipeline_s3_secret_name)
    _resources(
        download,
        cpu_request="250m",
        cpu_limit="1",
        memory_request="512Mi",
        memory_limit="1Gi",
    )

    convert = convert_pdf_with_docling(input_pdf=download.outputs["output_pdf"])
    _resources(
        convert,
        cpu_request="1",
        cpu_limit="4",
        memory_request="2Gi",
        memory_limit="8Gi",
    )

    build = build_dutch_publication_chunks(
        input_markdown=convert.outputs["output_markdown"],
        input_docling_json=convert.outputs["output_docling_json"],
        metadata_json=metadata_json,
        output_s3_key=output_s3_key,
        chunk_max_tokens=chunk_max_tokens,
    )
    _with_s3_secret(build, pipeline_s3_secret_name)
    _resources(
        build,
        cpu_request="500m",
        cpu_limit="2",
        memory_request="512Mi",
        memory_limit="2Gi",
    )


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
