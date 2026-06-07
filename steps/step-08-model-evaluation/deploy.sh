#!/bin/bash
# Step 08: Model Evaluation — Deploy Script
# 1. Applies ArgoCD Application (deploys ConfigMaps + PostSync Job for eval configs)
# 2. Builds the custom EvalHub RAG scenario adapter image
# 3. Waits for EvalHub and runs the product-native smoke evaluation
# 4. Launches the EvalHub ACME/whoami pre/post RAG evaluation suite
# 5. Compiles the legacy KFP RAG eval pipeline for optional compatibility runs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STEP_NAME="step-08-model-evaluation"
NAMESPACE="enterprise-rag"
EVALHUB_NAMESPACE="evalhub-system"
RUN_ID="eval-$(date +%s)"

source "$REPO_ROOT/scripts/lib.sh"

require_value() {
    local label="$1"
    local actual="$2"
    local expected="$3"

    if [[ "$actual" != "$expected" ]]; then
        log_error "$label expected '$expected', got '${actual:-<empty>}'"
        exit 1
    fi
    log_success "$label: $actual"
}

require_non_empty() {
    local label="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        log_error "$label is required"
        exit 1
    fi
    log_success "$label: $value"
}

check_rhoai_evalhub_prerequisites() {
    local installed_csv dsc_phase trustyai_state raw_deployment mlflow_available provider collection

    log_step "Checking RHOAI 3.4 EvalHub prerequisites..."

    installed_csv="$(oc get subscription rhods-operator -n redhat-ods-operator \
        -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
    require_value "RHOAI installed CSV" "$installed_csv" "rhods-operator.3.4.0"

    dsc_phase="$(oc get datasciencecluster default-dsc \
        -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    require_value "DataScienceCluster/default-dsc phase" "$dsc_phase" "Ready"

    trustyai_state="$(oc get datasciencecluster default-dsc \
        -o jsonpath='{.spec.components.trustyai.managementState}' 2>/dev/null || true)"
    require_value "TrustyAI managementState" "$trustyai_state" "Managed"

    raw_deployment="$(oc get datasciencecluster default-dsc \
        -o jsonpath='{.spec.components.kserve.rawDeploymentServiceConfig}' 2>/dev/null || true)"
    require_non_empty "KServe RawDeployment service config" "$raw_deployment"

    if ! oc get crd evalhubs.trustyai.opendatahub.io &>/dev/null; then
        log_error "EvalHub CRD evalhubs.trustyai.opendatahub.io is missing"
        exit 1
    fi
    log_success "EvalHub CRD present"

    mlflow_available="$(oc get mlflow mlflow \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)"
    require_value "Step 12 MLflow server Available" "$mlflow_available" "True"

    for provider in lm-evaluation-harness garak guidellm lighteval; do
        if oc get configmap -n redhat-ods-applications \
            -l "trustyai.opendatahub.io/evalhub-provider-name=${provider}" \
            --no-headers 2>/dev/null | grep -q .; then
            log_success "EvalHub provider ConfigMap present: $provider"
        else
            log_error "EvalHub provider ConfigMap missing: $provider"
            exit 1
        fi
    done

    for collection in safety-and-fairness-v1; do
        if oc get configmap -n redhat-ods-applications \
            -l "trustyai.opendatahub.io/evalhub-collection-name=${collection}" \
            --no-headers 2>/dev/null | grep -q .; then
            log_success "EvalHub collection ConfigMap present: $collection"
        else
            log_error "EvalHub collection ConfigMap missing: $collection"
            exit 1
        fi
    done
}

wait_for_evalhub_ready() {
    local timeout="${1:-600}" elapsed=0 phase ready route_host health_code

    log_step "Waiting for EvalHub readiness..."
    oc wait deployment/evalhub-postgres -n "$EVALHUB_NAMESPACE" \
        --for=condition=Available --timeout=300s >/dev/null
    log_success "EvalHub PostgreSQL is available"

    while [[ $elapsed -le $timeout ]]; do
        phase="$(oc get evalhub evalhub -n "$EVALHUB_NAMESPACE" \
            -o jsonpath='{.status.phase}' 2>/dev/null || true)"
        ready="$(oc get evalhub evalhub -n "$EVALHUB_NAMESPACE" \
            -o jsonpath='{.status.ready}' 2>/dev/null || true)"
        route_host="$(oc get route evalhub -n "$EVALHUB_NAMESPACE" \
            -o jsonpath='{.spec.host}' 2>/dev/null || true)"

        if [[ -n "$route_host" ]]; then
            health_code="$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' \
                "https://${route_host}/api/v1/health" 2>/dev/null || echo "000")"
        else
            health_code="000"
        fi

        if [[ "$phase" == "Ready" && "$health_code" == "200" ]]; then
            log_success "EvalHub is ready: https://${route_host}"
            return 0
        fi

        log_info "  EvalHub phase=${phase:-Unknown} ready=${ready:-Unknown} health=${health_code} (${elapsed}s / ${timeout}s)"
        sleep 15
        elapsed=$((elapsed + 15))
    done

    log_error "Timed out waiting for EvalHub readiness"
    oc get evalhub evalhub -n "$EVALHUB_NAMESPACE" -o yaml || true
    oc get pods,svc,route -n "$EVALHUB_NAMESPACE" || true
    exit 1
}

