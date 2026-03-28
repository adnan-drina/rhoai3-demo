# Step 13b: Edge AI on MicroShift (Optional)

**"Real edge hardware"** — Deploy the face recognition model on MicroShift 4.20 running on a RHEL 9.5 host with NVIDIA L4 GPU, using NVIDIA Triton Inference Server for GPU-accelerated ONNX inference via gRPC.

## The Business Story

Step 13 simulated an edge deployment using a separate namespace on the central OCP cluster. Step 13b deploys on **real edge hardware** — a RHEL host running MicroShift, the same way you'd deploy to a factory floor kiosk, a security checkpoint, or a remote camera station. The model was trained centrally (Steps 11-12), packaged as a ModelCar OCI image, and served by NVIDIA Triton on the L4 GPU. The Streamlit camera app uses gRPC for low-latency inference. This is the complete Red Hat Edge + On-Premise lifecycle.

## What It Does

```text
Edge AI on MicroShift (real edge hardware)
├── MicroShift 4.20                  → Edge-optimized Kubernetes on RHEL 9.5
├── microshift-ai-model-serving RPM  → KServe (raw deployment mode) + ServingRuntimes
├── triton-gpu ServingRuntime        → NVIDIA Triton with CUDA + ONNX Runtime on L4 GPU
├── face-recognition-edge ISVC       → YOLO11 ONNX model via ModelCar OCI image (v2)
├── edge-camera Deployment           → Streamlit app (same image as step-13)
│   ├── Photo mode                   → st.camera_input — single shot
│   └── Live Video mode              → camera_input_live — continuous capture
├── gRPC inference                   → tritonclient gRPC for ~30x lower latency vs REST
├── NVIDIA device plugin             → Exposes L4 GPU to Kubernetes (nvidia.com/gpu: 1)
└── Route (nip.io)                   → HTTPS access via public IP + nip.io DNS
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **MicroShift 4.20** | Edge-optimized Kubernetes distribution | System |
| **triton-gpu** ServingRuntime | NVIDIA Triton with CUDA + ONNX Runtime | `edge-ai` |
| **face-recognition-edge** InferenceService | YOLO11 ONNX via ModelCar OCI, GPU-accelerated | `edge-ai` |
| **face-recognition-edge-stable** Service | Non-headless ClusterIP for reliable gRPC connectivity | `edge-ai` |
| **edge-camera** Deployment | Streamlit camera app (gRPC inference) | `edge-ai` |
| **edge-camera** Route | HTTPS (nip.io, edge TLS) | `edge-ai` |

## Architecture

```text
┌─────────── RHEL 9.5 Host (MicroShift 4.20) ──────────────────────────────┐
│                                                                            │
│  ┌──────────────┐   KServe v2 gRPC   ┌──────────────────────────────────┐ │
│  │ edge-camera  │ ────────────────→  │ face-recognition-edge           │ │
│  │ (Streamlit)  │  tritonclient      │ InferenceService                │ │
│  │ Route: HTTPS │ ←───────────────── │ NVIDIA Triton + CUDA + ONNX    │ │
│  └──────────────┘                    │ NVIDIA L4 GPU (24 GB)          │ │
│       ↑ browser                      └──────────────────────────────────┘ │
│       (nip.io)                             ↑ model from                   │
│                                       localhost/face-recognition-          │
│                                       modelcar:v2 (Triton dir layout)     │
└────────────────────────────────────────────────────────────────────────────┘
         │
         │                     ┌─── Model trained centrally ───┐
         │                     │                                │
┌────────┼── Central OCP 4.20 (Datacenter) ────────────────────────────────┐
│        │                                                                  │
│        │   Step 12 Pipeline ──→ Model Registry ──→ ModelCar OCI build    │
│        │   (train + evaluate)   (versioned)         (quay.io or local)   │
└────────┼─────────────────────────────────────────────────────────────────┘
         │
    Laptop/phone camera
