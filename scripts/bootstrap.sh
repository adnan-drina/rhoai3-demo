#!/usr/bin/env bash
# Bootstrap OpenShift GitOps for RHOAI demo
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

load_env
check_oc_logged_in

# Auto-detect repo URL from git remote (supports forks)
GIT_REPO_URL=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "https://github.com/adnan-drina/rhoai3-demo.git")
# Convert SSH URLs (git@github.com:user/repo.git) to HTTPS for ArgoCD
if [[ "$GIT_REPO_URL" == git@* ]]; then
    GIT_REPO_URL=$(echo "$GIT_REPO_URL" | sed 's|git@github.com:|https://github.com/|')
fi
GIT_REPO_URL="${GIT_REPO_URL%.git}.git"
log_info "Repository: $GIT_REPO_URL"

# Update all ArgoCD Applications to use the detected repo URL
if [[ "$GIT_REPO_URL" != "https://github.com/adnan-drina/rhoai3-demo.git" ]]; then
    log_step "Updating ArgoCD Applications for fork: $GIT_REPO_URL"
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s|https://github.com/adnan-drina/rhoai3-demo.git|${GIT_REPO_URL}|g" \
            "$REPO_ROOT"/gitops/argocd/app-of-apps/step-*.yaml
    else
        sed -i "s|https://github.com/adnan-drina/rhoai3-demo.git|${GIT_REPO_URL}|g" \
            "$REPO_ROOT"/gitops/argocd/app-of-apps/step-*.yaml
    fi
    log_success "Updated $(ls "$REPO_ROOT"/gitops/argocd/app-of-apps/step-*.yaml | wc -l | tr -d ' ') Application files"
fi

log_step "Installing OpenShift GitOps operator"

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: gitops-1.15
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

log_info "Waiting for GitOps operator..."
sleep 30
until oc get namespace openshift-gitops &>/dev/null; do sleep 5; done

log_step "Configuring Argo CD RBAC"

cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-gitops-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: openshift-gitops-argocd-application-controller
  namespace: openshift-gitops
EOF

log_step "Configuring resource tracking method"

until oc get argocd openshift-gitops -n openshift-gitops &>/dev/null; do sleep 5; done
oc patch argocd openshift-gitops -n openshift-gitops --type merge \
    -p '{"spec":{"resourceTrackingMethod":"annotation"}}' 2>/dev/null \
    && log_success "Resource tracking set to annotation (GitOps 1.19 default)" \
    || log_warn "Could not patch ArgoCD tracking method (may not be ready yet)"

log_step "Configuring PVC health check (WaitForFirstConsumer = Healthy)"

# WaitForFirstConsumer PVCs stay Pending until a pod mounts them.
# ArgoCD treats Pending as Progressing, which blocks sync waves.
# Override: treat Pending PVCs as Healthy so sync waves proceed.
oc patch argocd openshift-gitops -n openshift-gitops --type merge -p '{
  "spec": {
    "resourceHealthChecks": [
      {
        "group": "",
        "kind": "PersistentVolumeClaim",
        "check": "hs = {}\nif obj.status ~= nil and obj.status.phase ~= nil then\n  if obj.status.phase == \"Pending\" then\n    hs.status = \"Healthy\"\n    hs.message = \"Waiting for first consumer\"\n  elseif obj.status.phase == \"Bound\" then\n    hs.status = \"Healthy\"\n    hs.message = obj.status.phase\n  else\n    hs.status = \"Progressing\"\n    hs.message = obj.status.phase\n  end\nelse\n  hs.status = \"Progressing\"\n  hs.message = \"Waiting for PVC status\"\nend\nreturn hs"
      }
    ]
  }
}' 2>/dev/null \
    && log_success "PVC health check configured (Pending = Healthy)" \
    || log_warn "Could not configure PVC health check"

log_step "Creating Argo CD project"

cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: rhoai-demo
  namespace: openshift-gitops
spec:
  destinations:
  - namespace: '*'
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
  sourceRepos:
  - '*'
EOF

log_success "Bootstrap complete"
log_info "Argo CD: $(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo 'loading...')"
