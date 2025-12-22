#!/usr/bin/env bash
# =============================================================================
# Step 02: Red Hat OpenShift AI 3.0 - Deploy Script
# =============================================================================
# Deploys:
# - RHOAI Operator (fast-3.x channel)
# - DSCInitialization
# - DataScienceCluster with 3.0 components
# - GenAI Studio (Playground) configuration
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-02-rhoai"

load_env
check_oc_logged_in

log_step "Step 02: Red Hat OpenShift AI 3.0"

# =============================================================================
# Prerequisites check
# =============================================================================
log_step "Checking prerequisites..."

# Check step-01-gpu was deployed
if ! oc get applications -n openshift-gitops step-01-gpu &>/dev/null; then
    log_error "step-01-gpu Argo CD Application not found!"
    log_info "Please run: ./steps/step-01-gpu/deploy.sh first"
    exit 1
fi

# Check Serverless is ready
if ! oc get knativeserving -n knative-serving knative-serving &>/dev/null; then
    log_error "KnativeServing not found - required for KServe"
    log_info "Please ensure step-01-gpu is fully synced"
    exit 1
fi

log_success "Prerequisites verified"

# =============================================================================
# Deploy via Argo CD Application
# =============================================================================
log_step "Creating Argo CD Application for RHOAI"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

# =============================================================================
# Wait for operator
# =============================================================================
log_step "Waiting for RHOAI Operator..."

# Wait for namespace
until oc get namespace redhat-ods-operator &>/dev/null; do
    log_info "Waiting for namespace redhat-ods-operator..."
    sleep 10
done

# Wait for CSV to succeed
log_info "Waiting for RHOAI Operator CSV..."
until oc get csv -n redhat-ods-operator -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift AI")].status.phase}' 2>/dev/null | grep -q "Succeeded"; do
    sleep 15
done
log_success "RHOAI Operator installed"

# Wait for RHOAI 3.0 CRDs
log_info "Waiting for DSCInitialization CRD..."
until oc get crd dscinitializations.dscinitialization.opendatahub.io &>/dev/null; do
    sleep 5
done
log_success "DSCInitialization CRD available"

log_info "Waiting for DataScienceCluster CRD..."
until oc get crd datascienceclusters.datasciencecluster.opendatahub.io &>/dev/null; do
    sleep 5
done
log_success "DataScienceCluster CRD available"

# Wait for DSC to be ready
log_info "Waiting for DataScienceCluster to initialize..."
until oc get datasciencecluster default-dsc &>/dev/null; do
    sleep 10
done
log_success "DataScienceCluster created"

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
echo "RHOAI 3.0 Components:"
echo "  - RHOAI Operator (fast-3.x channel)"
echo "  - DSCInitialization (default-dsci)"
echo "  - DataScienceCluster (default-dsc)"
echo "  - GenAI Studio enabled"
echo ""
echo "Managed Components:"
echo "  - Dashboard"
echo "  - Workbenches"
echo "  - KServe"
echo "  - LlamaStackOperator"
echo "  - ModelRegistry"
echo "  - TrainingOperator"
echo ""
log_info "Check Argo CD Application status:"
echo "  oc get applications -n openshift-gitops ${STEP_NAME}"
echo ""
log_info "Check RHOAI status:"
echo "  oc get datasciencecluster default-dsc"
echo "  oc get dscinitializations default-dsci"
echo "  oc get pods -n redhat-ods-applications"
echo ""
log_info "Access Dashboard:"
DASHBOARD_URL=$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')
echo "  https://${DASHBOARD_URL}"
