#!/bin/bash
# Step 10: MCP Integration — Deploy Script
# All 3 MCP servers use prebuilt images from Red Hat Ecosystem Catalog:
#   - quay.io/mcp-servers/edb-postgres-mcp (Database MCP)
#   - quay.io/mcp-servers/kubernetes-mcp-server (OpenShift MCP)
#   - quay.io/mcp-servers/slack-mcp-server (Slack MCP)
# No on-cluster builds required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"
STEP_NAME="step-10-mcp-integration"

source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 10: MCP Integration (All Red Hat Catalog Images)          ║"
echo "║  Database + OpenShift + Slack — Zero on-cluster builds          ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 0: Prerequisites
# ═══════════════════════════════════════════════════════════════════════════
log_step "Checking prerequisites..."

check_oc_logged_in

if ! oc get inferenceservice granite-8b-agent -n "$NAMESPACE" &>/dev/null; then
    log_error "granite-8b-agent InferenceService not found. Deploy step-05 first."
    exit 1
fi
log_success "granite-8b-agent present"

if ! oc get llamastackdistribution -n "$NAMESPACE" &>/dev/null 2>&1; then
    log_error "No LlamaStackDistribution found. Deploy step-05/07 first."
    exit 1
fi
log_success "LlamaStack present"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 1: Deploy via ArgoCD
# ═══════════════════════════════════════════════════════════════════════════
log_step "Deploying Step 10 via ArgoCD..."
oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/$STEP_NAME.yaml"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 2: Wait for ArgoCD sync
# ═══════════════════════════════════════════════════════════════════════════
log_step "Waiting for ArgoCD sync (no builds — all catalog images)..."
TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    SYNC=$(oc get application "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(oc get application "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    log_info "  Sync: $SYNC | Health: $HEALTH"

    if [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done
echo ""

log_step "Waiting for PostgreSQL..."
oc wait deploy/postgresql -n "$NAMESPACE" --for=condition=Available --timeout=120s 2>/dev/null || \
    log_error "PostgreSQL did not become available"

log_step "Waiting for MCP servers..."
for server in database-mcp openshift-mcp slack-mcp; do
    oc wait deploy/$server -n "$NAMESPACE" --for=condition=Available --timeout=120s 2>/dev/null || \
        log_error "$server did not become available"
done
log_success "All MCP servers running"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: Verify Playground ConfigMap
# ═══════════════════════════════════════════════════════════════════════════
log_step "Verifying MCP servers ConfigMap in redhat-ods-applications..."
if oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications &>/dev/null; then
    log_success "gen-ai-aa-mcp-servers ConfigMap present"
else
    log_error "gen-ai-aa-mcp-servers ConfigMap not found — check ArgoCD sync"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 4: Restart LlamaStack pods to discover MCP tools
# ═══════════════════════════════════════════════════════════════════════════
log_step "Restarting LlamaStack pods to discover MCP tool_groups..."

if oc get llamastackdistribution lsd-genai-playground -n "$NAMESPACE" &>/dev/null; then
    oc rollout restart deployment/lsd-genai-playground -n "$NAMESPACE" 2>/dev/null || true
    log_success "lsd-genai-playground restart triggered"
fi

if oc get llamastackdistribution lsd-rag -n "$NAMESPACE" &>/dev/null; then
    oc rollout restart deployment/lsd-rag -n "$NAMESPACE" 2>/dev/null || true
    log_success "lsd-rag restart triggered"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Done
# ═══════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 10 deployment complete!                                   ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                 ║"
echo "║  All MCP Servers from Red Hat Ecosystem Catalog:                ║"
echo "║    database-mcp  :8080 (quay.io/mcp-servers/edb-postgres-mcp) ║"
echo "║    openshift-mcp :8000 (quay.io/mcp-servers/kubernetes-mcp..) ║"
echo "║    slack-mcp     :8080 (quay.io/mcp-servers/slack-mcp-server) ║"
echo "║                                                                 ║"
echo "║  Playground: MCP servers visible in GenAI Studio > AI Assets   ║"
echo "║                                                                 ║"
echo "║  Validate:                                                      ║"
echo "║    ./steps/step-10-mcp-integration/validate.sh                 ║"
echo "║                                                                 ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
