# Step 13: Edge AI — Face Recognition at the Edge
**"From Datacenter to Edge"** — Deploy the face recognition model to a simulated edge environment with a camera app, demonstrating the Red Hat Edge + On-Premise AI/ML pattern.

## Overview

Steps 11 and 12 proved that Red Hat OpenShift AI handles the full ML lifecycle — from interactive training to automated pipelines with quality gates. But models have to run where the data is. As Red Hat states: *"Red Hat OpenShift AI allows training, deployment, and monitoring AI/ML workloads across various environments — cloud, on-premise datacenters, or at the edge."*

Step 13 brings the face recognition model to the edge: a camera captures faces, a local model server runs inference, and the model itself flows from the datacenter via GitOps. As Red Hat's AI adoption guide explains: *"Edge and on-premise deployments deliver low-latency inference for real-time applications without round-trip calls to external APIs."* This is the **Red Hat Edge + On-Premise** pattern — data acquisition and inference at the edge, model development in the datacenter, all managed by the same platform.

This step demonstrates RHOAI's **Disconnected environments and edge** capability: the same model trained centrally deploys to edge sites with zero code changes, proving that Red Hat OpenShift AI supports deployment across cloud, on-premise, and edge environments.

### What Gets Deployed

```text
Edge AI (simulated SNO)
├── edge-ai-demo Namespace          → Simulates a Single Node OpenShift edge site
├── kserve-ovms ServingRuntime       → OpenVINO Model Server (same as step-11)
├── face-recognition-edge ISVC       → Same YOLO11 ONNX model, served locally at the edge
├── edge-camera Deployment           → Streamlit app with camera + file upload
│   ├── Photo mode                   → st.camera_input — single shot, full annotated image
│   └── Live Video mode              → camera_input_live — continuous capture with detection overlay
└── Model delivery                   → Same MinIO bucket as step-11 (GitOps model sync)
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **kserve-ovms** ServingRuntime | OpenVINO Model Server for ONNX models | `edge-ai-demo` |
| **face-recognition-edge** InferenceService | Serves the YOLO11 ONNX model (CPU-only) at the edge | `edge-ai-demo` |
| **edge-camera** Deployment | Streamlit app — camera UI, sends frames to local inference | `edge-ai-demo` |
| **edge-camera** Route | HTTPS endpoint (required for browser camera access) | `edge-ai-demo` |

Manifests: [`gitops/step-13-edge-ai/base/`](../../gitops/step-13-edge-ai/base/)

#### Platform Features

| | Feature | Status |
|---|---|---|
| RHOAI | Disconnected environments and edge | Introduced |
| RHOAI | Optimized model serving (OpenVINO at edge) | Used |

#### Architecture

```text
┌─────────── edge-ai-demo namespace (simulates SNO at the edge) ───────────┐
│                                                                           │
│  ┌──────────────────┐    KServe v2 REST    ┌────────────────────────────┐ │
│  │  edge-camera     │ ──────────────────→  │  face-recognition-edge    │ │
│  │  (Streamlit)     │  binary tensors      │  InferenceService         │ │
│  │  Route: HTTPS    │ ←──────────────────  │  (OpenVINO + ONNX)       │ │
│  └──────────────────┘   annotated result   └────────────────────────────┘ │
│       ↑ browser                                    ↑ model from MinIO     │
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
   Laptop or phone camera
   (browser)
```

### Building the Container Image

The Streamlit app runs from a pre-built container image. Build for **linux/amd64** (the cluster architecture) and push:

```bash
podman build --platform linux/amd64 \
  -t quay.io/adrina/edge-camera:latest \
  -f steps/step-13-edge-ai/app/Containerfile \
  steps/step-13-edge-ai/app/

