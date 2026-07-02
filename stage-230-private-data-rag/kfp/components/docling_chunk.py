"""Chunk Docling JSON artifacts with Docling HybridChunker.

Reference component kept for alignment with opendatahub-io/data-processing.
The active pipeline uses ``docling_chunk_and_upload`` which combines chunking
with per-split S3 artifact publishing in a single step.
"""

from kfp import dsl

from .constants import DOCLING_BASE_IMAGE


@dsl.component(base_image=DOCLING_BASE_IMAGE)
def docling_chunk(
    input_path: dsl.Input[dsl.Artifact],
    output_path: dsl.Output[dsl.Artifact],
    max_tokens: int = 512,
    merge_peers: bool = True,
):
    """Produce one HybridChunker JSONL file for each converted Docling JSON file."""

    import json  # pylint: disable=import-outside-toplevel
    from datetime import datetime, timezone  # pylint: disable=import-outside-toplevel
    from pathlib import Path  # pylint: disable=import-outside-toplevel

    from docling.chunking import HybridChunker  # pylint: disable=import-outside-toplevel
    from docling_core.transforms.chunker.tokenizer.huggingface import (  # pylint: disable=import-outside-toplevel
        HuggingFaceTokenizer,
    )
    from docling_core.types import DoclingDocument  # pylint: disable=import-outside-toplevel
    from transformers import AutoTokenizer  # pylint: disable=import-outside-toplevel

    input_dir = Path(input_path.path)
    output_dir = Path(output_path.path)
    output_dir.mkdir(parents=True, exist_ok=True)

    embed_model_id = "sentence-transformers/all-MiniLM-L6-v2"
    hf_tokenizer = AutoTokenizer.from_pretrained(
        embed_model_id,
        resume_download=True,
        timeout=60,
    )
    tokenizer = HuggingFaceTokenizer(tokenizer=hf_tokenizer, max_tokens=max_tokens)
    chunker = HybridChunker(tokenizer=tokenizer, merge_peers=merge_peers)

    json_files = sorted(input_dir.glob("*.json"))
    if not json_files:
        raise RuntimeError(f"docling-chunk: no JSON files found in {input_dir}")

    timestamp = datetime.now(timezone.utc).isoformat()
    chunking_config = {
        "max_tokens": max_tokens,
        "merge_peers": merge_peers,
        "tokenizer_model": embed_model_id,
    }

    for json_file in json_files:
        doc_data = json.loads(json_file.read_text(encoding="utf-8"))
        document = DoclingDocument.model_validate(doc_data)
        chunks = list(chunker.chunk(dl_doc=document))
        output_file = output_dir / f"{json_file.stem}_chunks.jsonl"
        with output_file.open("w", encoding="utf-8") as output:
            for index, chunk in enumerate(chunks, start=1):
                record = {
                    "timestamp": timestamp,
                    "source_document": json_file.name,
                    "chunk_index": index,
                    "chunking_config": chunking_config,
                    "text": chunker.contextualize(chunk=chunk),
                }
                output.write(json.dumps(record, ensure_ascii=False) + "\n")
        print(f"docling-chunk: saved {len(chunks)} chunks to {output_file.name}", flush=True)

    print(f"docling-chunk: processed {len(json_files)} converted document(s)", flush=True)

