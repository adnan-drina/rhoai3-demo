# Step 13: Edge AI — Face Recognition at the Edge

**"From datacenter to edge"** — Deploy the face recognition model to a simulated edge environment with a phone camera app, demonstrating the Red Hat Edge + On-Premise AI/ML pattern.

## The Business Story

Steps 11 and 12 proved that RHOAI 3.3 handles the full ML lifecycle — from interactive training to automated pipelines with quality gates. But models have to run where the data is. Step 13 brings the face recognition model to the edge: a phone camera captures faces, a local model server runs inference, and the model itself flows from the datacenter via GitOps. This is the Red Hat Edge + On-Premise pattern: data acquisition and inference at the edge, model development in the datacenter.

## What It Does

```text
Edge AI (simulated SNO)
├── edge-ai-demo Namespace          → Simulates a Single Node OpenShift edge site
├── kserve-ovms ServingRuntime       → OpenVINO Model Server (same as step-11)
├── face-recognition-edge ISVC       → Same YOLO11 ONNX model, served locally at the edge
├── edge-camera Deployment           → Streamlit app with phone camera + file upload
│   ├── Photo mode                   → st.camera_input — take a photo, run inference
│   └── Live Video mode              → streamlit-webrtc — real-time video with bounding boxes
└── Model delivery                   → Same MinIO bucket as step-11 (GitOps model sync)
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **kserve-ovms** ServingRuntime | OpenVINO Model Server for ONNX models | `edge-ai-demo` |
| **face-recognition-edge** InferenceService | Serves the YOLO11 ONNX model (CPU-only) at the edge | `edge-ai-demo` |
| **edge-camera** Deployment | Streamlit app — phone camera UI, sends frames to local inference | `edge-ai-demo` |
| **edge-camera** Route | HTTPS endpoint (required for browser camera access) | `edge-ai-demo` |

Manifests: [`gitops/step-13-edge-ai/base/`](../../gitops/step-13-edge-ai/base/)

## Architecture

```text
┌─────────── edge-ai-demo namespace (simulates SNO at the edge) ───────────┐
│                                                                           │
│  ┌──────────────────┐    KServe v2 REST    ┌────────────────────────────┐ │
│  │  edge-camera     │ ──────────────────→  │  face-recognition-edge    │ │
│  │  (Streamlit)     │   POST /v2/infer     │  InferenceService         │ │
│  │  Route: HTTPS    │ ←──────────────────  │  (OpenVINO + ONNX)       │ │
│  └──────────────────┘   annotated result   └────────────────────────────┘ │
│       ↑ phone browser                              ↑ model from MinIO     │
└───────┼──────────────────────────────────────────────────────────────────-┘
        │                                            │
        │                        ┌───── GitOps model delivery ─────┐
        │                        │                                  │
┌───────┼──── private-ai namespace (datacenter) ───────────────────────────┐
│       │                                                                   │
│       │    Step 12 Pipeline ──→ Model Registry ──→ MinIO (model.onnx)    │
│       │    (train + evaluate)   (versioned)         (source of truth)    │
│       │                                                                   │
└───────┼──────────────────────────────────────────────────────────────────┘
        │
   Phone camera
   (your phone browser)
```

## Prerequisites

- Steps 01-03 deployed (GPU infra, RHOAI platform, MinIO + namespace)
- Step 11 deployed (face recognition model uploaded to MinIO)
- Edge camera container image built and pushed (see [Building the Container Image](#building-the-container-image))
- `oc` CLI logged in with cluster access

## Building the Container Image

The Streamlit app runs from a pre-built container image. Build and push it before deploying:

```bash
# Using podman (or docker)
podman build -t quay.io/adrina/edge-camera:latest \
  -f steps/step-13-edge-ai/app/Containerfile \
  steps/step-13-edge-ai/app/