podman push quay.io/adrina/edge-camera:latest
```

> **Note:** If building on Apple Silicon (M1/M2/M3), the `--platform linux/amd64` flag is required. Without it, the image will be ARM-based and fail with `Exec format error` on the cluster.

Or set `BUILD_EDGE_CAMERA=true` and the deploy script will build automatically:

```bash
BUILD_EDGE_CAMERA=true ./steps/step-13-edge-ai/deploy.sh
```

Update the image reference in `gitops/step-13-edge-ai/base/edge-camera/deployment.yaml` if you use a different registry path. The quay.io repository must be **public** for the cluster to pull it.

### Design Decisions

> **Separate `edge-ai-demo` namespace** to simulate the network boundary of a real SNO edge site. All edge components are self-contained in this namespace. Migration to actual SNO or MicroShift requires only changing the ArgoCD destination and adding a model sync mechanism.

> **Shared MinIO (`storageUri`)** for single-cluster demo. Both the central (`private-ai`) and edge (`edge-ai-demo`) InferenceServices read from the same S3 bucket. In production, a model sync mechanism (Tekton task, CronJob, or S3 replication) would push models to edge-local storage.

> **`camera_input_live`** for Live Video instead of `streamlit-webrtc`. WebRTC failed because the pod can't reach STUN servers over UDP (restricted egress). `camera_input_live` captures frames via `getUserMedia` + `canvas.toDataURL` and sends them over the existing Streamlit WebSocket — plain HTTPS, no STUN/TURN required.

> **gRPC for inference** using `tritonclient[grpc]`. Both OVMS (this step) and NVIDIA Triton (step-13b) implement the KServe v2 gRPC protocol on port 8001. gRPC provides ~30x lower latency compared to REST JSON. The same `inference.py` client code works against both servers. Ref: [YOLOv5 gRPC vs REST benchmark](https://ai-on-openshift.io/demos/yolov5-training-serving/yolov5-training-serving/)

> **`@st.fragment`** wraps the live camera section. Only the camera fragment re-executes on each new frame — the sidebar, header, and mode selector are not re-rendered. This is the [Streamlit-recommended pattern](https://docs.streamlit.io/develop/concepts/architecture/fragments) for live/streaming UI sections.

> **CPU-only inference** (OpenVINO) on the simulated edge. The YOLO11n model is ~11MB and runs at ~100ms on CPU. Step 13b demonstrates GPU inference on real edge hardware with NVIDIA Triton.

> **Shared application code** with step-13b. `inference.py`, `edge_camera.py`, `requirements.txt`, and the Containerfile are identical. Only the `GRPC_ENDPOINT` env var differs between the two deployments. Must be built with `--platform linux/amd64` on Apple Silicon.

> **No AMQ Streams / Kafka** in this step. gRPC between the Streamlit app and the model server is sufficient for the demo. Kafka-based streaming is a documented future extension.

### Future Improvements

#### Mobile live video support

The `camera_input_live` community component was not designed for mobile viewports where layout reflow can push its iframe off-screen. A proper fix requires one of:

- **Custom Streamlit component** — build a dedicated camera component that renders detection results as a canvas overlay inside the same iframe, eliminating layout shift entirely
- **Progressive Web App (PWA)** — a standalone mobile app using the phone camera natively, posting frames to the inference endpoint via REST. Eliminates the Streamlit iframe constraint
- **Server-Sent Events (SSE)** — a thin FastAPI endpoint that accepts JPEG frames and streams back annotated JPEGs, rendered in an `<img>` tag that updates in-place

#### Additional extensions

- **AMQ Streams (Kafka):** Replace direct REST with Kafka topics for edge-to-central data streaming
- **Edge data feedback:** Save captured frames to MinIO for retraining data (closes the Red Hat feedback loop)
- **MicroShift / SNO:** Move the `edge-ai-demo` namespace to real edge hardware
- **Model sync:** Tekton task that copies models from central MinIO to edge-local S3 on version change
- **Multiple edge sites:** Parameterize the namespace and deploy multiple edge instances via ArgoCD ApplicationSets

### Deploy

**Prerequisites:**

- Steps 01-03 deployed (GPU infra, RHOAI platform, MinIO + namespace)
- Step 11 deployed (face recognition model uploaded to MinIO)
- Edge camera container image built and pushed (see [Building the Container Image](#building-the-container-image))
- `oc` CLI logged in with cluster access

```bash
./steps/step-13-edge-ai/deploy.sh     # ArgoCD app: namespace + ServingRuntime + ISVC + Streamlit app
./steps/step-13-edge-ai/validate.sh   # Infrastructure + edge readiness checks
```

The script:
1. Verifies MinIO and model prerequisites
2. Optionally builds and pushes the edge-camera container image
3. Applies the ArgoCD Application (creates namespace, ServingRuntime, InferenceService, Streamlit app)
4. Waits for the edge InferenceService to become Ready
5. Waits for the Streamlit Deployment to have ready replicas

### What to Verify After Deployment

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
# Expected: ok

# Model server responds
oc exec -n edge-ai-demo deploy/face-recognition-edge-predictor -- \
  curl -s localhost:8888/v2/models/face-recognition-edge/ready

# Validate all checks
./steps/step-13-edge-ai/validate.sh
```

## The Demo

> In this demo, we deploy the face recognition model to a simulated edge site on Red Hat OpenShift — a camera app captures live faces, a local OpenVINO model server runs inference, and the model flows from the datacenter via GitOps. Same model, same platform, different location.

