#!/usr/bin/env python3
"""
RAG Ingestion Service — processes PDFs from S3/MinIO using Docling (local, no REST API)
and stores embeddings in Milvus via LlamaStack 0.4.x vector_stores API.

Adapted from: https://github.com/rh-ai-quickstart/RAG/tree/main/ingestion-service
"""

import os
import sys
import time
import yaml
import tempfile
import logging
from pathlib import Path
from typing import List, Dict, Any

from llama_stack_client import LlamaStackClient
from docling.document_converter import DocumentConverter, PdfFormatOption
from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import PdfPipelineOptions
from docling_core.transforms.chunker.hybrid_chunker import HybridChunker
from docling_core.types.doc.labels import DocItemLabel

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


class IngestionService:
    def __init__(self, config_path: str):
        with open(config_path, "r") as f:
            self.config = yaml.safe_load(f)

        self.llama_stack_url = self.config["llamastack"]["base_url"]
        self.client = None

        self.vector_db_config = self.config["vector_db"]

        pipeline_options = PdfPipelineOptions()
        pipeline_options.generate_picture_images = True
        self.converter = DocumentConverter(
            format_options={
                InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options)
            }
        )
        self.chunker = HybridChunker()

    def wait_for_llamastack(self, max_retries: int = 30, retry_delay: int = 5) -> bool:
        logger.info(f"Waiting for Llama Stack at {self.llama_stack_url}...")
        for attempt in range(max_retries):
            try:
                self.client = LlamaStackClient(
                    base_url=self.llama_stack_url, timeout=60.0
                )
                self.client.models.list()
                logger.info("Llama Stack is ready!")
                return True
            except Exception as e:
                if attempt < max_retries - 1:
                    logger.info(
                        f"Attempt {attempt + 1}/{max_retries}: not ready ({e}). Retrying in {retry_delay}s..."
                    )
                    time.sleep(retry_delay)
                else:
                    logger.error(f"Llama Stack unreachable after {max_retries} attempts: {e}")
                    return False
        return False

    def fetch_from_s3(self, config: Dict[str, Any], temp_dir: str) -> List[str]:
        import boto3

        endpoint = config["endpoint"]
        bucket = config["bucket"]
        access_key = config.get("access_key") or os.environ.get("AWS_ACCESS_KEY_ID", "")
        secret_key = config.get("secret_key") or os.environ.get("AWS_SECRET_ACCESS_KEY", "")
        prefix = config.get("prefix", "")

        logger.info(f"Fetching from S3: {endpoint}/{bucket}/{prefix}")

        s3 = boto3.client(
            "s3",
            endpoint_url=endpoint,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            verify=False,
        )

        download_dir = os.path.join(temp_dir, "s3_files")
        os.makedirs(download_dir, exist_ok=True)

        pdf_files = []
        try:
            paginator = s3.get_paginator("list_objects_v2")
            pages = paginator.paginate(Bucket=bucket, Prefix=prefix)

            for page in pages:
                for obj in page.get("Contents", []):
                    key = obj["Key"]
                    if key.lower().endswith(".pdf"):
                        file_path = os.path.join(download_dir, os.path.basename(key))
                        logger.info(f"  Downloading: {key}")
                        s3.download_file(bucket, key, file_path)
                        pdf_files.append(file_path)
        except Exception as e:
            logger.error(f"S3 fetch error: {e}")
            return []

        logger.info(f"Downloaded {len(pdf_files)} PDF files from S3")
        return pdf_files

    def process_documents(self, pdf_files: List[str]) -> List[Dict[str, str]]:
        """Process PDFs locally with Docling, return list of {name, content} dicts."""
        logger.info(f"Processing {len(pdf_files)} documents with docling (local)...")

        chunks = []
        for file_path in pdf_files:
            try:
                basename = os.path.basename(file_path)
                logger.info(f"  Processing: {basename}")

                docling_doc = self.converter.convert(source=file_path).document
                doc_chunks = self.chunker.chunk(docling_doc)

                chunk_count = 0
                md_parts = []
                for chunk in doc_chunks:
                    if any(
                        c.label in [DocItemLabel.TEXT, DocItemLabel.PARAGRAPH]
                        for c in chunk.meta.doc_items
                    ):
                        md_parts.append(chunk.text)
                        chunk_count += 1

                if md_parts:
                    chunks.append({
                        "name": basename.rsplit(".", 1)[0] + ".md",
                        "content": "\n\n".join(md_parts),
                    })
                logger.info(f"    {chunk_count} text chunks -> {len(md_parts)} parts merged")
            except Exception as e:
                logger.error(f"  Error processing {file_path}: {e}")

        logger.info(f"Processed {len(chunks)} documents total")
        return chunks

    def find_or_create_vector_store(self, store_name: str) -> str:
        """Find existing vector store by name, or create a new one. Returns store ID."""
        try:
            existing = self.client.vector_stores.list()
            items = existing.data if hasattr(existing, "data") else existing
            for vs in items:
                if getattr(vs, "name", None) == store_name:
                    logger.info(f"  Found existing vector store: {vs.id} (name={store_name})")
                    return vs.id
        except Exception as e:
            logger.warning(f"  Could not list stores: {e}")

        embedding_model = self.vector_db_config["embedding_model"]
        embedding_dim = self.vector_db_config["embedding_dimension"]
        provider_id = self.vector_db_config.get("provider_id", "milvus-shared")

        vs = self.client.vector_stores.create(
            name=store_name,
            extra_body={
                "embedding_model": embedding_model,
                "embedding_dimension": embedding_dim,
                "provider_id": provider_id,
                "vector_db_id": store_name,
            },
        )
        logger.info(f"  Created vector store: {vs.id} (name={store_name})")
        return vs.id

    def ingest_into_vector_store(
        self, store_id: str, documents: List[Dict[str, str]]
    ) -> int:
        """Upload documents and index them into the vector store. Returns success count."""
        chunk_size = self.vector_db_config.get("chunk_size_tokens", 512)
        chunk_overlap = max(1, chunk_size // 4)
        chunking_strategy = {
            "type": "static",
            "static": {
                "max_chunk_size_tokens": chunk_size,
                "chunk_overlap_tokens": chunk_overlap,
            },
        }

        success = 0
        for doc in documents:
            try:
                content_bytes = doc["content"].encode("utf-8")
                uploaded = self.client.files.create(
                    file=(doc["name"], content_bytes),
                    purpose="assistants",
                )
                self.client.vector_stores.files.create(
                    vector_store_id=store_id,
                    file_id=uploaded.id,
                    chunking_strategy=chunking_strategy,
                )
                logger.info(f"  [OK] {doc['name']} -> {uploaded.id}")
                success += 1
            except Exception as e:
                logger.error(f"  [FAIL] {doc['name']}: {e}")

        return success

    def process_pipeline(self, pipeline_name: str, pipeline_config: Dict[str, Any]) -> bool:
        logger.info(f"\n{'=' * 60}")
        logger.info(f"Pipeline: {pipeline_name}")
        logger.info(f"{'=' * 60}")

        if not pipeline_config.get("enabled", False):
            logger.info(f"  Disabled, skipping")
            return True

        store_name = pipeline_config["vector_store_name"]
        source = pipeline_config["source"]
        source_config = pipeline_config["config"]

        with tempfile.TemporaryDirectory() as temp_dir:
            if source == "S3":
                pdf_files = self.fetch_from_s3(source_config, temp_dir)
            else:
                logger.error(f"  Unsupported source type: {source}")
                return False

            if not pdf_files:
                logger.warning(f"  No PDF files found")
                return False

            documents = self.process_documents(pdf_files)
            if not documents:
                logger.warning(f"  No documents processed")
                return False

            store_id = self.find_or_create_vector_store(store_name)
            count = self.ingest_into_vector_store(store_id, documents)
            logger.info(f"  Inserted {count}/{len(documents)} documents into '{store_name}'")
            return count == len(documents)

    def run(self):
        logger.info("Starting RAG Ingestion Service")

        if not self.wait_for_llamastack():
            logger.error("Llama Stack unreachable. Exiting.")
            sys.exit(1)

        pipelines = self.config.get("pipelines", {})
        total = len(pipelines)
        successful = failed = skipped = 0

        for name, cfg in pipelines.items():
            if not cfg.get("enabled", False):
                skipped += 1
                continue
            try:
                if self.process_pipeline(name, cfg):
                    successful += 1
                else:
                    failed += 1
            except Exception as e:
                logger.error(f"Pipeline '{name}' error: {e}")
                failed += 1

        logger.info(f"\n{'=' * 60}")
        logger.info(f"Summary: {successful} ok, {failed} failed, {skipped} skipped (of {total})")
        logger.info(f"{'=' * 60}")
        sys.exit(1 if failed > 0 else 0)


if __name__ == "__main__":
    config_file = os.getenv("INGESTION_CONFIG", "/config/ingestion-config.yaml")
    if not os.path.exists(config_file):
        logger.error(f"Config not found: {config_file}")
        sys.exit(1)
    IngestionService(config_file).run()
