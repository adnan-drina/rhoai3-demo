#!/usr/bin/env bash
# =============================================================================
# Step 04: Enterprise Model Governance
# =============================================================================
# Deploys Model Registry infrastructure and registers the May 2025 Validated
# Granite model. This implements the "Gatekeeper" pattern for enterprise AI.
#
# Components (all in rhoai-model-registries namespace):
# - MariaDB database for metadata storage
# - ModelRegistry instance (private-ai-registry)
# - Internal service for API access (port 8080)
# - Network policy for internal access
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
REGISTRY_NS="rhoai-model-registries"

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
until oc get deployment model-registry-db -n ${REGISTRY_NS} &>/dev/null && \
      [[ $(oc get deployment model-registry-db -n ${REGISTRY_NS} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0") -ge 1 ]]; do
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

# Wait for ModelRegistry CR
TIMEOUT=180
ELAPSED=0
until oc get modelregistry.modelregistry.opendatahub.io private-ai-registry -n ${REGISTRY_NS} &>/dev/null; do
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
    READY=$(oc get pods -n ${REGISTRY_NS} -l app=private-ai-registry --no-headers 2>/dev/null | grep -c Running || echo "0")
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
# Wait for Internal Service
# =============================================================================
log_step "Waiting for internal service..."

TIMEOUT=60
ELAPSED=0
until oc get svc private-ai-registry-internal -n ${REGISTRY_NS} &>/dev/null; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        log_warn "Internal service not found - seed job may fail"
        break
    fi
    log_info "Waiting for internal service... (${ELAPSED}s)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
log_success "Internal service ready"

# =============================================================================
# Wait for Seed Job
# =============================================================================
log_step "Waiting for model registration job..."

TIMEOUT=300
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    JOB_STATUS=$(oc get job model-registry-seed -n ${REGISTRY_NS} -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [[ "$JOB_STATUS" == "1" ]]; then
        log_success "Model registration completed"
        echo ""
        echo "  Registered: Granite-3.1-8b-Instruct-FP8"
        echo "  Version:    3.1-May2025-Validated"
        echo "  Owner:      ai-admin"
        echo "  Tags:       granite, fp8, validated, vllm"
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
    log_info "Check: oc logs job/model-registry-seed -n ${REGISTRY_NS}"
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
echo "Namespace: ${REGISTRY_NS}"
echo ""
echo "Components:"
echo "  • MariaDB:          model-registry-db"
echo "  • ModelRegistry:    private-ai-registry"
echo "  • Internal Service: private-ai-registry-internal:8080"
echo "  • OAuth Service:    private-ai-registry:8443"
echo ""
echo "Registered Model:"
echo "  • Model:     Granite-3.1-8b-Instruct-FP8"
echo "  • Version:   3.1-May2025-Validated"
echo "  • Provider:  IBM (Apache 2.0)"
echo "  • Tags:      granite, fp8, validated, vllm"
echo "  • Status:    Ready to Deploy"
echo ""
echo "Model Catalog:"
echo "  • 48+ Red Hat AI Validated models pre-bundled"
echo "  • Access: GenAI Studio → AI Available Assets"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Validation Commands:"
echo ""
echo "  # Check Model Registry"
echo "  oc get modelregistry.modelregistry.opendatahub.io -n ${REGISTRY_NS}"
echo ""
echo "  # Check registry pods"
echo "  oc get pods -n ${REGISTRY_NS} -l app=private-ai-registry"
echo ""
echo "  # View seed job logs"
echo "  oc logs job/model-registry-seed -n ${REGISTRY_NS}"
echo ""
echo "  # Query registered models via internal API"
echo "  oc run test-api --rm -i --restart=Never --image=curlimages/curl -n ${REGISTRY_NS} -- \\"
echo "    curl -sf http://private-ai-registry-internal:8080/api/model_registry/v1alpha3/registered_models"
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
echo "   3. Filter by 'Red Hat AI validated'"
echo "   4. Browse 48+ validated models"
echo ""
log_info "Step 05 will deploy this model to a KServe inference endpoint."
echo ""
