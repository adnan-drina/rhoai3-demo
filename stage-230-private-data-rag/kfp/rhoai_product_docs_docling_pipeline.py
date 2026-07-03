"""KFP v2 end-to-end Docling pipeline for Stage 230 RHOAI product documents.

This pipeline follows the OpenDataHub `data-processing/kubeflow-pipelines`
Docling standard pattern for data preparation, then extends it with Llama
Stack vector store ingestion to produce a query-ready RAG corpus:

  import PDFs -> split for ParallelFor -> download Docling models
  -> convert + chunk per split -> enrich with RHOAI metadata
  -> ingest to Llama Stack vector store via Files API

Source selection (manifest filtering, PDF filename computation) is handled at
compile time via ``--max-documents``. This eliminates the runtime
``select_rhoai_product_doc_sources`` component and the cross-edges it created.

Product authority: RHOAI 3.4 "Working with AI pipelines", "Prepare your
data for AI consumption", and "Working with Llama Stack".
Implementation reference: opendatahub-io/data-processing main branch,
`kubeflow-pipelines/docling-standard`.
"""

import argparse
import json
from pathlib import Path

from components import (
    create_pdf_splits,
    docling_chunk_and_upload,
    docling_convert_standard,
    download_docling_models,
    enrich_and_publish_rhoai_chunks,
    import_pdfs,
    ingest_to_vector_store,
)
from kfp import compiler, dsl, kubernetes


ROOT = Path(__file__).resolve().parents[1]
_RAW_MANIFEST = json.loads(
    (ROOT / "data/rhoai-product-docs/metadata/rhoai-3.4-product-docs.json").read_text(encoding="utf-8")
)
DEFAULT_OUTPUT_S3_KEY = "processed/rhoai-product-docs/rhoai-3.4-product-docs-docling-kfp-chunks.jsonl"
DEFAULT_PIPELINE_S3_SECRET = "data-processing-docling-pipeline"
PIPELINE_ROOT = "s3://enterprise-rag/pipelines/stage-230"
SECRET_MOUNT_PATH = "/mnt/secrets"
DEFAULT_LLAMA_STACK_BASE_URL = "http://lsd-enterprise-rag-service.enterprise-rag.svc.cluster.local:8321"
DEFAULT_VECTOR_STORE_NAME = "stage230-rhoai-34-product-docs-kfp"
DEFAULT_EMBEDDING_MODEL = "sentence-transformers/nomic-ai/nomic-embed-text-v1.5"
DEFAULT_VECTOR_PROVIDER = "pgvector"


def _select_sources(max_documents: int = 0) -> tuple[str, str]:
    """Apply compile-time source selection and return (pdf_filenames, manifest_json)."""
    documents = list(_RAW_MANIFEST.get("documents", []))
    if max_documents > 0:
        documents = documents[:max_documents]
    if not documents:
        raise RuntimeError("manifest does not contain any documents to process")
    selected_manifest = dict(_RAW_MANIFEST, documents=documents)
    manifest_json = json.dumps(selected_manifest, ensure_ascii=False, separators=(",", ":"))
    pdf_filenames = ",".join(doc["source_file"] for doc in documents)
    return pdf_filenames, manifest_json


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
    # The DSPA object store uses the NooBaa HTTPS endpoint with a
    # service-CA-signed certificate. The KFP launcher's artifact client only
    # trusts the system pool, so point Go TLS at the DSP trusted-CA bundle
    # that the workflow controller mounts into every executor pod.
    task.set_env_variable("SSL_CERT_FILE", "/kfp/certs/ca.crt")
    return task


def _create_pipeline(
    default_pdf_filenames: str,
    default_manifest_json: str,
):
    """Create the pipeline function with compile-time-resolved defaults."""

    @dsl.pipeline(
        name="stage-230-rhoai-product-docs-docling",
        description="End-to-end Docling pipeline for Stage 230: data preparation, metadata enrichment, and Llama Stack vector store ingestion.",
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
        pdf_filenames: str = default_pdf_filenames,
        manifest_json: str = default_manifest_json,
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
        llama_stack_base_url: str = DEFAULT_LLAMA_STACK_BASE_URL,
        vector_store_name: str = DEFAULT_VECTOR_STORE_NAME,
        embedding_model: str = DEFAULT_EMBEDDING_MODEL,
        vector_provider: str = DEFAULT_VECTOR_PROVIDER,
    ):
        importer = import_pdfs(
            filenames=pdf_filenames,
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

        with dsl.ParallelFor(pdf_splits.output, name="process-pdf-splits") as pdf_split:
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

            chunker = docling_chunk_and_upload(
                input_path=converter.outputs["output_path"],
                manifest_json=manifest_json,
                output_s3_key=output_s3_key,
                s3_secret_mount_path=SECRET_MOUNT_PATH,
            )
            _docling_cache_env(chunker)
            _mount_pipeline_s3_secret(chunker, DEFAULT_PIPELINE_S3_SECRET)
            _resources(
                chunker,
                cpu_request="500m",
                cpu_limit="2",
                memory_request="1Gi",
                memory_limit="4Gi",
            )

        enricher = enrich_and_publish_rhoai_chunks(
            manifest_json=manifest_json,
            output_s3_key=output_s3_key,
            focus_only=focus_only,
            s3_secret_mount_path=SECRET_MOUNT_PATH,
        )
        enricher.after(chunker)
        _mount_pipeline_s3_secret(enricher, pipeline_s3_secret_name)
        _resources(
            enricher,
            cpu_request="500m",
            cpu_limit="2",
            memory_request="512Mi",
            memory_limit="2Gi",
        )

        ingester = ingest_to_vector_store(
            output_s3_key=output_s3_key,
            s3_secret_mount_path=SECRET_MOUNT_PATH,
            llama_stack_base_url=llama_stack_base_url,
            vector_store_name=vector_store_name,
            embedding_model=embedding_model,
            vector_provider=vector_provider,
        )
        ingester.after(enricher)
        _mount_pipeline_s3_secret(ingester, pipeline_s3_secret_name)
        _resources(
            ingester,
            cpu_request="500m",
            cpu_limit="2",
            memory_request="1Gi",
            memory_limit="4Gi",
        )

    return rhoai_product_docs_docling_pipeline


rhoai_product_docs_docling_pipeline = _create_pipeline(*_select_sources())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        default=str(ROOT / "kfp/compiled/stage-230-rhoai-product-docs-docling.yaml"),
    )
    parser.add_argument(
        "--max-documents",
        type=int,
        default=0,
        help="Limit the number of documents to process (0 = all). Applied at compile time.",
    )
    args = parser.parse_args()

    pdf_filenames, manifest_json = _select_sources(max_documents=args.max_documents)
    pipeline = _create_pipeline(pdf_filenames, manifest_json)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    compiler.Compiler().compile(pipeline, str(output))
    print(f"compiled pipeline: {output}")


if __name__ == "__main__":
    main()
