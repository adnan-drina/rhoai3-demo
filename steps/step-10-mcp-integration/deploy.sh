#!/bin/bash
# Step 10: MCP Integration — Deploy Script
# All 3 MCP servers use prebuilt images from Red Hat Ecosystem Catalog (quay.io/mcp-servers/).
# Zero on-cluster builds required.

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
# Step 1: Create Slack credentials Secret from .env (not in git)
# ═══════════════════════════════════════════════════════════════════════════
log_step "Creating Slack MCP credentials Secret..."
load_env

if [ -z "${SLACK_BOT_TOKEN:-}" ]; then
    log_info "⚠️  SLACK_BOT_TOKEN not set in .env — Slack MCP will start but posting will fail."
    log_info "   To enable Slack: add SLACK_BOT_TOKEN=xoxb-... to .env"
    log_info "   Create a Slack App at https://api.slack.com/apps with scopes:"
    log_info "   channels:history, channels:read, chat:write, reactions:write, users:read"
else
    oc create secret generic slack-mcp-credentials \
        --from-literal=SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | oc apply -f -
    log_success "slack-mcp-credentials Secret created/updated"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 2: Deploy via ArgoCD
# ═══════════════════════════════════════════════════════════════════════════
log_step "Deploying Step 10 via ArgoCD..."
oc apply -f "$REPO_ROOT/gitops/argocd/app-of-apps/$STEP_NAME.yaml"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: Wait for ArgoCD sync
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

    if [ "$SYNC" = "Synced" ]; then
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
    oc wait deploy/$server -n "$NAMESPACE" --for=condition=Available --timeout=180s 2>/dev/null || \
        log_error "$server did not become available"
done
log_success "All MCP servers running"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 4: Verify Playground ConfigMap
# ═══════════════════════════════════════════════════════════════════════════
log_step "Verifying MCP servers ConfigMap in redhat-ods-applications..."
if oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications &>/dev/null; then
    log_success "gen-ai-aa-mcp-servers ConfigMap present"
else
    log_error "gen-ai-aa-mcp-servers ConfigMap not found — check ArgoCD sync"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 5: Restart Playground LSD (safe — no RAG data)
# ═══════════════════════════════════════════════════════════════════════════
log_step "Restarting Playground LSD to discover MCP tool_groups..."

if oc get llamastackdistribution lsd-genai-playground -n "$NAMESPACE" &>/dev/null; then
    oc rollout restart deployment/lsd-genai-playground -n "$NAMESPACE" 2>/dev/null || true
    log_success "lsd-genai-playground restart triggered"
fi

# Register MCP tool_groups in lsd-rag (required on fresh clusters — persists in PostgreSQL)
if oc get llamastackdistribution lsd-rag -n "$NAMESPACE" &>/dev/null; then
    LSD_POD=$(oc get pods -l app.kubernetes.io/instance=lsd-rag -n "$NAMESPACE" \
        --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1 || true)
    if [[ -n "$LSD_POD" ]]; then
        log_step "Registering MCP tool_groups in lsd-rag..."
        for tg in openshift database slack; do
            MCP_URL="http://${tg}-mcp.${NAMESPACE}.svc:8080/sse"
            [[ "$tg" == "openshift" ]] && MCP_URL="http://openshift-mcp.${NAMESPACE}.svc:8000/sse"
            EXISTING=$(oc exec "$LSD_POD" -n "$NAMESPACE" -- \
                curl -sf "http://localhost:8321/v1/toolgroups/mcp::${tg}" 2>/dev/null || true)
            if [[ -n "$EXISTING" ]] && echo "$EXISTING" | grep -q "identifier"; then
                log_success "  mcp::${tg} already registered"
            else
                oc exec "$LSD_POD" -n "$NAMESPACE" -- \
                    curl -sf -X POST "http://localhost:8321/v1/toolgroups" \
                    -H "Content-Type: application/json" \
                    -d "{\"toolgroup_id\":\"mcp::${tg}\",\"provider_id\":\"model-context-protocol\",\"mcp_endpoint\":{\"uri\":\"${MCP_URL}\"}}" \
                    2>/dev/null && log_success "  mcp::${tg} registered" \
                    || log_warn "  mcp::${tg} registration failed"
            fi
        done
    else
        log_warn "lsd-rag pod not found — register tool_groups manually"
    fi
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
echo "║    database-mcp  :8080 (edb-postgres-mcp)                      ║"
echo "║    openshift-mcp :8000 (kubernetes-mcp-server)                 ║"
echo "║    slack-mcp     :8080 (slack-mcp-server)                      ║"
echo "║                                                                 ║"
echo "║  Validate:                                                      ║"
echo "║    ./steps/step-10-mcp-integration/validate.sh                 ║"
echo "║                                                                 ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
