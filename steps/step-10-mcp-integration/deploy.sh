#!/bin/bash
# Step 12: MCP Integration — Deploy Script
# Deploys PostgreSQL, builds 3 MCP server images, deploys MCP servers,
# registers them in the Playground, and restarts LlamaStack pods.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="private-ai"
STEP_NAME="step-10-mcp-integration"

source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 12: MCP Integration (Database + OpenShift + Slack)        ║"
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
    log_error "No LlamaStackDistribution found. Deploy step-06 first."
    exit 1
fi
log_success "LlamaStack present"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 1: Deploy via ArgoCD
# ═══════════════════════════════════════════════════════════════════════════
log_step "Deploying Step 12 via ArgoCD..."
oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/$STEP_NAME.yaml"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 2: Wait for builds
# ═══════════════════════════════════════════════════════════════════════════
log_step "Waiting for MCP server image builds..."
sleep 10

BUILD_TIMEOUT=300
BUILD_ELAPSED=0
while [ $BUILD_ELAPSED -lt $BUILD_TIMEOUT ]; do
    COMPLETE=$(oc get builds -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "Complete" || echo "0")
    TOTAL=$(oc get builds -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    log_info "  Builds: $COMPLETE/$TOTAL complete"

    if [ "$COMPLETE" -ge 3 ]; then
        break
    fi
    sleep 15
    BUILD_ELAPSED=$((BUILD_ELAPSED + 15))
done

if [ "$COMPLETE" -ge 3 ]; then
    log_success "All 3 MCP server images built"
else
    log_error "Build timeout. Check: oc get builds -n $NAMESPACE"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: Wait for ArgoCD sync + components
# ═══════════════════════════════════════════════════════════════════════════
log_step "Waiting for ArgoCD sync..."
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
# Step 4: Apply Playground MCP ConfigMap
# ═══════════════════════════════════════════════════════════════════════════
log_step "Registering MCP servers in GenAI Playground..."
oc apply -f "$SCRIPT_DIR/mcp-playground-config.yaml"
log_success "gen-ai-aa-mcp-servers ConfigMap applied to redhat-ods-applications"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 5: Restart LlamaStack pods
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
# Step 6: Validation output
# ═══════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 12 deployment complete!                                   ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                 ║"
echo "║  MCP Servers:                                                   ║"
echo "║    database-mcp  :8080/sse (PostgreSQL equipment queries)      ║"
echo "║    openshift-mcp :8000/sse (cluster inspection)                ║"
echo "║    slack-mcp     :8080/sse (team notifications, demo mode)     ║"
echo "║                                                                 ║"
echo "║  Playground: MCP servers visible in GenAI Studio > AI Assets   ║"
echo "║                                                                 ║"
echo "║  Validate:                                                      ║"
echo "║    ./steps/step-10-mcp-integration/validate.sh                 ║"
echo "║                                                                 ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
