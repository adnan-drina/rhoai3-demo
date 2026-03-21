"""
KFP v2 RAG Ingestion Pipeline — Orchestration

Defines two pipelines:
  1. docling_rag_pipeline       — Single-document ingestion (for testing)
  2. batch_docling_rag_pipeline — Batch ingestion with ParallelFor

Components are in kfp/components/ following KFP modular best practices.
Reuses the existing DSPA (dspa-rag) in private-ai namespace.

Key design choices (RHOAI 3.3 aligned):
  - kubernetes.use_secret_as_env()  for MinIO credentials (no secrets in params)
  - kubernetes.mount_pvc()          for inter-component file sharing
  - Server-side chunking            via vector_stores.files.create()
  - Docling fallback logic          for API version tolerance

Ref: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_llama_stack/deploying-a-rag-stack-in-a-project_rag
"""

import kfp
from kfp import dsl, kubernetes
from kfp.dsl import PipelineTask
from pathlib import Path

from components.setup_config import setup_config_component
from components.download_from_s3 import download_from_s3_component
from components.register_vector_db import register_vector_db_component
from components.process_with_docling import process_with_docling_component
from components.insert_via_llamastack import insert_via_llamastack_component
from components.split_pdf_list import split_pdf_list_component
from components.pipeline_completion import pipeline_completion_component

MINIO_SECRET = "minio-connection"
PIPELINE_PVC = "rag-pipeline-workspace"


def _set_resources(
    task: PipelineTask,
    *,
    cpu_req: str = "250m",
    cpu_lim: str = "500m",
    mem_req: str = "256Mi",
    mem_lim: str = "512Mi",
) -> None:
    task.set_cpu_request(cpu_req)
    task.set_cpu_limit(cpu_lim)
    task.set_memory_request(mem_req)
    task.set_memory_limit(mem_lim)


def _inject_minio(task: PipelineTask) -> None:
    kubernetes.use_secret_as_env(
        task,
        secret_name=MINIO_SECRET,
        secret_key_to_env={
            "AWS_S3_ENDPOINT": "AWS_S3_ENDPOINT",
            "AWS_ACCESS_KEY_ID": "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY": "AWS_SECRET_ACCESS_KEY",
        },
    )


def _mount_pvc(task: PipelineTask) -> None:
    kubernetes.mount_pvc(task, pvc_name=PIPELINE_PVC, mount_path="/shared-data")


# ---------------------------------------------------------------------------
# Pipeline 1: Single-document ingestion (for testing / ad-hoc use)
# ---------------------------------------------------------------------------

@dsl.pipeline(
    name="rag-ingestion-single",
    description="RAG single-document ingestion via Docling + LlamaStack Vector IO (v1.0.0)",
)
def docling_rag_pipeline(
    input_uri: str = "s3://rag-documents/acme/sample.pdf",
    minio_endpoint: str = "http://minio.minio-storage.svc.cluster.local:9000",
    llamastack_url: str = "http://lsd-rag-service.private-ai.svc.cluster.local:8321",
    docling_service: str = "http://docling-service.private-ai.svc:5001",
    model_id: str = "granite-8b-agent",
    embedding_model: str = "sentence-transformers/ibm-granite/granite-embedding-125m-english",
    embedding_dimension: int = 768,
    chunk_size_tokens: int = 512,
    vector_provider: str = "pgvector",
    vector_db_id: str = "acme_corporate",
    temperature: float = 0.0,
    max_tokens: int = 4096,
    processing_timeout: int = 600,
):
    # --- Step 1: Setup Configuration ---
    setup = setup_config_component(
        llamastack_url=llamastack_url,
        model_id=model_id,
        temperature=temperature,
        max_tokens=max_tokens,
        embedding_model=embedding_model,
        embedding_dimension=embedding_dimension,
        chunk_size_tokens=chunk_size_tokens,
        vector_provider=vector_provider,
        docling_service=docling_service,
        processing_timeout=processing_timeout,
        vector_db_id=vector_db_id,
    )
    setup.set_caching_options(False)

    # --- Step 2: Download from S3 ---
    download = download_from_s3_component(
        s3_prefix=input_uri,
        minio_endpoint=minio_endpoint,
    )
    _inject_minio(download)
    _mount_pvc(download)
    _set_resources(download, cpu_req="500m", cpu_lim="1", mem_req="512Mi", mem_lim="1Gi")
    download.set_caching_options(False)

    # --- Step 3: Register Vector DB ---
    reg_db = register_vector_db_component(
        setup_config=setup.outputs["setup_config"],
    )
    reg_db.after(download)
    reg_db.set_caching_options(False)

    # --- Step 4: Completion ---
    completion = pipeline_completion_component(
        vector_db_status=reg_db.outputs["vector_db_status"],
        file_count=download.outputs["file_count"],
    )
    completion.set_caching_options(False)


