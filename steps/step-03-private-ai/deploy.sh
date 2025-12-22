#!/usr/bin/env bash
# =============================================================================
# Step 03: Private AI - GPU as a Service
# =============================================================================
# Deploys GPU-as-a-Service infrastructure:
# - Authentication (HTPasswd, OAuth, Groups)
# - Kueue resources (ResourceFlavors, ClusterQueue, LocalQueue)
# - Project RBAC (ai-admin, ai-developer)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-03-private-ai"

load_env
check_oc_logged_in

log_step "Step 03: Private AI - GPU as a Service"

# =============================================================================
# Prerequisites check
# =============================================================================
log_step "Checking prerequisites..."

# Check step-02-rhoai was deployed
if ! oc get applications -n openshift-gitops step-02-rhoai &>/dev/null; then
    log_error "step-02-rhoai Argo CD Application not found!"
    log_info "Please run: ./steps/step-02-rhoai/deploy.sh first"
    exit 1
fi

# Check DSC is ready
DSC_PHASE=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$DSC_PHASE" != "Ready" ]]; then
    log_error "DataScienceCluster is not Ready (current: $DSC_PHASE)"
    exit 1
fi

# Check GPU nodes exist
GPU_NODES=$(oc get nodes -l node-role.kubernetes.io/gpu --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$GPU_NODES" -eq 0 ]]; then
    log_warn "No GPU nodes found with label 'node-role.kubernetes.io/gpu'"
    log_info "Kueue ResourceFlavors won't match any nodes until GPU nodes are available"
fi

log_success "Prerequisites verified"

# =============================================================================
# Deploy via Argo CD Application
# =============================================================================
log_step "Creating Argo CD Application for Private AI"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

# =============================================================================
# Wait for authentication resources
# =============================================================================
log_step "Waiting for authentication resources..."

# Wait for HTPasswd secret
until oc get secret htpass-secret -n openshift-config &>/dev/null; do
    log_info "Waiting for HTPasswd secret..."
    sleep 5
done
log_success "HTPasswd secret created"

# Wait for OAuth to update (this triggers auth pod restart)
log_info "Waiting for OAuth configuration to apply..."
sleep 10

# Wait for groups
until oc get group rhoai-admins &>/dev/null; do
    log_info "Waiting for rhoai-admins group..."
    sleep 5
done
log_success "Groups created"

# =============================================================================
# Wait for namespace and Kueue resources
# =============================================================================
log_step "Waiting for project resources..."

# Wait for namespace
until oc get namespace private-ai &>/dev/null; do
    log_info "Waiting for private-ai namespace..."
    sleep 5
done
log_success "Namespace 'private-ai' created"

# Wait for Kueue resources (if CRDs available)
if oc get crd clusterqueues.kueue.x-k8s.io &>/dev/null; then
    log_info "Waiting for Kueue resources..."
    
    until oc get clusterqueue rhoai-main-queue &>/dev/null; do
        sleep 5
    done
    log_success "ClusterQueue 'rhoai-main-queue' created"
    
    until oc get localqueue private-ai-queue -n private-ai &>/dev/null; do
        sleep 5
    done
    log_success "LocalQueue 'private-ai-queue' created"
else
    log_warn "Kueue CRDs not available - skipping queue verification"
fi

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "GPU-as-a-Service Infrastructure Deployed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Demo Users:"
echo "  ┌──────────────┬─────────────┬────────────────┐"
echo "  │ Username     │ Password    │ Role           │"
echo "  ├──────────────┼─────────────┼────────────────┤"
echo "  │ ai-admin     │ redhat123   │ Service Admin  │"
echo "  │ ai-developer │ redhat123   │ Service User   │"
echo "  └──────────────┴─────────────┴────────────────┘"
echo ""
echo "Kueue Resources:"
echo "  • ResourceFlavor: nvidia-l4-1gpu (g6.4xlarge)"
echo "  • ResourceFlavor: nvidia-l4-4gpu (g6.12xlarge)"
echo "  • ClusterQueue:   rhoai-main-queue"
echo "  • LocalQueue:     private-ai-queue"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Test login:"
echo "  oc login -u ai-admin -p redhat123"
echo "  oc login -u ai-developer -p redhat123"
echo ""
log_info "Check Kueue resources:"
echo "  oc get resourceflavors"
echo "  oc get clusterqueue rhoai-main-queue"
echo "  oc get localqueue -n private-ai"
echo ""
log_info "Monitor GPU utilization:"
echo "  OpenShift Console → Observe → Dashboards → NVIDIA DCGM Exporter Dashboard"
echo ""
log_info "RHOAI Dashboard:"
DASHBOARD_URL=$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')
echo "  https://${DASHBOARD_URL}"
echo ""
