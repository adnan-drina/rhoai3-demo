#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

STEP_NAME="step-02-rhoai"
GITOPS_PATH="gitops/step-02-rhoai"

load_env
check_oc_logged_in

log_step "Deploying $STEP_NAME"

# Apply Argo CD Application
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $STEP_NAME
  namespace: openshift-gitops
spec:
  project: rhoai-demo
  source:
    repoURL: ${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}
    targetRevision: ${GIT_REPO_BRANCH:-main}
    path: $GITOPS_PATH
  destination:
    server: https://kubernetes.default.svc
    namespace: redhat-ods-operator
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

log_success "Application $STEP_NAME deployed"
