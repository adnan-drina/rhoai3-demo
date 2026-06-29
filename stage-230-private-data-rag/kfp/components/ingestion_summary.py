"""Create dashboard-visible ingestion metrics and validate RAG retrieval."""

from typing import List

from kfp.dsl import Metrics, Output, component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.4.0",
    packages_to_install=["llama-stack-client>=0.7,<0.8"],
    pip_index_urls=["https://pypi.org/simple"],
)
def ingestion_summary_component(
    llamastack_url: str,
    vector_db_id: str,
    vector_store_ids: List[str],
    inference_model: str,
    workspace_path: str,
    metrics: Output[Metrics],
) -> str:
    """Summarize ingestion and verify the whoami RAG query path."""
    import json
    import os

    from llama_stack_client import LlamaStackClient

    log_path = os.path.join(workspace_path, "ingestion-log.jsonl")
    entries = []
    if os.path.exists(log_path):
        with open(log_path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if line:
                    entries.append(json.loads(line))

    successful = [
        item for item in entries
        if item.get("status") == "success" and item.get("vector_db") == vector_db_id
    ]
    if not successful:
        raise RuntimeError(f"No successful ingestion entries found for {vector_db_id}")

    client = LlamaStackClient(base_url=llamastack_url, timeout=300.0)
    if not vector_store_ids:
        raise RuntimeError("No vector store ids were returned by the registration step")
    vector_store_id = vector_store_ids[0]
    query = "Who is Adnan Drina and what is his current role?"
    rag_response = client.vector_stores.search(
        vector_store_id=vector_store_id,
        query=query,
        max_num_results=5,
    )
    context = str(rag_response)
    if not any(term in context.lower() for term in ["adnan", "red hat", "principal", "solution architect"]):
        raise RuntimeError(f"Unexpected RAG context: {context[:500]}")

    completion = client.chat.completions.create(
        model=inference_model,
        messages=[
            {"role": "system", "content": "Answer only from the provided context. Be concise."},
            {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {query}"},
        ],
        temperature=0.1,
    )
    answer = completion.choices[0].message.content
    if not answer:
        raise RuntimeError("Nemotron returned an empty RAG answer")

    metrics.log_metric("documents_ingested", len(successful))
    metrics.log_metric("vector_db", vector_db_id)
    metrics.log_metric("vector_store_id", vector_store_id)
    metrics.log_metric("rag_context_chars", len(context))

    print(f"RAG answer: {answer[:400]}")
    return f"{len(successful)} document(s) ingested into {vector_db_id}"
