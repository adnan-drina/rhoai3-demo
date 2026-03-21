"""Restart the face-recognition predictor pod and link ISVC to Model Registry."""

from kfp.dsl import component


@component(
    base_image="registry.redhat.io/ubi9/python-311:latest",
    packages_to_install=["kubernetes>=28.0.0", "model-registry>=0.3.7"],
)
def deploy_model(
    isvc_name: str,
    namespace: str,
    registry_url: str = "",
) -> str:
    """Restart the predictor pod and link the InferenceService to Model Registry.

    Args:
        isvc_name: Name of the InferenceService to redeploy.
        namespace: OpenShift namespace where the ISVC is deployed.
        registry_url: Model Registry REST endpoint for linking (optional).

    Returns:
        Name of the ready predictor pod, or a status string on failure.
    """
    import os, time
    from kubernetes import client, config

    config.load_incluster_config()
    v1 = client.CoreV1Api()
    custom = client.CustomObjectsApi()

    # Link ISVC to Model Registry by querying latest version IDs
    if registry_url:
        try:
            os.environ["KF_PIPELINES_SA_TOKEN_PATH"] = "/var/run/secrets/kubernetes.io/serviceaccount/token"
            from model_registry import ModelRegistry
            registry = ModelRegistry(server_address=registry_url, port=443,
                                     author="deploy-step", is_secure=False)
            rm = registry.get_registered_model(isvc_name)
            latest_v = None
            for v in registry.get_model_versions(isvc_name).order_by_id().descending():
                latest_v = v
                break

            if rm and latest_v:
                reg_id = str(rm.id)
                ver_id = str(latest_v.id)
                print(f"Linking ISVC to registry: model={reg_id}, version={ver_id}")
                custom.patch_namespaced_custom_object(
                    group="serving.kserve.io", version="v1beta1",
                    namespace=namespace, plural="inferenceservices",
                    name=isvc_name,
                    body={"metadata": {"labels": {
                        "modelregistry.opendatahub.io/registered-model-id": reg_id,
                        "modelregistry.opendatahub.io/model-version-id": ver_id,
                    }}},
                )
                print("  ISVC labeled with registry IDs")
        except Exception as e:
            print(f"  WARNING: Could not link to registry: {e}")

    # Restart predictor pod to load new model
    label = f"serving.kserve.io/inferenceservice={isvc_name}"
    pods = v1.list_namespaced_pod(namespace, label_selector=label)

    if not pods.items:
        print(f"No predictor pods found for {isvc_name}")
        return "no-pods"

    for pod in pods.items:
        print(f"Deleting pod {pod.metadata.name}...")
        v1.delete_namespaced_pod(pod.metadata.name, namespace)

    print("Waiting for new predictor pod...")
    for i in range(24):
        time.sleep(5)
        pods = v1.list_namespaced_pod(namespace, label_selector=label)
        for pod in pods.items:
            if pod.status.phase == "Running":
                ready = all(
                    cs.ready for cs in (pod.status.container_statuses or [])
                )
                if ready:
                    print(f"Predictor ready: {pod.metadata.name} (took ~{(i+1)*5}s)")
                    return pod.metadata.name

    print("WARNING: Predictor not ready after 120s")
    return "timeout"
