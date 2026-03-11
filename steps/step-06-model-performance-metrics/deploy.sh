#!/bin/bash
# Step 07: Model Performance Metrics - Deployment Script
# ============================================================================
# "The ROI of Quantization" - Comprehensive observability and benchmarking
#
# Components:
#   - Grafana with OpenShift User Workload Monitoring integration
#   - vLLM performance dashboards
#   - GuideLLM benchmarking with Poisson distribution
#
# Prerequisites:
#   - Step 01: User Workload Monitoring enabled
#   - Step 05: vLLM InferenceServices deployed
#
# Usage:
#   ./deploy.sh              # Direct deploy
#   ./deploy.sh --argocd     # Deploy via ArgoCD
#   ./deploy.sh --cleanup    # Remove all Step 07 resources
#   ./deploy.sh --benchmark  # Run ROI efficiency comparison
#   ./deploy.sh --validate   # Only validate, don't deploy
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NAMESPACE="private-ai"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Step 07: Model Performance Metrics${NC}"
echo -e "${CYAN}  \"The ROI of Quantization\" Demo${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"

# --- Cleanup Mode ---
if [ "$1" == "--cleanup" ]; then
    echo ""
    echo -e "${YELLOW}▶ Cleaning up Step 07 resources...${NC}"
    
    # Grafana resources
    oc delete deployment grafana -n ${NAMESPACE} --ignore-not-found
    oc delete service grafana -n ${NAMESPACE} --ignore-not-found
    oc delete route grafana -n ${NAMESPACE} --ignore-not-found
    oc delete configmap grafana-datasources grafana-dashboard-provisioner vllm-overview-dashboard -n ${NAMESPACE} --ignore-not-found
    oc delete serviceaccount grafana-sa -n ${NAMESPACE} --ignore-not-found
    oc delete clusterrolebinding grafana-cluster-monitoring-view --ignore-not-found
    
    # GuideLLM resources
    oc delete cronjob guidellm-daily -n ${NAMESPACE} --ignore-not-found
    oc delete configmap guidellm-scripts -n ${NAMESPACE} --ignore-not-found
    oc delete pvc guidellm-results -n ${NAMESPACE} --ignore-not-found
    oc delete job -l app=guidellm -n ${NAMESPACE} --ignore-not-found
    
    # ArgoCD Application
    oc delete application step-06-model-performance-metrics -n openshift-gitops --ignore-not-found
    
    echo -e "${GREEN}  ✓ Cleanup complete${NC}"
    exit 0
fi

