#!/usr/bin/env bash
# Step 03: Private AI — GPU as a Service — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 03: Private AI — GPU as a Service — Validation           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Argo CD Application ---
log_step "Argo CD Application"
# Step-03 manages resources that may show OutOfSync due to operator-managed
# secrets and manually-applied Kueue resources. Check health primarily.
SYNC=$(oc get application step-03-private-ai -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NOT_FOUND")
HEALTH=$(oc get application step-03-private-ai -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "NOT_FOUND")
if [[ "$SYNC" == "Synced" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app sync: Synced"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} Argo CD app sync: $SYNC (operator-managed resources may cause drift)"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi
if [[ "$HEALTH" == "Healthy" || "$HEALTH" == "Progressing" ]]; then
    echo -e "${GREEN}[PASS]${NC} Argo CD app health: $HEALTH"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Argo CD app health: $HEALTH"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- MinIO ---
log_step "MinIO Storage"
check "MinIO deployment ready" \
    "oc get deploy minio -n minio-storage -o jsonpath='{.status.readyReplicas}'" \
    "1"

check "MinIO init job completed" \
    "oc get job minio-init -n minio-storage -o jsonpath='{.status.succeeded}'" \
    "1"

# --- Data Connection ---
log_step "Data Connection"
check "minio-connection secret exists" \
    "oc get secret minio-connection -n private-ai -o jsonpath='{.metadata.name}'" \
    "minio-connection"

check "storage-config secret exists" \
    "oc get secret storage-config -n private-ai -o jsonpath='{.metadata.name}'" \
    "storage-config"

# --- Authentication ---
log_step "Authentication"
# Identity provider may be named htpasswd or local-users depending on the OAuth config
IDP_NAMES=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}' 2>/dev/null || echo "")
if [[ -n "$IDP_NAMES" ]]; then
    echo -e "${GREEN}[PASS]${NC} OAuth identity provider configured: $IDP_NAMES"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} No OAuth identity providers configured"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

check "Group rhoai-admins exists" \
    "oc get group rhoai-admins -o jsonpath='{.metadata.name}'" \
    "rhoai-admins"

check "Group rhoai-users exists" \
    "oc get group rhoai-users -o jsonpath='{.metadata.name}'" \
    "rhoai-users"

# --- Kueue ---
log_step "Kueue Configuration"
check "ClusterQueue rhoai-main-queue exists" \
    "oc get clusterqueue rhoai-main-queue -o jsonpath='{.metadata.name}'" \
    "rhoai-main-queue"

check "ClusterQueue rhoai-llmd-queue exists" \
    "oc get clusterqueue rhoai-llmd-queue -o jsonpath='{.metadata.name}'" \
    "rhoai-llmd-queue"

check "LocalQueue default exists in private-ai" \
    "oc get localqueue default -n private-ai -o jsonpath='{.spec.clusterQueue}'" \
    "rhoai-main-queue"

check "LocalQueue llmd exists in private-ai" \
    "oc get localqueue llmd -n private-ai -o jsonpath='{.spec.clusterQueue}'" \
    "rhoai-llmd-queue"

check "ResourceFlavor nvidia-l4-1gpu exists" \
    "oc get resourceflavor nvidia-l4-1gpu -o jsonpath='{.metadata.name}'" \
    "nvidia-l4-1gpu"

check "ResourceFlavor nvidia-l4-4gpu exists" \
    "oc get resourceflavor nvidia-l4-4gpu -o jsonpath='{.metadata.name}'" \
    "nvidia-l4-4gpu"

# --- RBAC ---
log_step "RBAC"
check "RoleBinding ai-admin-admin exists" \
    "oc get rolebinding ai-admin-admin -n private-ai -o jsonpath='{.metadata.name}'" \
    "ai-admin-admin"

check "RoleBinding ai-developer-edit exists" \
    "oc get rolebinding ai-developer-edit -n private-ai -o jsonpath='{.metadata.name}'" \
    "ai-developer-edit"

# --- Namespace ---
log_step "Namespace"
check "private-ai namespace exists" \
    "oc get namespace private-ai -o jsonpath='{.metadata.name}'" \
    "private-ai"

check "minio-storage namespace exists" \
    "oc get namespace minio-storage -o jsonpath='{.metadata.name}'" \
    "minio-storage"

# --- Summary ---
echo ""
validation_summary
