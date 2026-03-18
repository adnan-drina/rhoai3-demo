"""Restart the face-recognition predictor pod to load the new model."""

from kfp.dsl import component


@component(
    base_image="python:3.11",
    packages_to_install=["kubernetes>=28.0.0"],
)
def deploy_model(
    isvc_name: str,
    namespace: str,
) -> str:
    import time
    from kubernetes import client, config

    config.load_incluster_config()
    v1 = client.CoreV1Api()

    label = f"serving.kserve.io/inferenceservice={isvc_name}"
    pods = v1.list_namespaced_pod(namespace, label_selector=label)

    if not pods.items:
        print(f"No predictor pods found for {isvc_name}")
        return "no-pods"

    for pod in pods.items:
        print(f"Deleting pod {pod.metadata.name}...")
        v1.delete_namespaced_pod(pod.metadata.name, namespace)

    # Wait for new pod to be ready
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
