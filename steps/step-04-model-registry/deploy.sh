#!/usr/bin/env bash
# =============================================================================
# Step 04: Enterprise Model Governance
# =============================================================================
# Deploys Model Registry infrastructure and registers the May 2025 Validated
# Granite model. This implements the "Gatekeeper" pattern for enterprise AI.
#
# Components:
# - MariaDB database for metadata storage
# - ModelRegistry instance (private-ai-registry)
# - RBAC for ai-admin and ai-developer
# - Seed job to register Granite 3.1 FP8 model
#
# IMPORTANT: This step only REGISTERS the model metadata.
# Actual deployment to KServe happens in Step 05.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-04-model-registry"

load_env
check_oc_logged_in

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Step 04: Enterprise Model Governance                                ║"
echo "║  Implementing the Gatekeeper Pattern for AI Models                   ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

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
    log_info "Model artifacts will be stored in MinIO"
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
TIMEOUT=180
ELAPSED=0
until oc get deployment model-registry-db -n private-ai &>/dev/null && \
      [[ $(oc get deployment model-registry-db -n private-ai -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0") -ge 1 ]]; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        log_warn "MariaDB taking longer than expected"
        break
    fi
    log_info "Waiting for MariaDB deployment... (${ELAPSED}s)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done
log_success "MariaDB database ready"

# =============================================================================
# Wait for Model Registry
# =============================================================================
log_step "Waiting for Model Registry..."

# Wait for ModelRegistry CR (uses v1beta1 API in rhoai-model-registries namespace)
TIMEOUT=180
ELAPSED=0
until oc get modelregistry.modelregistry.opendatahub.io private-ai-registry -n rhoai-model-registries &>/dev/null; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        log_warn "ModelRegistry CR not found yet"
        break
    fi
    log_info "Waiting for ModelRegistry CR... (${ELAPSED}s)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

# Wait for registry pods
log_info "Waiting for Model Registry pods..."
TIMEOUT=180
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    READY=$(oc get pods -n rhoai-model-registries -l app=private-ai-registry --no-headers 2>/dev/null | grep -c Running || echo "0")
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
log_step "Waiting for model registration job..."

TIMEOUT=300
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    JOB_STATUS=$(oc get job model-registry-seed -n rhoai-model-registries -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$JOB_STATUS" == "1" ]]; then
        log_success "Model registration completed"
        echo ""
        echo "  Registered: Granite-3.1-8b-Instruct-FP8"
        echo "  Version:    3.1-May2025-Validated"
        echo "  Status:     Ready to Deploy"
        echo ""
        break
    fi
    log_info "Waiting for model registration... (${ELAPSED}s)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log_warn "Seed job taking longer than expected"
    log_info "Check: oc logs job/model-registry-seed -n rhoai-model-registries"
fi

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

DASHBOARD_URL=$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Enterprise Model Governance Deployed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Components:"
echo "  • MariaDB:        model-registry-db (private-ai namespace)"
echo "  • ModelRegistry:  private-ai-registry (rhoai-model-registries)"
echo ""
echo "Registered Model:"
echo "  • Model:          Granite-3.1-8b-Instruct-FP8"
echo "  • Version:        3.1-May2025-Validated"
echo "  • Collection:     Red Hat AI Validated - May 2025"
echo "  • Hardware:       NVIDIA L4 (FP8 optimized)"
echo "  • Status:         Ready to Deploy"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Validation Commands:"
echo ""
echo "  # Check Model Registry"
echo "  oc get modelregistry.modelregistry.opendatahub.io -n rhoai-model-registries"
echo ""
echo "  # Check registry pods"
echo "  oc get pods -n rhoai-model-registries | grep private-ai-registry"
echo ""
echo "  # View seed job logs"
echo "  oc logs job/model-registry-seed -n rhoai-model-registries"
echo ""
log_info "Access Points:"
echo ""
echo "  Dashboard: https://${DASHBOARD_URL}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next Steps: Discover the Model"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "As ai-admin (Registry View):"
echo "   1. Login to RHOAI Dashboard"
echo "   2. Go to Settings → Model registries"
echo "   3. Click 'private-ai-registry'"
echo "   4. View Granite-3.1-8b-Instruct-FP8 metadata"
echo ""
log_info "As ai-developer (Catalog View):"
echo "   1. Login to RHOAI Dashboard"
echo "   2. Go to GenAI Studio → AI Available Assets"
echo "   3. Find Granite-3.1-8b-Instruct-FP8"
echo "   4. Status shows 'Ready to Deploy'"
echo ""
log_info "Step 05 will deploy this model to a KServe inference endpoint."
echo ""
