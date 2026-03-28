# Step 11: Face Recognition — Predictive AI on RHOAI

**"Beyond LLMs"** — Train a YOLO11 face recognition model, export to ONNX, and serve it via KServe RawDeployment with OpenVINO Model Server. CPU-only inference, no GPU required.

## The Business Story

Generative AI gets the headlines, but enterprises also run traditional ML workloads — image classification, object detection, anomaly recognition. Step 11 proves that RHOAI 3.3 handles **both** on the same platform: LLMs on vLLM (Steps 05-10) and predictive AI on OpenVINO (this step). The "WhoAmI — Visual Identity" scenario lets you train a model that literally recognizes your face.

## What It Does

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

## Prerequisites

- Steps 01-03 deployed (GPU infra, RHOAI platform, MinIO + namespace)
- `oc` CLI logged in with cluster access
- ~200+ selfie photos for custom face training (optional — a pre-trained model is provided)
- ~600+ colleague/stranger photos for the unknown class (uploaded to MinIO and workbench)
- 1 test video (10-30s, you + another person) for the video demo (optional)

## Deploy

```bash
./steps/step-11-face-recognition/deploy.sh
```

The script:
1. Verifies MinIO and namespace prerequisites
2. Checks for the `kserve-ovms` platform template
3. Uploads the pre-trained YOLO11n-face ONNX model to MinIO
4. Applies the ArgoCD Application (creates ServingRuntime, InferenceService, Workbench)
5. Uploads notebook assets to the workbench (images, videos, training photos)

The workbench (`face-recognition-wb`) is deployed via ArgoCD with a git-sync initContainer that clones notebooks, `remote_infer.py`, and `requirements.txt` from the repo. Binary assets (photos, test images, video) are uploaded separately via `upload-to-workbench.sh`.

### Uploading notebook assets

The deploy script automatically uploads assets from the local `notebooks/` directory if they exist. To upload or re-upload manually:

```bash
./steps/step-11-face-recognition/upload-to-workbench.sh
```

This copies three folders to the workbench pod via `oc cp`:

| Folder | Contents | Purpose |
|--------|----------|---------|
| `notebooks/images/` | Test face and group photos (.jpg) | Used by notebooks 01, 03, 04 |
| `notebooks/videos/` | Test video (.mov) | Used by notebooks 03, 04 for video inference |
| `notebooks/my_photos/` | ~200+ selfie photos (.jpeg) | Training data — class 0 (adnan) |
| `notebooks/unknown_face/` | ~200+ colleague photos (.jpg) | Training data — class 1 (unknown_face) |

These folders are gitignored (binary assets). The workbench PVC persists them across pod restarts.

## Demo Walkthrough

### Scene 1: Explore Face Detection (Notebook 01)

**Do:** Open the workbench from the RHOAI Dashboard: **Data Science Projects** -> **private-ai** -> **Workbenches** -> **face-recognition-wb** -> **Open**. Run `01-explore-yolo11-face.ipynb`.

**Expect:** YOLO11 detects faces in test images with bounding boxes, confidence scores, and pixel coordinates. All detections are labelled as the generic class `face`.

**Say:** *"YOLO11 is a state-of-the-art object detection model. Out of the box, it detects faces — but it can't tell whose face it is. All detections are just 'face'. We need to retrain it."*

### Scene 2: Retrain for Your Face (Notebook 02)

**Do:** Verify `my_photos/` is populated (uploaded by `deploy.sh` or `upload-to-workbench.sh`). Run `02-retrain-face-model.ipynb`.

**Expect:** The notebook auto-annotates your photos, combines real colleague photos (`unknown_face/`) with 200 HuggingFace portraits for the "unknown" class, trains YOLO11m on GPU for ~1 hour (100 epochs, `workers=0`), and exports to ONNX.

**Say:** *"With ~200 selfie photos, ~600 colleague photos, and an hour of GPU training, we have a personalized face recognition model. YOLO11m's 20M parameters and face-optimized augmentation — mosaic for group scenes, horizontal flips for symmetry, no mixup to preserve identity features — deliver production-grade accuracy (mAP50 >0.93)."*

