# Step 13b: Edge AI on MicroShift (Optional)

**"Real edge hardware"** — Deploy the face recognition model on MicroShift 4.20 running on a RHEL 9.5 host with NVIDIA L4 GPU. This is the production version of Step 13's simulated edge, following the Red Hat Edge + On-Premise AI/ML architecture.

## The Business Story

Step 13 simulated an edge deployment using a separate namespace on the central OCP cluster. Step 13b deploys on **real edge hardware** — a RHEL host running MicroShift, the same way you'd deploy to a factory floor kiosk, a security checkpoint, or a remote camera station. The model was trained centrally (Step 11-12), packaged as a ModelCar OCI image, and runs at the edge on OpenVINO. This is the complete Red Hat Edge + On-Premise lifecycle.

## What It Does

```text
Edge AI on MicroShift (real edge hardware)
├── MicroShift 4.20                  → Edge-optimized Kubernetes on RHEL 9.5
├── microshift-ai-model-serving RPM  → KServe (raw deployment mode) + ServingRuntimes
├── kserve-ovms ServingRuntime       → OpenVINO Model Server (from platform template)
├── face-recognition-edge ISVC       → YOLO11 ONNX model via ModelCar OCI image
├── edge-camera Deployment           → Streamlit app (same image as step-13)
│   ├── Photo mode                   → st.camera_input — single shot
│   └── Live Video mode              → camera_input_live — continuous capture
└── Route (nip.io)                   → HTTPS access via public IP + nip.io DNS
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **MicroShift 4.20** | Edge-optimized Kubernetes distribution | System |
| **kserve-ovms** ServingRuntime | OpenVINO Model Server (extracted from RPM) | `edge-ai` |
| **face-recognition-edge** InferenceService | YOLO11 ONNX via ModelCar OCI image | `edge-ai` |
| **edge-camera** Deployment | Streamlit camera app | `edge-ai` |
| **edge-camera** Route | HTTPS (nip.io, edge TLS) | `edge-ai` |

## Architecture

```text
┌─────────── RHEL 9.5 Host (MicroShift 4.20) ──────────────────────────────┐
│                                                                            │
│  ┌──────────────┐   KServe v2 REST   ┌──────────────────────────────────┐ │
│  │ edge-camera  │ ────────────────→  │ face-recognition-edge           │ │
│  │ (Streamlit)  │  binary tensors    │ InferenceService                │ │
│  │ Route: HTTPS │ ←───────────────── │ OpenVINO + ONNX (ModelCar OCI) │ │
│  └──────────────┘                    └──────────────────────────────────┘ │
│       ↑ browser                              ↑ model from                 │
│       (nip.io)                          localhost/face-recognition-        │
│                                         modelcar:v1 (built with           │
│                                         sudo podman on this host)         │
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

## Prerequisites

- **RHEL 9.5+ host** with SSH access and sudo
- **NVIDIA GPU** with driver installed (tested with L4, driver 595.58)
- **Red Hat subscription** that includes `rhocp-4.20-for-rhel-9-x86_64-rpms` and `fast-datapath-for-rhel-9-x86_64-rpms` repos
- **Pull secret** at `/etc/crio/openshift-pull-secret` on the host
- `sshpass` installed on your local machine
- Step 13's `edge-camera` container image pushed to quay.io (public)

> **Note (RHOAI 3.3 / MicroShift 4.20):** AI model serving on MicroShift is a Technology Preview feature. The compatibility matrix shows MicroShift 4.20 is verified with RHEL 9.6, but it installed and ran successfully on RHEL 9.5 in our testing.

## Deploy

```bash
EDGE_HOST=rhaiis.example.com \
EDGE_USER=dev \
EDGE_PASS=<password> \
./steps/step-13b-edge-ai-microshift/deploy.sh
```

