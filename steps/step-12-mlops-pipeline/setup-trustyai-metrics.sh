#!/bin/bash
# =============================================================================
# TrustyAI Monitoring Setup for Face Recognition
# =============================================================================
# Populates TrustyAI with post-processed face-recognition inference metrics
# and configures SPD bias monitoring visible in the RHOAI Dashboard.
#
# This script:
#   1. Clears stale TrustyAI data
#   2. Uploads reference (TRAINING) data with proper tags
#   3. Uploads simulated prediction data (untagged → _trustyai_unlabeled)
#   4. Patches metadata for recordedInferences=true
#   5. Triggers model registration in TrustyAI's active tracker
#   6. Configures scheduled SPD metric
#   7. Verifies the metric appears in Prometheus
#
# The data represents post-processed YOLO inference results:
#   Input:  image_type   (0=known_face, 1=unknown_face)
#   Output: num_detections (count of detected faces)
#
# SPD measures fairness: whether known faces get detected at the same rate
# as unknown faces. A value between -0.1 and 0.1 indicates a fair model.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

NAMESPACE="private-ai"
MODEL_NAME="face-recognition"

load_env
check_oc_logged_in

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  TrustyAI Monitoring: Face Recognition SPD Bias Metric             ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Pre-flight
# =============================================================================
log_step "Checking TrustyAI..."
if ! oc get trustyaiservice trustyai-service -n "$NAMESPACE" &>/dev/null; then
    log_error "TrustyAIService not found. Deploy Step-12 first."
    exit 1
fi

