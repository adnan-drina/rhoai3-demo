#!/bin/bash
# =============================================================================
# Step 13b: Edge AI on MicroShift
# =============================================================================
# Deploys face recognition inference + Streamlit camera app on MicroShift 4.20
# running on a RHEL 9.5+ host with NVIDIA L4 GPU.
#
# This script is designed to run from your LOCAL machine (not the edge host).
# It SSHes into the edge host to perform all operations.
#
# Prerequisites:
#   - RHEL 9.5+ host with SSH access
#   - NVIDIA GPU with driver installed
#   - Pull secret available (extracted from central OCP or downloaded)
#   - sshpass installed locally
#
# Usage:
#   EDGE_HOST=rhaiis.example.com EDGE_USER=dev EDGE_PASS=password ./deploy.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BLUE}▶ $*${NC}"; }

OPERATOR_APP_NAME="step-13b-edge-ai-microshift-operator"
PIPELINE_APP_NAME="step-13b-edge-ai-microshift"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-openshift-gitops}"
MLOPS_NAMESPACE="${MLOPS_NAMESPACE:-enterprise-mlops}"

load_env
check_oc_logged_in

wait_for_tekton_crds() {
    log_info "Waiting for OpenShift Pipelines CRDs..."
    for i in $(seq 1 90); do
        if oc get crd tasks.tekton.dev pipelines.tekton.dev &>/dev/null; then
            log_success "OpenShift Pipelines CRDs are available"
            return 0
        fi
        if (( i % 12 == 0 )); then
            log_info "  Still waiting for Tekton CRDs... ($(( i * 10 ))s)"
        fi
        sleep 10
    done

    log_error "OpenShift Pipelines CRDs did not become available"
    return 1
}

approve_pipelines_install_plan() {
    log_info "Checking OpenShift Pipelines InstallPlan approval..."
    for i in $(seq 1 60); do
        local install_plan
        local approved
        install_plan=$(oc get subscription openshift-pipelines-operator-rh -n openshift-operators -o jsonpath='{.status.installPlanRef.name}' 2>/dev/null || true)

        if [[ -n "$install_plan" ]]; then
            approved=$(oc get installplan "$install_plan" -n openshift-operators -o jsonpath='{.spec.approved}' 2>/dev/null || true)
            if [[ "$approved" != "true" ]]; then
                oc patch installplan "$install_plan" -n openshift-operators --type merge -p '{"spec":{"approved":true}}' >/dev/null
                log_success "Approved InstallPlan ${install_plan}"
            else
                log_success "InstallPlan ${install_plan} already approved"
            fi
            return 0
        fi

        if (( i % 6 == 0 )); then
            log_info "  Still waiting for generated InstallPlan... ($(( i * 10 ))s)"
        fi
        sleep 10
    done

    log_error "OpenShift Pipelines InstallPlan was not generated"
    return 1
}