podman push quay.io/adrina/edge-camera:latest
```

Or set `BUILD_EDGE_CAMERA=true` and the deploy script will build automatically:

```bash
BUILD_EDGE_CAMERA=true ./steps/step-13-edge-ai/deploy.sh
```

Update the image reference in `gitops/step-13-edge-ai/base/edge-camera/deployment.yaml` if you use a different registry path.

## Deploy

```bash
./steps/step-13-edge-ai/deploy.sh
```

The script:
1. Verifies MinIO and model prerequisites
2. Optionally builds and pushes the edge-camera container image
3. Applies the ArgoCD Application (creates namespace, ServingRuntime, InferenceService, Streamlit app)
4. Waits for the edge InferenceService to become Ready
5. Waits for the Streamlit Deployment to have ready replicas

## Demo Walkthrough

### Scene 1: The Edge Namespace

**Do:** Show the `edge-ai-demo` namespace in the OpenShift Topology view or ArgoCD dashboard. Point out the two components: OpenVINO model server + Streamlit camera app.

**Say:** *"This namespace simulates an edge deployment — a factory floor kiosk, a security checkpoint, a retail store camera. In production, this would be a Single Node OpenShift or MicroShift instance at a remote site, completely separate from the datacenter."*

### Scene 2: Phone Camera — Photo Mode

**Do:** Open the edge-camera Route URL on your phone:

```bash
echo "https://$(oc get route edge-camera -n edge-ai-demo -o jsonpath='{.spec.host}')"
```

Select **Photo** mode. Take a selfie. Show the annotated result.

**Expect:** Green bounding box on your face ("adnan 0.94"), red on others ("unknown_face 0.87"). Latency metric shows ~200-500ms.

**Say:** *"I'm pointing my phone camera at my face and the inference happens entirely at the edge — same namespace, no data leaves this environment. The model knows who I am because it was trained on my photos in Step 11."*

### Scene 3: Live Video — Real-Time Detection

**Do:** Switch to **Live Video** mode. Point the camera at yourself and another person.

**Expect:** Real-time bounding boxes on the video feed. Green for you, red for anyone else.

**Say:** *"Now in real-time — every video frame goes through the YOLO11 model on OpenVINO. CPU-only, no GPU. This is the kind of inference you'd run on edge hardware with limited resources."*

### Scene 4: Model Lifecycle — Datacenter to Edge

**Do:** Open the Model Registry in the RHOAI Dashboard (from Step 12). Show that both `private-ai` and `edge-ai-demo` serve the same model.

**Say:** *"The model was trained centrally by the Step 12 MLOps pipeline, passed quality gates, and got registered. Both the datacenter and the edge serve the same model version from MinIO. When we retrain with better data, the new model flows to every edge device via GitOps. Zero manual intervention."*

### Scene 5 (Optional): Retrain and Update the Edge

**Do:** Run the Step 12 pipeline (`./steps/step-12-mlops-pipeline/run-training-pipeline.sh`). After completion, restart the edge predictor:

```bash
oc delete pod -n edge-ai-demo -l app=face-recognition-edge-predictor
```

Take another photo. Show the model version changed.

**Say:** *"We just retrained centrally and the edge picks up the new model automatically. This is the full Red Hat Edge + On-Premise loop: collect data at the edge, train in the datacenter, deploy back to the edge."*

## What to Verify After Deployment

```bash
# Namespace exists
oc get ns edge-ai-demo

# ServingRuntime exists
oc get servingruntime kserve-ovms -n edge-ai-demo

# InferenceService is Ready
oc get inferenceservice face-recognition-edge -n edge-ai-demo
# Expected: READY = True

# edge-camera pod is running
oc get pods -n edge-ai-demo -l app.kubernetes.io/name=edge-camera
# Expected: 1/1 Running

# Route is accessible (HTTPS)
curl -sk "https://$(oc get route edge-camera -n edge-ai-demo -o jsonpath='{.spec.host}')/_stcore/health"
# Expected: {"status":"ok"}

# Model server responds
oc exec -n edge-ai-demo deploy/face-recognition-edge-predictor -- \
  curl -s localhost:8888/v2/models/face-recognition-edge/ready

