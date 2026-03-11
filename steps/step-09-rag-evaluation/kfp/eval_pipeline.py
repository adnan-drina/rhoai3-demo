"""
KFP v2 RAG Evaluation Pipeline

2-step pipeline:
  1. scan_tests      -- discover *_tests.yaml in /eval-configs
  2. run_and_score   -- execute RAG agent, score, generate HTML, upload to S3

Reuses lsd-rag (step-09) for both generation and scoring, and
dspa-rag (step-09) for pipeline execution.
No new infrastructure is deployed.

Ref: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/evaluating_ai_systems/evaluating-rag-systems-with-ragas_evaluate
"""

import kfp
from kfp import dsl, kubernetes
from pathlib import Path

from components.scan_tests import scan_tests_component
from components.run_and_score_tests import run_and_score_tests_component


@dsl.pipeline(
    name="rag-eval",
    description="RAG quality evaluation: discover tests, execute RAG agent, score via Llama Stack, publish HTML reports to S3",
    pipeline_root="s3://pipelines/",
)
def rag_eval_pipeline(
    llamastack_url: str = "http://lsd-rag.private-ai.svc:8321",
    s3_report_secret: str = "minio-connection",
    run_id: str = "eval",
):
    pvc_name = "rag-pipeline-workspace"

    # Step 1: Discover test configs
    scan = scan_tests_component(eval_configs_dir="/eval-configs")
    kubernetes.mount_pvc(scan, pvc_name=pvc_name, mount_path="/eval-configs")

    # Step 2: Run all tests, score, generate reports, upload to S3
    run_score = run_and_score_tests_component(
        test_configs=scan.outputs["test_configs"],
        default_llamastack_url=llamastack_url,
        run_id=run_id,
    )
    run_score.after(scan)
    run_score.set_caching_options(False)
    run_score.set_cpu_request("500m")
    run_score.set_cpu_limit("2")
    run_score.set_memory_request("512Mi")
    run_score.set_memory_limit("2Gi")

    kubernetes.mount_pvc(run_score, pvc_name=pvc_name, mount_path="/eval-configs")
    kubernetes.use_secret_as_env(
        run_score,
        secret_name=s3_report_secret,
        secret_key_to_env={
            "AWS_S3_ENDPOINT": "AWS_S3_ENDPOINT",
            "AWS_ACCESS_KEY_ID": "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY": "AWS_SECRET_ACCESS_KEY",
            "AWS_S3_BUCKET": "AWS_S3_BUCKET",
            "AWS_DEFAULT_REGION": "AWS_DEFAULT_REGION",
        },
    )


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
