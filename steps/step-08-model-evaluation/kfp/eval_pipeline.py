"""
KFP v2 RAG Evaluation Pipeline

2-step pipeline:
  1. scan_tests      -- discover *_tests.yaml in /eval-configs
  2. run_and_score   -- execute RAG agent, score via mistral-3-bf16 (direct vLLM judge),
                       generate HTML reports, upload to MinIO

Components are in kfp/components/ following KFP modular best practices.
Reuses lsd-rag (step-07) for generation and dspa-rag (step-07) for pipeline execution.
Judge model (mistral-3-bf16) is called directly via its vLLM endpoint.

Ref: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate
"""

import kfp
from kfp import dsl, kubernetes
from kfp.dsl import PipelineTask
from pathlib import Path

from components.scan_tests import scan_tests_component
from components.run_and_score_tests import run_and_score_tests_component

S3_SECRET = "minio-connection"
PIPELINE_PVC = "rag-pipeline-workspace"


def _set_resources(
    task: PipelineTask,
    cpu_req: str = "500m", cpu_lim: str = "2",
    mem_req: str = "512Mi", mem_lim: str = "2Gi",
) -> None:
    task.set_cpu_request(cpu_req)
    task.set_cpu_limit(cpu_lim)
    task.set_memory_request(mem_req)
    task.set_memory_limit(mem_lim)


def _inject_minio(task: PipelineTask) -> None:
    kubernetes.use_secret_as_env(
        task,
        secret_name=S3_SECRET,
        secret_key_to_env={
            "AWS_S3_ENDPOINT": "AWS_S3_ENDPOINT",
            "AWS_ACCESS_KEY_ID": "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY": "AWS_SECRET_ACCESS_KEY",
            "AWS_S3_BUCKET": "AWS_S3_BUCKET",
            "AWS_DEFAULT_REGION": "AWS_DEFAULT_REGION",
        },
    )


def _mount_pvc(task: PipelineTask) -> None:
    kubernetes.mount_pvc(task, pvc_name=PIPELINE_PVC, mount_path="/shared-data")


@dsl.pipeline(
    name="rag-eval",
    description="RAG quality evaluation: discover tests, execute RAG agent, score via mistral-3-bf16, publish HTML reports to MinIO",
    pipeline_root="s3://pipelines/",
)
def rag_eval_pipeline(
    llamastack_url: str = "http://lsd-rag-service.private-ai.svc.cluster.local:8321",
    run_id: str = "eval",
):
    # --- Step 1: Discover Tests ---
    scan = scan_tests_component(eval_configs_dir="/shared-data/eval-configs")
    _mount_pvc(scan)
    scan.set_caching_options(False)

    # --- Step 2: Run & Score ---
    run_score = run_and_score_tests_component(
        test_configs=scan.outputs["test_configs"],
        default_llamastack_url=llamastack_url,
        run_id=run_id,
    )
    run_score.after(scan)
    _inject_minio(run_score)
    _mount_pvc(run_score)
    _set_resources(run_score)
    run_score.set_caching_options(False)


if __name__ == "__main__":
    script_dir = Path(__file__).parent.resolve()
    step_dir = script_dir.parent
    repo_root = step_dir.parent.parent
    artifacts_dir = repo_root / "artifacts"
    artifacts_dir.mkdir(exist_ok=True)

    out = artifacts_dir / "rag-eval.yaml"
    kfp.compiler.Compiler().compile(
        pipeline_func=rag_eval_pipeline,
        package_path=str(out),
    )
    print(f"Pipeline compiled: {out}")
