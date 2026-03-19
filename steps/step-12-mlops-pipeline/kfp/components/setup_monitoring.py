"""Set up TrustyAI monitoring for the face-recognition-metrics model.

Uploads baseline inference data (confidence, class distribution, detection counts)
to TrustyAI via the metrics proxy model, then subscribes to drift detection.
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

    METRICS_MODEL = "face-recognition-metrics"
    METRICS_URL = f"http://{METRICS_MODEL}-predictor.{namespace}.svc.cluster.local:8080"
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

    # Wait for metrics model to be ready
    print("Waiting for metrics model...")
    for i in range(12):
        try:
            r = requests.get(f"{METRICS_URL}/v2/health/ready", timeout=5)
            if r.status_code == 200:
                print(f"Metrics model ready")
                break
        except Exception:
            pass
        time.sleep(5)
    else:
        print("WARNING: Metrics model not reachable.")
        return "metrics-model-not-ready"

    # Generate baseline data representing normal face recognition results
    print(f"Generating {num_baseline_samples} baseline samples...")
    np.random.seed(42)
    confidence = np.random.normal(loc=0.85, scale=0.08, size=num_baseline_samples).clip(0.3, 1.0)
    class_id = np.random.choice([0.0, 1.0], size=num_baseline_samples, p=[0.4, 0.6])
    num_detections = np.random.poisson(lam=2.0, size=num_baseline_samples).astype(float)
    quality = ((confidence > 0.6) & (num_detections >= 1)).astype(float)

    n = num_baseline_samples

    # Upload baseline to TrustyAI matching MLServer's I/O schema
    training_data = {
        "model_name": METRICS_MODEL,
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
            "model_name": METRICS_MODEL,
            "model_version": "1",
            "outputs": [{
                "name": "predict",
                "datatype": "INT64",
                "shape": [n, 1],
                "data": [[int(quality[i])] for i in range(n)]
            }]
        }
    }

    print("Uploading baseline data to TrustyAI...")
    r = requests.post(f"{TRUSTYAI_URL}/data/upload", headers=headers, json=training_data, timeout=30)
    print(f"  Upload: {r.status_code} - {r.text[:200]}")

    if r.status_code != 200:
        print("WARNING: Baseline upload failed.")
        return "upload-failed"

    # Subscribe to drift detection
    print("Subscribing to meanshift drift...")
    r = requests.post(f"{TRUSTYAI_URL}/metrics/drift/meanshift/request", headers=headers,
                      json={"modelId": METRICS_MODEL, "referenceTag": "TRAINING"}, timeout=10)
    print(f"  Drift: {r.status_code} - {r.text[:200]}")

    print("Subscribing to confidence tracking...")
    r = requests.post(f"{TRUSTYAI_URL}/metrics/identity/request", headers=headers,
                      json={"modelId": METRICS_MODEL, "columnName": "predict-0", "batchSize": 50}, timeout=10)
    print(f"  Identity: {r.status_code} - {r.text[:200]}")

    # Verify
    r = requests.get(f"{TRUSTYAI_URL}/info", headers=headers, timeout=10)
    info = r.json() if r.text else {}
    model_info = info.get(METRICS_MODEL, {})
    obs = model_info.get("data", {}).get("observations", 0)
    metrics = model_info.get("metrics", {}).get("scheduledMetadata", {}).get("metricCounts", {})
    print(f"\nMonitoring configured:")
    print(f"  Observations: {obs}")
    print(f"  Metrics: {metrics}")
    print(f"  View in OpenShift Console > Observe > Metrics")

    return "monitoring-configured"
