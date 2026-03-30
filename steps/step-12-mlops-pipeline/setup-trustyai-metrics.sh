#!/bin/bash
# =============================================================================
# TrustyAI Monitoring Setup for Face Recognition
# =============================================================================
# Bootstraps the TrustyAI adapter which handles:
#   1. Uploading TRAINING baseline data to TrustyAI
#   2. Uploading initial prediction data
#   3. Configuring scheduled SPD fairness metric
#   4. Configuring drift detection (MeanShift)
#
# The adapter runs as a separate deployment and receives real-time detection
# results from inference clients (remote_infer.py, edge inference.py),
# transforming CV model output into tabular data for TrustyAI.
#
# Data schema (post-processed from YOLO detections):
#   Input:  image_type     (0=known_face/adnan, 1=unknown_face_only)
#   Output: num_detections (count of detected faces)
#
# SPD measures: whether known faces get detected at the same rate as unknowns.
# Fair range: -0.1 to 0.1
#
# Ref: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/monitoring_your_ai_systems/
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

NAMESPACE="private-ai"

load_env
check_oc_logged_in

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  TrustyAI Monitoring: Face Recognition SPD Bias Metric             ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Pre-flight
# =============================================================================
log_step "Checking TrustyAI and adapter..."
if ! oc get trustyaiservice trustyai-service -n "$NAMESPACE" &>/dev/null; then
    log_error "TrustyAIService not found. Deploy Step-12 first."
    exit 1
fi

ADAPTER_POD=$(oc get pod -n "$NAMESPACE" -l app=trustyai-adapter \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "$ADAPTER_POD" ]]; then
    log_error "TrustyAI adapter not running. Ensure step-12 GitOps is synced."
    exit 1
fi
log_success "Adapter pod: $ADAPTER_POD"

# =============================================================================
# Trigger bootstrap via adapter
# =============================================================================
log_step "Triggering adapter bootstrap (baseline + SPD + drift)..."

oc port-forward pod/"$ADAPTER_POD" -n "$NAMESPACE" 18090:8090 &>/dev/null &
PF_PID=$!
sleep 3

cleanup() {
    kill $PF_PID 2>/dev/null || true
    wait $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

BOOTSTRAP_RESP=$(curl -s --max-time 10 -X POST "http://localhost:18090/bootstrap" 2>/dev/null)
log_success "Bootstrap triggered: $BOOTSTRAP_RESP"

# =============================================================================
# Wait for bootstrap to complete
# =============================================================================
log_step "Waiting for TrustyAI to process data..."
sleep 20

TRUST_POD=$(oc get pod -n "$NAMESPACE" -l app.kubernetes.io/name=trustyai-service \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# =============================================================================
# Patch internal CSV: TrustyAI stores API-uploaded prediction data with an
# empty tag, but SPD requires the _trustyai_unlabeled tag. Also set
# recordedInferences=true in metadata.
# =============================================================================
log_step "Patching TrustyAI internal data for SPD compatibility..."
oc exec -n "$NAMESPACE" "$TRUST_POD" -c trustyai-service -- python3 -c "
import json

# Patch empty tags to _trustyai_unlabeled in internal CSV
csv_path = '/data/face-recognition-internal_data.csv'
lines = open(csv_path).readlines()
patched = 0
new_lines = []
for line in lines:
    parts = line.strip().split(',', 1)
    if parts[0] == '':
        new_lines.append('_trustyai_unlabeled,' + parts[1] + '\n')
        patched += 1
    else:
        new_lines.append(line)
open(csv_path, 'w').writelines(new_lines)
print(f'  Patched {patched} empty tags to _trustyai_unlabeled')

# Set recordedInferences=true
meta_path = '/data/face-recognition-metadata.json'
data = json.load(open(meta_path))
data['recordedInferences'] = True
json.dump(data, open(meta_path, 'w'), indent=2)
print('  recordedInferences set to True')
" 2>/dev/null
log_success "Internal data patched"

INFO=$(oc exec -n "$NAMESPACE" "$TRUST_POD" -c trustyai-service -- \
    curl -s "http://localhost:8080/info" 2>/dev/null)
OBS=$(echo "$INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('face-recognition',{}).get('data',{}).get('observations',0))" 2>/dev/null || echo "0")
METRICS=$(echo "$INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('face-recognition',{}).get('metrics',{}).get('scheduledMetadata',{}).get('metricCounts',{}))" 2>/dev/null || echo "{}")

if [[ "$OBS" -gt 0 ]]; then
    log_success "Model registered: $OBS observations, metrics=$METRICS"
else
    log_warn "Waiting for data to be ingested..."
    sleep 15
    INFO=$(oc exec -n "$NAMESPACE" "$TRUST_POD" -c trustyai-service -- \
        curl -s "http://localhost:8080/info" 2>/dev/null)
    OBS=$(echo "$INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('face-recognition',{}).get('data',{}).get('observations',0))" 2>/dev/null || echo "0")
    METRICS=$(echo "$INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('face-recognition',{}).get('metrics',{}).get('scheduledMetadata',{}).get('metricCounts',{}))" 2>/dev/null || echo "{}")
    log_info "Observations: $OBS, Metrics: $METRICS"
fi

# =============================================================================
# Verify Prometheus metrics
# =============================================================================
log_step "Checking Prometheus metrics..."
sleep 10

SPD_VALUE=$(oc exec -n "$NAMESPACE" "$TRUST_POD" -c trustyai-service -- \
    curl -s "http://localhost:8080/q/metrics" 2>/dev/null | grep "^trustyai_spd{" | head -1 | awk '{print $2}')

if [[ -n "$SPD_VALUE" && "$SPD_VALUE" != "NaN" ]]; then
    log_success "SPD metric live in Prometheus: $SPD_VALUE"
    echo ""
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │  trustyai_spd = $SPD_VALUE"
    echo "  │  Model: face-recognition                    │"
    echo "  │  Protected: image_type (known vs unknown)   │"
    echo "  │  Outcome: num_detections (≥1 = favorable)   │"
    echo "  │  Fair range: -0.1 to 0.1                    │"
    echo "  └─────────────────────────────────────────────┘"
else
    log_warn "SPD value not yet available. Check Dashboard in ~30s."
fi

echo ""
log_info "View in RHOAI Dashboard:"
echo "  AI hub → Deployments → face-recognition → Model bias"
echo ""
log_info "Live inference data will flow automatically from notebooks/edge app."
echo ""
