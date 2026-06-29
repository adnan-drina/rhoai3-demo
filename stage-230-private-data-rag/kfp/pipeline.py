"""Stage 230 KFP v2 whoami RAG ingestion pipeline.

Purpose:
- download private whoami source documents from the Stage 110 ODF/NooBaa bucket
- convert PDFs to Markdown through the Stage 230 Docling service
- register and populate the Stage 230 Llama Stack pgvector vector DB
- validate retrieval and a Nemotron-backed answer for dashboard-visible evidence

The pipeline runs on the Stage 230 DataSciencePipelinesApplication
`private-rag-pipelines` and follows the OpenShift AI 3.4 AI Pipelines guidance
captured in `.agents/skills/rhoai-ai-pipelines`.
"""

from pathlib import Path

import kfp
from kfp import dsl, kubernetes
from kfp.dsl import PipelineTask

from components.download_from_s3 import download_from_s3_component
from components.ingestion_summary import ingestion_summary_component
from components.insert_via_llamastack import insert_via_llamastack_component
from components.process_with_docling import process_with_docling_component
from components.register_vector_db import register_vector_db_component

SOURCE_OBC_SECRET = "demo-sandbox-bucket"
PIPELINE_PVC = "private-rag-pipeline-workspace"


def _set_resources(
    task: PipelineTask,
    *,
    cpu_request: str = "250m",
    cpu_limit: str = "1",
    memory_request: str = "512Mi",
    memory_limit: str = "1Gi",
) -> None:
    task.set_cpu_request(cpu_request)
    task.set_cpu_limit(cpu_limit)
    task.set_memory_request(memory_request)
    task.set_memory_limit(memory_limit)


def _mount_workspace(task: PipelineTask) -> None:
    kubernetes.mount_pvc(
        task,
        pvc_name=PIPELINE_PVC,
        mount_path="/shared-data",
    )


def _inject_source_bucket_credentials(task: PipelineTask) -> None:
    kubernetes.use_secret_as_env(
        task,
        secret_name=SOURCE_OBC_SECRET,
        secret_key_to_env={
            "AWS_ACCESS_KEY_ID": "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY": "AWS_SECRET_ACCESS_KEY",
        },
    )


@dsl.pipeline(
    name="whoami-rag-ingestion",
    description="Ingest the whoami PDF corpus into Llama Stack pgvector through Docling.",
    pipeline_root="s3://private-rag-pipelines/artifacts",
)
def whoami_rag_ingestion_pipeline(
    s3_uri: str,
    s3_endpoint: str,
    docling_service: str,
    llamastack_url: str,
    inference_model: str = "nemotron-3-nano-30b-a3b",
    embedding_model: str = "all-MiniLM-L6-v2",
    embedding_dimension: int = 384,
    vector_provider: str = "pgvector",
    vector_db_id: str = "whoami",
    chunk_size_tokens: int = 512,
    processing_timeout: int = 600,
    reset_vector_db: bool = True,
):
    download = download_from_s3_component(
        s3_uri=s3_uri,
        s3_endpoint=s3_endpoint,
    )
    _inject_source_bucket_credentials(download)
    _mount_workspace(download)
    _set_resources(download, cpu_request="500m", cpu_limit="1", memory_request="512Mi", memory_limit="1Gi")
    download.set_caching_options(False)

    register = register_vector_db_component(
        llamastack_url=llamastack_url,
        vector_db_id=vector_db_id,
        embedding_model=embedding_model,
        embedding_dimension=embedding_dimension,
        vector_provider=vector_provider,
        reset_vector_db=reset_vector_db,
    )
    register.after(download)
    _set_resources(register)
    register.set_caching_options(False)

    with dsl.ParallelFor(
        items=download.outputs["downloaded_files"],
        parallelism=1,
        name="process-source-pdf",
    ) as document_path:
        docling = process_with_docling_component(
            document_path=document_path,
            docling_service=docling_service,
            processing_timeout=processing_timeout,
        )
        docling.after(register)
        _mount_workspace(docling)
        _set_resources(docling, cpu_request="500m", cpu_limit="2", memory_request="1Gi", memory_limit="3Gi")
        docling.set_caching_options(False)

        insert = insert_via_llamastack_component(
            llamastack_url=llamastack_url,
            processed_file=docling.outputs["processed_file"],
            vector_db_ids=register.outputs["vector_db_ids"],
            vector_db_id=vector_db_id,
            chunk_size_tokens=chunk_size_tokens,
        )
        _mount_workspace(insert)
        _set_resources(insert)
        insert.set_caching_options(False)

    summary = ingestion_summary_component(
        llamastack_url=llamastack_url,
        vector_db_id=vector_db_id,
        inference_model=inference_model,
    )
    summary.after(insert)
    _mount_workspace(summary)
    _set_resources(summary)
    summary.set_caching_options(False)


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parents[2]
    artifacts_dir = repo_root / "artifacts"
    artifacts_dir.mkdir(exist_ok=True)
    output = artifacts_dir / "stage-230-whoami-rag-ingestion.yaml"
    kfp.compiler.Compiler().compile(
        pipeline_func=whoami_rag_ingestion_pipeline,
        package_path=str(output),
    )
    print(f"Pipeline compiled: {output}")
