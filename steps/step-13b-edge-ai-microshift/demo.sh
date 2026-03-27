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

# =============================================================================
clear
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║        Edge AI on MicroShift — Live Demo                    ║"
echo "  ║        Face Recognition at the Edge                         ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  This RHEL host was previously running a 1B parameter LLM."
echo "  We replaced it with MicroShift + a YOLO11 face recognition model."
echo ""
pause

# =============================================================================
section "1. The Edge Platform"
echo "  What's running on this host?"
echo ""

cmd "cat /etc/redhat-release"
cmd "rpm -q microshift microshift-ai-model-serving"
cmd "oc get nodes -o wide"

pause

# =============================================================================
section "2. GPU Hardware"
echo "  NVIDIA L4 GPU — 24 GB VRAM, available for edge inference."
echo ""

cmd "nvidia-smi"

pause

# =============================================================================
section "3. Kubernetes at the Edge"
echo "  MicroShift runs the same KServe API as the datacenter."
echo ""

cmd "oc get pods -A"

pause

# =============================================================================
section "4. The AI Model (ModelCar OCI Image)"
echo "  The model is packaged as an OCI container image — no S3 needed."
echo ""

cmd "oc get isvc -n edge-ai"
cmd "oc get isvc face-recognition-edge -n edge-ai -o jsonpath='{.spec.predictor.model.storageUri}'; echo ''"
cmd "sudo podman images | grep modelcar"

pause

# =============================================================================
section "5. Model Server Details"
echo "  OpenVINO Model Server — extracted from the MicroShift RPM template."
echo ""

cmd "oc get servingruntime -n edge-ai -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image"

echo "  Model metadata (input/output shapes):"
SVC_IP=$(oc get svc -n edge-ai face-recognition-edge-predictor -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [ -n "$SVC_IP" ] && [ "$SVC_IP" != "None" ]; then
    cmd "curl -s http://${SVC_IP}:80/v2/models/face-recognition-edge | python3 -m json.tool"
else
    cmd "oc exec -n edge-ai deploy/face-recognition-edge-predictor -c kserve-container -- curl -s localhost:8888/v2/models/face-recognition-edge | python3 -m json.tool"
fi

pause

# =============================================================================
section "6. GPU Visibility in Kubernetes"
echo "  The NVIDIA device plugin exposes the GPU to Kubernetes."
echo ""

cmd "oc get node -o jsonpath='{.items[0].status.capacity.nvidia\.com/gpu}'; echo ' GPU(s) available'"
cmd "oc get pods -n nvidia-device-plugin"

pause

# =============================================================================
section "7. The Camera App"
echo "  Streamlit app accessible via HTTPS — open it on your phone or laptop."
echo ""

ROUTE_HOST=$(oc get route edge-camera -n edge-ai -o jsonpath='{.spec.host}' 2>/dev/null)
echo -e "  ${BOLD}${GREEN}https://${ROUTE_HOST}${NC}"
echo ""
echo "  (Accept the self-signed certificate warning)"
echo ""

cmd "oc get route -n edge-ai"
cmd "oc get pods -n edge-ai"

pause

# =============================================================================
section "8. The Before and After"
echo "  This host was running RHAIIS (vLLM with Gemma 1B)."
echo "  We stopped it and deployed MicroShift with face recognition."
echo ""

cmd "cat /etc/systemd/system/rhaiis.service 2>/dev/null | grep -E 'Description|ExecStart' || echo 'RHAIIS service file not found'"
cmd "systemctl is-active rhaiis.service 2>/dev/null || echo 'RHAIIS: inactive (stopped for MicroShift)'"
cmd "systemctl is-active microshift"

pause

# =============================================================================
section "Demo Complete"
echo ""
echo -e "  ${BOLD}Red Hat Edge + On-Premise AI/ML Pattern:${NC}"
echo ""
echo "  Datacenter (OCP 4.20)        Edge (MicroShift 4.20 on RHEL)"
echo "  ┌──────────────────────┐     ┌──────────────────────────────┐"
echo "  │ Train (KFP pipeline) │     │ Streamlit Camera App         │"
echo "  │ Evaluate (mAP50)     │     │ OpenVINO Model Server        │"
echo "  │ Register (Model Reg) │────>│ YOLO11 ONNX (ModelCar OCI)   │"
echo "  │ Package (ModelCar)   │ OCI │ KServe v2 API                │"
echo "  └──────────────────────┘     └──────────────────────────────┘"
echo ""
echo -e "  Camera App: ${BOLD}${GREEN}https://${ROUTE_HOST}${NC}"
echo ""
