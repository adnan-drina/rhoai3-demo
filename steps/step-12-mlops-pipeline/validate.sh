#!/usr/bin/env bash
# Step 12: MLOps Training Pipeline — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="private-ai"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 12: MLOps Training Pipeline — Validation                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- ArgoCD Application ---
log_step "ArgoCD Application"
check_argocd_app "step-12-mlops-pipeline"

# --- Pipeline PVC ---
log_step "Pipeline PVC"
check "face-pipeline-workspace PVC exists" \
    "oc get pvc face-pipeline-workspace -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "face-pipeline-workspace"

# --- DSPA ---
log_step "Pipeline Server (DSPA)"
check "dspa-rag exists" \
    "oc get dspa dspa-rag -n $NAMESPACE -o jsonpath='{.metadata.name}'" \
    "dspa-rag"

check_warn "DSPA route available" \
    "oc get route ds-pipeline-dspa-rag -n $NAMESPACE -o jsonpath='{.spec.host}'" \
    "apps."

# --- Summary ---
echo ""
validation_summary
