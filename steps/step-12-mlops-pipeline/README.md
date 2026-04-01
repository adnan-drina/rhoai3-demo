# Step 12: MLOps Training Pipeline

**"From Notebook to Production"** — Automate the face recognition training workflow as a Kubeflow Pipeline with evaluation gates, Model Registry integration, and conditional deployment.

## The Business Story

Step 11 demonstrated the data scientist's inner loop — interactive training in a notebook. Step 12 is the MLOps engineer's outer loop: the same workflow automated as a pipeline that runs unattended, evaluates quality, and only deploys if the model passes. This is the first pipeline in the project that connects KFP to the Model Registry, demonstrating the full RHOAI 3.3 ML lifecycle.

## What It Does

```text
MLOps Training Pipeline (KFP v2, 7 Steps)
├── 1. prepare_dataset     → Download photos + unknowns from MinIO, auto-annotate, split train/val
├── 2. train_model         → YOLO11 training on GPU, ONNX export
├── 3. evaluate_model      → mAP50 quality gate (compare with previous version)
├── 4. register_model      → Upload ONNX to MinIO, register in Model Registry
├── 5. deploy_model        → Restart KServe predictor pod
├── 6. setup_monitoring    → Upload baseline to TrustyAI, configure drift metrics
├── 7. package_modelcar *  → Trigger Tekton pipeline: build ModelCar OCI, push, update Git
│      (* optional, release_to_edge=True)
└── Infrastructure
    ├── face-pipeline-workspace PVC → Shared storage between pipeline steps
    ├── TrustyAIService             → Fairness and drift monitoring
    └── modelcar-release Pipeline   → Tekton pipeline for edge model promotion
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| `prepare_dataset` | Download adnan + unknown photos from MinIO, auto-annotate, split train/val (augments with 200 HuggingFace portraits at runtime) | `private-ai` |
| `train_model` | YOLO11 training on CPU, ONNX export | `private-ai` |
| `evaluate_model` | mAP50 computation, compare with previous version, quality gate | `private-ai` |
| `register_model` | Upload ONNX to MinIO, register in Model Registry with metrics | `private-ai` |
| `deploy_model` | Restart KServe predictor pod, link ISVC to Registry | `private-ai` |
| `setup_monitoring` | Upload baseline to TrustyAI, configure SPD + drift metrics | `private-ai` |
| **TrustyAIService** | Fairness and drift monitoring, visible in RHOAI Dashboard | `private-ai` |
| **face-pipeline-workspace** PVC | Shared storage between pipeline steps | `private-ai` |

Pipeline code: [`steps/step-12-mlops-pipeline/kfp/`](kfp/)

## Prerequisites

- Steps 01-04 deployed (GPU infra, RHOAI, MinIO, Model Registry)
- Step 07 deployed (DSPA pipeline server)
- Step 11 deployed (face-recognition InferenceService + workbench with training photos)
- Training photos uploaded to MinIO (done automatically if step 11 workbench was used)

## Deploy

```bash
./steps/step-12-mlops-pipeline/deploy.sh
```

This creates the pipeline PVC and RBAC via ArgoCD. The pipeline server (DSPA) is reused from step 07.

## Run the Pipeline

```bash
./steps/step-12-mlops-pipeline/run-training-pipeline.sh
```

Options:

```bash
./run-training-pipeline.sh --version=v2.0 --epochs=20 --threshold=0.8
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--version` | timestamp | Model version string |
| `--epochs` | 15 | Training epochs |
| `--threshold` | 0.7 | Minimum mAP50 for deployment |

Monitor the run in the RHOAI Dashboard: **Data Science Projects** -> **private-ai** -> **Pipelines**.

Manifests: [`gitops/step-12-mlops-pipeline/base/`](../../gitops/step-12-mlops-pipeline/base/)

## Demo Walkthrough

### Scene 1: The Need for Automation

**Say:** *"We trained a face recognition model in a notebook — great for experimentation. But what happens when you need to retrain weekly as new photos come in? You need automation, governance, and quality gates."*

### Scene 2: Run the Pipeline

**Do:** Run `./run-training-pipeline.sh`. Open the RHOAI Dashboard Pipelines tab. Show the DAG visualization as steps execute.

**Expect:** 6 green steps completing in sequence (~20 minutes). With `release_to_edge=True`, a 7th step triggers the Tekton ModelCar pipeline.

**Say:** *"This is the same training workflow, but fully automated. Each step runs in its own container with explicit resource limits. Data flows between steps via a shared PVC."*

### Scene 3: Model Registry Integration

**Do:** After the pipeline completes, open the Model Registry in the RHOAI Dashboard. Show the new model version with mAP50 metadata.

**Expect:** A new version of "face-recognition" with metrics attached.

**Say:** *"The model is automatically registered with its accuracy metrics. Every version is traceable — you know exactly which pipeline run produced it."*

### Scene 4: The Quality Gate (Governance)

**Do:** Re-run with `--threshold=0.99`. The pipeline fails at the evaluation step.

**Expect:** Step 3 (evaluate) turns red. Steps 4-5 never execute.

**Say:** *"The quality gate caught a model that doesn't meet the bar. The old model stays in production. This is governance — the pipeline won't deploy a model that's worse than what you already have."*

## What to Verify After Deployment

```bash
# Pipeline PVC created
oc get pvc face-pipeline-workspace -n private-ai

