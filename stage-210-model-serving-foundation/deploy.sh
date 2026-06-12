#!/usr/bin/env bash
# deploy.sh - Stage 210: Model Serving Foundation
# Reconciles the shared Stage 110 RHOAI owner after the Stage 210 KServe patch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

if [[ -z "${RHOAI_EXPECTED_API_SERVER:-}" ]]; then
  echo "ERROR: RHOAI_EXPECTED_API_SERVER is not set." >&2
  exit 1
fi

ACTUAL_SERVER=$(oc whoami --show-server 2>/dev/null || true)
if [[ "$ACTUAL_SERVER" != *"$RHOAI_EXPECTED_API_SERVER"* ]]; then
  echo "ERROR: Active cluster ($ACTUAL_SERVER) does not match RHOAI_EXPECTED_API_SERVER." >&2
  exit 1
fi

echo "✓ Cluster guard passed: $ACTUAL_SERVER"

GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/adnan-drina/rhoai3-demo.git}"
GIT_REPO_BRANCH="${GIT_REPO_BRANCH:-main}"

APP_MANIFEST=$(mktemp)
trap 'rm -f "$APP_MANIFEST"' EXIT

sed \
  -e "s|repoURL: .*|repoURL: ${GIT_REPO_URL}|" \
  -e "s|targetRevision: .*|targetRevision: ${GIT_REPO_BRANCH}|" \
  "$ROOT_DIR/gitops/argocd/app-of-apps/stage-110-rhoai-base-platform.yaml" \
  > "$APP_MANIFEST"

echo "── Applying shared Stage 110 Argo CD Application ──"
oc apply -f "$APP_MANIFEST" --insecure-skip-tls-verify=true

echo "── Requesting Argo CD refresh for shared RHOAI owner ──"
oc annotate application stage-110-rhoai-base-platform -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite \
  --insecure-skip-tls-verify=true >/dev/null

echo "✓ Application stage-110-rhoai-base-platform applied"
echo "  Argo CD will reconcile the Stage 210 KServe patch through the shared DSC owner."
echo "  Run ./stage-210-model-serving-foundation/validate.sh to confirm readiness."
