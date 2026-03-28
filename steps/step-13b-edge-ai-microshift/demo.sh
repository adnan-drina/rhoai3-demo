#!/bin/bash
# =============================================================================
# Edge AI on MicroShift — Interactive Demo Script
# =============================================================================
# Run this script on the RHEL edge host to walk through the demo.
# Each section pauses so you can talk to the audience before continuing.
#
# Usage: ./demo.sh
# =============================================================================

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

pause() {
    echo ""
    echo -e "${YELLOW}Press ENTER to continue...${NC}"
    read -r
    echo ""
}

section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

cmd() {
    echo -e "${GREEN}\$ $1${NC}"
    eval "$1"
    echo ""
}

ROUTE_HOST=$(oc get route edge-camera -n edge-ai -o jsonpath='{.spec.host}' 2>/dev/null || echo "unknown")

# =============================================================================
clear
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║        Edge AI on MicroShift — Live Demo                    ║"
echo "  ║        Face Recognition on NVIDIA L4 GPU at the Edge        ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "  ${BOLD}Red Hat Edge + On-Premise AI/ML Pattern:${NC}"
echo ""
echo "  Datacenter (OCP 4.20)          Edge (MicroShift 4.20 on RHEL 9.5)"
echo "  ┌──────────────────────┐       ┌──────────────────────────────────┐"
echo "  │ Train (KFP pipeline) │       │ Streamlit Camera App             │"
echo "  │ Evaluate (mAP50)     │       │ NVIDIA Triton + ONNX Runtime     │"
echo "  │ Register (Model Reg) │──────>│ YOLO11 ONNX on L4 GPU           │"
echo "  │ Package (ModelCar)   │  OCI  │ KServe v2 API                    │"
echo "  └──────────────────────┘       │ ArgoCD core (GitOps from Git)    │"
echo "                                  └──────────────────────────────────┘"
echo ""
echo -e "  Camera App: ${BOLD}${GREEN}https://${ROUTE_HOST}${NC}"
echo ""
pause

# =============================================================================
section "1. The Edge Platform"
echo "  What's running on this host?"
echo ""

cmd "cat /etc/redhat-release"
cmd "rpm -q microshift microshift-ai-model-serving"
cmd "oc get nodes"

pause

# =============================================================================
section "2. GPU-Powered Inference"
echo "  NVIDIA L4 GPU running Triton Inference Server with our YOLO11 model."
echo ""

cmd "nvidia-smi"
cmd "oc get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'; echo ' GPU(s) allocatable to Kubernetes'"

pause

# =============================================================================
section "3. Edge AI Workloads"
echo "  Face recognition model + camera app running in the edge-ai namespace."
echo ""

cmd "oc get pods -n edge-ai"
cmd "oc get pods -n nvidia-device-plugin"

pause

# =============================================================================
section "4. Model Serving Stack"
echo "  YOLO11 ONNX model packaged as a ModelCar OCI image — no S3 needed."
echo "  Served by NVIDIA Triton with CUDA + ONNX Runtime on the L4 GPU."
echo ""

cmd "oc get isvc face-recognition-edge -n edge-ai"
cmd "oc get isvc face-recognition-edge -n edge-ai -o jsonpath='ModelCar: {.spec.predictor.model.storageUri}'; echo ''"
cmd "oc get servingruntime -n edge-ai -o custom-columns=RUNTIME:.metadata.name,IMAGE:.spec.containers[0].image"

pause

# =============================================================================
section "5. The Camera App"
echo "  Streamlit app accessible via HTTPS — open it on your phone or laptop."
echo ""

echo -e "  ${BOLD}${GREEN}https://${ROUTE_HOST}${NC}"
echo ""
echo "  (Accept the self-signed certificate warning)"
echo ""

cmd "oc get route -n edge-ai"

pause

# =============================================================================
section "6. Embedded GitOps (ArgoCD on MicroShift)"
echo "  ArgoCD core runs directly on this edge device — no central dependency."
echo "  It watches a Git repo and auto-syncs all edge-ai workloads."
echo "  Model updates = change the ModelCar tag in Git, push, done."
echo ""

cmd "oc get pods -n argocd"
cmd "oc get app -n argocd edge-ai"
cmd "oc get app -n argocd edge-ai -o jsonpath='Repo: {.spec.source.repoURL}  Path: {.spec.source.path}  Sync: {.status.sync.status}'; echo ''"

pause

# =============================================================================
section "Demo Complete"
echo ""
echo -e "  Camera App: ${BOLD}${GREEN}https://${ROUTE_HOST}${NC}"
echo ""
