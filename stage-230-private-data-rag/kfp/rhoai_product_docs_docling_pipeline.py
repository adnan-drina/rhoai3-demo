"""KFP v2 pipeline for Stage 230 RHOAI product-document Docling preparation.

This pipeline adapts the Red Hat-documented OpenDataHub data-processing
Docling standard pattern for Stage 230. It reads repo-staged RHOAI 3.4 product
PDFs from the project S3 bucket, converts them with Docling, builds the
metadata-rich JSONL chunk contract used by the Stage 230 RAG smoke helper, and
writes the reviewed chunks back to S3.

Product authority: RHOAI 3.4 "Working with AI pipelines" and "Prepare your
data for AI consumption".
"""

import argparse
import json
from pathlib import Path

from components.rhoai_product_docling_components import prepare_rhoai_product_doc_chunks
from kfp import compiler, dsl, kubernetes


ROOT = Path(__file__).resolve().parents[1]
METADATA_JSON = json.dumps(
    json.loads((ROOT / "data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json").read_text(encoding="utf-8")),
    ensure_ascii=False,
    separators=(",", ":"),
)
DEFAULT_INPUT_PREFIX = "raw/rhoai-product-docs"
DEFAULT_OUTPUT_S3_KEY = "processed/rhoai-product-docs/rhoai-3.4-product-docs-docling-kfp-chunks.jsonl"
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
    name="stage-230-rhoai-product-docs-docling",
    description="Prepare RHOAI 3.4 product documentation chunks with Docling for Stage 230 RAG.",
    pipeline_root=PIPELINE_ROOT,
)
def rhoai_product_docs_docling_pipeline(
    s3_source_prefix: str = DEFAULT_INPUT_PREFIX,
    output_s3_key: str = DEFAULT_OUTPUT_S3_KEY,
    pipeline_s3_secret_name: str = DEFAULT_PIPELINE_S3_SECRET,
    manifest_json: str = METADATA_JSON,
    max_chars: int = 1800,
    focus_only: bool = True,
    max_documents: int = 0,
    do_ocr: bool = False,
    do_table_structure: bool = True,
):
    prepare = prepare_rhoai_product_doc_chunks(
        manifest_json=manifest_json,
        s3_source_prefix=s3_source_prefix,
        output_s3_key=output_s3_key,
        max_chars=max_chars,
        focus_only=focus_only,
        max_documents=max_documents,
        do_ocr=do_ocr,
        do_table_structure=do_table_structure,
    )
    _with_s3_secret(prepare, pipeline_s3_secret_name)
    prepare.set_env_variable("HOME", "/tmp")
    prepare.set_env_variable("XDG_CACHE_HOME", "/tmp/.cache")
    prepare.set_env_variable("EASYOCR_MODULE_PATH", "/tmp/.EasyOCR")
    prepare.set_env_variable("TORCH_HOME", "/tmp/.cache/torch")
    _resources(
        prepare,
        cpu_request="2",
        cpu_limit="6",
        memory_request="6Gi",
        memory_limit="12Gi",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        default=str(ROOT / "kfp/compiled/stage-230-rhoai-product-docs-docling.yaml"),
    )
    args = parser.parse_args()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    compiler.Compiler().compile(rhoai_product_docs_docling_pipeline, str(output))
    print(f"compiled pipeline: {output}")


if __name__ == "__main__":
    main()
