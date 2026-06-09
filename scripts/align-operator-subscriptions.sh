#!/usr/bin/env bash
# Align live OperatorHub subscriptions with the RHOAI 3.4 / OCP 4.20 demo baseline.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/scripts/lib.sh"

MODE="${1:---apply}"
if [[ "$MODE" != "--apply" && "$MODE" != "--verify" ]]; then
    log_error "Usage: $0 [--apply|--verify]"
    exit 2
fi

load_env
RHOAI_EXPECTED_API_SERVER="${RHOAI_EXPECTED_API_SERVER:-cluster-5dmgr}"
check_oc_logged_in

APPLY="false"
if [[ "$MODE" == "--apply" ]]; then
    APPLY="true"
fi

log_step "Operator subscription alignment (${MODE#--})"

run_oc() {
    if [[ "$APPLY" == "true" ]]; then
        oc "$@"
    else
        printf 'oc'
        printf ' %q' "$@"
        printf '\n'
    fi
}

subscription_exists() {
    local namespace="$1" subscription="$2"
    oc get subscription "$subscription" -n "$namespace" &>/dev/null
}

align_subscription() {
    local namespace="$1"
    local subscription="$2"
    local channel="$3"
    local source="$4"
    local approval="$5"
    local starting_csv="${6:-}"
    local label="$7"
    local patch

    if ! subscription_exists "$namespace" "$subscription"; then
        log_warn "Subscription not found, skipping ${label}: ${subscription} in ${namespace}"
        return 0
    fi

    patch="{\"spec\":{\"channel\":\"${channel}\",\"source\":\"${source}\",\"sourceNamespace\":\"openshift-marketplace\",\"installPlanApproval\":\"${approval}\""
    if [[ -n "$starting_csv" ]]; then
        patch+=",\"startingCSV\":\"${starting_csv}\""
    fi
    patch+="}}"

    log_info "Aligning ${label}: ${namespace}/${subscription}"
    run_oc patch subscription "$subscription" -n "$namespace" --type merge -p "$patch"
}

delete_if_present() {
    local kind="$1" name="$2" namespace="$3" label="$4"

    if ! oc get "$kind" "$name" -n "$namespace" &>/dev/null; then
        return 0
    fi

    log_info "Deleting stale ${label}: ${kind}/${name} in ${namespace}"
    run_oc delete "$kind" "$name" -n "$namespace" --ignore-not-found --wait=false
}

cleanup_legacy_rhcl_dependency_stack() {
    log_step "Removing legacy standalone RHCL dependency subscriptions"

    delete_if_present subscription authorino-operator openshift-authorino "standalone Authorino subscription"
    delete_if_present csv authorino-operator.v1.3.1 openshift-authorino "standalone Authorino CSV"
    delete_if_present subscription limitador-operator openshift-limitador-operator "standalone Limitador subscription"
    delete_if_present csv limitador-operator.v1.3.1 openshift-limitador-operator "standalone Limitador CSV"
    delete_if_present subscription dns-operator openshift-dns-operator "standalone DNS Operator subscription"
    delete_if_present csv dns-operator.v1.3.1 openshift-dns-operator "standalone DNS Operator CSV"

    for namespace in openshift-authorino openshift-limitador-operator openshift-dns-operator; do
        if oc get namespace "$namespace" &>/dev/null; then
            log_info "Deleting stale legacy namespace: ${namespace}"
            run_oc delete namespace "$namespace" --ignore-not-found --wait=false
        fi
    done
}

approve_matching_installplans() {
    local namespace="$1"
    local pattern="$2"
    local plan approved csvs

    while IFS='|' read -r plan approved csvs; do
        [[ -z "$plan" || "$approved" == "true" ]] && continue
        if [[ "${csvs,,}" =~ $pattern ]]; then
            log_info "Approving install plan ${plan} in ${namespace} (${csvs})"
            run_oc patch installplan "$plan" -n "$namespace" --type merge -p '{"spec":{"approved":true}}'
        fi
    done < <(oc get installplan -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.approved}{"|"}{.spec.clusterServiceVersionNames}{"\n"}{end}' 2>/dev/null || true)
}

