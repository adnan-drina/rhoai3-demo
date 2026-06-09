#!/bin/bash
# =============================================================================
# Sync notebook files and assets (images, videos, training photos) to the
# face-recognition-wb workbench pod via oc cp. This keeps persisted workbench
# PVCs aligned with the repo when the initContainer skips its first-run sync.
#
# Safe to re-run — skips asset folders that don't exist locally and overwrites
# repo-managed notebooks/helpers already present in the pod.
#
# Usage:
#   ./steps/step-11-face-recognition/upload-to-workbench.sh
#   INCLUDE_TRAINING_ASSETS=true ./steps/step-11-face-recognition/upload-to-workbench.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

NAMESPACE="enterprise-mlops"
WB_NAME="face-recognition-wb"
WB_POD="${WB_NAME}-0"
WB_CONTAINER="$WB_NAME"
WB_WORKSPACE="/opt/app-root/src"
NOTEBOOKS_DIR="$SCRIPT_DIR/notebooks"
INCLUDE_TRAINING_ASSETS="${INCLUDE_TRAINING_ASSETS:-false}"

check_oc_logged_in

# ── Wait for workbench pod ────────────────────────────────────────────────
log_step "Waiting for workbench pod to be Running..."

TIMEOUT=120
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    PHASE=$(oc get pod "$WB_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [[ "$PHASE" == "Running" ]]; then
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if (( ELAPSED % 30 == 0 )); then
        log_info "  Pod status: $PHASE (${ELAPSED}s elapsed)"
    fi
done

if [[ "$PHASE" != "Running" ]]; then
    log_error "Workbench pod '$WB_POD' is not Running (status: $PHASE)"
    log_error "Deploy the workbench first: oc apply -f gitops/step-11-face-recognition/base/workbench/workbench.yaml"
    exit 1
fi
log_success "Workbench pod is Running"

# ── Sync notebooks and helper files ───────────────────────────────────────
log_step "Syncing notebooks and helper files..."

SYNCED=0
for PATTERN in "*.ipynb" "*.py" "*.txt"; do
    while IFS= read -r -d '' FILE; do
        BASENAME="$(basename "$FILE")"
        log_info "Syncing $BASENAME"
        oc cp "$FILE" "$NAMESPACE/$WB_POD:$WB_WORKSPACE/$BASENAME" -c "$WB_CONTAINER"
        SYNCED=$((SYNCED + 1))
    done < <(find "$NOTEBOOKS_DIR" -maxdepth 1 -type f -name "$PATTERN" -print0)
done

if [[ $SYNCED -eq 0 ]]; then
    log_warn "No notebook/helper files found in $NOTEBOOKS_DIR"
else
    log_success "Synced $SYNCED notebook/helper files"
fi

# ── Upload asset folders ──────────────────────────────────────────────────
UPLOADED=0
ASSET_FOLDERS=(images videos)
if [[ "$INCLUDE_TRAINING_ASSETS" == "true" ]]; then
    ASSET_FOLDERS+=(my_photos unknown_face)
else
    log_info "Skipping training asset folders by default; set INCLUDE_TRAINING_ASSETS=true to upload my_photos/ and unknown_face/"
fi

for FOLDER in "${ASSET_FOLDERS[@]}"; do
    LOCAL_DIR="$NOTEBOOKS_DIR/$FOLDER"
    if [[ -d "$LOCAL_DIR" ]]; then
        FILE_COUNT=$(find "$LOCAL_DIR" -type f | wc -l | tr -d ' ')
        if [[ "$FILE_COUNT" -eq 0 ]]; then
            log_warn "$FOLDER/ exists but is empty — skipping"
            continue
        fi
        log_info "Uploading $FOLDER/ ($FILE_COUNT files)..."
        oc cp "$LOCAL_DIR" "$NAMESPACE/$WB_POD:$WB_WORKSPACE/$FOLDER/" -c "$WB_CONTAINER"
        UPLOADED=$((UPLOADED + FILE_COUNT))
    else
        log_warn "$FOLDER/ not found locally — skipping"
    fi
done

if [[ $UPLOADED -eq 0 ]]; then
    log_warn "No files uploaded. Place assets in:"
    log_warn "  $NOTEBOOKS_DIR/images/     (test face + group photos)"
    log_warn "  $NOTEBOOKS_DIR/videos/     (test video)"
    log_warn "  $NOTEBOOKS_DIR/my_photos/  (selfies for optional training; requires INCLUDE_TRAINING_ASSETS=true)"
    log_warn "  $NOTEBOOKS_DIR/unknown_face/  (known negatives for optional training; requires INCLUDE_TRAINING_ASSETS=true)"
    exit 0
fi

# ── Verify ────────────────────────────────────────────────────────────────
log_step "Verifying uploads..."
oc exec -n "$NAMESPACE" "$WB_POD" -c "$WB_CONTAINER" -- bash -c '
    for d in images videos my_photos; do
        if [ -d "'$WB_WORKSPACE'/$d" ]; then
            count=$(find "'$WB_WORKSPACE'/$d" -type f | wc -l)
            echo "  $d/: $count files"
        fi
    done
'

log_success "Uploaded $UPLOADED files to workbench"
