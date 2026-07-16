"""KFP v2 pipeline: MLflow GenAI evaluation of the Stage 230 RAG assistant.

Replays the stage's 12-question validate-and-protect benchmark through the
same retrieval + generation path the chatbot uses (Llama Stack vector-store
search + chat completions), scores every answer with MLflow GenAI judges
(Correctness, RetrievalGroundedness, RelevanceToQuery, Safety) using the
MaaS-governed gpt-4o-mini as judge model, and records everything in the
product MLflow: the benchmark as an evaluation Dataset, one evaluation Run,
and per-row traces with judge assessments (Datasets / Evaluation runs /
Judges UI areas).

Product authority: RHOAI 3.4 "Working with MLflow" (workspace + RBAC
pseudo-resources; kubernetes-namespaced auth) and "Working with AI
pipelines". Judges run SDK-side against a direct OpenAI-compatible endpoint
because the product MLflow 3.10.1 build does not expose the AI Gateway
(verified live 2026-07-16; see stage PLAN.md).
"""

import argparse
import json
from pathlib import Path

from kfp import compiler, dsl, kubernetes

ROOT = Path(__file__).resolve().parents[1]
_BENCHMARK = json.loads(
    (ROOT / "data/rhoai-product-docs/autorag/benchmark_data.json").read_text(encoding="utf-8")
)

DEFAULT_LLAMA_STACK_BASE_URL = "http://lsd-enterprise-rag-service.enterprise-rag.svc.cluster.local:8321"
DEFAULT_VECTOR_STORE_NAME = "stage230-rhoai-34-product-docs-kfp"
DEFAULT_GENERATION_MODEL = "vllm-inference/nemotron-3-nano-30b-a3b"
DEFAULT_JUDGE_BASE_URL = (
    "http://maas-internal-proxy.enterprise-rag.svc.cluster.local:8080"
    "/models-as-a-service/gpt-4o-mini/v1"
)
DEFAULT_JUDGE_MODEL = "openai:/gpt-4o-mini"
DEFAULT_MLFLOW_TRACKING_URI = "https://mlflow.redhat-ods-applications.svc:8443"
DEFAULT_MLFLOW_EXPERIMENT = "private-rag-chatbot"
DEFAULT_DATASET_NAME = "private-rag-chatbot-benchmark"
MAAS_SECRET = "private-rag-llama-stack-secret"
PIPELINE_ROOT = "s3://enterprise-rag/pipelines/stage-230"