TRUST_POD=$(oc get pod -n "$NAMESPACE" -l app.kubernetes.io/name=trustyai-service \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$TRUST_POD" ]]; then
    log_error "TrustyAI pod not running."
    exit 1
fi
log_success "TrustyAI pod: $TRUST_POD"

# =============================================================================
# Step 1: Clear stale data
# =============================================================================
log_step "Clearing stale TrustyAI data..."
oc exec -n "$NAMESPACE" "$TRUST_POD" -c trustyai-service -- \
    sh -c "rm -rf /data/*" 2>/dev/null || true
oc rollout restart deployment/trustyai-service -n "$NAMESPACE" &>/dev/null
oc rollout status deployment/trustyai-service -n "$NAMESPACE" --timeout=120s &>/dev/null
log_success "TrustyAI data cleared and restarted"

# Refresh pod name after restart
sleep 5
TRUST_POD=$(oc get pod -n "$NAMESPACE" -l app.kubernetes.io/name=trustyai-service \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# =============================================================================
# Step 2: Port-forward to TrustyAI
# =============================================================================
log_step "Setting up port-forward to TrustyAI..."
oc port-forward pod/"$TRUST_POD" -n "$NAMESPACE" 18083:8080 &>/dev/null &
PF_PID=$!
sleep 5

cleanup() {
    kill $PF_PID 2>/dev/null || true
    wait $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

TRUSTYAI_URL="http://localhost:18083"

# =============================================================================
# Step 3: Upload TRAINING reference data (tagged)
# =============================================================================
log_step "Uploading TRAINING reference data (15 observations)..."

python3 << 'PYEOF'
import json, urllib.request, uuid, random, sys

URL = "http://localhost:18083/data/upload"
random.seed(42)

for i in range(15):
    req_id = str(uuid.uuid4())
    img_type = 0 if random.random() < 0.5 else 1
    n_det = random.choice([1,2,3,2,1]) if img_type == 0 else random.choice([0,1,0,0,1,0])
    payload = {"model_name": "face-recognition", "data_tag": "TRAINING",
        "request": {"id": req_id, "inputs": [{"name": "image_type", "shape": [1], "datatype": "INT32", "data": [img_type]}]},
        "response": {"model_name": "face-recognition", "id": req_id, "outputs": [{"name": "num_detections", "shape": [1], "datatype": "INT32", "data": [n_det]}]}}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(URL, data=data)
    req.add_header("Content-Type", "application/json")
    urllib.request.urlopen(req, timeout=60)

print("  15 TRAINING observations uploaded")
PYEOF

# =============================================================================
# Step 4: Upload prediction data (untagged → becomes _trustyai_unlabeled)
# =============================================================================
log_step "Uploading prediction data (20 observations, untagged)..."

python3 << 'PYEOF'
import json, urllib.request, uuid, random

URL = "http://localhost:18083/data/upload"
random.seed(123)

for i in range(20):
    req_id = str(uuid.uuid4())
    img_type = 0 if random.random() < 0.5 else 1
    n_det = random.choice([1,2,3,2,1]) if img_type == 0 else random.choice([0,1,0,0,1,0])
    payload = {"model_name": "face-recognition",
        "request": {"id": req_id, "inputs": [{"name": "image_type", "shape": [1], "datatype": "INT32", "data": [img_type]}]},
        "response": {"model_name": "face-recognition", "id": req_id, "outputs": [{"name": "num_detections", "shape": [1], "datatype": "INT32", "data": [n_det]}]}}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(URL, data=data)
    req.add_header("Content-Type", "application/json")
    urllib.request.urlopen(req, timeout=60)

print("  20 prediction observations uploaded")
PYEOF

# =============================================================================
# Step 5: Patch metadata for recordedInferences
# =============================================================================
log_step "Patching metadata (recordedInferences=true)..."
oc exec -n "$NAMESPACE" deployment/trustyai-service -c trustyai-service -- python3 -c "
import json
with open('/data/face-recognition-metadata.json', 'r') as f:
    data = json.load(f)
data['recordedInferences'] = True
with open('/data/face-recognition-metadata.json', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
log_success "Metadata patched"

# =============================================================================
# Step 6: Verify model registration
# =============================================================================
log_step "Verifying model registration in TrustyAI..."
INFO=$(curl -s --max-time 30 "$TRUSTYAI_URL/info" 2>/dev/null)
OBS=$(echo "$INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('face-recognition',{}).get('data',{}).get('observations',0))" 2>/dev/null || echo "0")

if [[ "$OBS" -gt 0 ]]; then
    log_success "Model registered: $OBS observations"
else
    log_error "Model not registered in TrustyAI active tracker"
    exit 1
fi

# =============================================================================
# Step 7: Configure scheduled SPD metric
# =============================================================================
log_step "Configuring scheduled SPD bias metric..."

SPD_RESPONSE=$(curl -s --max-time 60 -H "Content-Type: application/json" \
    -X POST "$TRUSTYAI_URL/metrics/group/fairness/spd/request" \
    -d "{
        \"modelId\": \"face-recognition\",
        \"requestName\": \"face-recognition-bias\",
        \"protectedAttribute\": \"image_type\",
        \"privilegedAttribute\": {\"type\": \"INT32\", \"value\": 0},
        \"unprivilegedAttribute\": {\"type\": \"INT32\", \"value\": 1},
        \"outcomeName\": \"num_detections\",
        \"favorableOutcome\": {\"type\": \"INT32\", \"value\": 1},
        \"batchSize\": 15
    }" 2>/dev/null)

REQUEST_ID=$(echo "$SPD_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('requestId',''))" 2>/dev/null || echo "")
if [[ -n "$REQUEST_ID" ]]; then
    log_success "SPD metric configured (requestId: $REQUEST_ID)"
else
    log_error "Failed to configure SPD: $SPD_RESPONSE"
    exit 1
fi

# =============================================================================
# Step 8: Verify Prometheus metrics
# =============================================================================
log_step "Waiting for Prometheus metric computation..."
sleep 15

SPD_VALUE=$(curl -s --max-time 30 "$TRUSTYAI_URL/q/metrics" 2>/dev/null | grep "^trustyai_spd{" | head -1 | awk '{print $2}')

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
echo "  Model Serving → face-recognition → Model bias"
echo ""
