#!/bin/bash
# Step 10: RAG Evaluation — Validation Script

set -euo pipefail

NAMESPACE="private-ai"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 10: RAG Evaluation — Validation                          ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Pipeline runs ---
log_step "Recent eval pipeline pods"
oc get pods -n "$NAMESPACE" -l pipeline/runid \
    --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null | tail -10 || \
    echo "  No pipeline pods found"

echo ""

# --- S3 reports ---
log_step "Eval reports in MinIO"

MINIO_NS="minio-storage"
MINIO_KEY=$(oc -n "$MINIO_NS" get secret minio-credentials \
    -o jsonpath='{.data.MINIO_ROOT_USER}' 2>/dev/null | base64 -d || true)
MINIO_SECRET=$(oc -n "$MINIO_NS" get secret minio-credentials \
    -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' 2>/dev/null | base64 -d || true)

if [ -n "$MINIO_KEY" ] && [ -n "$MINIO_SECRET" ]; then
    oc -n "$MINIO_NS" run mc-eval-ls-$(date +%s) --rm -i --restart=Never \
        --image=quay.io/minio/mc --env=HOME=/tmp \
        --env="AK=$MINIO_KEY" --env="SK=$MINIO_SECRET" \
        --env="ENDPOINT=http://minio.$MINIO_NS.svc:9000" \
        -- bash -c '
mkdir -p /tmp/.mc
export MC_CONFIG_DIR=/tmp/.mc
mc alias set myminio "$ENDPOINT" "$AK" "$SK" --api S3v4 >/dev/null 2>&1
echo "=== eval-results/ ==="
mc ls --recursive myminio/pipelines/eval-results/ 2>/dev/null || echo "  (no reports yet)"
' 2>/dev/null || echo "  Could not list MinIO eval-results"
else
    echo "  Could not read MinIO credentials"
fi

echo ""

# --- LlamaStack scoring health ---
log_step "LlamaStack scoring API health check"
LSD_POD=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=llamastack-rag \
    --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)

if [ -n "$LSD_POD" ]; then
    SCORE_RESULT=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/scoring/score \
        -H "Content-Type: application/json" \
        -d '{"input_rows":[{"input_query":"test","generated_answer":"test answer","expected_answer":"test answer"}],"scoring_functions":{"basic::subset_of":null}}' \
        2>/dev/null || echo "{}")

    echo "  Scoring API response:"
    echo "$SCORE_RESULT" | python3 -m json.tool 2>/dev/null || echo "  $SCORE_RESULT"
else
    echo "  lsd-rag pod not found"
fi

echo ""
log_success "Validation complete"