The script runs from your **local machine** and SSHes into the edge host. It:
1. Audits the host (GPU, services, disk)
2. Stops any existing RHAIIS/vLLM service to free the GPU
3. Installs MicroShift 4.20 + `microshift-ai-model-serving` RPM
4. Builds the YOLO11 ModelCar OCI image locally on the host (`sudo podman`)
5. Creates the ServingRuntime from the platform template (per official MicroShift docs)
6. Deploys the InferenceService and Streamlit camera app
7. Creates an HTTPS Route with nip.io domain

## Demo Walkthrough

### Scene 1: The Edge Device

**Do:** Show the audience the RHEL host terminal (`ssh dev@<host>`). Run `oc get nodes`, `oc get pods -n edge-ai`.

**Say:** *"This is a real RHEL 9.5 server with an NVIDIA L4 GPU — it was previously running a 1B parameter LLM. We've repurposed it as an edge device running MicroShift, Red Hat's edge-optimized Kubernetes. The face recognition model is served by OpenVINO, loaded from a ModelCar OCI image."*

### Scene 2: Edge Inference

**Do:** Open the edge camera URL in your browser:

```bash
echo "https://$(ssh dev@<host> oc get route edge-camera -n edge-ai -o jsonpath='{.spec.host}')"
```

Take a photo. Show bounding boxes and detection results.

**Say:** *"This is inference at the real edge — the model runs on this RHEL server, not in the cloud. The same model trained centrally in Step 12, packaged as a ModelCar image, deployed to the edge via MicroShift."*

### Scene 3: The Red Hat Edge Architecture

**Say:** *"This is the complete Red Hat Edge + On-Premise pattern: data scientists train models in the datacenter on RHOAI, package them as OCI images, and deploy to edge devices running MicroShift. The same KServe API, the same OpenVINO runtime, the same inference protocol — whether you're in the datacenter or at the edge."*

## What to Verify After Deployment

```bash
# Run the validation script
EDGE_HOST=rhaiis.example.com EDGE_USER=dev EDGE_PASS=<password> \
  ./steps/step-13b-edge-ai-microshift/validate.sh

# Or verify manually via SSH:
ssh dev@<host>

# MicroShift is running
systemctl is-active microshift

# Node is Ready
oc get nodes

# KServe controller is running
oc get pods -n redhat-ods-applications

# InferenceService is Ready
oc get isvc -n edge-ai
# Expected: READY = True

# Model metadata
oc exec -n edge-ai deploy/face-recognition-edge-predictor -c kserve-container -- \
  curl -s localhost:8888/v2/models/face-recognition-edge

# Streamlit app is running
oc get pods -n edge-ai -l app.kubernetes.io/name=edge-camera
```

## Design Decisions

> **Design Decision:** **ModelCar OCI format** for model storage (not S3). This is the MicroShift-recommended and tested approach. The model is baked into a container image, built with `sudo podman` so CRI-O can access it directly from root's container storage. No external storage dependency.

> **Design Decision:** **ServingRuntime extracted from RPM template**, not hand-crafted. Per MicroShift official docs, the OVMS image reference is extracted from `/usr/share/microshift/release/release-ai-model-serving-$(uname -i).json` and substituted into the template at `/usr/lib/microshift/manifests.d/050-microshift-ai-model-serving-runtimes/ovms-kserve.yaml`. This ensures the image version matches the installed MicroShift version.

> **Design Decision:** **CPU-only inference (OpenVINO)**. The NVIDIA device plugin failed to register with MicroShift's kubelet (5-second timeout on the registration socket). OpenVINO on CPU is the verified runtime per MicroShift docs. The YOLO11n model runs at ~100ms on CPU, which is sufficient for the demo. GPU inference is documented as a future improvement.

> **Design Decision:** **nip.io for Route DNS**. MicroShift defaults to `apps.example.com` which doesn't resolve. Using `<public-ip>.nip.io` provides automatic DNS resolution without configuring a DNS server. The deploy script detects the public IP from AWS metadata and configures the base domain dynamically.