wait_for_argocd_app() {
    local app_name="$1"
    local require_healthy="${2:-true}"

    if [[ "$require_healthy" == "true" ]]; then
        log_info "Waiting for ArgoCD application ${app_name} to become Synced/Healthy..."
    else
        log_info "Waiting for ArgoCD application ${app_name} to become Synced..."
    fi
    for i in $(seq 1 90); do
        local sync_status
        local health_status
        sync_status=$(oc get applications.argoproj.io "$app_name" -n "$ARGO_NAMESPACE" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
        health_status=$(oc get applications.argoproj.io "$app_name" -n "$ARGO_NAMESPACE" -o jsonpath='{.status.health.status}' 2>/dev/null || true)

        if [[ "$sync_status" == "Synced" && ( "$require_healthy" != "true" || "$health_status" == "Healthy" ) ]]; then
            if [[ "$require_healthy" == "true" ]]; then
                log_success "ArgoCD application is Synced and Healthy"
            else
                log_success "ArgoCD application is Synced"
            fi
            return 0
        fi

        if (( i % 6 == 0 )); then
            log_info "  Current state: sync=${sync_status:-unknown}, health=${health_status:-unknown}"
        fi
        sleep 10
    done

    if [[ "$require_healthy" == "true" ]]; then
        log_error "ArgoCD application ${app_name} did not become Synced/Healthy"
    else
        log_error "ArgoCD application ${app_name} did not become Synced"
    fi
    oc get applications.argoproj.io "$app_name" -n "$ARGO_NAMESPACE" -o wide || true
    return 1
}

wait_for_central_resources() {
    log_info "Waiting for central ModelCar release resources..."
    for i in $(seq 1 60); do
        if oc get task.tekton.dev build-modelcar -n "$MLOPS_NAMESPACE" &>/dev/null \
            && oc get task.tekton.dev update-gitops -n "$MLOPS_NAMESPACE" &>/dev/null \
            && oc get pipeline.tekton.dev modelcar-release -n "$MLOPS_NAMESPACE" &>/dev/null; then
            log_success "Central ModelCar release pipeline is installed"
            return 0
        fi
        if (( i % 6 == 0 )); then
            log_info "  Still waiting for Tekton tasks and pipeline... ($(( i * 10 ))s)"
        fi
        sleep 10
    done

    log_error "Central ModelCar release resources were not created"
    return 1
}

deploy_central_gitops() {
    log_step "Deploying central ModelCar release pipeline"

    oc whoami >/dev/null
    oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${OPERATOR_APP_NAME}.yaml"
    oc annotate applications.argoproj.io "$OPERATOR_APP_NAME" -n "$ARGO_NAMESPACE" argocd.argoproj.io/refresh=hard --overwrite &>/dev/null || true

    approve_pipelines_install_plan
    wait_for_tekton_crds

    wait_for_argocd_app "$OPERATOR_APP_NAME" false

    oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${PIPELINE_APP_NAME}.yaml"
    oc annotate applications.argoproj.io "$PIPELINE_APP_NAME" -n "$ARGO_NAMESPACE" argocd.argoproj.io/refresh=hard --overwrite &>/dev/null || true
    wait_for_argocd_app "$PIPELINE_APP_NAME"
    wait_for_central_resources
}

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 13b: Edge AI on MicroShift                                    ║"
echo "║  Face Recognition on RHEL 9.5 + MicroShift 4.20                    ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

deploy_central_gitops

if [[ -z "${EDGE_HOST:-}" || -z "${EDGE_PASS:-}" ]]; then
    log_warn "MicroShift host deployment skipped because EDGE_HOST or EDGE_PASS is not set."
    log_info "Central OpenShift resources are ready. Set EDGE_HOST, EDGE_USER, and EDGE_PASS to deploy the edge host."
    exit 0
fi

EDGE_HOST="${EDGE_HOST}"
EDGE_USER="${EDGE_USER:-dev}"
EDGE_PASS="${EDGE_PASS}"
MODELCAR_TAG="${MODELCAR_TAG:-v1}"

SSH_CMD="sshpass -p '$EDGE_PASS' ssh -o StrictHostKeyChecking=no ${EDGE_USER}@${EDGE_HOST}"

run_remote() {
    sshpass -p "$EDGE_PASS" ssh -o StrictHostKeyChecking=no "${EDGE_USER}@${EDGE_HOST}" "$1"
}

# =============================================================================
# Phase 1: Audit
# =============================================================================
log_step "1/7 Auditing edge host ${EDGE_HOST}..."

run_remote "cat /etc/redhat-release && nvidia-smi --query-gpu=name,memory.free --format=csv,noheader" || {
    log_error "Cannot connect or GPU not available"; exit 1
}
log_success "Edge host reachable, GPU present"

# =============================================================================
# Phase 2: Stop existing AI workload
# =============================================================================
log_step "2/7 Stopping existing AI workload (RHAIIS)..."

run_remote "
    if systemctl is-active rhaiis.service &>/dev/null; then
        sudo systemctl stop rhaiis.service
        sudo systemctl disable rhaiis.service 2>/dev/null
        echo 'RHAIIS stopped'
    else
        echo 'RHAIIS not running — skipping'
    fi
" || log_warn "Could not stop RHAIIS"

# =============================================================================
# Phase 3: Install MicroShift
# =============================================================================
log_step "3/7 Installing MicroShift..."

run_remote "
    if rpm -q microshift &>/dev/null; then
        echo 'MicroShift already installed'
    else
        echo 'Configuring subscription repos...'
        sudo subscription-manager repos \
            --enable rhocp-4.20-for-rhel-9-\$(uname -m)-rpms \
            --enable fast-datapath-for-rhel-9-\$(uname -m)-rpms 2>&1 | tail -3

        echo 'Installing MicroShift + AI model serving + oc CLI...'
        sudo dnf install -y microshift microshift-ai-model-serving \
            microshift-ai-model-serving-release-info openshift-clients 2>&1 | tail -5
    fi

    # Ensure pull-secret is in place
    if [ ! -f /etc/crio/openshift-pull-secret ]; then
        echo 'ERROR: Pull secret not found at /etc/crio/openshift-pull-secret'
        echo 'Copy it before running this script:'
        echo '  scp pull-secret.json \${EDGE_USER}@\${EDGE_HOST}:/tmp/'
        echo '  ssh ... sudo cp /tmp/pull-secret.json /etc/crio/openshift-pull-secret'
        exit 1
    fi

    # Configure NVIDIA runtime for CRI-O
    sudo nvidia-ctk runtime configure --runtime=crio --set-as-default 2>/dev/null || true

    # Configure nip.io base domain
    PUBLIC_IP=\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || hostname -I | awk '{print \$1}')
    sudo mkdir -p /etc/microshift
    echo \"dns:
  baseDomain: \${PUBLIC_IP}.nip.io\" | sudo tee /etc/microshift/config.yaml

    # Start MicroShift
    sudo systemctl enable --now microshift 2>&1 || sudo systemctl restart microshift

    # Setup kubeconfig
    sleep 30
    mkdir -p ~/.kube
    sudo cp /var/lib/microshift/resources/kubeadmin/kubeconfig /tmp/kubeconfig
    sudo chmod 644 /tmp/kubeconfig
    cp /tmp/kubeconfig ~/.kube/config
