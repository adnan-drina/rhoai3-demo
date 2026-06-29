#!/usr/bin/env bash
#
# Pre-deployment readiness check for the RHOAI demo.
# Run this before starting the deployment sequence.
#
# Exit codes:
#   0 = all checks pass
#   1 = blocking failures found
#   2 = warnings only (non-blocking)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BASELINE_FILE="$REPO_ROOT/docs/PLATFORM_BASELINE.md"
TARGET_OCP_VERSION="$(
  awk -F'|' '/Red Hat OpenShift Container Platform/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
    print $3
    exit
  }' "$BASELINE_FILE" 2>/dev/null || true
)"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

pass()  { ((PASS+=1)); echo -e "${GREEN}[PASS]${NC} $1"; }
warn()  { ((WARN+=1)); echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { ((FAIL+=1)); echo -e "${RED}[FAIL]${NC} $1"; }

echo "============================================="
echo " RHOAI Demo — Prerequisite Check"
echo "============================================="
echo ""

# Load local environment values before the first oc call. Use export semantics
# so child processes see KUBECONFIG and the expected-cluster guard variables.
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env" 2>/dev/null || true
  set +a
fi

# 1. oc login status
echo "--- Cluster Access ---"
if oc whoami &>/dev/null; then
  USER=$(oc whoami)
  CLUSTER=$(oc whoami --show-server 2>/dev/null || echo "unknown")
  pass "Logged in as $USER to $CLUSTER"
else
  fail "Not logged in (run: oc login ...)"
fi

# 2. Cluster version
if oc get clusterversion version -o jsonpath='{.status.desired.version}' &>/dev/null; then
  OCP_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}')
  if [[ -n "$TARGET_OCP_VERSION" && "$OCP_VERSION" == "$TARGET_OCP_VERSION"* ]]; then
    pass "OCP version: $OCP_VERSION"
  else
    warn "OCP version $OCP_VERSION — demo targets ${TARGET_OCP_VERSION:-the repo baseline}"
  fi
else
  warn "Could not determine cluster version"
fi

# 3. GPU nodes
echo ""
echo "--- GPU Infrastructure ---"
GPU_NODES=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$GPU_NODES" -ge 1 ]]; then
  pass "GPU nodes found: $GPU_NODES"
else
  warn "No GPU nodes found yet (Stage 120 creates the GPU MachineSet and installs GPU support)"
fi

# 4. Required CRDs
echo ""
echo "--- Required CRDs ---"
REQUIRED_CRDS=(
  "datascienceclusters.datasciencecluster.opendatahub.io"
  "inferenceservices.serving.kserve.io"
  "servingruntimes.serving.kserve.io"
)
for crd in "${REQUIRED_CRDS[@]}"; do
  if oc get crd "$crd" &>/dev/null; then
    pass "CRD: $crd"
  else
    warn "CRD missing: $crd (installed by the owning active stage)"
  fi
done

OPTIONAL_CRDS=(
  "modelregistries.modelregistry.opendatahub.io"
  "lmevaljobs.trustyai.opendatahub.io"
  "guardrailsorchestrators.guardrails.trustyai.opendatahub.io"
)
for crd in "${OPTIONAL_CRDS[@]}"; do
  if oc get crd "$crd" &>/dev/null; then
    pass "CRD: $crd"
  else
    warn "CRD missing: $crd (installed by a later step)"
  fi
done

# 5. ArgoCD / GitOps
echo ""
echo "--- ArgoCD / GitOps ---"
if oc get namespace openshift-gitops &>/dev/null; then
  pass "openshift-gitops namespace exists"
else
  warn "openshift-gitops namespace missing before Stage 110 bootstrap"
fi

if oc get appproject rhoai-demo -n openshift-gitops &>/dev/null; then
  pass "ArgoCD AppProject 'rhoai-demo' exists"
else
  warn "ArgoCD AppProject 'rhoai-demo' missing before Stage 110 bootstrap"
fi

TRACKING=$(oc get configmap argocd-cm -n openshift-gitops -o jsonpath='{.data.application\.resourceTrackingMethod}' 2>/dev/null || echo "")
if [[ "$TRACKING" == "annotation" ]]; then
  pass "ArgoCD resourceTrackingMethod = annotation"
else
  warn "ArgoCD resourceTrackingMethod is '$TRACKING' (expected 'annotation')"
fi

# 6. .env file
echo ""
echo "--- Environment ---"
if [[ -f "$REPO_ROOT/.env" ]]; then
  pass ".env file exists at $REPO_ROOT/.env"
  for var in KUBECONFIG RHOAI_EXPECTED_API_SERVER GIT_REPO_URL GIT_REPO_BRANCH; do
    if [[ -n "${!var:-}" ]]; then
      pass "  $var is set"
    else
      warn "  $var is not set in .env"
    fi
  done
else
  fail ".env file not found at $REPO_ROOT/.env"
fi

# Summary
echo ""
echo "============================================="
echo " Results: ${GREEN}$PASS pass${NC}, ${YELLOW}$WARN warn${NC}, ${RED}$FAIL fail${NC}"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}Blocking failures found. Fix before deploying.${NC}"
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo -e "${YELLOW}Warnings found. Review before deploying.${NC}"
  exit 2
else
  echo -e "${GREEN}All checks passed. Ready to deploy.${NC}"
  exit 0
fi
