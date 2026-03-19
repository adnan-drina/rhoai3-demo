"""Set up TrustyAI monitoring for the deployed face-recognition model.

Uploads baseline inference results (confidence scores, class distribution)
and subscribes to meanshift drift detection metrics.
"""

from kfp.dsl import component


@component(
    base_image="python:3.11",
    packages_to_install=[
        "requests>=2.31.0",
        "numpy>=1.26.0",
    ],
)
def setup_monitoring(
    model_name: str,
    namespace: str,
    num_baseline_samples: int,
) -> str:
    import json, time
    import requests
    import numpy as np

    TRUSTYAI_URL = f"http://trustyai-service.{namespace}.svc.cluster.local"

    # Wait for TrustyAI to be ready
    print("Waiting for TrustyAI service...")
    for i in range(12):
        try:
            r = requests.get(f"{TRUSTYAI_URL}/info", timeout=5)
            if r.status_code == 200:
                print(f"TrustyAI ready (took ~{(i+1)*5}s)")
                break
        except Exception:
            pass
        time.sleep(5)
    else:
        print("WARNING: TrustyAI not reachable. Skipping monitoring setup.")
        return "trustyai-not-ready"

    # Read SA token for auth
    try:
        with open("/var/run/secrets/kubernetes.io/serviceaccount/token") as f:
            token = f.read()
    except Exception:
        token = None

    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    # Generate synthetic baseline data representing normal inference
    # For CV models, we monitor confidence scores and class predictions
    # rather than raw image tensors
    print(f"Generating {num_baseline_samples} baseline inference samples...")

    np.random.seed(42)
    baseline_confidences = np.random.normal(loc=0.85, scale=0.08, size=num_baseline_samples).clip(0.3, 1.0)
    baseline_classes = np.random.choice([0, 1], size=num_baseline_samples, p=[0.4, 0.6])

    # Format as KServe v2 request/response pairs for TrustyAI
    input_data = {
        "confidence": baseline_confidences.tolist(),
        "class_id": baseline_classes.tolist(),
        "detections_per_image": np.random.poisson(lam=2.0, size=num_baseline_samples).tolist(),
    }

    output_data = {
        "is_adnan": (baseline_classes == 0).astype(float).tolist(),
    }

    training_data = {
        "model_name": model_name,
        "data_tag": "TRAINING",
        "request": {
            "inputs": [
                {
                    "name": name,
                    "shape": [len(values)],
                    "datatype": "FP32",
                    "data": values,
                }
                for name, values in input_data.items()
            ]
        },
        "response": {
            "model_name": model_name,
            "model_version": "1",
            "outputs": [
                {
                    "name": name,
                    "datatype": "FP32",
                    "shape": [len(values)],
                    "data": values,
                }
                for name, values in output_data.items()
            ]
        },
    }

    # Upload baseline data
    print("Uploading baseline data to TrustyAI...")
    r = requests.post(f"{TRUSTYAI_URL}/data/upload", headers=headers, json=training_data, timeout=30)
    print(f"  Upload response: {r.status_code} - {r.text[:200]}")

    # Subscribe to meanshift drift on confidence scores
    print("Subscribing to confidence drift metrics...")
    drift_payload = {
        "modelId": model_name,
        "referenceTag": "TRAINING",
        "fitColumns": ["confidence", "class_id", "detections_per_image"],
    }
    r = requests.post(f"{TRUSTYAI_URL}/metrics/drift/meanshift/request", headers=headers, json=drift_payload, timeout=10)
    print(f"  Drift subscription: {r.status_code} - {r.text[:200]}")

    # Subscribe to identity metric for tracking confidence over time
    print("Subscribing to confidence tracking metric...")
    identity_payload = {
        "modelId": model_name,
        "columnName": "confidence",
        "batchSize": 50,
    }
    r = requests.post(f"{TRUSTYAI_URL}/metrics/identity/request", headers=headers, json=identity_payload, timeout=10)
    print(f"  Identity subscription: {r.status_code} - {r.text[:200]}")

    # Verify setup
    r = requests.get(f"{TRUSTYAI_URL}/info", headers=headers, timeout=10)
    print(f"\nTrustyAI info: {r.text[:300]}")

    print("\nMonitoring setup complete.")
    print("  View metrics: OpenShift Console → Observe → Metrics")
    print("  Drift metric: trustyai_meanshift")
    print("  Confidence tracking: trustyai_identity")

    return "monitoring-configured"