### The Edge Namespace

> This namespace simulates an edge deployment — a factory floor kiosk, a security checkpoint, a retail store camera. In production, this would be a Single Node OpenShift or MicroShift instance at a remote site, completely separate from the datacenter.

1. Show the `edge-ai-demo` namespace in the OpenShift Topology view or ArgoCD dashboard
2. Point out the two components: OpenVINO model server + Streamlit camera app

**Expect:** The namespace contains a self-contained edge deployment: model server, camera app, route — no dependencies on the `private-ai` datacenter namespace at runtime.

> All edge components are self-contained in one namespace. Red Hat OpenShift AI deploys the same model serving infrastructure — KServe, OpenVINO — to any namespace, any cluster, any site. The architecture is identical whether this runs on the central OCP cluster or a Single Node OpenShift at a remote location.

### Photo Mode — The Wow Moment

> We point a camera at a real person and the inference happens entirely at the edge — same namespace, no data leaves this environment. The model knows who we are because it was trained on our photos in Step 11.

1. Open the edge-camera Route URL on your laptop or phone:

```bash
echo "https://$(oc get route edge-camera -n edge-ai-demo -o jsonpath='{.spec.host}')"
```

2. Select **Photo** mode
3. Take a selfie and show the annotated result with bounding boxes

**Expect:** Green bounding box on your face ("adnan 0.91"), red on others ("unknown_face 0.60"). Latency metric shows ~100-150ms.

> Face recognized in 100 milliseconds — CPU-only, no GPU. The same model from Step 11, served by OpenVINO at the edge. This is how Red Hat OpenShift AI brings AI to where the data lives — a REST API running on edge hardware with minimal resources.

### Live Video — Continuous Detection

> Beyond single photos, the edge camera app supports continuous video capture — every frame goes through the YOLO11 model for real-time face detection and recognition.

1. Switch to **Live Video** mode on a laptop
2. Point the camera at yourself and another person

**Expect:** Camera feed updates continuously (~1.5s interval). Annotated image with bounding boxes appears below. Detection metrics update in real time.

> Continuous inference at 100ms per frame on CPU — no GPU, no cloud round-trip. This is the kind of inference you run on edge hardware with limited resources, and Red Hat OpenShift AI makes it operationally identical to the datacenter deployment.

### Model Lifecycle — Datacenter to Edge

> The model was trained centrally, evaluated by an automated pipeline, and registered in the Model Registry. Both the datacenter and the edge serve the same version. When we retrain, the new model flows to every edge device via GitOps.

1. Open the **Model Registry** in the RHOAI Dashboard (from Step 12)
2. Show that both `private-ai` and `edge-ai-demo` serve the same model

**Expect:** The same model version is deployed at both locations, with the Model Registry tracking provenance.

> Train in the datacenter, deploy to the edge — and when you retrain with better data, the new model flows to every edge device via GitOps. Zero manual intervention. This is the complete Red Hat Edge + On-Premise lifecycle: data acquisition at the edge, model development in the datacenter, delivery back to the edge through the same platform.

### (Optional) Retrain and Update the Edge

> We close the loop by retraining the model centrally and watching it propagate to the edge deployment — proving the full lifecycle works end to end.

1. Run the Step 12 pipeline:

```bash
./steps/step-12-mlops-pipeline/run-training-pipeline.sh
```

2. After completion, restart the edge predictor:

```bash
oc delete pod -n edge-ai-demo -l app=face-recognition-edge-predictor
```

3. Take another photo and show the model version changed

**Expect:** The edge picks up the new model. Detection results may differ slightly as the new model has different weights.

> Retrained centrally, deployed to the edge automatically. The full Red Hat Edge + On-Premise loop: collect data at the edge, train in the datacenter, deploy back to the edge — all managed by Red Hat OpenShift AI.

## Key Takeaways

**For business stakeholders:**

- AI inference runs where the data lives — the same model trained centrally deploys to edge sites with zero code changes and minimal hardware (CPU-only)
- The Red Hat Edge + On-Premise pattern separates concerns: data acquisition and inference at the edge, model development and governance in the datacenter
- GitOps-driven model delivery means edge devices always run the latest approved model — no manual intervention, no site visits
- *"AI adoption is rarely a single project."* The datacenter-to-edge progression demonstrates iterative adoption — use learnings from initial deployments to refine your approach, expand to new use cases, and build internal capabilities

**For technical teams:**

