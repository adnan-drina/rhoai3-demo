#!/usr/bin/env bash
# =============================================================================
# Step 03: Private AI - GPU as a Service
# =============================================================================
# Deploys GPU-as-a-Service infrastructure:
# - MinIO S3 storage provider
# - Authentication (HTPasswd, OAuth, Groups)
# - RHOAI Data Connection for MinIO
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

# Check GPU nodes
if ! oc get nodes -l nvidia.com/gpu.product --no-headers 2>/dev/null | grep -q Ready; then
    log_warn "No GPU nodes found — models will be pending until GPU MachineSets scale up"
fi

# Check GPU nodes exist
GPU_NODES=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$GPU_NODES" -eq 0 ]]; then
    log_warn "No GPU nodes found with label 'nvidia.com/gpu.present=true'"
    log_info "Workbenches will remain Pending until GPU nodes are available"
else
    log_success "Found $GPU_NODES GPU node(s)"
fi

log_success "Prerequisites verified"

# =============================================================================
# Deploy via Argo CD Application
# =============================================================================
log_step "Creating Argo CD Application for Private AI"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

# =============================================================================
# Wait for MinIO storage provider
# =============================================================================
log_step "Waiting for MinIO storage provider..."

# Wait for minio namespace
until oc get namespace minio-storage &>/dev/null; do
    log_info "Waiting for minio-storage namespace..."
    sleep 5
done

# Wait for MinIO deployment
log_info "Waiting for MinIO deployment to be ready..."
until oc get deployment minio -n minio-storage &>/dev/null && \
      [[ $(oc get deployment minio -n minio-storage -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0") -ge 1 ]]; do
    sleep 5
done
log_success "MinIO deployment ready"

# Apply MinIO Route manually (excluded from ArgoCD due to structured merge diff bug)
log_info "Applying MinIO Route (excluded from ArgoCD)..."
oc apply -f "$REPO_ROOT/gitops/step-03-private-ai/base/minio/route.yaml"
log_success "MinIO Route created"

# Wait for init job to complete (with timeout)
log_info "Waiting for MinIO initialization..."
TIMEOUT=120
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    JOB_STATUS=$(oc get job minio-init -n minio-storage -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$JOB_STATUS" == "1" ]]; then
        log_success "MinIO initialization complete"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log_warn "MinIO init job taking longer than expected - continuing anyway"
fi

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

# =============================================================================
# Create OpenShift Groups
# =============================================================================
# NOTE: Groups are created via script because ArgoCD cannot parse
# user.openshift.io/v1 Group schema for comparison
log_step "Creating OpenShift Groups..."

# Create rhoai-admins group
if ! oc get group rhoai-admins &>/dev/null; then
    oc adm groups new rhoai-admins ai-admin
    log_success "Created group 'rhoai-admins' with user 'ai-admin'"
else
    # Ensure ai-admin is in the group
    oc adm groups add-users rhoai-admins ai-admin 2>/dev/null || true
    log_success "Group 'rhoai-admins' already exists"
fi

# Create rhoai-users group
if ! oc get group rhoai-users &>/dev/null; then
    oc adm groups new rhoai-users ai-developer
    log_success "Created group 'rhoai-users' with user 'ai-developer'"
else
    # Ensure ai-developer is in the group
    oc adm groups add-users rhoai-users ai-developer 2>/dev/null || true
    log_success "Group 'rhoai-users' already exists"
fi

log_success "Groups configured"

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

# Wait for Data Connection
until oc get secret minio-connection -n private-ai &>/dev/null; do
    log_info "Waiting for MinIO Data Connection..."
    sleep 5
done
log_success "Data Connection 'minio-connection' created"

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

# Get URLs
GATEWAY_HOST=$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null || echo "loading...")
DASHBOARD_URL=$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')
MINIO_URL=$(oc get route minio-console -n minio-storage -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "GPU-as-a-Service Infrastructure Deployed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Demo Users:"
echo "  ┌──────────────┬─────────────┬────────────────────┐"
echo "  │ Username     │ Password    │ Role               │"
echo "  ├──────────────┼─────────────┼────────────────────┤"
echo "  │ ai-admin     │ redhat123   │ Service Governor   │"
echo "  │ ai-developer │ redhat123   │ Service Consumer   │"
echo "  └──────────────┴─────────────┴────────────────────┘"
echo ""
echo "S3 Storage (MinIO):"
echo "  • Console:      https://${MINIO_URL}"
echo "  • Credentials:  minio-admin / minio-secret-123"
echo "  • Buckets:      rhoai-storage, models, pipelines"
echo "  • Data Conn:    minio-connection (appears in Dashboard)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Validation Commands:"
echo ""
echo "  # Verify S3 Provider"
echo "  oc get pods -n minio-storage"
echo ""
echo "  # Verify RHOAI Data Connection"
echo "  oc get secret -n private-ai -l opendatahub.io/connection-type=s3"
echo ""
log_info "Test login:"
echo "  oc login -u ai-admin -p redhat123"
echo "  oc login -u ai-developer -p redhat123"
echo ""
log_info "RHOAI Dashboard:"
echo "  https://${DASHBOARD_URL}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Demo: GPU Queuing Demonstration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Apply demo workbenches (2 notebooks competing for 1 GPU):"
echo "  oc apply -k gitops/step-03-private-ai/gpu-as-a-service-demo/"
echo ""
log_info "Watch the queuing behavior:"
echo "  oc get pods -n private-ai -w"
echo ""
log_info "Access workbenches via Gateway API:"
echo "  https://${GATEWAY_HOST}/notebook/private-ai/demo-workbench-1/"
echo "  https://${GATEWAY_HOST}/notebook/private-ai/demo-workbench-2/"
echo ""
log_info "Monitor GPU utilization:"
echo "  OpenShift Console → Observe → Dashboards → NVIDIA DCGM Exporter Dashboard"
echo ""
log_info "Cleanup demo workbenches:"
echo "  oc delete -k gitops/step-03-private-ai/gpu-as-a-service-demo/"
echo ""