> **Design Decision:** **Remote deploy script** (`deploy.sh` runs locally, SSHes into the edge host). This matches the operational model — you manage edge devices remotely, not by logging into each one interactively.

> **Design Decision:** **Specific tag (`v1`) on ModelCar image**, not `latest`. Per MicroShift docs, using `latest` sets `imagePullPolicy: Always`, which would fail in offline environments. A specific tag uses `IfNotPresent`.

## Known Limitations

### NVIDIA device plugin registration timeout

**Symptom:** `nvidia-device-plugin-daemonset` pod logs show `Could not register device plugin: context deadline exceeded`.

**Root Cause:** The NVIDIA device plugin tries to register with the kubelet at `/var/lib/kubelet/device-plugins/kubelet.sock`. The registration handshake times out after 5 seconds. This may be related to MicroShift's kubelet configuration or the OVN networking instability observed during initial startup.

**Workaround:** Use CPU-only inference with OpenVINO. The YOLO11n model inference is ~100ms on CPU. GPU support can be revisited when the NVIDIA device plugin compatibility with MicroShift is verified.

### OVN networking pods in CrashLoopBackOff

**Symptom:** `ovnkube-master` and `ovnkube-node` pods crash with port binding errors.

**Root Cause:** Port conflicts from stale processes after MicroShift restarts. The router and workload pods continue to function because they use host networking.

**Workaround:** The pods eventually stabilize, or a clean restart (`sudo systemctl stop microshift; sleep 10; sudo systemctl start microshift`) resolves the conflicts.

### RHDP Lab subscription doesn't include MicroShift repos

**Symptom:** `subscription-manager repos --enable rhocp-4.20-for-rhel-9-x86_64-rpms` fails on RHDP-provisioned hosts.

**Root Cause:** RHDP Labs content views only expose baseos, appstream, and ansible repos. MicroShift repos are not included.

**Solution:** Re-register the host with a personal Red Hat subscription that includes OpenShift entitlements:
```bash
sudo subscription-manager config --server.hostname=subscription.rhsm.redhat.com \
  --server.prefix=/subscription --rhsm.baseurl=https://cdn.redhat.com
sudo subscription-manager config --rhsm.repo_ca_cert=/etc/rhsm/ca/redhat-uep.pem
sudo subscription-manager register --username=<your-rh-email>
```

## Future Improvements

- **GPU inference:** Resolve the NVIDIA device plugin registration issue and enable `nvidia.com/gpu: 1` on the InferenceService
- **Offline deployment:** Pre-pull all container images and build a bootc image with MicroShift + model baked in
- **Fleet management:** Use RHEL Image Builder + Ansible to deploy MicroShift + model to multiple edge sites
- **Model sync:** Automate ModelCar image rebuild when the central Model Registry has a new version
- **Metrics:** Enable `microshift-observability` RPM for Open Telemetry model server metrics

## References

- [MicroShift 4.20 — Using AI models](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/using_ai_models/microshift-rh-openshift-ai)
- [MicroShift 4.20 — Installing from RPM package](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/installing_with_an_rpm_package/microshift-install-rpm)
- [MicroShift 4.20 — Getting ready to install](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html/getting_ready_to_install_microshift/)
- [NVIDIA GPU with Red Hat Device Edge](https://docs.nvidia.com/datacenter/cloud-native/edge/latest/nvidia-gpu-with-device-edge.html)
- [Build and deploy a ModelCar container in OpenShift AI](https://developers.redhat.com/articles/2025/01/30/build-and-deploy-modelcar-container-openshift-ai)

> **See also:** [Step 13 — Edge AI (simulated)](../step-13-edge-ai/README.md), [Step 11 — Face Recognition](../step-11-face-recognition/README.md), [Step 12 — MLOps Pipeline](../step-12-mlops-pipeline/README.md)
