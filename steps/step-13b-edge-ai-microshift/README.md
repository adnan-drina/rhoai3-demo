# Step 13b: Edge AI on MicroShift (Optional)
**"Real Edge Hardware"** — Deploy the face recognition model on MicroShift 4.20 running on a RHEL 9.5 host with NVIDIA L4 GPU, using NVIDIA Triton Inference Server for GPU-accelerated ONNX inference via gRPC.

## Overview

Step 13 simulated edge placement on-cluster; Step 13b proves it on **real edge hardware** — same operating model, real RHEL host, edge footprint. **Red Hat Build of MicroShift 4.20** brings KServe-style serving and embedded ArgoCD to a single RHEL host with an NVIDIA L4 GPU, so edge inference stays aligned with central standards without creating a second stack.

This optional step demonstrates RHOAI's **Disconnected environments and edge** capability on real hardware: the same model trained in the datacenter deploys to MicroShift at the edge — different infrastructure, same operational model, with embedded GitOps for autonomous updates.

> **Note (RHOAI 3.3 / MicroShift 4.20):** AI model serving on MicroShift is a Technology Preview feature.

### What Gets Deployed

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
├── Route (nip.io)                   → HTTPS access via public IP + nip.io DNS
└── ArgoCD core (embedded GitOps)    → Syncs edge-ai workloads from Git, no SSH needed
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **MicroShift 4.20** | Edge-optimized Kubernetes distribution | System |
| **triton-gpu** ServingRuntime | NVIDIA Triton with CUDA + ONNX Runtime | `edge-ai` |
| **face-recognition-edge** InferenceService | YOLO11 ONNX via ModelCar OCI, GPU-accelerated | `edge-ai` |
| **face-recognition-edge-stable** Service | Non-headless ClusterIP for reliable gRPC connectivity | `edge-ai` |
| **edge-camera** Deployment | Streamlit camera app (gRPC inference) | `edge-ai` |
| **edge-camera** Route | HTTPS (nip.io, edge TLS) | `edge-ai` |
| **ArgoCD core** (controller + repo-server + redis) | Embedded GitOps — syncs workloads from Git | `argocd` |

#### Platform Features

| | Feature | Status |
|---|---|---|
| RHOAI | Disconnected environments and edge (real hardware) | Used |
| OCP | MicroShift 4.20 | Introduced |
| OCP | OpenShift Pipelines (Tekton — ModelCar build) | Used |

#### Architecture

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
│                                       quay.io/adrina/face-recognition-    │
│  ┌──────────────────┐                 modelcar:v3 (ModelCar OCI)          │
│  │ ArgoCD core      │                                                     │
│  │ (argocd ns)      │ ← watches Git: gitops/edge-ai-microshift/          │
│  │ auto-sync + heal │   model update = change storageUri tag + push       │
│  └──────────────────┘                                                     │
└────────────────────────────────────────────────────────────────────────────┘
         │                               │
         │                               │ Git (auto-sync)
         │                     ┌─────────┴─────────────────┐
         │                     │ github.com/adnan-drina/    │
         │                     │ rhoai3-demo (main)         │
         │                     │ gitops/edge-ai-microshift/ │
         │                     └─────────┬─────────────────┘
         │                               │
         │                     ┌─── Model trained centrally ───┐
         │                     │                                │
┌────────┼── Central OCP 4.20 (Datacenter) ────────────────────────────────┐
│        │                                                                  │
│        │   Step 12 Pipeline ──→ Model Registry ──→ ModelCar OCI build    │
│        │   (train + evaluate)   (versioned)         (quay.io)            │
└────────┼─────────────────────────────────────────────────────────────────┘
         │
    Laptop/phone camera