```

## Shared Code with Step 13

Steps 13 and 13b share identical application code:

| File | Shared? | Description |
|---|---|---|
| `inference.py` | Yes | KServe v2 gRPC client using `tritonclient[grpc]` |
| `edge_camera.py` | Yes | Streamlit app with Photo + Live Video modes |
| `requirements.txt` | Yes | Same dependencies |
| `Containerfile` | Yes | Same container image (`quay.io/adrina/edge-camera:latest`) |

The only difference is the infrastructure manifests and the env vars in the Deployment:

| Env Var | Step 13 (OCP) | Step 13b (MicroShift) |
|---|---|---|
| `GRPC_ENDPOINT` | `face-recognition-edge-predictor:8001` | `face-recognition-edge-stable:8001` |
| `MODEL_NAME` | `face-recognition-edge` | `face-recognition-edge` |

## Prerequisites

- **RHEL 9.5+ host** with SSH access and sudo
- **NVIDIA GPU** with driver installed (tested with L4, driver 595.58)
- **Red Hat subscription** that includes `rhocp-4.20-for-rhel-9-x86_64-rpms` and `fast-datapath-for-rhel-9-x86_64-rpms` repos
- **Pull secret** at `/etc/crio/openshift-pull-secret` on the host
- `sshpass` installed on your local machine
- Step 13's `edge-camera` container image pushed to quay.io (public)

> **Note (RHOAI 3.3 / MicroShift 4.20):** AI model serving on MicroShift is a Technology Preview feature.

## Deploy

```bash
EDGE_HOST=rhaiis.example.com \
EDGE_USER=dev \
EDGE_PASS=<password> \
./steps/step-13b-edge-ai-microshift/deploy.sh
```

## Demo Script

An interactive demo script is included for live presentations:

```bash
ssh dev@<edge-host>
./demo.sh
```

The script walks through 7 sections with pause-and-talk flow: platform overview, GPU-powered inference (`nvidia-smi` shows `tritonserver`), edge workloads, ModelCar OCI model, Triton serving runtime, GPU in Kubernetes, and the camera app URL.

## Design Decisions

> **Design Decision:** **NVIDIA Triton Inference Server** as a custom ServingRuntime instead of OpenVINO (OVMS). OVMS only supports Intel CPUs/GPUs — it cannot use NVIDIA CUDA. Triton supports ONNX models on NVIDIA GPUs via the CUDA execution provider. This is the documented approach for custom runtimes in RHOAI 3.3. Ref: [Custom Triton Runtime on AI on OpenShift](https://ai-on-openshift.io/odh-rhoai/custom-runtime-triton/)

> **Design Decision:** **gRPC for inference** instead of REST. Both OVMS (step-13) and Triton (step-13b) implement the KServe v2 gRPC protocol on port 8001. Using `tritonclient[grpc]` provides ~30x lower latency compared to REST JSON, with the same client code working against both servers. Ref: [YOLOv5 gRPC vs REST benchmark](https://ai-on-openshift.io/demos/yolov5-training-serving/yolov5-training-serving/)

> **Design Decision:** **ModelCar OCI format** with Triton directory layout (`/models/<model-name>/<version>/model.onnx`). Built with `sudo podman` so CRI-O can access it directly from root container storage. Uses tag `v2` (not `latest`) so `imagePullPolicy` is `IfNotPresent`.

> **Design Decision:** **Non-headless stable service** (`face-recognition-edge-stable`) for gRPC connectivity. KServe creates a headless service (`ClusterIP: None`) which doesn't provide a stable ClusterIP. The stable service ensures the edge-camera can use a DNS name that survives pod restarts.

> **Design Decision:** **NVIDIA device plugin** deployed via MicroShift auto-manifests at `/etc/microshift/manifests/` with SELinux permissions (`container_use_devices` boolean + custom policy module). Follows the [NVIDIA GPU with Red Hat Device Edge](https://docs.nvidia.com/datacenter/cloud-native/edge/latest/nvidia-gpu-with-device-edge.html) guide.

> **Design Decision:** **nip.io for Route DNS**. MicroShift defaults to `apps.example.com` which doesn't resolve. Using `<public-ip>.nip.io` provides automatic DNS resolution.

> **Design Decision:** **Restart recovery verified**. All workloads survive full server reboots — MicroShift auto-starts, etcd-stored resources are reconciled, NVIDIA device plugin re-registers via auto-manifests, Triton reloads the model on the GPU.

## Known Limitations

### RHDP Lab subscription doesn't include MicroShift repos

**Solution:** Re-register with a personal Red Hat subscription:
```bash
sudo subscription-manager config --server.hostname=subscription.rhsm.redhat.com \
  --server.prefix=/subscription --rhsm.baseurl=https://cdn.redhat.com \
  --rhsm.repo_ca_cert=/etc/rhsm/ca/redhat-uep.pem
