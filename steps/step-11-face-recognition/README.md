# Step 11: Face Recognition — Predictive AI on RHOAI
**"Beyond LLMs"** — Train a YOLO11 face recognition model, export to ONNX, and serve it via KServe RawDeployment with OpenVINO Model Server. CPU-only inference, no GPU required.

## Overview

**Build, train, and operationalize predictive AI on the same platform as generative AI.** You do not adopt a separate toolchain for traditional ML: the **serving**, **pipelines**, **observability**, and **governance** you established in earlier themes carry forward here. Red Hat's AI adoption guide describes predictive AI as helping organizations *"identify and connect patterns, historical events, and real-time data to predict future outcomes with extremely high accuracy"* — including demand forecasting, preventive maintenance, and operational planning. In the visual domain, *"Computer vision enables object detection, image classification, and segmentation, which is particularly valuable in manufacturing and quality control."* As Red Hat states: *"Red Hat OpenShift AI allows training, deployment, and monitoring AI/ML workloads across various environments — cloud, on-premise datacenters, or at the edge."*

The **same platform** that serves LLMs with vLLM (Steps 05–10) also supports computer vision: this step trains a YOLO11 model, exports to ONNX, and serves it with OpenVINO on KServe — **one infrastructure footprint, one operational model** for both generative and predictive AI. The "WhoAmI — Visual Identity" scenario is the proof moment: face recognition runs on **Red Hat OpenShift AI 3.3** alongside your GenAI stack, not on an island.

This is where Choice shows up at the platform level: the same governed platform supports both generative and predictive patterns. This step demonstrates RHOAI's **Model development and customization** and **Model training and experimentation** capabilities for predictive AI — proving that the same platform that serves LLMs also handles computer vision training, ONNX export, and CPU-based inference.

### What Gets Deployed

```text
Face Recognition
├── kserve-ovms ServingRuntime   → OpenVINO Model Server for ONNX models
├── face-recognition ISVC        → Serves YOLO11 ONNX model (CPU-only, ~11MB)
├── face-recognition-wb Notebook → JupyterLab with git-synced notebooks (4 notebooks)
├── upload-face-model Job        → Downloads pre-trained ONNX from HuggingFace to MinIO
└── Notebook workflow: Explore → Retrain → Test → Query via REST v2 API
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **kserve-ovms** ServingRuntime | OpenVINO Model Server for ONNX models | `private-ai` |
| **face-recognition** InferenceService | Serves the YOLO11 ONNX model (CPU-only) | `private-ai` |
| **face-recognition-wb** Notebook | JupyterLab workbench with git-synced notebooks | `private-ai` |
| **upload-face-model** Job | Downloads pre-trained ONNX from HuggingFace to MinIO | `minio-storage` |

Manifests: [`gitops/step-11-face-recognition/base/`](../../gitops/step-11-face-recognition/base/)

#### Platform Features

| | Feature | Status |
|---|---|---|
| RHOAI | Model training and experimentation | Introduced |
| RHOAI | Model development and customization (JupyterLab workbench) | Used |
| RHOAI | Optimized model serving (OpenVINO) | Used |

### Design Decisions

> **KServe RawDeployment** (not ModelMesh) because ModelMesh is deprecated in RHOAI 3.3 ([release notes section 6.1.9](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/release_notes/support-removals_relnotes)). The `kserve-ovms` template is the platform-recommended approach for ONNX/OpenVINO models.

> **CPU inference, GPU training.** OpenVINO serves the ONNX model on CPU workers (no GPU needed for inference). Training uses GPU when available (`device=0`, `workers=0` to avoid `/dev/shm` limits in containers) for ~1 hour on L4, with CPU fallback (~6 hours). The YOLO11m ONNX model is ~77MB.

> **YOLO11m** (medium, 20M params). YOLO11n (2.6M) lacked capacity to distinguish similar-looking people. YOLO11m provides 7.7x more parameters for learning subtle facial features. YOLO26m was tested but fails on small datasets (<1K images) due to its NMS-free architecture requiring COCO-scale data.

> **Auto-annotation** using the pre-trained YOLO11-face detector eliminates manual bounding box labeling. Users only need to provide raw selfie photos.

> **Identity uniqueness constraint** at inference. A known person can only appear once per frame — any duplicate "adnan" detection is guaranteed to be a false positive. The `enforce_identity_uniqueness()` function in `remote_infer.py` keeps only the highest-confidence detection for the identified class and reclassifies duplicates as unknown. This is a standard domain-constrained post-processing technique used in production identity-aware detection systems, combined with a confidence threshold of 0.6 (vs default 0.25) to filter low-confidence predictions.

> **Real colleague photos + HuggingFace portraits for unknown class.** Using surveillance-style datasets (e.g. WIDER Face) as negatives causes the model to classify any close-up face as "adnan" because the visual domain is too different. The `unknown_face/` directory contains ~600 photos of real colleagues from the same events and camera conditions. Combined with 200 high-quality portraits downloaded from [HuggingFace](https://huggingface.co/datasets/prithivMLmods/Realistic-Face-Portrait-1024px) at runtime, this produces mAP50 >0.93 vs ~0.76 with WIDER Face alone.

> **Pre-trained model fallback.** A pre-trained ONNX model is uploaded to MinIO by the deploy script so the InferenceService works even without running the training notebooks.

> **Dashboard template annotations on ServingRuntime.** The RHOAI Dashboard identifies runtimes by matching `opendatahub.io/template-name` and `opendatahub.io/template-display-name` annotations against platform templates in `redhat-ods-applications`. Without these, runtimes show as "Unknown Serving Runtime" in the Model Deployments view. The `kserve-ovms` ServingRuntime includes `template-name: kserve-ovms` and `template-display-name: OpenVINO Model Server` to match the platform template.

### Deploy

**Prerequisites:**

- Steps 01-03 deployed (GPU infra, RHOAI platform, MinIO + namespace)
- `oc` CLI logged in with cluster access
- ~200+ selfie photos for custom face training (optional — a pre-trained model is provided)
- ~600+ colleague/stranger photos for the unknown class (uploaded to MinIO and workbench)
- 1 test video (10-30s, you + another person) for the video demo (optional)

```bash
./steps/step-11-face-recognition/deploy.sh     # ArgoCD app: ServingRuntime + ISVC + Workbench + model upload
./steps/step-11-face-recognition/validate.sh   # Infrastructure + model readiness checks
```

The script:
1. Verifies MinIO and namespace prerequisites
2. Checks for the `kserve-ovms` platform template
3. Uploads the pre-trained YOLO11n-face ONNX model to MinIO
4. Applies the ArgoCD Application (creates ServingRuntime, InferenceService, Workbench)
5. Uploads notebook assets to the workbench (images, videos, training photos)

The workbench (`face-recognition-wb`) is deployed via ArgoCD with a git-sync initContainer that clones notebooks, `remote_infer.py`, and `requirements.txt` from the repo. Binary assets (photos, test images, video) are uploaded separately via `upload-to-workbench.sh`.

#### Uploading notebook assets

The deploy script automatically uploads assets from the local `notebooks/` directory if they exist. To upload or re-upload manually:

```bash
./steps/step-11-face-recognition/upload-to-workbench.sh
```

This copies folders to the workbench pod via `oc cp`:

| Folder | Contents | Purpose |
|--------|----------|---------|
| `notebooks/images/` | Test face and group photos (.jpg) | Used by notebooks 01, 03, 04 |
| `notebooks/videos/` | Test video (.mov) | Used by notebooks 03, 04 for video inference |
| `notebooks/my_photos/` | ~200+ selfie photos (.jpeg) | Training data — class 0 (adnan) |
| `notebooks/unknown_face/` | ~200+ colleague photos (.jpg) | Training data — class 1 (unknown_face) |

These folders are gitignored (binary assets). The workbench PVC persists them across pod restarts.

### What to Verify After Deployment

```bash
# ServingRuntime exists
oc get servingruntime kserve-ovms -n private-ai

