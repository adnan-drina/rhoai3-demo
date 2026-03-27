"""
KFP v2 Face Recognition Training Pipeline

Automates the full MLOps lifecycle: dataset preparation, training,
evaluation with quality gate, Model Registry registration, and deployment.

Components are in kfp/components/ following KFP modular best practices.
Reuses the existing DSPA (dspa-rag) in private-ai namespace.

Ref: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_ai_pipelines/
"""

import kfp
from kfp import dsl, kubernetes
from kfp.dsl import PipelineTask
from datetime import datetime

from components.prepare_dataset import prepare_dataset
from components.train_model import train_model
from components.evaluate_model import evaluate_model
from components.register_model import register_model
from components.deploy_model import deploy_model
from components.setup_monitoring import setup_monitoring

MINIO_SECRET = "dspa-minio-credentials"
PIPELINE_PVC = "face-pipeline-workspace"


def _set_resources(
    task: PipelineTask,
    cpu_req: str = "500m", cpu_lim: str = "2",
    mem_req: str = "1Gi", mem_lim: str = "4Gi",
) -> None:
    task.set_cpu_request(cpu_req)
    task.set_cpu_limit(cpu_lim)
    task.set_memory_request(mem_req)
    task.set_memory_limit(mem_lim)


def _inject_minio(task: PipelineTask) -> None:
    kubernetes.use_secret_as_env(
        task, secret_name=MINIO_SECRET,
        secret_key_to_env={
            "accesskey": "AWS_ACCESS_KEY_ID",
            "secretkey": "AWS_SECRET_ACCESS_KEY",
        },
    )


def _mount_pvc(task: PipelineTask) -> None:
    kubernetes.mount_pvc(task, pvc_name=PIPELINE_PVC, mount_path="/shared-data")


@dsl.pipeline(
    name="face-recognition-training",
    description="Train YOLO11 face recognition, evaluate, register, deploy, and configure monitoring",
    pipeline_root="s3://pipelines/",
)
def face_recognition_training_pipeline(
    photos_s3_prefix: str = "s3://face-training-photos/adnan/",
    unknown_s3_prefix: str = "s3://face-training-photos/unknown/",
    model_name: str = "face-recognition",
    version: str = "",
    epochs: int = 15,
    mAP_threshold: float = 0.7,
    minio_endpoint: str = "http://minio.minio-storage.svc.cluster.local:9000",
    registry_url: str = "https://private-ai-registry-rest.apps.cluster-kb4dq.kb4dq.sandbox2381.opentlc.com",
    isvc_namespace: str = "private-ai",
):
    # Auto-generate version if not provided
    if not version:
        version = datetime.now().strftime("%Y%m%d-%H%M%S")

    # --- Step 1: Prepare Dataset ---
    prep_task = prepare_dataset(
        photos_s3_prefix=photos_s3_prefix,
        unknown_s3_prefix=unknown_s3_prefix,
        minio_endpoint=minio_endpoint,
    )
    _inject_minio(prep_task)
    _mount_pvc(prep_task)
    _set_resources(prep_task, cpu_req="1", cpu_lim="2", mem_req="2Gi", mem_lim="4Gi")
    prep_task.set_caching_options(False)
    prep_task.set_retry(num_retries=2, backoff_duration="30s", backoff_factor=2.0)

    # --- Step 2: Train Model ---
    train_task = train_model(epochs=epochs)
    _mount_pvc(train_task)
    train_task.set_cpu_request("2").set_cpu_limit("4")
    train_task.set_memory_request("4Gi").set_memory_limit("8Gi")
    train_task.set_gpu_limit(1)
    kubernetes.add_toleration(train_task, key="nvidia.com/gpu", operator="Exists", effect="NoSchedule")
    kubernetes.add_node_selector(train_task, label_key="node-role.kubernetes.io/gpu", label_value="")
    train_task.after(prep_task)
    train_task.set_caching_options(False)

    # --- Step 3: Evaluate Model ---
    eval_task = evaluate_model(
        onnx_path=train_task.outputs["Output"],
        mAP_threshold=mAP_threshold,
        registry_url=registry_url,
        model_name=model_name,
    )
    _mount_pvc(eval_task)
    _set_resources(eval_task, cpu_req="1", cpu_lim="2", mem_req="2Gi", mem_lim="4Gi")
    eval_task.set_caching_options(False)

    # --- Step 4: Register Model ---
    reg_task = register_model(
        onnx_path=train_task.outputs["Output"],
        model_name=model_name,
        version=version,
        registry_url=registry_url,
        minio_endpoint=minio_endpoint,
    )
    _inject_minio(reg_task)
    _mount_pvc(reg_task)
    _set_resources(reg_task)
    reg_task.after(eval_task)
    reg_task.set_caching_options(False)
    reg_task.set_retry(num_retries=2, backoff_duration="10s", backoff_factor=2.0)

    # --- Step 5: Deploy Model + Link to Registry ---
    dep_task = deploy_model(
        isvc_name=model_name,
        namespace=isvc_namespace,
        registry_url=registry_url,
    )
    _set_resources(dep_task, cpu_req="250m", cpu_lim="500m", mem_req="256Mi", mem_lim="512Mi")
    dep_task.after(reg_task)
    dep_task.set_caching_options(False)
    dep_task.set_retry(num_retries=2, backoff_duration="10s", backoff_factor=2.0)

    # --- Step 6: Setup Monitoring ---
    mon_task = setup_monitoring(
        model_name=model_name,
        namespace=isvc_namespace,
        num_baseline_samples=500,
    )
    _set_resources(mon_task, cpu_req="250m", cpu_lim="500m", mem_req="256Mi", mem_lim="512Mi")
    mon_task.after(dep_task)
    mon_task.set_caching_options(False)
    mon_task.set_retry(num_retries=2, backoff_duration="10s", backoff_factor=2.0)


if __name__ == "__main__":
    kfp.compiler.Compiler().compile(
        face_recognition_training_pipeline,
        "face-recognition-training.yaml",
    )
    print("Compiled: face-recognition-training.yaml")
