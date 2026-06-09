#!/usr/bin/env bash
# Step 03: Enterprise projects and storage foundation validation script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 03: Enterprise Projects and Storage — Validation         ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Argo CD Application ---
log_step "Argo CD Application"
# Step-03 manages resources that may show OutOfSync due to operator-managed
# secrets and manually-applied resources. Check health primarily.
SYNC=$(oc get applications.argoproj.io step-03-enterprise-projects -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NOT_FOUND")
HEALTH=$(oc get applications.argoproj.io step-03-enterprise-projects -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "NOT_FOUND")
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

MINIO_INIT_SUCCEEDED=$(oc get job minio-init -n minio-storage -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "")
if [[ "$MINIO_INIT_SUCCEEDED" == "1" ]]; then
    echo -e "${GREEN}[PASS]${NC} MinIO init job completed"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
elif [[ -z "$MINIO_INIT_SUCCEEDED" ]]; then
    echo -e "${GREEN}[PASS]${NC} MinIO init job already cleaned up by TTL after bootstrap"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${YELLOW}[WARN]${NC} MinIO init job status not confirmed: $MINIO_INIT_SUCCEEDED"
    VALIDATE_WARN=$((VALIDATE_WARN + 1))
fi

# --- Data Connections ---
log_step "Data Connections"
for ns in maas enterprise-rag enterprise-mlops; do
    check "minio-connection secret exists in $ns" \
        "oc get secret minio-connection -n $ns -o jsonpath='{.metadata.name}'" \
        "minio-connection"

    check "storage-config secret exists in $ns" \
        "oc get secret storage-config -n $ns -o jsonpath='{.metadata.name}'" \
        "storage-config"
done

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

# --- RBAC ---
log_step "RBAC"
for ns in maas enterprise-rag enterprise-mlops; do
    check "RoleBinding ai-admin-admin exists in $ns" \
        "oc get rolebinding ai-admin-admin -n $ns -o jsonpath='{.metadata.name}'" \
        "ai-admin-admin"

    check "RoleBinding ai-developer-edit exists in $ns" \
        "oc get rolebinding ai-developer-edit -n $ns -o jsonpath='{.metadata.name}'" \
        "ai-developer-edit"
done

# --- Namespaces ---
log_step "Namespaces"
for ns in maas enterprise-rag enterprise-mlops; do
    check "$ns namespace exists" \
        "oc get namespace $ns -o jsonpath='{.metadata.name}'" \
        "$ns"
done

check "maas project display name avoids MaaS system namespace collision" \
    "oc get namespace maas -o jsonpath='{.metadata.annotations.openshift\\.io/display-name}'" \
    "MaaS Runtime"

check "enterprise-rag namespace is an EvalHub tenant" \
    "oc get namespace enterprise-rag -o json | python3 -c 'import json,sys; labels=json.load(sys.stdin).get(\"metadata\",{}).get(\"labels\",{}); print(\"present\" if \"evalhub.trustyai.opendatahub.io/tenant\" in labels else \"missing\")'" \
    "present"

check "minio-storage namespace exists" \
    "oc get namespace minio-storage -o jsonpath='{.metadata.name}'" \
    "minio-storage"

# --- MLflow Workspace ---
log_step "MLflow Workspaces"
for ns in enterprise-rag enterprise-mlops; do
    check "$ns namespace is selectable by MLflow workspace selector" \
        "oc get namespace $ns -o jsonpath='{.metadata.labels.kubernetes\\.io/metadata\\.name}'" \
        "$ns"
done

# --- Kueue ---
log_step "Kueue"
check "maas namespace is Kueue-managed" \
    "oc get namespace maas -o jsonpath='{.metadata.labels.kueue\\.openshift\\.io/managed}'" \
    "true"

check_warn "maas LocalQueue exists" \
    "oc get localqueue maas-default -n maas -o jsonpath='{.metadata.name}'" \
    "maas-default"

# --- Summary ---
echo ""
validation_summary