```

### Shared Code with Step 13

Steps 13 and 13b share identical application code:

| File | Shared? | Description |
|------|---------|-------------|
| `inference.py` | Yes | KServe v2 gRPC client using `tritonclient[grpc]` |
| `edge_camera.py` | Yes | Streamlit app with Photo + Live Video modes |
| `requirements.txt` | Yes | Same dependencies |
| `Containerfile` | Yes | Same container image (`quay.io/adrina/edge-camera:latest`) |

The only difference is the infrastructure manifests and the env vars in the Deployment:

| Env Var | Step 13 (OCP) | Step 13b (MicroShift) |
|---------|---------------|------------------------|
| `GRPC_ENDPOINT` | `face-recognition-edge-predictor:8001` | `face-recognition-edge-stable:8001` |
| `MODEL_NAME` | `face-recognition-edge` | `face-recognition-edge` |

### Design Decisions

> **NVIDIA Triton Inference Server** as a custom ServingRuntime instead of OpenVINO (OVMS). OVMS only supports Intel CPUs/GPUs — it cannot use NVIDIA CUDA. Triton supports ONNX models on NVIDIA GPUs via the CUDA execution provider. This is the documented approach for custom runtimes in RHOAI 3.3. Ref: [Custom Triton Runtime on AI on OpenShift](https://ai-on-openshift.io/odh-rhoai/custom-runtime-triton/)

> **gRPC for inference** instead of REST. Both OVMS (step-13) and Triton (step-13b) implement the KServe v2 gRPC protocol on port 8001. Using `tritonclient[grpc]` provides ~30x lower latency compared to REST JSON, with the same client code working against both servers. Ref: [YOLOv5 gRPC vs REST benchmark](https://ai-on-openshift.io/demos/yolov5-training-serving/yolov5-training-serving/)

> **ModelCar OCI format** with Triton directory layout (`/models/<model-name>/<version>/model.onnx`). Built with `sudo podman` so CRI-O can access it directly from root container storage. Uses tag `v2` (not `latest`) so `imagePullPolicy` is `IfNotPresent`.

<details>
<summary>Additional design decisions</summary>

> **Non-headless stable service** (`face-recognition-edge-stable`) for gRPC connectivity. KServe creates a headless service (`ClusterIP: None`) which doesn't provide a stable ClusterIP. The stable service ensures the edge-camera can use a DNS name that survives pod restarts.

> **NVIDIA device plugin** deployed via MicroShift auto-manifests at `/etc/microshift/manifests/` with SELinux permissions (`container_use_devices` boolean + custom policy module). Follows the [NVIDIA GPU with Red Hat Device Edge](https://docs.nvidia.com/datacenter/cloud-native/edge/latest/nvidia-gpu-with-device-edge.html) guide.

> **nip.io for Route DNS.** MicroShift defaults to `apps.example.com` which doesn't resolve. Using `<public-ip>.nip.io` provides automatic DNS resolution.

> **Recreate deployment strategy** for the predictor. With a single GPU on the edge device, the default RollingUpdate strategy creates a new pod before deleting the old one, requiring 2 GPUs. `deploymentStrategy: { type: Recreate }` in the InferenceService spec terminates the old pod first, freeing the GPU for the new revision.

> **Restart recovery verified.** All workloads survive full server reboots — MicroShift auto-starts, etcd-stored resources are reconciled, NVIDIA device plugin re-registers via auto-manifests, Triton reloads the model on the GPU.

> **Central OCP ArgoCD Application** (`step-13b-edge-ai-microshift`) manages the Tekton `modelcar-release` pipeline in the `private-ai` namespace via [`gitops/step-13b-edge-ai-microshift/base/`](../../gitops/step-13b-edge-ai-microshift/base/). The Tekton pipeline builds ModelCar OCI images and updates the edge GitOps manifest. Secrets (`quay-push-credentials`, `github-push-credentials`) are created by `deploy.sh` and not stored in Git.

</details>

### Deploy

**Prerequisites:**

- **RHEL 9.5+ host** with SSH access and sudo
- **NVIDIA GPU** with driver installed (tested with L4, driver 595.58)
- **Red Hat subscription** that includes `rhocp-4.20-for-rhel-9-x86_64-rpms` and `fast-datapath-for-rhel-9-x86_64-rpms` repos
- **Pull secret** at `/etc/crio/openshift-pull-secret` on the host
- `sshpass` installed on your local machine
- Step 13's `edge-camera` container image pushed to quay.io (public)

```bash
EDGE_HOST=rhaiis.example.com \
EDGE_USER=dev \
EDGE_PASS=<password> \
./steps/step-13b-edge-ai-microshift/deploy.sh
```

#### Interactive Demo Script

An interactive demo script is included for live presentations:

```bash
ssh dev@<edge-host>
./demo.sh
```

The script walks through 5 sections with pause-and-talk flow: edge platform, GPU-powered inference, model serving stack, edge AI workloads (with camera app URL), and embedded GitOps (ArgoCD syncing from Git).

### What to Verify After Deployment

SSH into the edge host and verify:

```bash
# MicroShift running
sudo systemctl is-active microshift
# Expected: active

# GPU device available
oc get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'
# Expected: 1

# ServingRuntime exists
oc get servingruntime triton-gpu -n edge-ai
# Expected: triton-gpu listed

# InferenceService is Ready
oc get inferenceservice face-recognition-edge -n edge-ai
# Expected: READY = True

# edge-camera pod is running
oc get pods -n edge-ai -l app.kubernetes.io/name=edge-camera
# Expected: 1/1 Running