@dsl.component(
    base_image="registry.access.redhat.com/ubi9/python-312:latest",
    packages_to_install=["mlflow[kubernetes]>=3.11,<4", "openai", "requests"],
)
def evaluate_rag_assistant(
    benchmark_json: str,
    llama_stack_base_url: str,
    vector_store_name: str,
    generation_model: str,
    judge_model: str,
    judge_base_url: str,
    mlflow_tracking_uri: str,
    mlflow_experiment: str,
    dataset_name: str,
    top_k: int,
    max_tokens: int,
) -> str:
    """Run mlflow.genai.evaluate over the benchmark via the live RAG path."""
    import json
    import logging
    import os

    import requests

    logging.basicConfig(level=logging.INFO)
    log = logging.getLogger("evaluate-rag")

    # kfp env vars must be compile-time constants, so runtime-parameterized
    # config is applied here before mlflow is imported. OPENAI_API_KEY comes
    # from the MaaS secret via use_secret_as_env.
    os.environ["MLFLOW_TRACKING_URI"] = mlflow_tracking_uri
    os.environ["MLFLOW_TRACKING_AUTH"] = "kubernetes-namespaced"
    os.environ["MLFLOW_TRACKING_INSECURE_TLS"] = "true"
    os.environ["MLFLOW_EXPERIMENT_NAME"] = mlflow_experiment
    os.environ["MLFLOW_DISABLE_TELEMETRY"] = "true"
    os.environ["OPENAI_BASE_URL"] = judge_base_url

    import mlflow
    from mlflow.genai.scorers import (
        Correctness,
        RelevanceToQuery,
        RetrievalGroundedness,
        Safety,
    )

    experiment = mlflow.set_experiment(
        os.environ.get("MLFLOW_EXPERIMENT_NAME", "private-rag-chatbot")
    )
    log.info("experiment id %s", experiment.experiment_id)

    # -- Evaluation dataset (Datasets UI): create once, merge benchmark rows --
    records = []
    for item in json.loads(benchmark_json):
        records.append({
            "inputs": {"question": item["question"]},
            "expectations": {"expected_facts": item["correct_answers"]},
        })

    from mlflow.genai import datasets as genai_datasets

    dataset = None
    try:
        found = genai_datasets.search_datasets(
            experiment_ids=[experiment.experiment_id],
            filter_string=f"name = '{dataset_name}'",
        )
        found_list = list(found) if not isinstance(found, list) else found
        if found_list:
            dataset = found_list[0]
            log.info("found existing dataset %s", dataset.dataset_id)
    except Exception as exc:  # pylint: disable=broad-exception-caught
        log.info("dataset search unavailable (%s); will create", exc)
    if dataset is None:
        dataset = genai_datasets.create_dataset(
            name=dataset_name, experiment_id=[experiment.experiment_id]
        )
        log.info("created dataset %s", dataset.dataset_id)
    dataset.merge_records(records)
    log.info("dataset has benchmark records merged (%d rows)", len(records))

    # -- Resolve the vector store id by display name (chatbot parity) ---------
    stores = requests.get(
        f"{llama_stack_base_url}/v1/vector_stores", timeout=30
    ).json().get("data", [])
    store_id = next(
        (s["id"] for s in stores if s.get("name") == vector_store_name), None
    )
    if not store_id:
        raise RuntimeError(f"vector store {vector_store_name!r} not found")
    log.info("vector store %s -> %s", vector_store_name, store_id)

    # -- predict_fn: the chatbot's Direct-mode flow, server-side --------------
    def predict_fn(question: str) -> dict:
        with mlflow.start_span(name="retrieve", span_type="RETRIEVER") as rspan:
            rspan.set_inputs({"query": question, "vector_store": vector_store_name})
            search = requests.post(
                f"{llama_stack_base_url}/v1/vector_stores/{store_id}/search",
                json={"query": question, "max_num_results": top_k},
                timeout=60,
            ).json()
            documents = []
            for result in search.get("data", []):
                text = ""
                content = result.get("content")
                if isinstance(content, list):
                    text = " ".join(c.get("text", "") for c in content if isinstance(c, dict))
                elif isinstance(content, str):
                    text = content
                attrs = result.get("attributes") or {}
                documents.append({
                    "page_content": text,
                    "metadata": {"doc_uri": attrs.get("source_url") or attrs.get("guide_slug") or "unknown"},
                })
            rspan.set_outputs(documents)

        context = "\n\n".join(
            f"[Source: {d['metadata']['doc_uri']}]: {d['page_content']}" for d in documents
        )
        prompt = (
            "Please answer the following query using the context below.\n\n"
            f"CONTEXT:\n{context}\n\nQUERY:\n{question}"
        )
        with mlflow.start_span(name="generate", span_type="LLM") as lspan:
            lspan.set_inputs({"question": question, "model": generation_model})
            completion = requests.post(
                f"{llama_stack_base_url}/v1/chat/completions",
                json={
                    "model": generation_model,
                    "messages": [
                        {"role": "system", "content": "You are a helpful AI assistant."},
                        {"role": "user", "content": prompt},
                    ],
                    "max_tokens": max_tokens,
                    "temperature": 0.1,
                },
                timeout=300,
            ).json()
            answer = (completion.get("choices") or [{}])[0].get("message", {}).get("content") or ""
            lspan.set_outputs({"response": answer})
        return {"response": answer}

    scorers = [
        Correctness(model=judge_model),
        RelevanceToQuery(model=judge_model),
        RetrievalGroundedness(model=judge_model),
        Safety(model=judge_model),
    ]

    results = mlflow.genai.evaluate(
        data=dataset, predict_fn=predict_fn, scorers=scorers
    )
    metrics = {k: v for k, v in (results.metrics or {}).items()}
    log.info("evaluation run %s metrics: %s", results.run_id, json.dumps(metrics))
    if not metrics:
        raise RuntimeError("evaluation produced no metrics")
    return json.dumps({"run_id": results.run_id, "metrics": metrics})


@dsl.pipeline(
    name="stage-230-mlflow-genai-evaluation",
    description=(
        "Evaluate the Stage 230 RAG assistant against its benchmark with "
        "MLflow GenAI judges (judge model: MaaS gpt-4o-mini); results land "
        "in the product MLflow as dataset + evaluation run + assessments."
    ),
)
def mlflow_genai_evaluation_pipeline(
    llama_stack_base_url: str = DEFAULT_LLAMA_STACK_BASE_URL,
    vector_store_name: str = DEFAULT_VECTOR_STORE_NAME,
    generation_model: str = DEFAULT_GENERATION_MODEL,
    judge_model: str = DEFAULT_JUDGE_MODEL,
    judge_base_url: str = DEFAULT_JUDGE_BASE_URL,
    mlflow_tracking_uri: str = DEFAULT_MLFLOW_TRACKING_URI,
    mlflow_experiment: str = DEFAULT_MLFLOW_EXPERIMENT,
    dataset_name: str = DEFAULT_DATASET_NAME,
    top_k: int = 5,
    max_tokens: int = 2048,
):
    task = evaluate_rag_assistant(
        benchmark_json=json.dumps(_BENCHMARK, ensure_ascii=False),
        llama_stack_base_url=llama_stack_base_url,
        vector_store_name=vector_store_name,
        generation_model=generation_model,
        judge_model=judge_model,
        judge_base_url=judge_base_url,
        mlflow_tracking_uri=mlflow_tracking_uri,
        mlflow_experiment=mlflow_experiment,
        dataset_name=dataset_name,
        top_k=top_k,
        max_tokens=max_tokens,
    )
    task.set_caching_options(False)
    # The judge model is addressed as openai:/gpt-4o-mini; the OpenAI client
    # is routed at the in-cluster MaaS proxy inside the component and
    # authorized with the stage MaaS token from the secret.
    kubernetes.use_secret_as_env(
        task,
        secret_name=MAAS_SECRET,
        secret_key_to_env={"VLLM_API_TOKEN": "OPENAI_API_KEY"},
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    compiler.Compiler().compile(
        pipeline_func=mlflow_genai_evaluation_pipeline, package_path=args.output
    )


if __name__ == "__main__":
    main()
