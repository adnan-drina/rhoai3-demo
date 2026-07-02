"""Ingest enriched RHOAI product-document chunks into a Llama Stack vector store.

Reads the enriched JSONL output from S3, creates a pgvector-backed vector store
via Llama Stack, uploads each chunk through the Files API with per-chunk metadata
attributes, verifies ingestion file counts, and runs a lightweight search smoke
test to confirm the vector store is queryable.
"""

from kfp import dsl
from kfp.dsl import Metrics, Output

from .constants import PYTHON312_BASE_IMAGE


@dsl.component(
    base_image=PYTHON312_BASE_IMAGE,
    packages_to_install=["boto3==1.42.54", "llama-stack-client==0.7.2"],
)
def ingest_to_vector_store(
    output_metrics: Output[Metrics],
    output_s3_key: str,
    s3_secret_mount_path: str = "/mnt/secrets",
    llama_stack_base_url: str = "http://lsd-enterprise-rag-service.enterprise-rag.svc.cluster.local:8321",
    vector_store_name: str = "stage230-rhoai-34-product-docs",
    embedding_model: str = "sentence-transformers/nomic-ai/nomic-embed-text-v1.5",
    vector_provider: str = "pgvector",
):
    """Ingest enriched chunks from S3 into a Llama Stack vector store."""

    import inspect  # pylint: disable=import-outside-toplevel
    import json  # pylint: disable=import-outside-toplevel
    import tempfile  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    import boto3  # pylint: disable=import-outside-toplevel
    from botocore.config import Config  # pylint: disable=import-outside-toplevel
    from llama_stack_client import LlamaStackClient  # pylint: disable=import-outside-toplevel
    from urllib3 import disable_warnings  # pylint: disable=import-outside-toplevel
    from urllib3.exceptions import InsecureRequestWarning  # pylint: disable=import-outside-toplevel

    ALLOWED_ATTRIBUTES = {
        "id", "access_tier", "chunk_index", "corpus", "document_title",
        "document_type", "documentation_category", "guide_slug", "language",
        "matched_terms", "page_start", "page_end", "preparation_method",
        "product", "product_version", "retrieved_url", "source",
        "source_authority", "source_file", "source_format", "source_url",
        "tenant_id", "topic", "version", "version_no",
    }

    def secret_value(name: str) -> str:
        value_path = Path(s3_secret_mount_path) / name
        if not value_path.is_file():
            raise RuntimeError(f"missing S3 Secret key {name} in {s3_secret_mount_path}")
        return value_path.read_text(encoding="utf-8").strip()

    def record_attributes(record: dict) -> dict:
        attrs = {
            k: record[k]
            for k in sorted(ALLOWED_ATTRIBUTES)
            if k in record and record[k] is not None
        }
        if isinstance(attrs.get("matched_terms"), list):
            attrs["matched_terms"] = ",".join(str(t) for t in attrs["matched_terms"])
        attrs["record_id"] = record["id"]
        return attrs

    def get_value(item, *keys):
        for key in keys:
            if isinstance(item, dict) and key in item:
                return item[key]
            value = getattr(item, key, None)
            if value is not None:
                return value
        return None

    def as_items(response):
        if isinstance(response, list):
            return response
        for key in ("data", "vector_stores", "items"):
            value = getattr(response, key, None)
            if value is not None:
                return list(value)
            if isinstance(response, dict) and key in response:
                return response[key]
        return list(response) if not isinstance(response, (str, dict)) else []

    # -- Read enriched JSONL from S3 ------------------------------------------

    disable_warnings(InsecureRequestWarning)
    bucket = secret_value("S3_BUCKET")
    s3_client = boto3.client(
        "s3",
        endpoint_url=secret_value("S3_ENDPOINT_URL"),
        aws_access_key_id=secret_value("S3_ACCESS_KEY"),
        aws_secret_access_key=secret_value("S3_SECRET_KEY"),
        region_name="us-east-1",
        verify=False,
        config=Config(signature_version="s3v4"),
    )

    output_key = output_s3_key.strip("/")
    body = s3_client.get_object(Bucket=bucket, Key=output_key)["Body"].read().decode("utf-8")
    records = [json.loads(line) for line in body.splitlines() if line.strip()]
    if not records:
        raise RuntimeError(f"ingest-to-vector-store: no records in s3://{bucket}/{output_key}")
    print(f"ingest-to-vector-store: loaded {len(records)} chunks from S3", flush=True)

    # -- Connect to Llama Stack and verify embedding model --------------------

    client = LlamaStackClient(base_url=llama_stack_base_url)
    models = client.models.list()
    model_list = list(models) if not isinstance(models, list) else models
    model_ids = [get_value(m, "id", "identifier") for m in model_list]
    if embedding_model not in model_ids:
        raise RuntimeError(
            f"ingest-to-vector-store: embedding model {embedding_model} not found "
            f"in Llama Stack; available: {model_ids}"
        )
    print(f"ingest-to-vector-store: Llama Stack connected, embedding model verified", flush=True)

    # -- Delete existing vector store if present ------------------------------

    for store in as_items(client.vector_stores.list()):
        if get_value(store, "name") == vector_store_name:
            existing_id = get_value(store, "id", "vector_store_id")
            print(f"ingest-to-vector-store: deleting existing vector store {existing_id}", flush=True)
            client.vector_stores.delete(vector_store_id=existing_id)

    # -- Create vector store --------------------------------------------------

    first_record = records[0]
    store_metadata = {
        "tenant_id": first_record.get("tenant_id", ""),
        "version_no": first_record.get("version_no", ""),
        "corpus": first_record.get("corpus", ""),
        "environment": "demo",
        "language": first_record.get("language", ""),
        "product": first_record.get("product", ""),
        "product_version": first_record.get("product_version", ""),
        "provider_id": vector_provider,
        "embedding_model": embedding_model,
    }

    create_kwargs: dict = {
        "name": vector_store_name,
        "metadata": store_metadata,
        "extra_body": {"provider_id": vector_provider},
    }
    if "embedding_model" in inspect.signature(client.vector_stores.create).parameters:
        create_kwargs["embedding_model"] = embedding_model
    else:
        create_kwargs["extra_body"]["embedding_model"] = embedding_model

    store = client.vector_stores.create(**create_kwargs)
    vector_store_id = get_value(store, "id", "vector_store_id")
    print(f"ingest-to-vector-store: created vector store {vector_store_name} ({vector_store_id})", flush=True)

    # -- Upload chunks via Files API ------------------------------------------

    uploaded = 0
    with tempfile.TemporaryDirectory(prefix="stage230-kfp-ingest-") as tmpdir:
        tmp = Path(tmpdir)
        for record in records:
            chunk_path = tmp / f"{record['id']}.txt"
            chunk_path.write_text(
                f"{record['title']}\n"
                f"Source: {record['source_url']}\n"
                f"Topic: {record['topic']}\n\n"
                f"{record['text']}\n",
                encoding="utf-8",
            )
            with chunk_path.open("rb") as f:
                file_obj = client.files.create(file=f, purpose="assistants")
            file_id = get_value(file_obj, "id", "file_id")

            client.vector_stores.files.create(
                vector_store_id=vector_store_id,
                file_id=file_id,
                attributes=record_attributes(record),
            )
            uploaded += 1
            if uploaded % 25 == 0 or uploaded == len(records):
                print(f"ingest-to-vector-store: uploaded {uploaded}/{len(records)} chunks...", flush=True)

    print(f"ingest-to-vector-store: ingestion complete ({uploaded} chunks)", flush=True)

    # -- Verify ingestion file counts -----------------------------------------

    store_info = client.vector_stores.retrieve(vector_store_id=vector_store_id)
    file_counts = get_value(store_info, "file_counts") or {}
    completed = int(get_value(file_counts, "completed") or 0)
    failed = int(get_value(file_counts, "failed") or 0)
    in_progress = int(get_value(file_counts, "in_progress") or 0)
    total = int(get_value(file_counts, "total") or 0)

    if failed > 0:
        raise RuntimeError(f"ingest-to-vector-store: {failed} file(s) failed ingestion")
    if in_progress > 0:
        print(f"ingest-to-vector-store: WARNING: {in_progress} file(s) still in progress", flush=True)
    print(
        f"ingest-to-vector-store: file counts - completed={completed}, "
        f"in_progress={in_progress}, failed={failed}, total={total}",
        flush=True,
    )

    # -- Quick search smoke test ----------------------------------------------

    test_query = "How does OpenShift AI use Llama Stack for RAG?"
    results = client.vector_stores.search(
        vector_store_id=vector_store_id,
        query=test_query,
        max_num_results=3,
    )
    result_list = as_items(results)
    if not result_list:
        raise RuntimeError("ingest-to-vector-store: search smoke test returned no results")
    print(
        f"ingest-to-vector-store: search smoke test returned {len(result_list)} result(s) "
        f"for query: '{test_query}'",
        flush=True,
    )

    # -- Emit KFP metrics ----------------------------------------------------

    output_metrics.log_metric("record_count", len(records))
    output_metrics.log_metric("uploaded_count", uploaded)
    output_metrics.log_metric("file_count_completed", completed)
    output_metrics.log_metric("file_count_failed", failed)
    output_metrics.log_metric("file_count_in_progress", in_progress)
    output_metrics.log_metric("file_count_total", total)
    output_metrics.log_metric("search_smoke_result_count", len(result_list))
    output_metrics.metadata["vector_store_id"] = str(vector_store_id)
    output_metrics.metadata["vector_store_name"] = vector_store_name
    output_metrics.metadata["embedding_model"] = embedding_model
    output_metrics.metadata["vector_provider"] = vector_provider
    output_metrics.metadata["llama_stack_base_url"] = llama_stack_base_url

    print("ingest-to-vector-store: done", flush=True)