# ArgoCD core running
oc get pods -n argocd
# Expected: argocd-application-controller, argocd-repo-server, argocd-redis Running
```

From your laptop (not the edge host):

```bash
# Route accessible
curl -sk "https://edge-camera-edge-ai.<public-ip>.nip.io/_stcore/health"
# Expected: ok
```

## The Demo

> In this demo, we show the face recognition model running on real edge hardware — a RHEL host with MicroShift 4.20 and an NVIDIA L4 GPU. The model was trained centrally, packaged as a ModelCar OCI image, and delivered to the edge via embedded ArgoCD. GPU-accelerated inference, live camera, full GitOps lifecycle.

### The Edge Platform

> MicroShift is Red Hat's edge-optimized Kubernetes distribution — it runs on a single RHEL host with minimal footprint. Combined with the `microshift-ai-model-serving` RPM, it provides KServe model serving at the edge.

1. SSH into the edge host:

```bash
ssh dev@<edge-host>
```

2. Show the platform status:

```bash
sudo systemctl is-active microshift
oc get nodes
oc get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'
```

**Expect:** MicroShift active, single node ready, 1 NVIDIA GPU allocatable.

> A single RHEL host running MicroShift with an L4 GPU — this is what edge AI looks like in production. The same Kubernetes API, the same `oc` commands, but optimized for remote sites with limited resources. Red Hat Build of MicroShift brings the OpenShift operational model to the edge.

### GPU-Accelerated Inference

> The model is served by NVIDIA Triton Inference Server on the L4 GPU, accessed via gRPC for minimal latency. The same YOLO11 model from Step 11, but GPU-accelerated at the edge.

1. Open the edge-camera Route URL on your laptop or phone:

```bash
echo "https://edge-camera-edge-ai.<public-ip>.nip.io"
```

2. Select **Photo** mode, take a selfie

**Expect:** Face recognized with bounding boxes. Inference latency is significantly lower than CPU-only (Step 13) due to the L4 GPU.

> GPU-accelerated inference at the edge — the NVIDIA L4 provides the compute, NVIDIA Triton serves the model, and KServe on MicroShift manages the lifecycle. All on a single RHEL host, delivered through the same platform that manages datacenter AI workloads.

### Embedded GitOps — Model Delivery

> The model wasn't SSH'd or manually copied to this device. ArgoCD core runs directly on MicroShift, watching a Git repository. When the model version changes in Git, ArgoCD syncs the new configuration automatically — no human intervention required.

1. Show the ArgoCD state on the edge host:

```bash
oc get applications -n argocd
oc get application edge-ai -n argocd -o jsonpath='{.status.sync.status}'
```

2. Show the current model version:

```bash
oc get inferenceservice face-recognition-edge -n edge-ai -o jsonpath='{.spec.predictor.model.storageUri}'
```

**Expect:** ArgoCD application is `Synced`. The `storageUri` points to a specific ModelCar OCI tag (e.g., `quay.io/adrina/face-recognition-modelcar:v3`).

> Embedded GitOps on the edge device. ArgoCD core watches the Git repository and auto-syncs — when Step 12's Tekton pipeline builds a new ModelCar and updates the tag in Git, every edge device picks up the new model within minutes. No SSH, no manual intervention, no site visits. This is how Red Hat manages AI at scale across edge fleets.

### Live Camera — Continuous Detection

> Beyond single photos, the same Streamlit camera app from Step 13 runs on the MicroShift edge device with GPU-accelerated inference for faster continuous detection.

1. Switch to **Live Video** mode on a laptop
2. Point the camera at yourself and another person

**Expect:** Continuous face detection with GPU-accelerated inference. Lower latency than the CPU-only Step 13 deployment.

> The same application code, the same container image — but now backed by an NVIDIA GPU on real edge hardware. Red Hat OpenShift AI on MicroShift provides the full edge AI stack: model serving, GPU management, GitOps delivery, and HTTPS routing.

## Key Takeaways

**For business stakeholders:**

- Prove the edge story on real hardware, not just in simulation
- Keep low-latency inference aligned to central standards
- Extend the same governed approach to smaller edge footprints

**For technical teams:**

- Use the same operating model on MicroShift and central OpenShift
- Deliver models to edge through GitOps and existing release patterns
- Reuse the same application flow while changing only the edge runtime and target

## Edge Fleet Management: Three Tiers

Edge deployments range from a single demo device to thousands of production edge nodes. This section documents three tiers of fleet management, matching Red Hat's recommended progression.

### Tier 1: Manual Deployment (Single Device)

SSH into the device, install RPMs, apply manifests with `oc apply`. Model updates require SSH, `podman build`, and pod restarts. This is what `deploy.sh` does — appropriate for demos and prototyping.

### Tier 2: Embedded GitOps (Dozens of Devices)

Deploy ArgoCD core controller (no UI, no API server) directly on MicroShift. The controller watches a Git repository and automatically syncs edge workloads. Model updates become Git commits — no SSH required.

**This is deployed on our demo edge host.** ArgoCD core runs in the `argocd` namespace and manages all `edge-ai` workloads from [`gitops/edge-ai-microshift/`](../../gitops/edge-ai-microshift/).

```text
ArgoCD Application "edge-ai" (argocd namespace)
  └── Source: github.com/adnan-drina/rhoai3-demo.git
      └── Path: gitops/edge-ai-microshift/
          ├── namespace.yaml
          ├── serving-runtime.yaml    (Triton GPU)
          ├── inference-service.yaml  (ModelCar OCI tag → model version)
          ├── stable-service.yaml     (gRPC ClusterIP)
          ├── edge-camera-deployment.yaml
          ├── edge-camera-service.yaml
          └── edge-camera-route.yaml