"
log_success "MicroShift installed and running"

# Wait for node Ready
log_info "Waiting for node to be Ready..."
for i in $(seq 1 24); do
    STATUS=$(run_remote "oc get nodes --no-headers 2>/dev/null | awk '{print \$2}'" 2>/dev/null || echo "")
    if [[ "$STATUS" == "Ready" ]]; then
        log_success "Node is Ready"
        break
    fi
    sleep 10
done

# =============================================================================
# Phase 4: Build ModelCar OCI image
# =============================================================================
log_step "4/7 Building ModelCar OCI image..."

sshpass -p "$EDGE_PASS" scp -o StrictHostKeyChecking=no \
    "$SCRIPT_DIR/modelcar/Containerfile" \
    "${EDGE_USER}@${EDGE_HOST}:/tmp/modelcar-Containerfile"

run_remote "
    if sudo podman image exists localhost/face-recognition-modelcar:${MODELCAR_TAG} 2>/dev/null; then
        echo 'ModelCar image already exists'
    else
        sudo podman build -t localhost/face-recognition-modelcar:${MODELCAR_TAG} \
            -f /tmp/modelcar-Containerfile /tmp/ 2>&1 | tail -5
    fi
    sudo podman run --rm localhost/face-recognition-modelcar:${MODELCAR_TAG} \
        ls -lh /models/1/model.onnx
"
log_success "ModelCar image ready"

# =============================================================================
# Phase 5: Deploy ServingRuntime (per MicroShift official procedure)
# =============================================================================
log_step "5/7 Deploying ServingRuntime and InferenceService..."