# DSPA is running
oc get dspa dspa-rag -n private-ai

# Validate
./steps/step-12-mlops-pipeline/validate.sh
```

## Model Monitoring with TrustyAI

The pipeline deploys **TrustyAI** and configures bias monitoring for the face-recognition model:

- **SPD Fairness metric** (`trustyai_spd`) — measures whether the model detects known faces at the same rate as unknown faces. Visible in **RHOAI Dashboard > AI hub > Deployments > face-recognition > Model bias** tab.
- **Drift detection** (`trustyai_meanshift`) — detects distribution shifts in inference data vs training baseline.
- **Endpoint performance** — request count, latency visible in the **Endpoint performance** tab.

### Architecture: TrustyAI Adapter Pattern

TrustyAI's fairness algorithms require **tabular data**, but the YOLO model has tensor I/O (`[1,3,640,640]` image in, `[1,6,8400]` detections out). We use a **post-processing adapter** that transforms detection results into tabular metrics:

```text
Inference Client (Notebook/Streamlit)
  │
  ├── 1. Send image → OVMS (KServe v2) → YOLO detections
  │
  └── 2. POST /report → trustyai-adapter (fire-and-forget)
                              │
                              └── Transform to tabular:
                                    Input:  image_type (0=known, 1=unknown_only)
                                    Output: num_detections (face count)
                                         │
                                         └── POST /data/upload → TrustyAI
                                                                    │
                                                                    └── trustyai_spd → Prometheus → Dashboard