build_evalhub_rag_adapter() {
    local adapter_dir="$SCRIPT_DIR/evalhub-rag-scenario-adapter"

    log_step "Building EvalHub RAG scenario adapter image..."
    if [[ ! -d "$adapter_dir" ]]; then
        log_error "Adapter source directory not found: $adapter_dir"
        exit 1
    fi

    if ! oc get buildconfig evalhub-rag-scenario-adapter -n "$NAMESPACE" &>/dev/null; then
        log_error "BuildConfig evalhub-rag-scenario-adapter not found in $NAMESPACE"
        exit 1
    fi

    oc start-build evalhub-rag-scenario-adapter -n "$NAMESPACE" \
        --from-dir="$adapter_dir" \
        --wait \
        --follow
    log_success "EvalHub RAG scenario adapter image built"
}

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 08: Model Evaluation                                     ║"
echo "║  EvalHub + RAG Scenario Evaluation + Standard Benchmarks       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 0: Prerequisites (step-07 must be deployed)
# ═══════════════════════════════════════════════════════════════════════════
log_step "Checking prerequisites..."

check_oc_logged_in
check_rhoai_evalhub_prerequisites

if ! oc get llamastackdistribution lsd-rag -n "$NAMESPACE" &>/dev/null; then
    log_error "lsd-rag not found. Deploy step-07 first."
    exit 1
fi
log_success "lsd-rag present"

if ! oc get dspa dspa-rag -n "$NAMESPACE" &>/dev/null; then
    log_error "dspa-rag not found. Deploy step-07 first."
    exit 1
fi
log_success "dspa-rag present"

if ! oc get pvc rag-pipeline-workspace -n "$NAMESPACE" &>/dev/null; then
    log_error "PVC rag-pipeline-workspace not found. Deploy step-07 first."
    exit 1
fi
log_success "PVC rag-pipeline-workspace present"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 1: Deploy via ArgoCD
# ═══════════════════════════════════════════════════════════════════════════
log_step "Deploying Step 08 via ArgoCD..."

ARGOCD_APP="$REPO_ROOT/gitops/argocd/app-of-apps/$STEP_NAME.yaml"
if [ ! -f "$ARGOCD_APP" ]; then
    log_error "ArgoCD Application not found: $ARGOCD_APP"
    exit 1
fi

oc apply -f "$ARGOCD_APP"
log_success "ArgoCD Application applied: $STEP_NAME"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 2: Wait for ArgoCD sync (ConfigMaps + PostSync Job copies configs)
# ═══════════════════════════════════════════════════════════════════════════
log_step "Waiting for ArgoCD sync..."
sleep 5

TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    SYNC_STATUS=$(oc get applications.argoproj.io "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(oc get applications.argoproj.io "$STEP_NAME" -n openshift-gitops \
        -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

    if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
        log_success "ArgoCD sync complete: $SYNC_STATUS / $HEALTH"
        break
    fi

    log_info "  Status: $SYNC_STATUS / $HEALTH (${ELAPSED}s / ${TIMEOUT}s)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ "$SYNC_STATUS" != "Synced" ]; then
    log_warn "ArgoCD not fully synced ($SYNC_STATUS) — continuing, but eval configs may not be ready"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 3: Build custom EvalHub RAG scenario adapter image
# ═══════════════════════════════════════════════════════════════════════════
build_evalhub_rag_adapter
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 4: Configure EvalHub tenant and run product-native smoke evaluation
# ═══════════════════════════════════════════════════════════════════════════
log_step "Registering $NAMESPACE as an EvalHub tenant..."
oc label namespace "$NAMESPACE" "evalhub.trustyai.opendatahub.io/tenant=" --overwrite >/dev/null
log_success "Tenant label applied to namespace/$NAMESPACE"

wait_for_evalhub_ready 600

if [ -f "$SCRIPT_DIR/run-evalhub-smoke.sh" ]; then
    chmod +x "$SCRIPT_DIR/run-evalhub-smoke.sh"
    "$SCRIPT_DIR/run-evalhub-smoke.sh" "$RUN_ID"
else
    log_error "run-evalhub-smoke.sh not found"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 5: Run EvalHub ACME/whoami pre/post RAG scenario suite
# ═══════════════════════════════════════════════════════════════════════════
if [ -f "$SCRIPT_DIR/run-evalhub-rag-scenarios.sh" ]; then
    chmod +x "$SCRIPT_DIR/run-evalhub-rag-scenarios.sh"
    "$SCRIPT_DIR/run-evalhub-rag-scenarios.sh" "$RUN_ID"
else
    log_error "run-evalhub-rag-scenarios.sh not found"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 6: Compile KFP RAG eval pipeline for optional compatibility runs
# ═══════════════════════════════════════════════════════════════════════════
log_step "Compiling optional KFP RAG eval pipeline..."

VENV_PATH="$REPO_ROOT/.venv-kfp"
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH"
fi
"$VENV_PATH/bin/pip" install -q --upgrade pip
"$VENV_PATH/bin/pip" install -q kfp kfp-kubernetes

mkdir -p "$REPO_ROOT/artifacts"
(cd "$SCRIPT_DIR/kfp" && "$VENV_PATH/bin/python3" eval_pipeline.py)

if [ -f "$REPO_ROOT/artifacts/rag-eval.yaml" ]; then
    log_success "Pipeline compiled: artifacts/rag-eval.yaml"
else
    log_error "Pipeline compilation failed"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Step 7: Optional KFP RAG eval pipeline run
# ═══════════════════════════════════════════════════════════════════════════
log_step "Checking optional KFP RAG eval run setting..."

if [[ "${RUN_KFP_RAG_EVAL:-false}" == "true" && -f "$SCRIPT_DIR/run-rag-eval.sh" ]]; then
    chmod +x "$SCRIPT_DIR/run-rag-eval.sh"
    "$SCRIPT_DIR/run-rag-eval.sh" "$RUN_ID" || log_error "Pipeline launch failed — try manually via RHOAI Dashboard"
elif [[ "${RUN_KFP_RAG_EVAL:-false}" == "true" ]]; then
    log_info "run-rag-eval.sh not found — upload pipeline manually via RHOAI Dashboard"
else
    log_info "Skipping KFP RAG eval run. Set RUN_KFP_RAG_EVAL=true to run the legacy pipeline path."
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Step 08 deployed!                                             ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                ║"
echo "║  EvalHub smoke (automated):                                    ║"
echo "║    Tenant:  $NAMESPACE                                  ║"
echo "║    Model:   granite-8b-agent                                  ║"
echo "║    Rerun:   ./steps/step-08-model-evaluation/run-evalhub-smoke.sh ║"
echo "║                                                                ║"
echo "║  EvalHub RAG scenarios (automated):                            ║"
echo "║    Suite:   rhoai-rag-pre-post-v1                              ║"
echo "║    Rerun:   ./steps/step-08-model-evaluation/run-evalhub-rag-scenarios.sh ║"
echo "║                                                                ║"
echo "║  KFP RAG Evaluation (optional compatibility):                  ║"
echo "║    Enable:  RUN_KFP_RAG_EVAL=true ./steps/step-08-model-evaluation/deploy.sh ║"
echo "║    Rerun:   ./steps/step-08-model-evaluation/run-rag-eval.sh   ║"
echo "║    Quick:   ./steps/step-08-model-evaluation/run-eval-report.sh║"
echo "║                                                                ║"
echo "║  Standard Benchmarks (on-demand):                              ║"
echo "║    CLI:     ./steps/step-08-model-evaluation/run-lmeval.sh granite-8b-agent ║"
echo "║    CLI:     ./steps/step-08-model-evaluation/run-lmeval.sh mistral-3-bf16   ║"
echo "║    Dashboard: Develop & train > Evaluations                    ║"
echo "║                                                                ║"
echo "║  Validate:                                                     ║"
echo "║    ./steps/step-08-model-evaluation/validate.sh                ║"
echo "║                                                                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