run_remote "
    oc create ns edge-ai 2>/dev/null || true

    # Create ServingRuntime from platform template (official MicroShift procedure)
    if oc get servingruntime kserve-ovms -n edge-ai &>/dev/null; then
        echo 'ServingRuntime already exists'
    else
        OVMS_IMAGE=\$(jq -r '.images | with_entries(select(.key == \"ovms-image\")) | .[]' \
            /usr/share/microshift/release/release-ai-model-serving-\$(uname -i).json)
        cp /usr/lib/microshift/manifests.d/050-microshift-ai-model-serving-runtimes/ovms-kserve.yaml /tmp/ovms-kserve.yaml
        sed -i \"s,image: ovms-image,image: \${OVMS_IMAGE},\" /tmp/ovms-kserve.yaml
        oc create -n edge-ai -f /tmp/ovms-kserve.yaml
        echo \"ServingRuntime created (OVMS image: \${OVMS_IMAGE})\"
    fi
"

# Apply InferenceService
sshpass -p "$EDGE_PASS" scp -o StrictHostKeyChecking=no \
    "$SCRIPT_DIR/manifests/inference-service.yaml" \
    "${EDGE_USER}@${EDGE_HOST}:/tmp/inference-service.yaml"

run_remote "oc apply -f /tmp/inference-service.yaml"

# Wait for predictor
log_info "Waiting for predictor pod (may take 2-5 min for image pull)..."
for i in $(seq 1 30); do
    READY=$(run_remote "oc get pods -n edge-ai --no-headers 2>/dev/null | grep face-recognition | grep '2/2.*Running'" 2>/dev/null || echo "")
    if [[ -n "$READY" ]]; then
        log_success "Face recognition predictor is Running"
        break
    fi
    if (( i % 6 == 0 )); then
        log_info "  Still waiting... ($(( i * 10 ))s)"
    fi
    sleep 10
done

# =============================================================================
# Phase 6: Deploy Streamlit edge-camera app
# =============================================================================
log_step "6/7 Deploying edge-camera Streamlit app..."

for f in edge-camera-deployment.yaml edge-camera-service.yaml; do
    sshpass -p "$EDGE_PASS" scp -o StrictHostKeyChecking=no \
        "$SCRIPT_DIR/manifests/$f" "${EDGE_USER}@${EDGE_HOST}:/tmp/$f"
    run_remote "oc apply -f /tmp/$f"
done

# Create Route with dynamic nip.io host
run_remote "
    PUBLIC_IP=\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || hostname -I | awk '{print \$1}')
    oc delete route edge-camera -n edge-ai 2>/dev/null || true
    cat << ROUTEEOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: edge-camera
  namespace: edge-ai
spec:
  host: edge-camera-edge-ai.apps.\${PUBLIC_IP}.nip.io
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  to:
    kind: Service
    name: edge-camera
  port:
    targetPort: 8501
ROUTEEOF
"

# Wait for edge-camera pod
for i in $(seq 1 12); do
    READY=$(run_remote "oc get pods -n edge-ai --no-headers 2>/dev/null | grep edge-camera | grep '1/1.*Running'" 2>/dev/null || echo "")
    if [[ -n "$READY" ]]; then
        log_success "edge-camera pod is Running"
        break
    fi
    sleep 10
done

# =============================================================================
# Phase 7: Summary
# =============================================================================
log_step "7/7 Deployment Complete"

ROUTE_HOST=$(run_remote "oc get route edge-camera -n edge-ai -o jsonpath='{.spec.host}'" 2>/dev/null || echo "unknown")

echo ""
echo "  Edge Camera App (MicroShift):"
echo "    https://${ROUTE_HOST}"
echo "    (accept the self-signed certificate warning)"
echo ""
echo "  Edge Model Server:"
echo "    ssh ${EDGE_USER}@${EDGE_HOST} oc get isvc -n edge-ai"
echo ""
log_info "Validate: EDGE_HOST=${EDGE_HOST} EDGE_USER=${EDGE_USER} EDGE_PASS=*** ./validate.sh"
echo ""