sudo subscription-manager register --username=<your-rh-email>
```

### Live Video mode on mobile phones

**Symptom:** Camera captures first frame, then stops streaming.

**Workaround:** Use Photo mode on phones. Live Video works on laptops.

## Future: Production-Grade Edge Deployment with bootc

The current deployment uses RPM installation + auto-manifests, which is appropriate for demos and single-device deployments. For **production fleet management** of multiple edge devices, Red Hat recommends the **RHEL Image Mode (bootc)** approach:

> **RHEL Image Mode** packages the entire edge device — OS, MicroShift, GPU drivers, model, and application manifests — into a single bootable OCI container image. Updates are atomic: `bootc switch` to a new image version, and greenboot auto-rolls back if the health check fails.

**Production deployment workflow:**

1. **Build a bootc image** using RHEL Image Builder with a blueprint that includes:
   - MicroShift + `microshift-ai-model-serving` RPMs
   - NVIDIA driver + container toolkit RPMs
   - Pull-secret, MicroShift config, auto-manifests
   - Pre-pulled container images (Triton, edge-camera, ModelCar)

2. **Publish the bootc image** to a container registry (quay.io)

3. **Deploy to edge devices** via `bootc switch` or PXE boot from the ISO

4. **Update the fleet** by building a new bootc image with the updated model/app, pushing to the registry, and having each device pull the update

**Key benefits over RPM deployment:**
- **Atomic updates** — entire OS + workload updated as one unit, rollback on failure
- **Immutable** — no configuration drift across fleet
- **Offline-capable** — all images pre-pulled into the bootc image
- **Greenboot integration** — automatic health checks and rollback

**References:**
- [Embedding in a RHEL for Edge image](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/embedding_in_a_rhel_for_edge_image/)
- [Installing with image mode for RHEL](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html-single/installing_with_image_mode_for_rhel/)
- [Automated recovery from manual backups](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/backup_and_restore/microshift-auto-recover-manual-backup)
- [Greenboot workload health checks](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/running_applications/microshift-greenboot-workload-health-checks)

## References

- [MicroShift 4.20 — Using AI models](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/using_ai_models/microshift-rh-openshift-ai)
- [MicroShift 4.20 — Installing from RPM package](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/installing_with_an_rpm_package/microshift-install-rpm)
- [NVIDIA GPU with Red Hat Device Edge](https://docs.nvidia.com/datacenter/cloud-native/edge/latest/nvidia-gpu-with-device-edge.html)
- [Custom Triton Runtime on AI on OpenShift](https://ai-on-openshift.io/odh-rhoai/custom-runtime-triton/)
- [RHOAI 3.3 — Custom ServingRuntimes (Triton examples)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/configuring_your_model-serving_platform/configuring_model_servers)
- [YOLOv5 Training and Serving (gRPC vs REST)](https://ai-on-openshift.io/demos/yolov5-training-serving/yolov5-training-serving/)
- [KServe Binary Tensor Data Extension](https://kserve.github.io/website/docs/concepts/architecture/data-plane/v2-protocol/binary-tensor-data-extension)

> **See also:** [Step 13 — Edge AI (simulated)](../step-13-edge-ai/README.md), [Step 11 — Face Recognition](../step-11-face-recognition/README.md), [Step 12 — MLOps Pipeline](../step-12-mlops-pipeline/README.md)
