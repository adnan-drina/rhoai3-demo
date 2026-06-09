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

OPENSHIFT_GITOPS_CHANNEL="${OPENSHIFT_GITOPS_CHANNEL:-gitops-1.20}"

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
  channel: ${OPENSHIFT_GITOPS_CHANNEL}
  installPlanApproval: Automatic
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
    && log_success "Resource tracking set to annotation (GitOps 1.20 default)" \
    || log_warn "Could not patch ArgoCD tracking method (may not be ready yet)"

# Operator-owned resources update status frequently and can emit high-volume
# Argo CD watch events during RHOAI and OLM reconciliation. Ignore status-only
# updates while still diffing and syncing desired specs.
oc patch argocd openshift-gitops -n openshift-gitops --type merge \
    -p '{"spec":{"extraConfig":{"resource.ignoreResourceUpdatesEnabled":"true","resource.customizations.ignoreResourceUpdates.datasciencecluster.opendatahub.io_DataScienceCluster":"jsonPointers:\n- /status\n","resource.customizations.ignoreResourceUpdates.dscinitialization.opendatahub.io_DSCInitialization":"jsonPointers:\n- /status\n","resource.customizations.ignoreResourceUpdates.operators.coreos.com_Subscription":"jsonPointers:\n- /status\n","resource.customizations.ignoreResourceUpdates.operators.coreos.com_OperatorGroup":"jsonPointers:\n- /status\n","resource.customizations.ignoreResourceUpdates.serving.kserve.io_InferenceService":"jsonPointers:\n- /status\n","resource.customizations.ignoreResourceUpdates.modelregistry.opendatahub.io_ModelRegistry":"jsonPointers:\n- /status\n","resource.customizations.ignoreResourceUpdates.llamastack.io_LlamaStackDistribution":"jsonPointers:\n- /status\n"},"resourceIgnoreDifferences":{"resourceIdentifiers":[{"group":"datasciencecluster.opendatahub.io","kind":"DataScienceCluster","customization":{"jsonPointers":["/status"]}},{"group":"dscinitialization.opendatahub.io","kind":"DSCInitialization","customization":{"jsonPointers":["/status"]}},{"group":"operators.coreos.com","kind":"Subscription","customization":{"jsonPointers":["/status"]}},{"group":"operators.coreos.com","kind":"OperatorGroup","customization":{"jsonPointers":["/status"]}},{"group":"serving.kserve.io","kind":"InferenceService","customization":{"jsonPointers":["/status"]}},{"group":"modelregistry.opendatahub.io","kind":"ModelRegistry","customization":{"jsonPointers":["/status"]}},{"group":"llamastack.io","kind":"LlamaStackDistribution","customization":{"jsonPointers":["/status"]}}]}}}' 2>/dev/null \
    && log_success "Ignored operator-owned status-only updates in Argo CD" \
    || log_warn "Could not configure operator status update ignores"

oc patch argocd openshift-gitops -n openshift-gitops --type merge \
    -p '{"spec":{"controller":{"resources":{"limits":{"cpu":"2","memory":"4Gi"},"requests":{"cpu":"500m","memory":"2Gi"}}}}}' 2>/dev/null \
    && log_success "Application controller resources sized for full demo resync" \
    || log_warn "Could not patch ArgoCD controller resources"

log_step "Configuring custom resource health checks"

