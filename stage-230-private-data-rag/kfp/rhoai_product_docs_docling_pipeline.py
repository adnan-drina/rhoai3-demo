"""KFP v2 modular Docling pipeline for Stage 230 RHOAI product documents.

This pipeline follows the OpenDataHub `data-processing/kubeflow-pipelines`
Docling standard pattern: select/import PDFs, split work for `ParallelFor`,
download Docling models, convert PDFs to Markdown and Docling JSON, chunk with
Docling HybridChunker, then run a small Stage 230 adapter that enriches chunks
with RHOAI product-document metadata and writes the RAG JSONL handoff to S3.

Product authority: RHOAI 3.4 "Working with AI pipelines" and "Prepare your
data for AI consumption".
Implementation reference: opendatahub-io/data-processing main branch,
`kubeflow-pipelines/docling-standard`.
"""

import argparse
import json
from pathlib import Path

from components import (
    create_pdf_splits,
    docling_chunk,
    docling_convert_standard,
    download_docling_models,
    import_pdfs,
    normalize_rhoai_product_doc_chunks,
    publish_docling_split_outputs,
    select_rhoai_product_doc_sources,
)
from kfp import compiler, dsl, kubernetes


ROOT = Path(__file__).resolve().parents[1]
METADATA_JSON = json.dumps(
    json.loads((ROOT / "data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json").read_text(encoding="utf-8")),
    ensure_ascii=False,
    separators=(",", ":"),
)
DEFAULT_OUTPUT_S3_KEY = "processed/rhoai-product-docs/rhoai-3.4-product-docs-docling-kfp-chunks.jsonl"
DEFAULT_PIPELINE_S3_SECRET = "data-processing-docling-pipeline"
PIPELINE_ROOT = "s3://enterprise-rag/pipelines/stage-230"
SECRET_MOUNT_PATH = "/mnt/secrets"


def _mount_pipeline_s3_secret(task: dsl.PipelineTask, secret_name: str) -> dsl.PipelineTask:
    return kubernetes.use_secret_as_volume(
        task=task,
        secret_name=secret_name,
        mount_path=SECRET_MOUNT_PATH,
        optional=False,
    )


