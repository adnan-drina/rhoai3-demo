# Step 12: MLOps Training Pipeline

**"From Notebook to Production"** — Automate the face recognition training workflow as a Kubeflow Pipeline with evaluation gates, Model Registry integration, and conditional deployment.

## The Business Story

Step 11 demonstrated the data scientist's inner loop -- interactive training in a notebook. Step 12 is the MLOps engineer's outer loop: the same workflow automated as a pipeline that runs unattended, evaluates quality, and only deploys if the model passes. This is the first pipeline in the project that connects KFP to the Model Registry, demonstrating the full RHOAI 3.3 ML lifecycle.

## What It Does

```text
┌────────────────────────────────────────────────────────────────────────────┐
│                       KFP v2 Pipeline (6 Steps)                            │
│                                                                            │
│  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐ │
│  │1.Prepare│→│2.Train  │→│3.Eval   │→│4.Regis- │→│5.Deploy │→│6.Moni- │ │
│  │Dataset  │  │YOLO11  │  │mAP50 > │  │ter in  │  │to      │  │toring  │ │
│  │(annot.) │  │(CPU)   │  │thresh? │  │Registry│  │KServe  │  │TrustyAI│ │
│  └────────┘  └────────┘  └────────┘  └────────┘  └────────┘  └────────┘ │
│       ↕            ↕           ↕           ↕                       ↕      │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │              Shared PVC: face-pipeline-workspace                    │   │
│  └────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
        ↑                                ↓           ↓            ↓
   MinIO (photos)                  MinIO (ONNX)  Registry    TrustyAI
```

| Component | Purpose | Location |
|-----------|---------|----------|
| `prepare_dataset` | Download photos + WIDER Face, auto-annotate, split train/val | KFP component |
| `train_model` | YOLO11 training on CPU, ONNX export | KFP component |
| `evaluate_model` | mAP50 computation, compare with previous version, quality gate | KFP component |
| `register_model` | Upload ONNX to MinIO, register in Model Registry with metrics | KFP component |
| `deploy_model` | Restart KServe predictor pod | KFP component |
| `setup_monitoring` | Upload baseline to TrustyAI, configure SPD fairness + drift metrics | KFP component |
| **TrustyAIService** | Fairness and drift monitoring, visible in RHOAI Dashboard | GitOps manifest |
| `face-pipeline-workspace` PVC | Shared storage between pipeline steps | GitOps manifest |

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

**Say:** *"We trained a face recognition model in a notebook -- great for experimentation. But what happens when you need to retrain weekly as new photos come in? You need automation, governance, and quality gates."*

### Scene 2: Run the Pipeline

**Do:** Run `./run-training-pipeline.sh`. Open the RHOAI Dashboard Pipelines tab. Show the DAG visualization as steps execute.

**Expect:** 5 green steps completing in sequence (~20 minutes).

**Say:** *"This is the same training workflow, but fully automated. Each step runs in its own container with explicit resource limits. Data flows between steps via a shared PVC."*

### Scene 3: Model Registry Integration

**Do:** After the pipeline completes, open the Model Registry in the RHOAI Dashboard. Show the new model version with mAP50 metadata.

**Expect:** A new version of "face-recognition" with metrics attached.

**Say:** *"The model is automatically registered with its accuracy metrics. Every version is traceable -- you know exactly which pipeline run produced it."*

### Scene 4: The Quality Gate (Governance)

**Do:** Re-run with `--threshold=0.99`. The pipeline fails at the evaluation step.

**Expect:** Step 3 (evaluate) turns red. Steps 4-5 never execute.

**Say:** *"The quality gate caught a model that doesn't meet the bar. The old model stays in production. This is governance -- the pipeline won't deploy a model that's worse than what you already have."*

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

The pipeline deploys **TrustyAI** and configures monitoring directly on the face-recognition model:

- **SPD Fairness metric** (`trustyai_spd`) -- measures whether the model detects known faces at the same rate as unknown faces. Visible in **RHOAI Dashboard > Model Serving > face-recognition > Model bias** tab.
- **Endpoint performance** -- request count, latency visible in the **Endpoint performance** tab.

The monitoring setup uses a **post-processing pattern**: since TrustyAI's fairness algorithms require tabular data (not raw tensors), YOLO inference outputs are transformed into scalar metrics (`image_type`, `num_detections`) and uploaded to TrustyAI:

```bash
./steps/step-12-mlops-pipeline/setup-trustyai-metrics.sh
```

This script uploads TRAINING reference data and untagged prediction data, configures the scheduled SPD metric, and verifies the Prometheus gauge is live. The `ServiceMonitor trustyai-service` scrapes the metric every 4s for the Dashboard.

## Design Decisions

> **Design Decision:** **Reuse existing DSPA** (`dspa-rag`). One pipeline server handles RAG ingestion, evaluation, benchmarks, and now training. No additional infrastructure needed.

> **Design Decision:** **Model Registry as quality gate**. The evaluate step queries the previous version's mAP50 from the registry. If the new model is worse, the pipeline fails. This is inspired by the [AI500 MLOps Jukebox](https://github.com/rhoai-mlops/jukebox) pattern.

> **Design Decision:** **Shared PVC** (not KFP artifacts) for inter-component data. The training dataset and model files are too large for KFP artifact passing. The shared PVC pattern follows [step-07 RAG pipeline](../step-07-rag/kfp/).

> **Design Decision:** **TrustyAI uses post-processed tabular metrics**, not raw tensor data. Vision model I/O (1.2M float tensors) cannot be used directly by TrustyAI's fairness algorithms, which require scalar columns. The `setup-trustyai-metrics.sh` script uploads post-processed metrics (image_type, num_detections) that represent the model's behavior in a format TrustyAI can compute SPD on. This is the standard production pattern for monitoring CV models.

> **Design Decision:** **External Model Registry route** with auth token. The internal service has a NetworkPolicy blocking cross-namespace access. Pipeline components use the HTTPS route.

## Troubleshooting

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

- [RHOAI 3.3 -- Working with AI Pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/working_with_ai_pipelines/)
- [RHOAI 3.3 -- Managing Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/managing_model_registries/)
- [Fine-tune AI pipelines in RHOAI 3.3](https://developers.redhat.com/articles/2026/02/26/fine-tune-ai-pipelines-red-hat-openshift-ai)
- [AI500 MLOps Enablement (Jukebox)](https://github.com/rhoai-mlops/jukebox)
- [KFP Pipelines Components](https://github.com/red-hat-data-services/pipelines-components)

> **See also:** [Step 07 -- RAG Pipeline](../step-07-rag/README.md) (KFP patterns), [Step 11 -- Face Recognition](../step-11-face-recognition/README.md) (notebook-based training), [Step 04 -- Model Registry](../step-04-model-registry/README.md) (governance)