delete_stale_gitops_csv() {
    local current old_phase

    current="$(
        oc get csv -n openshift-operators --no-headers 2>/dev/null \
            | awk '$1 ~ /^openshift-gitops-operator\.v1\.20\./ {print $NF; exit}' \
            || true
    )"
    if [[ -z "$current" ]]; then
        log_warn "OpenShift GitOps v1.20.x CSV is not present yet; not deleting older GitOps CSVs"
        return 0
    fi

    old_phase="$(oc get csv openshift-gitops-operator.v1.15.4 -n openshift-operators -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ -n "$old_phase" ]]; then
        log_info "Deleting stale OpenShift GitOps v1.15 CSV after v1.20 CSV was found"
        run_oc delete csv openshift-gitops-operator.v1.15.4 -n openshift-operators --ignore-not-found --wait=false
    fi
}

align_service_mesh_side_effect() {
    local current starting installed phase

    if ! subscription_exists openshift-operators servicemeshoperator3; then
        log_warn "Service Mesh 3 subscription not found yet; RHOAI creates it after DSCI reconciliation"
        return 0
    fi

    current="$(oc get subscription servicemeshoperator3 -n openshift-operators -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)"
    starting="$(oc get subscription servicemeshoperator3 -n openshift-operators -o jsonpath='{.spec.startingCSV}' 2>/dev/null || true)"
    if [[ "$current" == servicemeshoperator3.v* && "$starting" != "$current" ]]; then
        log_info "Aligning Service Mesh 3 startingCSV from '${starting:-unset}' to '${current}'"
        run_oc patch subscription servicemeshoperator3 -n openshift-operators --type merge -p "{\"spec\":{\"startingCSV\":\"${current}\"}}"
    fi

    approve_matching_installplans openshift-operators "servicemeshoperator3"

    installed="$(oc get subscription servicemeshoperator3 -n openshift-operators -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
    if [[ -n "$installed" ]]; then
        phase="$(oc get csv "$installed" -n openshift-operators -o jsonpath='{.status.phase}' 2>/dev/null || true)"
        log_info "Service Mesh 3 installedCSV=${installed:-missing} phase=${phase:-missing}"
    fi
}

verify_subscription() {
    local namespace="$1" subscription="$2" expected_channel="$3" expected_source="$4" label="$5"
    local channel source installed phase

    if ! subscription_exists "$namespace" "$subscription"; then
        log_warn "Missing subscription: ${label} (${namespace}/${subscription})"
        return 0
    fi

    channel="$(oc get subscription "$subscription" -n "$namespace" -o jsonpath='{.spec.channel}' 2>/dev/null || true)"
    source="$(oc get subscription "$subscription" -n "$namespace" -o jsonpath='{.spec.source}' 2>/dev/null || true)"
    installed="$(oc get subscription "$subscription" -n "$namespace" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
    phase=""
    if [[ -n "$installed" ]]; then
        phase="$(oc get csv "$installed" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    fi

    if [[ "$channel" == "$expected_channel" && "$source" == "$expected_source" && "$phase" == "Succeeded" ]]; then
        log_success "${label}: ${installed} Succeeded"
    else
        log_warn "${label}: channel=${channel:-missing} source=${source:-missing} installedCSV=${installed:-missing} phase=${phase:-missing}"
    fi
}

align_subscription openshift-operators openshift-gitops-operator gitops-1.20 redhat-operators Automatic "" "OpenShift GitOps"
delete_stale_gitops_csv

align_subscription redhat-ods-operator rhods-operator stable-3.x redhat-operators Automatic "" "Red Hat OpenShift AI 3.4"

