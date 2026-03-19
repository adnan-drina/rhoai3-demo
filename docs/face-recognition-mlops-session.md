# Session: Face Recognition (Steps 11-12) — Predictive AI + MLOps Pipeline

## Objective

Add predictive AI / computer vision capabilities to the RHOAI 3.3 demo:
1. **Step 11** — Interactive face recognition with YOLO11 + OpenVINO (notebooks)
2. **Step 12** — Automated MLOps training pipeline with Model Registry + TrustyAI monitoring (KFP v2)

Inspired by the [Parasol Insurance workshop](https://rh-aiservices-bu.github.io/parasol-insurance/) (YOLOv8 car accident detection) and the [AI500 MLOps Jukebox](https://github.com/rhoai-mlops/jukebox) (full ML lifecycle with Model Registry).

## Reference Documentation

- [RHOAI 3.3 — Deploying models (KServe RawDeployment)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/)
- [RHOAI 3.3 — Release notes: ModelMesh deprecation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/release_notes/support-removals_relnotes)
- [RHOAI 3.3 — Working with AI Pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_ai_pipelines/)
- [RHOAI 3.3 — Monitoring your AI Systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/monitoring_your_ai_systems/)
- [Fine-tune AI pipelines in RHOAI 3.3](https://developers.redhat.com/articles/2026/02/26/fine-tune-ai-pipelines-red-hat-openshift-ai)
- [Ultralytics YOLO11](https://docs.ultralytics.com/models/yolo11/)
- [OpenVINO Model Server KServe API](https://docs.openvino.ai/2026/model-server/ovms_docs_rest_api_kfs.html)

## Critical Findings

### ModelMesh is deprecated in RHOAI 3.3

The Parasol Insurance workshop uses ModelMesh + OpenVINO. In RHOAI 3.3, ModelMesh is deprecated since version 2.19. The replacement is **KServe RawDeployment** with the `kserve-ovms` template:

```bash
oc process -n redhat-ods-applications -o yaml kserve-ovms | oc apply -f -
```

We use an explicit YAML in GitOps for reproducibility. The image digest was obtained from the cluster:
```
registry.redhat.io/rhoai/odh-openvino-model-server-rhel9@sha256:defd01ac5a37a6138de73a8f1b10c676a2efa617238049378f8bc63fb0eb00c6
```

### YOLO11 replaces YOLOv8

YOLO11 (Sep 2024) has 22% fewer parameters and higher mAP than YOLOv8 (Jan 2023). Same `ultralytics` package. Pre-trained face detection model from [AdamCodd/YOLOv11n-face-detection](https://huggingface.co/AdamCodd/YOLOv11n-face-detection) (PyTorch) and [ariakang/YOLOv11n-face-detection](https://huggingface.co/ariakang/YOLOv11n-face-detection) (ONNX).

### KF_PIPELINES_SA_TOKEN_PATH for Model Registry auth

Pipeline pods authenticate with the Model Registry using the ServiceAccount token. The `model-registry` SDK reads this automatically:

```python
os.environ["KF_PIPELINES_SA_TOKEN_PATH"] = "/var/run/secrets/kubernetes.io/serviceaccount/token"
registry = ModelRegistry(server_address=registry_url, port=443, author="pipeline", is_secure=False)
```

Pattern from [rhoai-mlops/jukebox](https://github.com/rhoai-mlops/jukebox/blob/main/3-prod_datascience/save_model.py).

### Pipeline pod constraints

Pipeline pods on this cluster:
- **Cannot reach github.com** (GitHub asset downloads fail) -- pre-upload `yolo11n.pt` to MinIO
- **Run as non-root** -- cannot use `apt-get install` for system libraries
- **OpenCV needs headless mode** -- `pip install --force-reinstall --no-deps opencv-python-headless` replaces the full OpenCV that ultralytics installs (which requires libGL)
- **Read-only root filesystem** -- YOLO writes to `/runs` by default; set `project=` parameter to write to shared PVC

## Implementation Outcome

### Step 11: Face Recognition (Inner Loop)

| Deliverable | Status | Notes |
|-------------|--------|-------|
| KServe + OpenVINO serving (CPU-only) | Done | `kserve-ovms` ServingRuntime + `face-recognition` InferenceService |
| 4 Jupyter notebooks | Done | Originally 5 (merged 01+02); explore, retrain, test+video, query server |
| Git-sync workbench | Done | `face-recognition-wb` Notebook CR with initContainer |
| Upload-to-workbench script | Done | `upload-to-workbench.sh` copies images/videos/photos via `oc cp` |
| Video inference (local + REST) | Done | ffmpeg re-encode to H.264 for inline JupyterLab playback |
| Model upload to MinIO from notebook | Done | Notebook 03 uploads ONNX + restarts predictor |
| Compliance review fixes | Done | Removed gpu:0, added part-of labels, removed gp3-csi hardcode |

### Step 12: MLOps Training Pipeline (Outer Loop)

| Deliverable | Status | Notes |
|-------------|--------|-------|
| 6-step KFP v2 pipeline | Done | prepare, train, evaluate, register, deploy, monitor |
| Quality gate (mAP threshold) | Done | Pipeline fails if mAP50 < 0.7 |
| Model Registry integration | Done | Registers with metrics metadata; `KF_PIPELINES_SA_TOKEN_PATH` auth |
| ISVC-to-Registry link | Done | Deploy step labels ISVC with `modelregistry.opendatahub.io/*` |
| TrustyAI monitoring | Done | TrustyAIService CR deployed; step 6 uploads baseline + subscribes to drift |
| Pipeline trigger script | Done | `run-training-pipeline.sh` with --version, --epochs, --threshold flags |
| Training data upload script | Done | `upload-training-data.sh` copies photos to MinIO |

## Architecture

### Step 11 components

```
gitops/step-11-face-recognition/base/
  serving-runtime/kserve-ovms.yaml     # OpenVINO Model Server (platform template)
  inference/face-recognition.yaml       # CPU-only InferenceService
  model-upload/upload-face-model.yaml   # Job: HuggingFace ONNX -> MinIO
  workbench/workbench.yaml              # SA, PVC, Notebook, Role, RoleBinding

steps/step-11-face-recognition/
  deploy.sh                             # Deploys ArgoCD app + uploads model + workbench assets
  validate.sh                           # 7 checks: ArgoCD, SR, Job, ISVC, Workbench, Health
  upload-to-workbench.sh                # oc cp for images/videos/my_photos
  notebooks/
    01-explore-yolo11-face.ipynb        # Detect faces + bounding boxes
    02-retrain-face-model.ipynb         # Train YOLO11 (CPU), export ONNX
    03-test-retrained-model.ipynb       # Test images + video + deploy to MinIO
    04-query-model-server.ipynb         # REST API inference via KServe
    remote_infer.py                     # Preprocessing, inference, video helpers
    requirements.txt                    # ultralytics, huggingface_hub, boto3, etc.
```

### Step 12 components

```
gitops/step-12-mlops-pipeline/base/
  pipeline-pvc.yaml                     # face-pipeline-workspace (10Gi)
  pipeline-rbac.yaml                    # Pod delete + ISVC patch for pipeline SA
  trustyai-service.yaml                 # TrustyAIService CR (PVC storage, 5s schedule)

steps/step-12-mlops-pipeline/
  deploy.sh                             # ArgoCD app for PVC + RBAC + TrustyAI
  validate.sh                           # ArgoCD, PVC, DSPA checks
  run-training-pipeline.sh              # Compile + upload + run pipeline
  upload-training-data.sh               # Photos from local -> MinIO bucket
  kfp/
    pipeline.py                         # 6-step pipeline orchestration
    components/
      prepare_dataset.py                # MinIO photos + WIDER Face + auto-annotate
      train_model.py                    # YOLO11 train (CPU) + ONNX export
      evaluate_model.py                 # mAP50 + registry comparison + quality gate
      register_model.py                 # S3 upload + Model Registry registration
      deploy_model.py                   # Restart predictor + registry label link
      setup_monitoring.py               # TrustyAI baseline + drift subscription
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| KServe RawDeployment (not ModelMesh) | ModelMesh deprecated in RHOAI 3.3 |
| CPU-only inference and training | OpenVINO optimized for CPU; avoids GPU conflicts with LLMs |
| YOLO11 (not YOLOv8) | Better accuracy, fewer params, same ultralytics package |
| Reuse existing DSPA (dspa-rag) | One pipeline server for all steps |
| Shared PVC for pipeline data | Dataset/model too large for KFP artifacts |
| Model Registry via external route | Internal service blocked by NetworkPolicy |
| Auto-annotation (no manual labeling) | YOLO11-face detector generates bounding box labels |
| Pre-trained model fallback | deploy.sh uploads generic ONNX so serving works without training |
| TrustyAI on output distribution | Confidence/class drift is meaningful for CV; pixel drift is not |
| Notebooks for inner loop, pipeline for outer loop | Different governance levels by design |

## Issues Encountered and Resolved

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Storage-initializer `NoCredentialsError` | Missing `storage.key: minio-connection` in ISVC | Added storage key reference |
| PVC `WaitForFirstConsumer` deadlock | ArgoCD waited for PVC before creating Notebook | Aligned sync waves |
| `ultralytics` not installed in workbench | Standard notebook image doesn't include it | Uncommented `pip install` in all notebooks |
| `.heic` photos from iPhone | OpenCV can't read HEIC | User re-exported as JPEG |
| Image display distortion | `.resize((500, 400))` ignores aspect ratio | Changed to `.thumbnail((500, 500))` |
| LFW site unreachable | `vis-www.cs.umass.edu` DNS fails | Switched to WIDER Face via HuggingFace |
| `libGL.so.1` missing in pipeline pods | `python:3.11` image lacks OpenGL | Force-reinstall `opencv-python-headless` via pip |
| `apt-get` fails in pipeline pods | Pods run as non-root | Replaced with pip workaround |
| `yolo11n.pt` download from GitHub blocked | Pipeline pods can't reach github.com | Pre-uploaded to MinIO, downloaded in prepare step |
| `model-registry==0.3.7a1` not on PyPI | Alpha version doesn't exist | Changed to `>=0.3.7` |
| YOLO writes to read-only `/runs` | Container root filesystem is read-only | Set `project=` to shared PVC path |
| Model Registry `403 Forbidden` | Pipeline SA lacks auth for OAuth route | `KF_PIPELINES_SA_TOKEN_PATH` + ClusterRoleBinding |
| Video won't play inline in JupyterLab | `mp4v` codec not supported in HTML5 | Added ffmpeg re-encode to H.264 |
| OVMS `/ready` endpoint returns empty body | OpenVINO health endpoint has no JSON body | Use `/v2/health/ready` (HTTP 200 check) + `/v2/models/` for metadata |

## Training Results

Best results from pipeline run `train-20260318-185319`:
- **mAP50: 0.834** (threshold: 0.7 -- PASSED)
- **adnan mAP50: 0.637**
- **mAP50-95: 0.485**
- Training data: 117 selfies + 100 WIDER Face images
- Training time: ~15 min on CPU (AMD EPYC 7R13)

## Files Changed (Summary)

| Category | Files | Count |
|----------|-------|-------|
| GitOps step-11 | kustomization, ServingRuntime, InferenceService, upload Job, workbench | 8 |
| GitOps step-12 | kustomization, PVC, RBAC, TrustyAIService | 4 |
| ArgoCD apps | step-11, step-12 | 2 |
| Step-11 scripts | deploy.sh, validate.sh, upload-to-workbench.sh | 3 |
| Step-12 scripts | deploy.sh, validate.sh, run-training-pipeline.sh, upload-training-data.sh | 4 |
| Notebooks | 01-04 + remote_infer.py + requirements.txt | 6 |
| KFP pipeline | pipeline.py + 6 components | 7 |
| READMEs | step-11, step-12, root | 3 |
| .gitignore | Binary asset exclusions | 1 |
| **Total** | | **38** |

## Known Limitations

- **TrustyAI data format mismatch for CV models** -- TrustyAI's `/data/upload` and drift APIs expect inference payloads matching the model's KServe schema. Our YOLO model has `[1,3,640,640]` tensor input and `[1,6,8400]` output. The synthetic confidence/class data uploaded by step 6 doesn't match this schema (returns 400). For production CV monitoring, a post-processing adapter is needed to extract scalar metrics (confidence, class) from YOLO output and forward to TrustyAI. The AI500 Jukebox pattern works because their model has 13 numeric input features.

## Pending / Future Work

- **TrustyAI CV adapter** -- Create a post-processing sidecar or webhook that extracts confidence scores and class predictions from YOLO inference output and forwards them to TrustyAI in compatible format.
- **Pipeline-to-registry traceability** -- Store `pipeline_run_id` in model version custom properties (like the Jukebox pattern) so artifacts can be traced back to specific pipeline runs.
- **Scheduled retraining** -- Use KFP scheduled runs to retrain weekly when new photos are added to MinIO.
- **Model comparison** -- Evaluate step queries previous mAP from registry; enhance to show side-by-side comparison in pipeline logs.
- **Multi-person training** -- Extend the dataset to recognize multiple people (3+ classes) for a more realistic demo.