# --- Benchmark Mode ---
if [ "$1" == "--benchmark" ]; then
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Running ROI Efficiency Comparison (Poisson Stress Test)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    
    # Check which models are available
    echo ""
    echo -e "${YELLOW}▶ Checking model availability...${NC}"
    
    AVAILABLE_MODELS=""
    for model in mistral-3-int4 mistral-3-bf16 granite-8b-agent devstral-2 gpt-oss-20b; do
        ISVC_READY=$(oc get inferenceservice ${model} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        if [ "${ISVC_READY}" == "True" ]; then
            echo -e "${GREEN}  ✓ ${model} is Ready${NC}"
            AVAILABLE_MODELS="${AVAILABLE_MODELS} ${model}"
        else
            echo -e "${YELLOW}  ⚠️  ${model} is not Ready (skipping)${NC}"
        fi
    done
    
    if [ -z "${AVAILABLE_MODELS}" ]; then
        echo -e "${RED}❌ No models available for benchmarking${NC}"
        exit 1
    fi
    
    # Create benchmark job
    JOB_NAME="roi-comparison-$(date +%Y%m%d-%H%M)"
    echo ""
    echo -e "${YELLOW}▶ Creating benchmark job: ${JOB_NAME}${NC}"
    
    if oc get cronjob guidellm-daily -n ${NAMESPACE} &>/dev/null; then
        oc create job ${JOB_NAME} --from=cronjob/guidellm-daily -n ${NAMESPACE}
        
        echo ""
        echo -e "${YELLOW}▶ Watching benchmark progress (Ctrl+C to stop watching)...${NC}"
        oc logs -f job/${JOB_NAME} -n ${NAMESPACE} || true
        
        echo ""
        echo -e "${GREEN}▶ Benchmark job completed. View results in Grafana or:${NC}"
        echo -e "  oc logs job/${JOB_NAME} -n ${NAMESPACE}"
    else
        echo -e "${RED}❌ GuideLLM CronJob not found. Deploy Step 07 first.${NC}"
        exit 1
    fi
    exit 0
fi

# --- Validate Only Mode ---
VALIDATE_ONLY=false
if [ "$1" == "--validate" ]; then
    VALIDATE_ONLY=true
fi

# --- Pre-flight Checks ---
echo ""
echo -e "${YELLOW}▶ Pre-flight Checks...${NC}"

# Check oc login
if ! oc whoami &>/dev/null; then
    echo -e "${RED}❌ Not logged in to OpenShift. Please run 'oc login' first.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Logged in as $(oc whoami)${NC}"

# Check admin access (needed for ClusterRoleBinding)
if ! oc auth can-i create clusterrolebinding &>/dev/null; then
    echo -e "${RED}❌ Cluster admin access required for ClusterRoleBinding.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Cluster admin access verified${NC}"

# Check User Workload Monitoring
if ! oc get cm cluster-monitoring-config -n openshift-monitoring -o yaml 2>/dev/null | grep -q "enableUserWorkload: true"; then
    echo -e "${YELLOW}  ⚠️  User Workload Monitoring may not be enabled${NC}"
else
    echo -e "${GREEN}  ✓ User Workload Monitoring enabled${NC}"
fi

# Check namespace exists
if ! oc get namespace ${NAMESPACE} &>/dev/null; then
    echo -e "${RED}❌ Namespace '${NAMESPACE}' not found. Run Step 03 first.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Namespace '${NAMESPACE}' exists${NC}"

# Check for vLLM InferenceServices
ISVC_COUNT=$(oc get inferenceservice -n ${NAMESPACE} --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${ISVC_COUNT}" -eq 0 ]; then
    echo -e "${YELLOW}  ⚠️  No InferenceServices found. Deploy models from Step 05 first.${NC}"
else
    echo -e "${GREEN}  ✓ Found ${ISVC_COUNT} InferenceService(s)${NC}"
fi

# Check ROI comparison models specifically
echo ""
echo -e "${YELLOW}  ROI Comparison Models (The Business Story):${NC}"
for model in mistral-3-int4 mistral-3-bf16; do
    ISVC_READY=$(oc get inferenceservice ${model} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [ "${ISVC_READY}" == "True" ]; then
        echo -e "    ${GREEN}✓ ${model} is Ready${NC}"
    elif oc get inferenceservice ${model} -n ${NAMESPACE} &>/dev/null; then
        echo -e "    ${YELLOW}⚠️  ${model} exists but not Ready${NC}"
    else
        echo -e "    ${YELLOW}⚠️  ${model} not found${NC}"
    fi
done

# Check for ServiceMonitors
SERVICEMONITORS=$(oc get servicemonitor -n ${NAMESPACE} -o name 2>/dev/null | grep -c "metrics" || echo "0")
if [ "${SERVICEMONITORS}" -eq 0 ]; then
    echo -e "${YELLOW}  ⚠️  No vLLM ServiceMonitors found (auto-created with InferenceServices)${NC}"
else
    echo -e "${GREEN}  ✓ Found ${SERVICEMONITORS} vLLM ServiceMonitor(s)${NC}"
fi

# Validate kustomize build
echo ""
echo -e "${YELLOW}▶ Validating Kustomize build...${NC}"
if ! kustomize build "${PROJECT_ROOT}/gitops/step-06-model-performance-metrics/base" > /dev/null 2>&1; then
    echo -e "${RED}❌ Kustomize build failed${NC}"
    kustomize build "${PROJECT_ROOT}/gitops/step-06-model-performance-metrics/base"
    exit 1
fi
echo -e "${GREEN}  ✓ Kustomize build validated${NC}"

if [ "${VALIDATE_ONLY}" == "true" ]; then
    echo ""
    echo -e "${GREEN}✓ Validation complete. Use ./deploy.sh to deploy.${NC}"
    exit 0
fi

# --- Deployment ---
echo ""
echo -e "${YELLOW}▶ Deploying Step 07 components...${NC}"

if [ "$1" == "--argocd" ]; then
    echo "  Deploying via ArgoCD..."
    oc apply -f "${PROJECT_ROOT}/gitops/argocd/app-of-apps/step-06-model-performance-metrics.yaml"
    echo -e "${GREEN}  ✓ ArgoCD Application created${NC}"
    echo ""
    echo "  Waiting for sync..."
    sleep 10
    oc wait --for=condition=Healthy application/step-06-model-performance-metrics -n openshift-gitops --timeout=120s || true
else
    echo "  Applying Kustomize manifests..."
    oc apply -k "${PROJECT_ROOT}/gitops/step-06-model-performance-metrics/base"
    echo -e "${GREEN}  ✓ Manifests applied${NC}"
fi

# --- Wait for Deployments ---
echo ""
echo -e "${YELLOW}▶ Waiting for deployments...${NC}"

echo "  Grafana..."
oc rollout status deployment/grafana -n ${NAMESPACE} --timeout=120s 2>/dev/null || echo "  (still starting...)"

# --- Validation ---
echo ""
echo -e "${YELLOW}▶ Validation...${NC}"

# Get Grafana URL
GRAFANA_URL=$(oc get route grafana -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "${GRAFANA_URL}" ]; then
    echo -e "${GREEN}  ✓ Grafana Route: https://${GRAFANA_URL}${NC}"
else
    echo -e "${YELLOW}  ⚠️  Grafana Route not found${NC}"
fi

# Check health endpoint
if [ -n "${GRAFANA_URL}" ]; then
    echo ""
    echo "  Checking Grafana health..."
    sleep 5
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${GRAFANA_URL}/api/health" 2>/dev/null || echo "000")
    if [ "${HTTP_CODE}" == "200" ]; then
        echo -e "${GREEN}  ✓ Grafana is healthy (HTTP 200)${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Grafana health check returned HTTP ${HTTP_CODE}${NC}"
    fi
fi

# Check GuideLLM components
echo ""
echo -e "${YELLOW}▶ Checking GuideLLM components (Poisson distribution)...${NC}"

if oc get cronjob guidellm-daily -n ${NAMESPACE} &>/dev/null; then
    SCHEDULE=$(oc get cronjob guidellm-daily -n ${NAMESPACE} -o jsonpath='{.spec.schedule}')
    echo -e "${GREEN}  ✓ GuideLLM CronJob: ${SCHEDULE}${NC}"
else
    echo -e "${YELLOW}  ⚠️  GuideLLM CronJob not found${NC}"
fi

if oc get pvc guidellm-results -n ${NAMESPACE} &>/dev/null; then
    PVC_STATUS=$(oc get pvc guidellm-results -n ${NAMESPACE} -o jsonpath='{.status.phase}')
    echo -e "${GREEN}  ✓ GuideLLM PVC: ${PVC_STATUS}${NC}"
else
    echo -e "${YELLOW}  ⚠️  GuideLLM PVC not found${NC}"
fi

if oc get configmap guidellm-scripts -n ${NAMESPACE} &>/dev/null; then
    echo -e "${GREEN}  ✓ GuideLLM Scripts ConfigMap (ROI comparison scripts included)${NC}"
else
    echo -e "${YELLOW}  ⚠️  GuideLLM Scripts ConfigMap not found${NC}"
fi

# --- Summary ---
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}  🎯 The 'ROI of Quantization' Demo:${NC}"
echo ""
echo -e "  ${GREEN}Access URLs:${NC}"
echo "     Grafana Dashboard:   https://${GRAFANA_URL}"
echo ""
echo -e "  ${GREEN}Demo Flow:${NC}"
echo "     1. Open Grafana - view vLLM performance metrics"
echo "     2. Run ROI benchmark: ./deploy.sh --benchmark"
echo "     3. Observe saturation points in Grafana"
echo ""
echo -e "  ${GREEN}Quick Commands:${NC}"
echo "     # Run ROI efficiency comparison"
echo "     ./deploy.sh --benchmark"
echo ""
echo "     # Manual benchmark job"
echo "     oc create job --from=cronjob/guidellm-daily test-\$(date +%H%M) -n ${NAMESPACE}"
echo ""
echo "     # View benchmark results"
echo "     oc logs -f job/<job-name> -n ${NAMESPACE}"
echo ""
echo -e "  ${GREEN}SLA Targets:${NC}"
echo "     TTFT: < 1.0s (acceptable), < 500ms (excellent)"
echo "     TPOT: > 20 tokens/sec"
echo "     KV Cache: < 85% (warning at 95%)"
echo ""
echo -e "  ${GREEN}Additional Monitoring:${NC}"
echo "     • GPU Metrics: OpenShift Console → Observe → Dashboards → NVIDIA DCGM"
echo "     • Raw Metrics: OpenShift Console → Observe → Metrics"
echo ""
echo -e "  📚 Documentation: steps/step-06-model-performance-metrics/README.md"
echo ""