# ---------------------------------------------------------------------------
# Pipeline 2: Batch ingestion with parallel processing
# ---------------------------------------------------------------------------

@dsl.pipeline(
    name="rag-ingestion-batch",
    description="RAG batch ingestion: Docling + LlamaStack Vector IO with parallel processing (v1.0.0)",
    pipeline_root="s3://pipelines/",
)
def batch_docling_rag_pipeline(
    s3_prefix: str = "s3://rag-documents/acme/",
    minio_endpoint: str = "http://minio.minio-storage.svc.cluster.local:9000",
    llamastack_url: str = "http://lsd-rag-service.private-ai.svc.cluster.local:8321",
    docling_service: str = "http://docling-service.private-ai.svc:5001",
    model_id: str = "granite-8b-agent",
    embedding_model: str = "sentence-transformers/ibm-granite/granite-embedding-125m-english",
    embedding_dimension: int = 768,
    chunk_size_tokens: int = 512,
    vector_provider: str = "pgvector",
    vector_db_id: str = "acme_corporate",
    temperature: float = 0.0,
    max_tokens: int = 4096,
    processing_timeout: int = 600,
    num_splits: int = 2,
    cache_buster: str = "",
):
    bucket_name = "rag-documents"

    # --- Stage 1: Setup Configuration ---
    setup = setup_config_component(
        llamastack_url=llamastack_url,
        model_id=model_id,
        temperature=temperature,
        max_tokens=max_tokens,
        embedding_model=embedding_model,
        embedding_dimension=embedding_dimension,
        chunk_size_tokens=chunk_size_tokens,
        vector_provider=vector_provider,
        docling_service=docling_service,
        processing_timeout=processing_timeout,
        vector_db_id=vector_db_id,
    )
    setup.set_caching_options(False)

    # --- Stage 2: Download all PDFs from S3 prefix ---
    download = download_from_s3_component(
        s3_prefix=s3_prefix,
        minio_endpoint=minio_endpoint,
    )
    _inject_minio(download)
    _mount_pvc(download)
    _set_resources(download, cpu_req="500m", cpu_lim="1", mem_req="512Mi", mem_lim="1Gi")
    download.set_caching_options(False)

    # --- Stage 3: Register vector DB (idempotent, cache disabled — UUIDs change on LlamaStack restart) ---
    reg_db = register_vector_db_component(
        setup_config=setup.outputs["setup_config"],
    )
    reg_db.after(download)
    reg_db.set_caching_options(False)

    # --- Stage 4: Split files into groups for parallel processing ---
    split = split_pdf_list_component(
        downloaded_files=download.outputs["downloaded_files"],
        original_keys=download.outputs["original_keys"],
        num_splits=num_splits,
    )
    split.after(reg_db)
    split.set_caching_options(False)

    # --- Stage 5: Process each group in parallel ---
    with dsl.ParallelFor(
        items=split.outputs["file_groups"],
        name="process-group",
    ) as file_group:
        with dsl.ParallelFor(
            items=file_group,
            parallelism=1,
            name="process-pdf",
        ) as doc_path:
            # Docling conversion
            docling = process_with_docling_component(
                document_path=doc_path,
                original_key=doc_path,
                setup_config=setup.outputs["setup_config"],
            )
            _mount_pvc(docling)
            _set_resources(docling, cpu_req="500m", cpu_lim="1", mem_req="512Mi", mem_lim="1Gi")
            docling.set_caching_options(False)

            # Insert into pgvector via LlamaStack
            insert = insert_via_llamastack_component(
                setup_config=setup.outputs["setup_config"],
                processed_file=docling.outputs["processed_file"],
                original_key=doc_path,
                bucket_name=bucket_name,
                vector_db_ids=reg_db.outputs["vector_db_ids"],
            )
            _mount_pvc(insert)
            _set_resources(insert)
            insert.set_caching_options(False)

    # --- Stage 6: Convergence ---
    completion = pipeline_completion_component(
        vector_db_status=reg_db.outputs["vector_db_status"],
        file_count=download.outputs["file_count"],
    )
    completion.set_caching_options(False)


if __name__ == "__main__":
    script_dir = Path(__file__).parent.resolve()
    step_dir = script_dir.parent
    repo_root = step_dir.parent.parent
    artifacts_dir = repo_root / "artifacts"
    artifacts_dir.mkdir(exist_ok=True)

    out = artifacts_dir / "rag-ingestion-batch.yaml"
    kfp.compiler.Compiler().compile(
        pipeline_func=batch_docling_rag_pipeline,
        package_path=str(out),
    )
    print(f"Pipeline compiled: {out}")