# Validate all checks
./steps/step-13-edge-ai/validate.sh
```

## Design Decisions

> **Design Decision:** We use a **separate `edge-ai-demo` namespace** to simulate the network boundary of a real SNO edge site. All edge components are self-contained in this namespace. Migration to actual SNO or MicroShift requires only changing the ArgoCD destination and adding a model sync mechanism.

> **Design Decision:** **Shared MinIO (`storageUri`)** for single-cluster demo. Both the central (`private-ai`) and edge (`edge-ai-demo`) InferenceServices read from the same S3 bucket. In production, a model sync mechanism (Tekton task, CronJob, or S3 replication) would push models to edge-local storage.

> **Design Decision:** **Both `st.camera_input()` and `streamlit-webrtc`** are included. Photo mode is reliable on any phone/browser. Live video is impressive but requires WebRTC connectivity (STUN/TURN). Having both provides a fallback for restrictive network environments.

> **Design Decision:** **CPU-only inference** at the edge. Same rationale as Step 11 — OpenVINO is CPU-optimized, the YOLO11n model is ~11MB. Edge devices often lack GPUs. No GPU allocation conflicts.

> **Design Decision:** **Pre-built container image** for the Streamlit app. Consistent with the rhoai3-demo pattern (all other steps use pre-built images). The Containerfile is in the repo for reproducibility.

> **Design Decision:** **No AMQ Streams / Kafka** in this step. Direct REST from the Streamlit app to the local InferenceService is simpler and sufficient for the demo. Kafka-based streaming is a documented future extension.

## Troubleshooting

### edge-camera pod in CrashLoopBackOff

**Root Cause:** The container image was not pushed to the registry, or the image pull fails.

**Solution:**
```bash
oc describe pod -n edge-ai-demo -l app.kubernetes.io/name=edge-camera | tail -20

# Build and push the image
podman build -t quay.io/adrina/edge-camera:latest \
  -f steps/step-13-edge-ai/app/Containerfile \
  steps/step-13-edge-ai/app/
podman push quay.io/adrina/edge-camera:latest
```

### InferenceService stuck in "Not Ready"

**Root Cause:** The model is not at the expected MinIO path, or the `storage-config` secret is missing/incorrect.

**Solution:**
```bash
oc logs -n edge-ai-demo deploy/face-recognition-edge-predictor

# Verify model exists in MinIO
oc exec -n minio-storage deploy/minio -- mc ls local/models/face-recognition/1/
# Expected: model.onnx

# Verify storage-config secret
oc get secret storage-config -n edge-ai-demo -o yaml
```

### Live Video mode doesn't start (WebRTC)

**Root Cause:** WebRTC requires STUN/TURN server connectivity. Corporate firewalls may block STUN.

**Solution:** Use Photo mode as a fallback. For TURN server support, set the `TURN_SERVER_URL` environment variable and update the `rtc_configuration` in `edge_camera.py`.

### Camera not working on phone

**Root Cause:** Browser camera access (`getUserMedia`) requires HTTPS. The Route must use TLS.

**Solution:**
```bash
# Verify the route has TLS
oc get route edge-camera -n edge-ai-demo -o jsonpath='{.spec.tls.termination}'
# Expected: edge
```

## Future Extensions

- **AMQ Streams (Kafka):** Replace direct REST with Kafka topics for edge-to-central data streaming
- **Edge data feedback:** Save captured frames to MinIO for retraining data (closes the Red Hat feedback loop)
- **MicroShift / SNO:** Move the `edge-ai-demo` namespace to real edge hardware
- **Model sync:** Tekton task that copies models from central MinIO to edge-local S3 on version change
- **Multiple edge sites:** Parameterize the namespace and deploy multiple edge instances via ArgoCD ApplicationSets

## References

- [RHOAI 3.3 — Deploying models (KServe RawDeployment)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/)
- [Red Hat Edge + On-Premise AI/ML Architecture](https://www.redhat.com/en/topics/ai/ai-at-the-edge)
- [MicroShift documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/)
- [Streamlit camera_input API](https://docs.streamlit.io/develop/api-reference/widgets/st.camera_input)
- [streamlit-webrtc](https://github.com/whitphx/streamlit-webrtc)
- [OpenVINO Model Server KServe-compatible API](https://docs.openvino.ai/2026/model-server/ovms_docs_rest_api_kfs.html)

> **See also:** [Step 11 — Face Recognition](../step-11-face-recognition/README.md) (model training), [Step 12 — MLOps Pipeline](../step-12-mlops-pipeline/README.md) (automated lifecycle), [Step 03 — Private AI](../step-03-private-ai/README.md) (MinIO + namespace)
