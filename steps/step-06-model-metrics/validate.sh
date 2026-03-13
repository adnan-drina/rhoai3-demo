#!/usr/bin/env bash
# Step 06: Model Performance Metrics — Validation Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/validate-lib.sh"

NAMESPACE="private-ai"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 06: Model Performance Metrics — Validation               ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# --- Grafana Operator ---
log_step "Grafana Operator"
check_csv_succeeded "grafana-operator" "grafana"

# --- Grafana Instance ---
log_step "Grafana Instance"
check "Grafana instance exists" \
    "oc get grafana -n $NAMESPACE --no-headers 2>/dev/null | wc -l | tr -d ' '" \
    "1"

# --- Grafana Dashboards ---
log_step "Grafana Dashboards"
DASH_COUNT=$(oc get grafanadashboard -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$DASH_COUNT" -ge 1 ]]; then
    echo -e "${GREEN}[PASS]${NC} GrafanaDashboards found: $DASH_COUNT"
    VALIDATE_PASS=$((VALIDATE_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} No GrafanaDashboards found in $NAMESPACE"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- Grafana Route ---
log_step "Grafana Route"
GRAFANA_HOST=$(oc get route grafana-route -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -n "$GRAFANA_HOST" ]]; then
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$GRAFANA_HOST/api/health" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo -e "${GREEN}[PASS]${NC} Grafana health endpoint: HTTP 200"
        VALIDATE_PASS=$((VALIDATE_PASS + 1))
    else
        echo -e "${YELLOW}[WARN]${NC} Grafana health returned HTTP $HTTP_CODE"
        VALIDATE_WARN=$((VALIDATE_WARN + 1))
    fi
else
    echo -e "${RED}[FAIL]${NC} Grafana route not found"
    VALIDATE_FAIL=$((VALIDATE_FAIL + 1))
fi

# --- GuideLLM CronJob ---
log_step "GuideLLM"
CJ_COUNT=$(oc get cronjob -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "guidellm" || echo "0")
check_warn "GuideLLM CronJob exists" \
    "echo $CJ_COUNT" \
    "1"

# --- Summary ---
echo ""
validation_summary