def _docling_cache_env(task: dsl.PipelineTask) -> dsl.PipelineTask:
    task.set_env_variable("HOME", "/tmp")
    task.set_env_variable("XDG_CACHE_HOME", "/tmp/.cache")
    task.set_env_variable("EASYOCR_MODULE_PATH", "/tmp/.EasyOCR")
    task.set_env_variable("TORCH_HOME", "/tmp/.cache/torch")
    task.set_env_variable("HF_HOME", "/tmp/.cache/huggingface")
    task.set_env_variable("TRANSFORMERS_CACHE", "/tmp/.cache/huggingface/transformers")
    return task


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
    description="Modular Docling standard pipeline for Stage 230 RHOAI product-document RAG preparation.",
    pipeline_root=PIPELINE_ROOT,
    pipeline_config=dsl.PipelineConfig(
        workspace=dsl.WorkspaceConfig(
            size="5Gi",
            kubernetes=dsl.KubernetesWorkspaceConfig(
                pvcSpecPatch={"accessModes": ["ReadWriteOnce"]},
            ),
        ),
    ),
)
def rhoai_product_docs_docling_pipeline(
    output_s3_key: str = DEFAULT_OUTPUT_S3_KEY,
    pipeline_s3_secret_name: str = DEFAULT_PIPELINE_S3_SECRET,
    manifest_json: str = METADATA_JSON,
    max_documents: int = 0,
    num_splits: int = 3,
    pdf_from_s3: bool = True,
    pdf_base_url: str = "",
    focus_only: bool = True,
    docling_pdf_backend: str = "dlparse_v4",
    docling_image_export_mode: str = "embedded",
    docling_table_mode: str = "accurate",
    docling_num_threads: int = 4,
    docling_timeout_per_document: int = 300,
    docling_ocr: bool = False,
    docling_force_ocr: bool = False,
    docling_ocr_engine: str = "tesseract_cli",
    docling_allow_external_plugins: bool = False,
    docling_enrich_code: bool = False,
    docling_enrich_formula: bool = False,
    docling_enrich_picture_classes: bool = False,
    docling_enrich_picture_description: bool = False,
    docling_chunk_max_tokens: int = 512,
    docling_chunk_merge_peers: bool = True,
):
    sources = select_rhoai_product_doc_sources(
        manifest_json=manifest_json,
        max_documents=max_documents,
    )
    sources.set_caching_options(False)

    importer = import_pdfs(
        filenames=sources.outputs["pdf_filenames"],
        base_url=pdf_base_url,
        from_s3=pdf_from_s3,
        s3_secret_mount_path=SECRET_MOUNT_PATH,
    )
    _mount_pipeline_s3_secret(importer, pipeline_s3_secret_name)
    _resources(
        importer,
        cpu_request="250m",
        cpu_limit="1",
        memory_request="512Mi",
        memory_limit="1Gi",
    )

    pdf_splits = create_pdf_splits(
        input_path=importer.outputs["output_path"],
        num_splits=num_splits,
    )
    _resources(
        pdf_splits,
        cpu_request="100m",
        cpu_limit="500m",
        memory_request="256Mi",
        memory_limit="512Mi",
    )

    docling_models = download_docling_models(
        pipeline_type="standard",
        remote_model_endpoint_enabled=False,
    )
    _docling_cache_env(docling_models)
    _resources(
        docling_models,
        cpu_request="500m",
        cpu_limit="2",
        memory_request="2Gi",
        memory_limit="6Gi",
    )

    with dsl.ParallelFor(pdf_splits.output) as pdf_split:
        converter = docling_convert_standard(
            input_path=importer.outputs["output_path"],
            artifacts_path=docling_models.outputs["output_path"],
            pdf_filenames=pdf_split,
            pdf_backend=docling_pdf_backend,
            image_export_mode=docling_image_export_mode,
            table_mode=docling_table_mode,
            num_threads=docling_num_threads,
            timeout_per_document=docling_timeout_per_document,
            ocr=docling_ocr,
            force_ocr=docling_force_ocr,
            ocr_engine=docling_ocr_engine,
            allow_external_plugins=docling_allow_external_plugins,
            enrich_code=docling_enrich_code,
            enrich_formula=docling_enrich_formula,
            enrich_picture_classes=docling_enrich_picture_classes,
            enrich_picture_description=docling_enrich_picture_description,
        )
        _docling_cache_env(converter)
        _resources(
            converter,
            cpu_request="1",
            cpu_limit="4",
            memory_request="3Gi",
            memory_limit="8Gi",
        )

        chunker = docling_chunk(
            input_path=converter.outputs["output_path"],
            max_tokens=docling_chunk_max_tokens,
            merge_peers=docling_chunk_merge_peers,
        )
        _docling_cache_env(chunker)
        _resources(
            chunker,
            cpu_request="500m",
            cpu_limit="2",
            memory_request="1Gi",
            memory_limit="4Gi",
        )

        publisher = publish_docling_split_outputs(
            converted_path=converter.outputs["output_path"],
            chunked_path=chunker.outputs["output_path"],
            manifest_json=sources.outputs["selected_manifest_json"],
            output_s3_key=output_s3_key,
            s3_secret_mount_path=SECRET_MOUNT_PATH,
        )
        # RHOAI/KFP resolves Kubernetes secret mounts in nested ParallelFor
        # tasks from the parent DAG, not from the child task's parameter list.
        # Use this stage's GitOps-owned deterministic Secret name inside the
        # loop so the modular publisher remains portable across fresh redeploys.
        _mount_pipeline_s3_secret(publisher, DEFAULT_PIPELINE_S3_SECRET)
        _resources(
            publisher,
            cpu_request="250m",
            cpu_limit="1",
            memory_request="256Mi",
            memory_limit="1Gi",
        )

    normalizer = normalize_rhoai_product_doc_chunks(
        manifest_json=sources.outputs["selected_manifest_json"],
        output_s3_key=output_s3_key,
        focus_only=focus_only,
        s3_secret_mount_path=SECRET_MOUNT_PATH,
    )
    normalizer.after(publisher)
    _mount_pipeline_s3_secret(normalizer, pipeline_s3_secret_name)
    _resources(
        normalizer,
        cpu_request="500m",
        cpu_limit="2",
        memory_request="512Mi",
        memory_limit="2Gi",
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
