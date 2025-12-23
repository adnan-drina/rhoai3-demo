#!/usr/bin/env bash
# =============================================================================
# Step 04: Model Registry & Governance
# =============================================================================
# Deploys Model Registry infrastructure:
# - MariaDB database for metadata storage
# - ModelRegistry CR instance
# - RBAC for ai-admin and ai-developer
# - Seed job to register demo model
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-04-model-registry"

load_env
check_oc_logged_in

log_step "Step 04: Model Registry & Governance"

# =============================================================================
# Prerequisites check
# =============================================================================
log_step "Checking prerequisites..."

# Check step-03-private-ai was deployed
if ! oc get applications -n openshift-gitops step-03-private-ai &>/dev/null; then
    log_error "step-03-private-ai Argo CD Application not found!"
    log_info "Please run: ./steps/step-03-private-ai/deploy.sh first"
    exit 1
fi

# Check MinIO is available
if ! oc get pods -n minio-storage -l app=minio --no-headers 2>/dev/null | grep -q Running; then
    log_warn "MinIO not running in minio-storage namespace"
    log_info "Model Registry requires S3 storage for artifacts"
fi

# Check Model Registry component is enabled in DSC
if ! oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.modelregistry.managementState}' 2>/dev/null | grep -qi "Managed"; then
    log_warn "ModelRegistry component may not be enabled in DataScienceCluster"
    log_info "Check: oc get datasciencecluster default-dsc -o yaml | grep modelregistry"
fi

log_success "Prerequisites verified"

# =============================================================================
# Deploy via Argo CD Application
# =============================================================================
log_step "Creating Argo CD Application for Model Registry"

oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/${STEP_NAME}.yaml"

log_success "Argo CD Application '${STEP_NAME}' created"

# =============================================================================
# Wait for Database
# =============================================================================
log_step "Waiting for MariaDB database..."

# Wait for deployment
until oc get deployment model-registry-db -n private-ai &>/dev/null && \
      [[ $(oc get deployment model-registry-db -n private-ai -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0") -ge 1 ]]; do
    log_info "Waiting for MariaDB deployment..."
    sleep 10
done
log_success "MariaDB database ready"

# =============================================================================
# Wait for Model Registry
# =============================================================================
log_step "Waiting for Model Registry..."

# Wait for ModelRegistry CR
until oc get modelregistry private-ai-registry -n redhat-ods-applications &>/dev/null; do
    log_info "Waiting for ModelRegistry CR..."
    sleep 10
done

# Wait for registry pods
log_info "Waiting for Model Registry pods..."
TIMEOUT=180
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    READY=$(oc get pods -n redhat-ods-applications -l app=private-ai-registry --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [[ "$READY" -ge 1 ]]; then
        log_success "Model Registry pods ready"
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log_warn "Model Registry pods not ready yet - continuing anyway"
fi

# =============================================================================
# Wait for Seed Job
# =============================================================================
log_step "Waiting for seed job to complete..."

TIMEOUT=120
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    JOB_STATUS=$(oc get job model-registry-seed -n redhat-ods-applications -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$JOB_STATUS" == "1" ]]; then
        log_success "Seed job completed - demo model registered"
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log_warn "Seed job taking longer than expected"
    log_info "Check: oc logs job/model-registry-seed -n redhat-ods-applications"
fi

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

DASHBOARD_URL=$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')
REGISTRY_URL=$(oc get route private-ai-registry-rest -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Model Registry & Governance Deployed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Components:"
echo "  • MariaDB:        model-registry-db (private-ai namespace)"
echo "  • ModelRegistry:  private-ai-registry (redhat-ods-applications)"
echo "  • Demo Model:     Granite-7b-Inference v1.0"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Validation Commands:"
echo ""
echo "  # Check Model Registry"
echo "  oc get modelregistry -n redhat-ods-applications"
echo ""
echo "  # Check registry pods"
echo "  oc get pods -n redhat-ods-applications | grep model-registry"
echo ""
echo "  # Check REST API"
echo "  curl -sf https://${REGISTRY_URL}/api/model_registry/v1alpha3/registered_models | jq ."
echo ""
log_info "Access Points:"
echo ""
echo "  Dashboard:      https://${DASHBOARD_URL}"
echo "  Registry API:   https://${REGISTRY_URL}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Demo: Model Catalog"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "1. Login as ai-developer to RHOAI Dashboard"
log_info "2. Go to GenAI Studio → AI Available Assets"
log_info "3. Find 'Granite-7b-Inference' model"
log_info "4. Click Deploy → Select Hardware Profile → Deploy"
echo ""
log_info "Registry Admin (ai-admin):"
echo "   Settings → Model registries → private-ai-registry"
echo ""
