"""Trigger the Tekton modelcar-release pipeline to build, push, and promote to edge."""

from kfp.dsl import component


@component(
    base_image="registry.redhat.io/rhai/base-image-cpu-rhel9:3.3.0",
    packages_to_install=["kubernetes>=28.1.0"],
    pip_index_urls=["https://pypi.org/simple"],
)
def package_modelcar(
    model_name: str,
    model_version: str,
    registry_image: str,
    minio_endpoint: str,
    namespace: str,
    timeout_seconds: int = 600,
) -> str:
    """Create a Tekton PipelineRun for modelcar-release and wait for completion.

    Args:
        model_name: Model name for the ModelCar directory layout.
        model_version: Tag for the OCI image (e.g. v4).
        registry_image: Registry path without tag (e.g. quay.io/adrina/face-recognition-modelcar).
        minio_endpoint: MinIO endpoint for downloading the ONNX model.
        namespace: Namespace where the Tekton pipeline is installed.
        timeout_seconds: Max wait time for the PipelineRun to complete.

    Returns:
        The full image reference that was built and pushed.
    """
    import time
    from kubernetes import client, config

    config.load_incluster_config()
    api = client.CustomObjectsApi()

    image_ref = f"{registry_image}:{model_version}"
    run_name = f"modelcar-release-{model_version.replace('.', '-')}"

    pipeline_run = {
        "apiVersion": "tekton.dev/v1",
        "kind": "PipelineRun",
        "metadata": {
            "name": run_name,
            "namespace": namespace,
        },
        "spec": {
            "pipelineRef": {"name": "modelcar-release"},
            "params": [
                {"name": "model-name", "value": model_name},
                {"name": "model-version", "value": model_version},
                {"name": "registry-image", "value": registry_image},
                {"name": "minio-endpoint", "value": minio_endpoint},
            ],
            "workspaces": [
                {
                    "name": "shared-workspace",
                    "volumeClaimTemplate": {
                        "spec": {
                            "accessModes": ["ReadWriteOnce"],
                            "resources": {"requests": {"storage": "1Gi"}},
                        }
                    },
                }
            ],
        },
    }

    print(f"Creating PipelineRun {run_name}...")
    api.create_namespaced_custom_object(
        group="tekton.dev", version="v1", namespace=namespace,
        plural="pipelineruns", body=pipeline_run,
    )

    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        time.sleep(15)
        run = api.get_namespaced_custom_object(
            group="tekton.dev", version="v1", namespace=namespace,
            plural="pipelineruns", name=run_name,
        )
        conditions = run.get("status", {}).get("conditions", [])
        for c in conditions:
            status = c.get("status", "")
            reason = c.get("reason", "")
            print(f"  PipelineRun {run_name}: {reason} ({status})")
            if status == "True" and reason == "Succeeded":
                print(f"ModelCar released: {image_ref}")
                return image_ref
            if status == "False":
                msg = c.get("message", "unknown error")
                raise RuntimeError(f"PipelineRun failed: {msg}")

    raise TimeoutError(f"PipelineRun {run_name} did not complete in {timeout_seconds}s")