# Model uploaded to MinIO
oc get job upload-face-model -n minio-storage -o jsonpath='{.status.succeeded}'
# Expected: 1

# InferenceService is Ready
oc get inferenceservice face-recognition -n private-ai
# Expected: READY = True

# Workbench is Running
oc get notebook face-recognition-wb -n private-ai
oc get pod face-recognition-wb-0 -n private-ai
# Expected: 2/2 Running

# Notebook assets uploaded
oc exec -n private-ai face-recognition-wb-0 -c face-recognition-wb -- \
  bash -c 'for d in images videos my_photos; do [ -d $d ] && echo "$d: $(ls $d | wc -l) files"; done'

# Validate all checks
./steps/step-11-face-recognition/validate.sh
```

## The Demo

> In this demo, we walk through the complete face recognition workflow on Red Hat OpenShift AI — from exploring a generic face detector, to retraining a personalized model, to serving it via KServe and OpenVINO. Four notebooks, one platform, the same RHOAI infrastructure used for LLMs in earlier steps.

### Explore Face Detection

> YOLO11 is a state-of-the-art object detection model. Out of the box, it detects faces — but it can't tell whose face it is. We start by exploring what the base model can and can't do.

1. Open the workbench from the RHOAI Dashboard: **Data Science Projects** → **private-ai** → **Workbenches** → **face-recognition-wb** → **Open**
2. Run `01-explore-yolo11-face.ipynb`

**Expect:** YOLO11 detects faces in test images with bounding boxes, confidence scores, and pixel coordinates. All detections are labelled as the generic class `face`.

> Every face is just "face" — no identity, no distinction. The model detects but doesn't recognize. Red Hat OpenShift AI provides the notebook environment and GPU access to retrain it on our own data.

### Retrain for Your Face

> With ~200 selfie photos and ~600 colleague photos, we retrain the YOLO11 model to distinguish a specific person from everyone else — all inside the RHOAI workbench with GPU access.

1. Verify `my_photos/` is populated (uploaded by `deploy.sh` or `upload-to-workbench.sh`)
2. Run `02-retrain-face-model.ipynb`

**Expect:** The notebook auto-annotates your photos, combines real colleague photos (`unknown_face/`) with 200 HuggingFace portraits for the "unknown" class, trains YOLO11m on GPU for ~1 hour (100 epochs, `workers=0`), and exports to ONNX.

> YOLO11m's 20M parameters and face-optimized augmentation deliver production-grade accuracy (mAP50 >0.93). The same RHOAI platform that serves LLMs also provides the GPU compute and notebook environment for training computer vision models.

### The Wow Moment — Video Recognition

> The retrained model should now identify a specific person by name, in real time, from video — distinguishing them from everyone else in the frame.

1. Run `03-test-retrained-model.ipynb`
2. Verify `videos/test_group_video.mov` exists

**Expect:** An annotated video plays inline — green boxes on your face ("adnan 0.94"), red boxes on others ("unknown_face 0.87").

> The model processes every frame and correctly identifies specific individuals versus unknown faces. This ran locally on the ONNX model — next we see it through the production serving platform that Red Hat OpenShift AI provides.

### Production Inference via Model Server

> The notebook proved the model works. Now we query it through the KServe REST v2 API — the same way a production application would consume this model, served on OpenVINO Model Server with CPU-only inference.

1. Run `04-query-model-server.ipynb`

**Expect:** Same recognition results, but now coming from the KServe REST API endpoint served by OpenVINO.

> Same model, same accuracy — now served on OpenVINO Model Server via KServe RawDeployment. No GPU needed for inference. This is how Red Hat OpenShift AI serves predictive AI models in production: a REST API that any service can call, deployed and managed via GitOps like every other platform component.

## Key Takeaways

**For business stakeholders:**

- Support predictive and generative AI on one platform
- Reuse the same controls and operations for computer vision workloads
- Avoid a separate toolchain for classical ML

**For technical teams:**

- Train and serve a predictive model in the same governed environment used for GenAI
- Reuse serving, observability, and governance patterns already in place
- Show that efficient CPU inference can fit real deployment needs

## Troubleshooting

### InferenceService stuck in "Not Ready"

**Root Cause:** The model is not at the expected MinIO path, or the `storage-config` secret is missing.

**Solution:**
```bash
# Check the predictor pod logs
oc logs -n private-ai deploy/face-recognition-predictor

