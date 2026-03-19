# Continuation Prompt: TrustyAI Metrics Proxy for Face Recognition

## Context

Steps 11 (Face Recognition) and 12 (MLOps Pipeline) are fully implemented and working. The pipeline trains YOLO11, evaluates, registers in Model Registry, deploys to KServe, and configures TrustyAI. However, TrustyAI's drift monitoring requires tabular inference payloads, and our face recognition model's I/O is large image tensors that don't fit TrustyAI's format.

## Objective

Implement a **metrics-proxy InferenceService** using RHOAI 3.3's **MLServer runtime** (Tech Preview) that:
1. Receives face recognition results as tabular input (confidence, class_id, num_detections)
2. Returns a quality score (simple threshold classifier)
3. TrustyAI monitors this service's I/O through the RHOAI Dashboard Model Bias tab
4. Demonstrates both **MLServer** and **TrustyAI Dashboard monitoring** as RHOAI 3.3 capabilities

## Architecture

```
Face Recognition Pipeline (Step 12)
  └─ Step 6: setup_monitoring
       │
       ▼
face-recognition-metrics (MLServer)
  ├── Input: confidence (FP32), class_id (FP32), num_detections (FP32)
  ├── Output: quality_score (FP32)
  ├── Runtime: MLServer ServingRuntime for KServe
  └── Model: scikit-learn threshold classifier (.joblib)
       │
       ▼
TrustyAI monitors this service:
  ├── Dashboard: Model Bias tab shows drift metrics
  ├── Prometheus: trustyai_meanshift, trustyai_identity
  └── Features: confidence distribution, class balance, detection counts
```

## Implementation Steps

### 1. Create a simple scikit-learn model

A notebook or script that creates a minimal threshold classifier:

```python
from sklearn.tree import DecisionTreeClassifier
import numpy as np
import joblib

# Synthetic training data: confidence, class_id, num_detections -> quality (0/1)
X = np.random.rand(1000, 3)  # [confidence, class_id, num_detections]
y = (X[:, 0] > 0.5).astype(int)  # quality = 1 if confidence > 0.5
model = DecisionTreeClassifier(max_depth=2)
model.fit(X, y)
joblib.dump(model, "model.joblib")
```

Upload `model.joblib` to MinIO at `s3://models/face-recognition-metrics/model.joblib`.

### 2. Deploy with MLServer

Following RHOAI 3.3 docs: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/deploying_models#deploying-models-using-mlserver-runtime_rhoai-user

InferenceService with environment variables:
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: face-recognition-metrics
  namespace: private-ai
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      runtime: mlserver  # Use the platform MLServer template
      modelFormat:
        name: sklearn
      storageUri: s3://models/face-recognition-metrics/
      env:
        - name: MLSERVER_MODEL_IMPLEMENTATION
          value: mlserver_sklearn.SKLearnModel
        - name: MLSERVER_MODEL_URI
          value: /mnt/models/model.joblib
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 500m
          memory: 1Gi
```

### 3. Configure TrustyAI monitoring

Upload training baseline data via TrustyAI's `/data/upload` API with the model name `face-recognition-metrics`. Then subscribe to drift metrics via the Dashboard's Model Bias tab.

### 4. Update pipeline step 6

After deploying the face recognition model, the monitoring step:
1. Runs inference on test images via the YOLO model
2. Extracts confidence, class_id, num_detections from results
3. Sends these as tabular inference requests to `face-recognition-metrics`
4. TrustyAI intercepts and monitors

### 5. Update GitOps manifests

Add to `gitops/step-12-mlops-pipeline/base/`:
- `metrics-model/inferenceservice.yaml` - MLServer InferenceService
- `metrics-model/upload-job.yaml` - Job to upload sklearn model to MinIO
- Update `kustomization.yaml`

## Key References

- MLServer deployment: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/deploying_models#deploying-models-using-mlserver-runtime_rhoai-user
- TrustyAI monitoring: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/monitoring_your_ai_systems/
- AI500 Jukebox TrustyAI pattern: https://github.com/rhoai-mlops/jukebox/tree/main/4-metrics
- Existing step-12 code: steps/step-12-mlops-pipeline/
- Session doc: docs/face-recognition-mlops-session.md

## What's Already Working

- TrustyAIService CR deployed and running in private-ai
- Pipeline runs 6 steps successfully (monitoring step exists but data format doesn't match YOLO)
- Model Registry has face-recognition with 3 versions
- InferenceService linked to registry via labels
- MLServer template available on cluster (RHOAI 3.3 Tech Preview)

## Demo Narrative Addition

"We have two serving paradigms: OpenVINO for the YOLO vision model, and MLServer for the metrics classifier. TrustyAI monitors the metrics model, giving us real-time drift detection on face recognition confidence and class distribution. When confidence starts dropping -- maybe due to new lighting conditions or camera angles -- the dashboard shows it immediately."
