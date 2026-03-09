#!/bin/bash
# Step 09: RAG Pipeline — Validation Script

set -euo pipefail

NAMESPACE="private-ai"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 09: RAG Pipeline — Validation                            ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Infrastructure ---
log_step "Infrastructure"

echo ""
echo "Milvus:"
oc get deploy milvus-standalone -n "$NAMESPACE" 2>/dev/null || echo "  NOT FOUND"

echo ""
echo "Docling:"
oc get deploy docling-service -n "$NAMESPACE" 2>/dev/null || echo "  NOT FOUND"

echo ""
echo "DSPA:"
oc get dspa dspa-rag -n "$NAMESPACE" 2>/dev/null || echo "  NOT FOUND"

echo ""
echo "LlamaStack RAG:"
oc get llamastackdistribution lsd-rag -n "$NAMESPACE" 2>/dev/null || echo "  NOT FOUND"

echo ""

# --- Milvus health ---
log_step "Milvus health check"
oc exec deploy/milvus-standalone -n "$NAMESPACE" -- \
    curl -s http://localhost:9091/healthz 2>/dev/null && echo "" || \
    echo "  Could not reach Milvus health endpoint"

echo ""

# --- LlamaStack models ---
log_step "LlamaStack registered models"
oc exec deploy/lsd-rag -n "$NAMESPACE" -- \
    curl -s http://localhost:8321/v1/models 2>/dev/null | \
    python3 -m json.tool 2>/dev/null || \
    echo "  Could not query LlamaStack models"

echo ""

# --- Vector store queries ---
log_step "Vector store content (chunks per collection)"

for collection in red_hat_docs acme_corporate eu_ai_act; do
    RESULT=$(oc exec deploy/lsd-rag -n "$NAMESPACE" -- \
        curl -s http://localhost:8321/v1/vector-io/query \
        -H "Content-Type: application/json" \
        -d "{\"vector_db_id\":\"$collection\",\"query\":\"test\"}" 2>/dev/null || echo "{}")

    CHUNKS=$(echo "$RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data.get('chunks', [])))
except:
    print('N/A')
" 2>/dev/null)

    echo "  $collection: $CHUNKS chunks returned"
done

echo ""

# --- Pipeline runs ---
log_step "Recent pipeline pods"
oc get pods -n "$NAMESPACE" -l pipeline/runid --sort-by=.metadata.creationTimestamp \
    --no-headers 2>/dev/null | tail -10 || echo "  No pipeline pods found"

echo ""
log_success "Validation complete"
