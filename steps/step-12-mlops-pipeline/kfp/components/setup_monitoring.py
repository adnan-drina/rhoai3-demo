"""Set up TrustyAI monitoring for the face-recognition model.

Uploads baseline inference data and configures SPD fairness metric
directly on the face-recognition InferenceService. The SPD metric
measures whether the model's quality differs between known (adnan)
and unknown faces, visible in the RHOAI Dashboard Model Bias tab.
"""

from kfp.dsl import component


@component(
    base_image="registry.redhat.io/ubi9/python-311:latest",
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
    """Configure TrustyAI monitoring with baseline data and fairness metrics.

    Args:
        model_name: Name of the deployed InferenceService to monitor.
        namespace: OpenShift namespace where TrustyAI and the model are deployed.
        num_baseline_samples: Number of synthetic baseline samples to generate.

    Returns:
        Monitoring status string (e.g. monitoring-configured, trustyai-not-ready).
    """
    import json, time
    import requests
    import numpy as np

    TRUSTYAI_URL = f"http://trustyai-service.{namespace}.svc.cluster.local"
    headers = {"Content-Type": "application/json"}

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

    # Generate baseline data representing normal face recognition results
    # Features: confidence (0-1), class_id (0=adnan, 1=unknown), num_detections
    print(f"Generating {num_baseline_samples} baseline samples...")
    np.random.seed(42)
    n = num_baseline_samples
    confidence = np.random.normal(loc=0.85, scale=0.08, size=n).clip(0.3, 1.0)
    class_id = np.random.choice([0.0, 1.0], size=n, p=[0.4, 0.6])
    num_detections = np.random.poisson(lam=2.0, size=n).astype(float)
    quality = ((confidence > 0.6) & (num_detections >= 1)).astype(float)

    # Upload training baseline to TrustyAI
    training_data = {
        "model_name": model_name,
        "data_tag": "TRAINING",
        "request": {
            "inputs": [{
                "name": "predict",
                "shape": [n, 3],
                "datatype": "FP32",
                "data": [[float(confidence[i]), float(class_id[i]), float(num_detections[i])] for i in range(n)]
            }]
        },
        "response": {
            "model_name": model_name,
            "model_version": "1",
            "outputs": [{
                "name": "predict",
                "datatype": "INT64",
                "shape": [n, 1],
                "data": [[int(quality[i])] for i in range(n)]
            }]
        }
    }

    print("Uploading baseline data...")
    r = requests.post(f"{TRUSTYAI_URL}/data/upload", headers=headers, json=training_data, timeout=30)
    print(f"  Upload: {r.status_code} - {r.text[:200]}")

    if r.status_code != 200:
        print("WARNING: Baseline upload failed.")
        return "upload-failed"

    # Configure SPD fairness metric
    # Measures: does quality differ between adnan (class 0) and unknown (class 1)?
    print("Configuring SPD fairness metric...")
    spd_payload = {
        "modelId": model_name,
        "requestName": "Face Recognition Fairness",
        "protectedAttribute": "predict-1",
        "privilegedAttribute": {"type": "DOUBLE", "value": 0.0},
        "unprivilegedAttribute": {"type": "DOUBLE", "value": 1.0},
        "outcomeName": "predict-0-0",
        "favorableOutcome": {"type": "INT64", "value": 1},
        "batchSize": 50,
    }
    r = requests.post(f"{TRUSTYAI_URL}/metrics/spd/request", headers=headers, json=spd_payload, timeout=10)
    print(f"  SPD: {r.status_code} - {r.text[:200]}")

    # Subscribe to meanshift drift on training baseline
    print("Subscribing to drift detection...")
    r = requests.post(f"{TRUSTYAI_URL}/metrics/drift/meanshift/request", headers=headers,
                      json={"modelId": model_name, "referenceTag": "TRAINING"}, timeout=10)
    print(f"  Drift: {r.status_code} - {r.text[:200]}")

    # Verify
    r = requests.get(f"{TRUSTYAI_URL}/info", headers=headers, timeout=10)
    info = r.json() if r.text else {}
    model_info = info.get(model_name, {})
    obs = model_info.get("data", {}).get("observations", 0)
    metrics = model_info.get("metrics", {}).get("scheduledMetadata", {}).get("metricCounts", {})
    print(f"\nMonitoring configured:")
    print(f"  Model: {model_name}")
    print(f"  Observations: {obs}")
    print(f"  Metrics: {metrics}")
    print(f"  Dashboard: RHOAI > Deployments > {model_name} > Model bias")

    return "monitoring-configured"