```

The adapter runs as a standalone Deployment (`trustyai-adapter`) in `private-ai`. Inference clients (`remote_infer.py`, edge `inference.py`) call `report_to_trustyai()` after each inference — fire-and-forget with 1s timeout.

### Setup

```bash
./steps/step-12-mlops-pipeline/setup-trustyai-metrics.sh
```

This script:
1. Triggers the adapter's `/bootstrap` endpoint (uploads TRAINING baseline + prediction samples)
2. Patches TrustyAI's internal CSV to tag predictions as `_trustyai_unlabeled` (required for SPD computation)
3. Sets `recordedInferences=true` in TrustyAI metadata
4. Configures scheduled SPD and drift metrics
5. Verifies `trustyai_spd` appears in Prometheus

> **Known Limitation (RHOAI 3.3):** TrustyAI's KServe inference logger uses HTTPS to forward payloads, but the `inferenceservice-config` ConfigMap is actively reconciled by the RHOAI operator, preventing `caBundle`/`tlsSkipVerify` settings from being persisted (per RHOAI 3.3 docs Section 2.5). The adapter pattern bypasses this by receiving data directly from clients instead of relying on the KServe logger path.

## ModelCar Release Pipeline (Edge Promotion)

After the KFP training pipeline registers a model, you can promote it to the edge fleet using the **Tekton `modelcar-release` pipeline**. This bridges data science (KFP) and CI/CD (Tekton):

```text
KFP Training Pipeline                Tekton modelcar-release Pipeline
┌──────────────────────────┐         ┌──────────────────────────────────┐
│ 1. Prepare Dataset       │         │ 1. build-modelcar                │
│ 2. Train (GPU)           │         │    Download ONNX from MinIO      │
│ 3. Evaluate (quality gate│         │    buildah ModelCar OCI image    │
│ 4. Register (MinIO + MR) │──────>  │    Push to quay.io               │
│ 5. Deploy (central OCP)  │ trigger │ 2. update-gitops                 │
│ 6. Monitoring            │         │    Update storageUri tag in Git   │
│ 7. Package ModelCar *    │         │    ArgoCD on MicroShift syncs     │
└──────────────────────────┘         └──────────────────────────────────┘
  * optional (release_to_edge=True)
```

### Run Standalone (Tekton)

```bash
oc create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: modelcar-release-
  namespace: private-ai
spec:
  pipelineRef:
    name: modelcar-release
  params:
    - name: model-version
      value: v5
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 1Gi
EOF
```

### Run from KFP (Integrated)

Set `release_to_edge=True` when running the training pipeline:

```bash
./run-training-pipeline.sh --release-to-edge --modelcar-version=v5
```

The KFP `package_modelcar` component creates a Tekton PipelineRun and waits for completion.

### Prerequisites

- **OpenShift Pipelines operator** installed (Tekton)
- **`quay-push-credentials`** secret in `private-ai` (docker-registry type with quay.io auth)
- **`github-push-credentials`** secret in `private-ai` (generic with `username` + `token` keys)

Tekton source manifests: [`steps/step-12-mlops-pipeline/tekton/`](tekton/)

ArgoCD-managed copies (synced to cluster): [`gitops/step-13b-edge-ai-microshift/base/`](../../gitops/step-13b-edge-ai-microshift/base/) via the `step-13b-edge-ai-microshift` ArgoCD Application.

## Design Decisions

> **Design Decision:** **Reuse existing DSPA** (`dspa-rag`). One pipeline server handles RAG ingestion, evaluation, benchmarks, and now training. No additional infrastructure needed.

> **Design Decision:** **Threshold-based quality gate with Registry context**. The evaluate step computes mAP50 and compares it against a configurable threshold (default 0.7). It also queries the Model Registry for the previous version's mAP50 for informational logging. If the new model's mAP50 is below the threshold, the pipeline fails and deployment is skipped. Inspired by the [AI500 MLOps Jukebox](https://github.com/rhoai-mlops/jukebox) pattern.

> **Design Decision:** **Shared PVC** (not KFP artifacts) for inter-component data. The training dataset and model files are too large for KFP artifact passing. The shared PVC pattern follows [step-07 RAG pipeline](../step-07-rag/kfp/).

> **Design Decision:** **TrustyAI adapter pattern for CV models.** Vision model I/O (1.2M float tensors) cannot be used directly by TrustyAI's fairness algorithms, which require scalar columns. The `trustyai-adapter` Deployment receives post-processed detection results from inference clients and transforms them into tabular metrics (`image_type`, `num_detections`) that TrustyAI computes SPD on. This approach bypasses the KServe inference logger's TLS limitation in RawDeployment mode (RHOAI 3.3). See [RHOAI 3.3 Monitoring](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/monitoring_your_ai_systems/).

> **Design Decision:** **External Model Registry route** with auth token. The internal service has a NetworkPolicy blocking cross-namespace access. Pipeline components use the HTTPS route.

> **Design Decision:** **Tekton for ModelCar builds, not KFP**. Building OCI images requires `buildah` with elevated security context — inappropriate for the DSPA pipeline environment. Tekton tasks run in dedicated pods with the required capabilities. The KFP `package_modelcar` component bridges the two by creating a Tekton PipelineRun via the Kubernetes API and polling for completion.

> **Design Decision:** **`pip_index_urls=["https://pypi.org/simple"]`** on all components that require packages outside the Red Hat index. The RHOAI base image (`rhai/base-image-cpu-rhel9:3.3.0`) configures pip to use Red Hat's Python index, which lacks `ultralytics`, `onnxruntime`, `onnxslim`, and other ML packages. Adding `pip_index_urls` in the `@component` decorator tells KFP to use PyPI instead. This also resolves the KFP SDK version mismatch (base image has 2.15.2, compiled pipeline requests 2.16.0).

## Troubleshooting

### Pipeline fails at "train_model" with "No matching distribution found for ultralytics"

**Root Cause:** The RHOAI base image uses Red Hat's Python package index which doesn't include `ultralytics`.

**Solution:** Ensure `pip_index_urls=["https://pypi.org/simple"]` is set in the `@component` decorator. See `kfp/components/train_model.py` for the pattern.

### Pipeline fails at "evaluate_model" with "No module named 'onnxruntime'"

**Root Cause:** `onnxruntime` was missing from `packages_to_install` in evaluate_model. YOLO ONNX inference requires it.

**Solution:** Add `"onnxruntime>=1.17.0"` to the component's `packages_to_install`.

### TrustyAIService stuck in "Progressing" / "Pending deletion"

**Root Cause:** A `foregroundDeletion` finalizer can get stuck if the ArgoCD Application is deleted and recreated while the TrustyAIService is being reconciled.

**Solution:**
```bash
oc patch trustyaiservice trustyai-service -n private-ai --type json \
  -p '[{"op": "remove", "path": "/metadata/finalizers"}]'
```
ArgoCD will recreate the resource from Git automatically.

### Pipeline fails at "prepare_dataset" with S3 credentials error

**Root Cause:** The `dspa-minio-credentials` secret doesn't have the correct keys.

**Solution:**
```bash
oc get secret dspa-minio-credentials -n private-ai -o yaml
```

### Pipeline fails at "evaluate_model" with threshold error

**This is expected behavior** when the model doesn't meet the quality bar. Lower the threshold or improve training data:

```bash
./run-training-pipeline.sh --threshold=0.5
```

### Pipeline fails at "deploy_model" with permission error

**Root Cause:** The pipeline ServiceAccount lacks pod delete permission.

**Solution:**
```bash
oc apply -f gitops/step-12-mlops-pipeline/base/pipeline-rbac.yaml
```

## References

- [RHOAI 3.3 — Working with AI Pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_ai_pipelines/)
- [RHOAI 3.3 — Managing Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_model_registries/)
- [Fine-tune AI pipelines in RHOAI 3.3](https://developers.redhat.com/articles/2026/02/26/fine-tune-ai-pipelines-red-hat-openshift-ai)
- [AI500 MLOps Enablement (Jukebox)](https://github.com/rhoai-mlops/jukebox)
- [KFP Pipelines Components](https://github.com/red-hat-data-services/pipelines-components)

> **See also:** [Step 07 — RAG Pipeline](../step-07-rag/README.md) (KFP patterns), [Step 11 — Face Recognition](../step-11-face-recognition/README.md) (notebook-based training), [Step 04 — Model Registry](../step-04-model-registry/README.md) (governance), [Step 13b — Edge AI on MicroShift](../step-13b-edge-ai-microshift/README.md) (ArgoCD consumes the ModelCar tag updates)
