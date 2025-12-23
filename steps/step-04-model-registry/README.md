# Step 04: Model Registry

> **Status**: 🚧 Placeholder - Implementation pending

Implements centralized model versioning, metadata management, and lifecycle tracking using RHOAI 3.0 Model Registry.

---

## Overview

Model Registry provides:
- **Version Control**: Track model versions and lineage
- **Metadata Management**: Store model parameters, metrics, and artifacts
- **Lifecycle Management**: Promote models through dev → staging → production
- **Integration**: Connect with Model Serving for deployment

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Model Registry Architecture                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────┐         ┌─────────────────┐         ┌─────────────┐  │
│   │   Data Science  │────────▶│  Model Registry │────────▶│   Model     │  │
│   │   Workbench     │         │                 │         │   Serving   │  │
│   │                 │         │  • Versions     │         │             │  │
│   │  ┌───────────┐  │         │  • Metadata     │         │  ┌───────┐  │  │
│   │  │ Train     │  │         │  • Artifacts    │         │  │ KServe│  │  │
│   │  │ Model     │  │         │                 │         │  │       │  │  │
│   │  └───────────┘  │         │  ┌───────────┐  │         │  └───────┘  │  │
│   │                 │         │  │ PostgreSQL│  │         │             │  │
│   └─────────────────┘         │  └───────────┘  │         └─────────────┘  │
│                               └─────────────────┘                          │
│                                       │                                     │
│                                       ▼                                     │
│                               ┌─────────────────┐                          │
│                               │   MinIO S3      │                          │
│                               │   (Artifacts)   │                          │
│                               └─────────────────┘                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- [x] Step 01 completed (GPU infrastructure)
- [x] Step 02 completed (RHOAI 3.0)
- [x] Step 03 completed (Private AI with MinIO)
- [ ] PostgreSQL database (for registry metadata)

---

## What Will Be Installed

| Resource | Name | Purpose |
|----------|------|---------|
| **Namespace** | `model-registry` | Registry isolation |
| **ModelRegistry** | `rhoai-model-registry` | RHOAI Model Registry CR |
| **PostgreSQL** | `model-registry-db` | Metadata storage |
| **Secret** | `model-registry-s3` | MinIO connection |

---

## Deploy

```bash
./steps/step-04-model-registry/deploy.sh
```

---

## Demo Walkthrough

> **TODO**: Add demo steps for:
> 1. Registering a model from workbench
> 2. Viewing model versions in Dashboard
> 3. Promoting model to serving
> 4. Tracking model lineage

---

## Documentation Links

- [RHOAI 3.0 - Model Registry](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/managing_models/index)
- [MLflow Model Registry Concepts](https://mlflow.org/docs/latest/model-registry.html)

---

## Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Model Registry CR | 🚧 Pending | - |
| PostgreSQL | 🚧 Pending | - |
| S3 Integration | 🚧 Pending | Uses MinIO from Step 03 |
| Dashboard Integration | 🚧 Pending | - |