align_subscription openshift-nfd nfd stable redhat-operators Automatic "" "Node Feature Discovery"
align_subscription nvidia-gpu-operator gpu-operator-certified v25.10 certified-operators Automatic "" "NVIDIA GPU Operator"
align_subscription openshift-serverless serverless-operator stable-1.37 redhat-operators Automatic "" "OpenShift Serverless"
align_subscription openshift-cluster-observability-operator cluster-observability-operator stable redhat-operators Automatic "" "Cluster Observability Operator"
align_subscription openshift-tempo-operator tempo-product stable redhat-operators Automatic "" "Tempo Operator"
align_subscription openshift-opentelemetry-operator opentelemetry-product stable redhat-operators Automatic "" "Red Hat build of OpenTelemetry"
align_subscription openshift-kueue-operator kueue-operator stable-v1.3 redhat-operators Automatic "" "Red Hat build of Kueue"
align_subscription openshift-lws-operator leader-worker-set stable-v1.0 redhat-operators Automatic "" "Leader Worker Set"
align_subscription cert-manager-operator openshift-cert-manager-operator stable-v1 redhat-operators Automatic "" "cert-manager Operator"
align_subscription openshift-operators rhcl-operator stable redhat-operators-rhoai Automatic rhcl-operator.v1.3.4 "Red Hat Connectivity Link"

align_subscription openshift-operators authorino-operator-stable-redhat-operators-rhoai-openshift-marketplace stable redhat-operators-rhoai Automatic "" "RHCL Authorino dependency"
align_subscription openshift-operators limitador-operator-stable-redhat-operators-rhoai-openshift-marketplace stable redhat-operators-rhoai Automatic "" "RHCL Limitador dependency"
align_subscription openshift-operators dns-operator-stable-redhat-operators-rhoai-openshift-marketplace stable redhat-operators-rhoai Automatic "" "RHCL DNS dependency"

align_subscription grafana-operator grafana-operator v5 community-operators Automatic "" "Grafana Operator"
align_subscription openshift-operators openshift-pipelines-operator-rh pipelines-1.22 redhat-operators Manual "" "OpenShift Pipelines"

cleanup_legacy_rhcl_dependency_stack
repair_maas_authconfig_for_authorino_upgrade || true
approve_matching_installplans openshift-operators "rhcl-operator|authorino-operator|limitador-operator|dns-operator"
align_service_mesh_side_effect

log_step "Alignment summary"
verify_subscription openshift-operators openshift-gitops-operator gitops-1.20 redhat-operators "OpenShift GitOps"
verify_subscription redhat-ods-operator rhods-operator stable-3.x redhat-operators "Red Hat OpenShift AI"
verify_subscription openshift-operators rhcl-operator stable redhat-operators-rhoai "Red Hat Connectivity Link"
verify_subscription openshift-operators authorino-operator-stable-redhat-operators-rhoai-openshift-marketplace stable redhat-operators-rhoai "RHCL Authorino dependency"
verify_subscription openshift-operators limitador-operator-stable-redhat-operators-rhoai-openshift-marketplace stable redhat-operators-rhoai "RHCL Limitador dependency"
verify_subscription openshift-operators dns-operator-stable-redhat-operators-rhoai-openshift-marketplace stable redhat-operators-rhoai "RHCL DNS dependency"
verify_subscription openshift-serverless serverless-operator stable-1.37 redhat-operators "OpenShift Serverless"
verify_subscription openshift-kueue-operator kueue-operator stable-v1.3 redhat-operators "Red Hat build of Kueue"
verify_subscription openshift-cluster-observability-operator cluster-observability-operator stable redhat-operators "Cluster Observability Operator"
verify_subscription openshift-tempo-operator tempo-product stable redhat-operators "Tempo Operator"
verify_subscription openshift-opentelemetry-operator opentelemetry-product stable redhat-operators "Red Hat build of OpenTelemetry"

log_success "Operator subscription alignment pass complete"
