#!/usr/bin/env bash
# =============================================================================
# Step 02: Red Hat OpenShift AI - Deploy Script
# =============================================================================
# Deploys:
# - RHOAI Operator
# - DataScienceCluster with core components
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-02-rhoai"

load_env
check_oc_logged_in

log_step "Step 02: Red Hat OpenShift AI"

# Get Git repo info
GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"

log_info "Git Repo: $GIT_REPO_URL"
log_info "Branch: $GIT_REPO_BRANCH"

# =============================================================================
# Deploy via Argo CD
# =============================================================================
log_step "Creating Argo CD Application for RHOAI"

cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${STEP_NAME}
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${GIT_REPO_URL}
    targetRevision: ${GIT_REPO_BRANCH}
    path: gitops/step-02-rhoai/base
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

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

# =============================================================================
# Summary
# =============================================================================
log_step "Deployment Complete"

echo ""
echo "Components:"
echo "  - RHOAI Operator (redhat-ods-operator)"
echo "  - DataScienceCluster (default-dsc)"
echo ""
log_info "Check status:"
echo "  oc get datasciencecluster default-dsc"
echo "  oc get pods -n redhat-ods-applications"
echo ""
log_info "Access Dashboard:"
echo "  oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}'"
