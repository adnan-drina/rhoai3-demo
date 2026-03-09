#!/bin/bash
# Step 12: MCP Integration — Validation Script

set -euo pipefail

NAMESPACE="private-ai"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 12: MCP Integration — Validation                         ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Infrastructure ---
log_step "MCP Server Deployments"
for server in database-mcp openshift-mcp slack-mcp; do
    STATUS=$(oc get deploy "$server" -n "$NAMESPACE" \
        -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
    if [ "$STATUS" = "1" ]; then
        log_success "  $server: Running"
    else
        log_error "  $server: NOT READY"
    fi
done
echo ""

# --- PostgreSQL ---
log_step "PostgreSQL"
oc get deploy postgresql -n "$NAMESPACE" 2>/dev/null || echo "  NOT FOUND"
echo ""

# --- Builds ---
log_step "Image Builds"
oc get builds -n "$NAMESPACE" --no-headers 2>/dev/null | \
    awk '{printf "  %-25s %s\n", $1, $4}' || echo "  No builds found"
echo ""

# --- Playground ConfigMap ---
log_step "Playground MCP ConfigMap"
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications \
    --no-headers 2>/dev/null && log_success "  ConfigMap present" || \
    log_error "  ConfigMap NOT FOUND in redhat-ods-applications"
echo ""

# --- MCP server connectivity ---
log_step "MCP Server Connectivity"
for server_port in "database-mcp:8080" "openshift-mcp:8000" "slack-mcp:8080"; do
    server=$(echo "$server_port" | cut -d: -f1)
    port=$(echo "$server_port" | cut -d: -f2)
    POD=$(oc get pods -l app="$server" -n "$NAMESPACE" \
        --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1)
    if [ -n "$POD" ]; then
        log_success "  $server pod: $POD (port $port)"
    else
        log_error "  $server: no pod found"
    fi
done
echo ""

log_success "Validation complete"