# PVC: WaitForFirstConsumer PVCs stay Pending until a pod mounts them.
#   ArgoCD treats Pending as Progressing, blocking sync waves.
# ISVC: ArgoCD default health check misreads KServe condition format,
#   showing Ready ISVCs as "Progressing". Custom check reads Ready condition.
# TrustyAIService: ArgoCD has no built-in health check for this CRD.
#   Reports Available=True but ArgoCD shows Progressing without this check.
# Subscription: OLM can keep stale InstallPlanFailed conditions after
#   the CSV reaches the latest known version. Use state as the primary signal.
# Pod: Step 10 intentionally keeps one sample equipment pod in CrashLoopBackOff
#   for the MCP troubleshooting story. Annotated intentional failures should not
#   degrade the owning Argo CD application.
oc patch argocd openshift-gitops -n openshift-gitops --type merge -p '{
  "spec": {
    "resourceHealthChecks": [
      {
        "group": "",
        "kind": "Pod",
        "check": "hs = {}\nannotations = {}\nif obj.metadata ~= nil and obj.metadata.annotations ~= nil then\n  annotations = obj.metadata.annotations\nend\nif annotations[\"demo.rhoai.redhat.com/intentional-failure\"] == \"true\" then\n  hs.status = \"Healthy\"\n  hs.message = annotations[\"demo.rhoai.redhat.com/health-message\"] or \"Intentional demo failure\"\n  return hs\nend\nif obj.status == nil then\n  hs.status = \"Progressing\"\n  hs.message = \"Waiting for Pod status\"\n  return hs\nend\nif obj.metadata ~= nil and obj.metadata.deletionTimestamp ~= nil then\n  hs.status = \"Progressing\"\n  hs.message = \"Terminating\"\n  return hs\nend\nif obj.status.phase == \"Succeeded\" then\n  hs.status = \"Healthy\"\n  hs.message = \"Succeeded\"\n  return hs\nend\nif obj.status.phase == \"Failed\" then\n  hs.status = \"Degraded\"\n  hs.message = obj.status.reason or \"Failed\"\n  return hs\nend\nlocal statuses = {}\nif obj.status.initContainerStatuses ~= nil then\n  for _, s in ipairs(obj.status.initContainerStatuses) do table.insert(statuses, s) end\nend\nif obj.status.containerStatuses ~= nil then\n  for _, s in ipairs(obj.status.containerStatuses) do table.insert(statuses, s) end\nend\nfor _, s in ipairs(statuses) do\n  if s.state ~= nil and s.state.waiting ~= nil then\n    local reason = s.state.waiting.reason or \"Waiting\"\n    if reason == \"CrashLoopBackOff\" or reason == \"ImagePullBackOff\" or reason == \"ErrImagePull\" or reason == \"CreateContainerConfigError\" or reason == \"CreateContainerError\" then\n      hs.status = \"Degraded\"\n      hs.message = reason\n      return hs\n    end\n    hs.status = \"Progressing\"\n    hs.message = reason\n    return hs\n  end\nend\nif obj.status.phase == \"Running\" then\n  hs.status = \"Healthy\"\n  hs.message = \"Running\"\nelseif obj.status.phase == \"Pending\" then\n  hs.status = \"Progressing\"\n  hs.message = obj.status.reason or \"Pending\"\nelse\n  hs.status = \"Progressing\"\n  hs.message = obj.status.phase or \"Unknown\"\nend\nreturn hs"
      },
      {
        "group": "",
        "kind": "PersistentVolumeClaim",
        "check": "hs = {}\nif obj.status ~= nil and obj.status.phase ~= nil then\n  if obj.status.phase == \"Pending\" then\n    hs.status = \"Healthy\"\n    hs.message = \"Waiting for first consumer\"\n  elseif obj.status.phase == \"Bound\" then\n    hs.status = \"Healthy\"\n    hs.message = obj.status.phase\n  else\n    hs.status = \"Progressing\"\n    hs.message = obj.status.phase\n  end\nelse\n  hs.status = \"Progressing\"\n  hs.message = \"Waiting for PVC status\"\nend\nreturn hs"
      },
      {
        "group": "serving.kserve.io",
        "kind": "InferenceService",
        "check": "hs = {}\nif obj.status ~= nil and obj.status.conditions ~= nil then\n  for _, c in ipairs(obj.status.conditions) do\n    if c.type == \"Ready\" then\n      if c.status == \"True\" then\n        hs.status = \"Healthy\"\n        hs.message = \"Ready\"\n      elseif c.status == \"False\" then\n        hs.status = \"Degraded\"\n        hs.message = c.message or \"Not ready\"\n      else\n        hs.status = \"Progressing\"\n        hs.message = c.message or \"Waiting\"\n      end\n      return hs\n    end\n  end\nend\nhs.status = \"Progressing\"\nhs.message = \"Waiting for conditions\"\nreturn hs"
      },
      {
        "group": "trustyai.opendatahub.io",
        "kind": "TrustyAIService",
        "check": "hs = {}\nif obj.status ~= nil and obj.status.conditions ~= nil then\n  for _, c in ipairs(obj.status.conditions) do\n    if c.type == \"Available\" then\n      if c.status == \"True\" then\n        hs.status = \"Healthy\"\n        hs.message = c.reason or \"Available\"\n      elseif c.status == \"False\" then\n        hs.status = \"Degraded\"\n        hs.message = c.message or \"Not available\"\n      else\n        hs.status = \"Progressing\"\n        hs.message = c.message or \"Waiting\"\n      end\n      return hs\n    end\n  end\nend\nhs.status = \"Progressing\"\nhs.message = \"Waiting for conditions\"\nreturn hs"
      },
      {
        "group": "operators.coreos.com",
        "kind": "Subscription",
        "check": "hs = {}\nif obj.status ~= nil then\n  if obj.status.state == \"AtLatestKnown\" then\n    hs.status = \"Healthy\"\n    hs.message = obj.status.installedCSV or \"AtLatestKnown\"\n    return hs\n  end\n  if obj.status.conditions ~= nil then\n    for _, c in ipairs(obj.status.conditions) do\n      if c.type == \"InstallPlanFailed\" and c.status == \"True\" then\n        hs.status = \"Degraded\"\n        hs.message = c.message or \"InstallPlanFailed\"\n        return hs\n      end\n      if c.type == \"InstallPlanPending\" and c.status == \"True\" then\n        hs.status = \"Progressing\"\n        hs.message = c.reason or \"InstallPlanPending\"\n        return hs\n      end\n    end\n  end\n  if obj.status.state ~= nil then\n    hs.status = \"Progressing\"\n    hs.message = obj.status.state\n    return hs\n  end\nend\nhs.status = \"Progressing\"\nhs.message = \"Waiting for Subscription status\"\nreturn hs"
      }
    ]
  }
}' 2>/dev/null \
    && log_success "Pod + PVC + InferenceService + TrustyAIService + Subscription health checks configured" \
    || log_warn "Could not configure health checks"

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