```

**Model update workflow:**
1. Train a new model version centrally (Step 12)
2. Build and push a new ModelCar tag: `quay.io/adrina/face-recognition-modelcar:v4`
3. Update `inference-service.yaml` in Git: change `storageUri` tag from `v3` to `v4`
4. Push to `main` — ArgoCD on MicroShift detects the change within 3 minutes
5. KServe reconciles the InferenceService, pulls the new ModelCar, restarts the predictor

**Setup notes:** ArgoCD core was installed from the upstream `core-install.yaml` (v2.14.11). Required fixes for MicroShift:
- Grant `anyuid` SCC to ArgoCD service accounts (Redis and controller run as non-standard UIDs)
- Create `argocd-redis` secret with empty `auth` key
- Recreate the Redis deployment (simplified, no init container)
- Create `default` AppProject (not included in core-install)

### Tier 3: Centralized Fleet Management (Hundreds+ Devices)

For production fleets, Red Hat recommends **RHEL Image Mode (bootc)** combined with **Red Hat Advanced Cluster Management (RHACM)** or **Red Hat Edge Manager**:

- **bootc images** package the entire edge device — OS, MicroShift, GPU drivers, model, and manifests — into a single bootable OCI container image. Updates are atomic; greenboot auto-rolls back on failure.
- **RHACM / Edge Manager** orchestrates fleet-wide updates from the central OCP cluster. Each device auto-registers and receives its configuration declaratively.

**References:**
- [Embedding in a RHEL for Edge image](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/embedding_in_a_rhel_for_edge_image/)
- [Installing with image mode for RHEL](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html-single/installing_with_image_mode_for_rhel/)
- [Manage MicroShift with RHACM and OpenShift GitOps](https://developers.redhat.com/articles/2024/10/07/manage-microshift-red-hat-advanced-cluster-management-and-openshift-gitops)
- [Red Hat Edge Manager (RHACM 2.13)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.13/html-single/edge_manager)

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

## Troubleshooting

### InferenceService stuck in "Not Ready"

**Root Cause:** The ModelCar OCI image is not accessible, or the GPU device plugin is not running.

**Solution:**
```bash
# Check predictor pod status
oc get pods -n edge-ai -l serving.kserve.io/inferenceservice=face-recognition-edge

# Check NVIDIA device plugin
oc get pods -n nvidia-device-plugin

# Verify GPU is allocatable
oc get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'
```

### ArgoCD not syncing

**Root Cause:** Repository access issue, or ArgoCD pods not running.

**Solution:**
```bash
# Check ArgoCD pods
oc get pods -n argocd

# Check application status
oc get application edge-ai -n argocd -o yaml | grep -A 5 status
```

## References

- [MicroShift 4.20 — Using AI models](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/using_ai_models/microshift-rh-openshift-ai)
- [MicroShift 4.20 — Installing from RPM package](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/installing_with_an_rpm_package/microshift-install-rpm)
- [NVIDIA GPU with Red Hat Device Edge](https://docs.nvidia.com/datacenter/cloud-native/edge/latest/nvidia-gpu-with-device-edge.html)
- [Custom Triton Runtime on AI on OpenShift](https://ai-on-openshift.io/odh-rhoai/custom-runtime-triton/)
- [RHOAI 3.3 — Custom ServingRuntimes (Triton examples)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/configuring_your_model-serving_platform/configuring_model_servers)
- [YOLOv5 Training and Serving (gRPC vs REST)](https://ai-on-openshift.io/demos/yolov5-training-serving/yolov5-training-serving/)
- [KServe Binary Tensor Data Extension](https://kserve.github.io/website/docs/concepts/architecture/data-plane/v2-protocol/binary-tensor-data-extension)
- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet)
- [Get started with AI for enterprise organizations — Red Hat](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)

> **See also:** [Step 13 — Edge AI (simulated)](../step-13-edge-ai/README.md), [Step 11 — Face Recognition](../step-11-face-recognition/README.md), [Step 12 — MLOps Pipeline](../step-12-mlops-pipeline/README.md)

## Next Steps

- This is the final step in the RHOAI 3.3 demo sequence. Return to the [project README](../../README.md) for the full demo overview.