- KServe + OpenVINO serves ONNX models at ~100ms on CPU — the same `kserve-ovms` ServingRuntime works identically on central OCP and edge namespaces
- The edge namespace is fully self-contained — migration to actual SNO or MicroShift requires only changing the ArgoCD destination
- gRPC inference via `tritonclient[grpc]` provides ~30x lower latency vs REST, with the same client code working against both OpenVINO (this step) and NVIDIA Triton (step 13b)

## Known Limitations

### Live Video mode does not work reliably on mobile phones

**Symptom:** Camera captures the first frame but stops streaming after the first inference result renders.

**Root Cause:** The `camera_input_live` component runs in a Streamlit iframe. When the inference result renders below the camera, the page layout shifts, pushing the camera iframe partially off-screen. Mobile browsers (Safari, Chrome) aggressively pause `setInterval` timers in off-screen iframes to conserve battery, which stops frame capture.

**Workaround:** Use **Photo mode** on phones — it uses Streamlit's built-in `st.camera_input()` which handles mobile camera permissions natively and works reliably on all devices.

**Status:** Live Video works well on laptops where the viewport is large enough to keep the camera iframe on-screen. A proper mobile fix requires a custom Streamlit component that either: (a) renders results as a lightweight overlay inside the camera iframe itself, or (b) uses `IntersectionObserver` to detect when the iframe scrolls off-screen and compensate. See [Future Improvements](#future-improvements).

## Troubleshooting

### edge-camera pod — "Exec format error"

**Root Cause:** The container image was built for ARM (Apple Silicon) but the cluster runs x86_64.

**Solution:**
```bash
podman build --platform linux/amd64 \
  -t quay.io/adrina/edge-camera:latest \
  -f steps/step-13-edge-ai/app/Containerfile \
  steps/step-13-edge-ai/app/
podman push quay.io/adrina/edge-camera:latest
```

### edge-camera pod in CrashLoopBackOff / ImagePullBackOff

**Root Cause:** The container image was not pushed, or the quay.io repository is private.

**Solution:**
```bash
oc describe pod -n edge-ai-demo -l app.kubernetes.io/name=edge-camera | tail -20

# Ensure the quay.io repo is public:
# https://quay.io/repository/adrina/edge-camera?tab=settings
```

### InferenceService stuck in "Not Ready"

**Root Cause:** The model is not at the expected MinIO path, or the `storage-config` secret is missing.

**Solution:**
```bash
oc logs -n edge-ai-demo deploy/face-recognition-edge-predictor

# Verify model exists in MinIO
oc exec -n minio-storage deploy/minio -- mc ls local/models/face-recognition/1/
# Expected: model.onnx

# Verify storage-config secret
oc get secret storage-config -n edge-ai-demo -o yaml
```

### Camera not working in browser

**Root Cause:** Browser camera access (`getUserMedia`) requires HTTPS. The Route must use TLS.

**Solution:**
```bash
oc get route edge-camera -n edge-ai-demo -o jsonpath='{.spec.tls.termination}'
# Expected: edge
```

## References

- [RHOAI 3.3 — Deploying models (KServe RawDeployment)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/)
- [Red Hat Edge + On-Premise AI/ML Architecture](https://www.redhat.com/en/topics/ai/ai-at-the-edge)
- [KServe Binary Tensor Data Extension](https://kserve.github.io/website/docs/concepts/architecture/data-plane/v2-protocol/binary-tensor-data-extension)
- [MicroShift documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/)
- [Streamlit camera_input API](https://docs.streamlit.io/develop/api-reference/widgets/st.camera_input)
- [Streamlit fragments](https://docs.streamlit.io/develop/concepts/architecture/fragments)
- [streamlit-camera-input-live](https://github.com/blackary/streamlit-camera-input-live)
- [OpenVINO Model Server KServe-compatible API](https://docs.openvino.ai/2026/model-server/ovms_docs_rest_api_kfs.html)
- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet)
- [Get started with AI for enterprise organizations — Red Hat](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)

> **See also:** [Step 11 — Face Recognition](../step-11-face-recognition/README.md) (model training), [Step 12 — MLOps Pipeline](../step-12-mlops-pipeline/README.md) (automated lifecycle), [Step 13b — Edge AI on MicroShift](../step-13b-edge-ai-microshift/README.md) (real edge hardware), [Step 03 — Private AI](../step-03-private-ai/README.md) (MinIO + namespace)

## Next Steps

- **Step 13b**: [Edge AI on MicroShift](../step-13b-edge-ai-microshift/README.md) — Real edge hardware with NVIDIA Triton GPU inference on MicroShift 4.20