### Scene 3: The Wow Moment — Video Recognition (Notebook 03)

**Do:** Run `03-test-retrained-model.ipynb`. Verify `videos/test_group_video.mov` exists.

**Expect:** An annotated video plays inline — green boxes on your face ("adnan 0.94"), red boxes on others ("unknown_face 0.87").

**Say:** *"The model processes every frame and correctly identifies me versus an unknown person. This ran locally on the ONNX model — now let's see it through the production serving platform."*

### Scene 4: Production Inference via Model Server (Notebook 04)

**Do:** Run `04-query-model-server.ipynb`.

**Expect:** Same results, but now coming from the KServe REST API endpoint.

**Say:** *"Same model, same results — but now served on OpenVINO Model Server via KServe RawDeployment. No GPU needed. This is how you'd integrate it into a production application: a REST API that any service can call."*

## What to Verify After Deployment

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

## Design Decisions

> **Design Decision:** We use **KServe RawDeployment** (not ModelMesh) because ModelMesh is deprecated in RHOAI 3.3 ([release notes section 6.1.9](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/release_notes/support-removals_relnotes)). The `kserve-ovms` template is the platform-recommended approach for ONNX/OpenVINO models.

> **Design Decision:** **CPU inference, GPU training.** OpenVINO serves the ONNX model on CPU workers (no GPU needed for inference). Training uses GPU when available (`device=0`, `workers=0` to avoid `/dev/shm` limits in containers) for ~1 hour on L4, with CPU fallback (~6 hours). The YOLO11m ONNX model is ~77MB.

> **Design Decision:** **YOLO11m** (medium, 20M params). YOLO11n (2.6M) lacked capacity to distinguish similar-looking people. YOLO11m provides 7.7x more parameters for learning subtle facial features. YOLO26m was tested but fails on small datasets (<1K images) due to its NMS-free architecture requiring COCO-scale data.

> **Design Decision:** **Auto-annotation** using the pre-trained YOLO11-face detector eliminates manual bounding box labeling. Users only need to provide raw selfie photos.

> **Design Decision:** **Real colleague photos + HuggingFace portraits for unknown class.** Using surveillance-style datasets (e.g. WIDER Face) as negatives causes the model to classify any close-up face as "adnan" because the visual domain is too different. The `unknown_face/` directory contains ~600 photos of real colleagues from the same events and camera conditions. Combined with 200 high-quality portraits downloaded from [HuggingFace](https://huggingface.co/datasets/prithivMLmods/Realistic-Face-Portrait-1024px) at runtime, this produces mAP50 >0.93 vs ~0.76 with WIDER Face alone.

> **Design Decision:** **Pre-trained model fallback**. A pre-trained ONNX model is uploaded to MinIO by the deploy script so the InferenceService works even without running the training notebooks.

> **Dashboard template annotations on ServingRuntime.** The RHOAI Dashboard identifies runtimes by matching `opendatahub.io/template-name` and `opendatahub.io/template-display-name` annotations against platform templates in `redhat-ods-applications`. Without these, runtimes show as "Unknown Serving Runtime" in the Model Deployments view. The `kserve-ovms` ServingRuntime includes `template-name: kserve-ovms` and `template-display-name: OpenVINO Model Server` to match the platform template.

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
- [Pre-trained model (PyTorch): AdamCodd/YOLOv11n-face-detection](https://huggingface.co/AdamCodd/YOLOv11n-face-detection) -- used by notebooks for exploration
- [Pre-trained model (ONNX): ariakang/YOLOv11n-face-detection](https://huggingface.co/ariakang/YOLOv11n-face-detection) -- deployed to MinIO by `deploy.sh`

> **See also:** [Step 05 — LLM Serving on vLLM](../step-05-llm-on-vllm/README.md) (GPU model serving pattern), [Step 09 — Guardrails](../step-09-guardrails/README.md) (CPU-only InferenceService pattern)