# Verify model exists in MinIO
oc exec -n minio-storage deploy/minio -- mc ls local/models/face-recognition/1/
# Expected: model.onnx

# Verify storage-config secret exists
oc get secret storage-config -n private-ai
```

### kserve-ovms ServingRuntime image not pulling

**Root Cause:** The placeholder image digest in the ServingRuntime YAML needs to be replaced with the actual image from your cluster.

**Solution:**
```bash
# Get the correct image from the platform template
oc process -n redhat-ods-applications kserve-ovms \
  -o jsonpath='{.items[0].spec.containers[0].image}'

# Update the ServingRuntime manifest with the correct digest
```

### Training notebook fails with "No photos found"

**Root Cause:** No images in the `my_photos/` directory inside the workbench.

**Solution:**
```bash
# Upload from local machine
./steps/step-11-face-recognition/upload-to-workbench.sh

# Or verify they're already there
oc exec -n private-ai face-recognition-wb-0 -c face-recognition-wb -- ls my_photos/ | head
```

### Workbench pod not starting

**Root Cause:** PVC binding or image pull issue.

**Solution:**
```bash
oc describe pod face-recognition-wb-0 -n private-ai | tail -20
oc get events -n private-ai --sort-by='.lastTimestamp' | grep face-recognition | tail -10
```

## References

- [RHOAI 3.3 — Deploying models (KServe RawDeployment)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/)
- [RHOAI 3.3 — Release notes: ModelMesh deprecation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/release_notes/support-removals_relnotes)
- [Ultralytics YOLO11 documentation](https://docs.ultralytics.com/models/yolo11/)
- [YOLO11 data augmentation](https://docs.ultralytics.com/guides/yolo-data-augmentation/)
- [OpenVINO Model Server KServe-compatible API](https://docs.openvino.ai/2026/model-server/ovms_docs_rest_api_kfs.html)
- [Pre-trained model (PyTorch): AdamCodd/YOLOv11n-face-detection](https://huggingface.co/AdamCodd/YOLOv11n-face-detection) — used by notebooks for exploration
- [Pre-trained model (ONNX): ariakang/YOLOv11n-face-detection](https://huggingface.co/ariakang/YOLOv11n-face-detection) — deployed to MinIO by `deploy.sh`
- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet)
- [Get started with AI for enterprise organizations — Red Hat](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)

> **See also:** [Step 05 — LLM Serving on vLLM](../step-05-llm-on-vllm/README.md) (GPU model serving pattern), [Step 09 — Guardrails](../step-09-guardrails/README.md) (CPU-only InferenceService pattern)

## Next Steps

- **Step 12**: [MLOps Training Pipeline](../step-12-mlops-pipeline/README.md) — Automate the face recognition workflow as a Kubeflow Pipeline with quality gates and Model Registry integration
