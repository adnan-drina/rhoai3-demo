#!/usr/bin/env bash
# Pre-merge documentation and product-alignment audit for GitOps-managed demo components.
#
# The audit requires live access to the target OpenShift cluster. It renders
# Kustomize bases, checks for stale product-version references, verifies schemas
# against the live API server, and writes a durable evidence ledger. It does not
# produce offline fallback evidence.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BASE_REF="origin/main"
COMPONENT=""
ORIGINAL_ARGS="$*"
LEDGER_PATH="$REPO_ROOT/docs/alignment-evidence-ledger.md"
RH_BRAIN_DIR="${RH_BRAIN_DIR:-/Users/adrina/Sandbox/rh-brain/Red Hat Brain}"
STRICT_CLUSTER="${AUDIT_STRICT_CLUSTER:-true}"
OC_REQUEST_TIMEOUT="${OC_REQUEST_TIMEOUT:-5s}"
OC_SERVER_DRY_RUN_TIMEOUT_SECONDS="${OC_SERVER_DRY_RUN_TIMEOUT_SECONDS:-90}"

RHOAI_DOCS="https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/"
RHOAI_RELEASE_NOTES="https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/release_notes/index"
OCP_DOCS="https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/"

usage() {
    cat <<EOF
Usage:
  ./scripts/audit-doc-alignment.sh [--base <git-ref>] [--component <component-name>]

Examples:
  ./scripts/audit-doc-alignment.sh --base origin/main
  ./scripts/audit-doc-alignment.sh --component step-05-maas-model-serving

Environment:
  RH_BRAIN_DIR=/path/to/rh-brain/Red Hat Brain
  AUDIT_STRICT_CLUSTER=true   # fail when live schema checks fail; default true
  OC_REQUEST_TIMEOUT=5s       # timeout for live oc whoami/explain checks
  OC_SERVER_DRY_RUN_TIMEOUT_SECONDS=90
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base)
            BASE_REF="${2:-}"
            shift 2
            ;;
        --component)
            COMPONENT="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

cd "$REPO_ROOT"

if [[ -z "${RHOAI_EXPECTED_API_SERVER:-}" && -f "$REPO_ROOT/.env" ]]; then
    RHOAI_EXPECTED_API_SERVER="$(
        awk -F= '$1 == "RHOAI_EXPECTED_API_SERVER" { print $2; exit }' "$REPO_ROOT/.env"
    )"
fi
EXPECTED_API_SERVER="${RHOAI_EXPECTED_API_SERVER:-${RHOAI_EXPECTED_CLUSTER:-}}"

canonical_component() {
    local component="$1"
    case "$component" in
        step-03-private-ai) echo "step-03-enterprise-projects" ;;
        step-05-llm-on-vllm) echo "step-05-maas-model-serving" ;;
        *) echo "$component" ;;
    esac
}

if [[ -n "$COMPONENT" ]]; then
    COMPONENT="$(canonical_component "$COMPONENT")"
fi

if [[ -n "$COMPONENT" && ! -d "gitops/$COMPONENT" && ! -f "gitops/argocd/app-of-apps/$COMPONENT.yaml" ]]; then
    echo "Unknown component: $COMPONENT" >&2
    exit 2
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

changed_files="$tmp_dir/changed-files.txt"
components="$tmp_dir/components.txt"
audit_components="$tmp_dir/audit-components.txt"
touch "$changed_files" "$components" "$audit_components"

add_unique() {
    local value="$1" file="$2"
    [[ -z "$value" ]] && return 0
    grep -qxF "$value" "$file" 2>/dev/null || echo "$value" >> "$file"
}

component_from_path() {
    local path="$1"
    case "$path" in
        gitops/argocd/app-of-apps/step-*.yaml)
            basename "$path" .yaml
            ;;
        gitops/step-*/base/*|gitops/step-*/*)
            printf '%s\n' "$path" | cut -d/ -f2
            ;;
        steps/step-*/*)
            printf '%s\n' "$path" | cut -d/ -f2
            ;;
        gitops/edge-ai-microshift/*)
            printf '%s\n' "edge-ai-microshift"
            ;;
    esac
}

dependencies_for() {
    local component="$1"
    case "$component" in
        step-01-*) ;;
        step-02-*) echo "step-01-gpu-and-prereq" ;;
        step-03-*) echo "step-01-gpu-and-prereq"; echo "step-02-rhoai" ;;
        step-04-*) echo "step-01-gpu-and-prereq"; echo "step-02-rhoai"; echo "step-03-enterprise-projects" ;;
        step-05-*) echo "step-01-gpu-and-prereq"; echo "step-02-rhoai"; echo "step-03-enterprise-projects"; echo "step-04-model-registry" ;;
        step-06-*) echo "step-01-gpu-and-prereq"; echo "step-05-maas-model-serving" ;;
        step-07-*) echo "step-01-gpu-and-prereq"; echo "step-02-rhoai"; echo "step-03-enterprise-projects"; echo "step-04-model-registry"; echo "step-05-maas-model-serving" ;;
        step-08-*) echo "step-07-rag" ;;
        step-09-*) echo "step-02-rhoai"; echo "step-05-maas-model-serving" ;;
        step-10-*) echo "step-05-maas-model-serving"; echo "step-07-rag"; echo "step-09-guardrails" ;;
        step-11-*) echo "step-01-gpu-and-prereq"; echo "step-02-rhoai"; echo "step-03-enterprise-projects" ;;
        step-12-*) echo "step-03-enterprise-projects"; echo "step-04-model-registry"; echo "step-07-rag"; echo "step-11-face-recognition" ;;
        step-13-*) echo "step-11-face-recognition"; echo "step-12-mlops-pipeline" ;;
        step-13b-*) echo "step-11-face-recognition"; echo "step-12-mlops-pipeline" ;;
        edge-ai-microshift) echo "step-13b-edge-ai-microshift" ;;
    esac
}

gitops_path_for() {
    local component="$1"
    if [[ "$component" == "step-13b-edge-ai-microshift-operator" ]]; then
        printf 'gitops/step-13b-edge-ai-microshift/operator\n'
    elif [[ -d "gitops/$component/base" ]]; then
        printf 'gitops/%s/base\n' "$component"
    elif [[ -d "gitops/$component" ]]; then
        printf 'gitops/%s\n' "$component"
    else
        printf '\n'
    fi
}

readme_path_for() {
    local component="$1"
    if [[ "$component" == "step-13b-edge-ai-microshift-operator" ]]; then
        printf 'steps/step-13b-edge-ai-microshift/README.md\n'
    elif [[ -f "steps/$component/README.md" ]]; then
        printf 'steps/%s/README.md\n' "$component"
    else
        printf '\n'
    fi
}

app_path_for() {
    local component="$1"
    if [[ -f "gitops/argocd/app-of-apps/$component.yaml" ]]; then
        printf 'gitops/argocd/app-of-apps/%s.yaml\n' "$component"
    else
        printf '\n'
    fi
}

run_kustomize() {
    local path="$1"
    if command -v kustomize >/dev/null 2>&1; then
        kustomize build "$path"
    elif command -v oc >/dev/null 2>&1; then
        oc kustomize "$path"
    else
        echo "Neither kustomize nor oc is available for rendering $path" >&2
        return 127
    fi
}

oc_cluster_available() {
    local server
    command -v oc >/dev/null 2>&1 || return 1
    oc --request-timeout="$OC_REQUEST_TIMEOUT" whoami >/dev/null 2>&1 || return 1
    server="$(oc --request-timeout="$OC_REQUEST_TIMEOUT" whoami --show-server 2>/dev/null || true)"
    if [[ -n "$EXPECTED_API_SERVER" && "$server" != *"$EXPECTED_API_SERVER"* ]]; then
        echo "ERROR: OpenShift API server guard failed" >&2
        echo "  expected: $EXPECTED_API_SERVER" >&2
        echo "  actual:   $server" >&2
        return 42
    fi
    OC_CLUSTER_SERVER="$server"
}

oc_explain_kind() {
    local kind="$1" api="$2"
    oc --request-timeout="$OC_REQUEST_TIMEOUT" explain "$kind" --api-version="$api" >/dev/null 2>&1
}

oc_server_dry_run() {
    local rendered_file="$1" err_file="${2:-/dev/null}"
    python3 - "$OC_REQUEST_TIMEOUT" "$OC_SERVER_DRY_RUN_TIMEOUT_SECONDS" "$rendered_file" "$err_file" <<'PY'
import subprocess
import sys

request_timeout, timeout_seconds, rendered_file, err_file = sys.argv[1:5]
cmd = [
    "oc",
    f"--request-timeout={request_timeout}",
    "apply",
    "--dry-run=server",
    "--validate=strict",
    "-f",
    rendered_file,
]

with open(err_file, "wb") as stderr:
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=stderr,
            timeout=int(timeout_seconds),
            check=False,
        )
    except subprocess.TimeoutExpired:
        stderr.write(
            f"oc server dry-run timed out after {timeout_seconds}s\n".encode()
        )
        sys.exit(124)

sys.exit(result.returncode)
PY
}

dry_run_missing_declared_namespaces() {
    local rendered_file="$1" err_file="$2"
    python3 - "$rendered_file" "$err_file" <<'PY'
import re
import sys
from pathlib import Path

rendered = Path(sys.argv[1]).read_text()
err = Path(sys.argv[2]).read_text()

declared_namespaces = set()
for doc in re.split(r"\n---\s*\n", rendered):
    if not re.search(r"(?m)^kind:\s*Namespace\s*$", doc):
        continue
    match = re.search(
        r"(?m)^metadata:\s*\n(?:^[ \t].*\n)*?^[ \t]{2}name:\s*([^\s#]+)",
        doc,
    )
    if match:
        declared_namespaces.add(match.group(1).strip("\"'"))

missing_namespaces = re.findall(r'namespaces "([^"]+)" not found', err)
remaining = re.sub(
    r'Error from server \(NotFound\): error when (?:creating|patching) "[^"]+": namespaces "[^"]+" not found\n?',
    "",
    err,
).strip()

if missing_namespaces and set(missing_namespaces) <= declared_namespaces and not remaining:
    print(", ".join(sorted(set(missing_namespaces))))
    sys.exit(0)

sys.exit(1)
PY
}

latest_image_classification() {
    local image="$1"
    case "$image" in
        registry.redhat.io/rhel9/postgresql-*:*|registry.redhat.io/rhel9/mariadb-*:*|registry.redhat.io/ubi9/*:*|registry.access.redhat.com/ubi9/*:*)
            echo "Red Hat managed version stream"
            ;;
        image-registry.openshift-image-registry.svc:5000/openshift/*:*)
            echo "OpenShift platform ImageStream"
            ;;
        image-registry.openshift-image-registry.svc:5000/enterprise-rag/*:*|quay.io/adrina/edge-camera:*)
            echo "internal demo build output"
            ;;
        *)
            echo "unmanaged external dependency"
            ;;
    esac
}

app_ignores_pvc_spec() {
    local app_path="$1"
    [[ -n "$app_path" && -f "$app_path" ]] || return 1
    grep -q 'kind: PersistentVolumeClaim' "$app_path" && grep -q '/spec' "$app_path"
}

is_pvc_immutable_drift() {
    local err_file="$1"
    [[ -s "$err_file" ]] || return 1
    grep -q 'PersistentVolumeClaim' "$err_file" \
        && grep -q 'spec is immutable after creation except resources.requests and volumeAttributesClassName for bound claims' "$err_file" \
        && ! grep -Eq 'strict decoding error|unknown field|no matches for kind' "$err_file"
}

rh_brain_terms_for() {
    local component="$1"
    case "$component" in
        step-05-*|step-06-*) echo "Models-as-a-Service"; echo "llm-d"; echo "vLLM" ;;
        step-07-*) echo "RAG"; echo "AutoRAG"; echo "evaluation" ;;
        step-08-*) echo "RAG"; echo "AutoRAG"; echo "evaluation"; echo "EvalHub"; echo "MLflow" ;;
        step-09-*) echo "guardrails"; echo "AI safety" ;;
        step-10-*) echo "MCP"; echo "agentic" ;;
        step-11-*|step-12-*) echo "MLflow"; echo "MLOps"; echo "predictive AI" ;;
        step-13-*|step-13b-*|edge-ai-microshift) echo "edge AI"; echo "MicroShift" ;;
        *) echo "OpenShift AI" ;;
    esac
}

find_rh_brain_sources() {
    local component="$1" count=0 term
    [[ -d "$RH_BRAIN_DIR" ]] || return 0
    while IFS= read -r term; do
        [[ -z "$term" ]] && continue
        while IFS= read -r source; do
            [[ -z "$source" ]] && continue
            printf '%s\n' "${source#$RH_BRAIN_DIR/}"
            count=$((count + 1))
            [[ $count -ge 4 ]] && return 0
        done < <(find "$RH_BRAIN_DIR/wiki" "$RH_BRAIN_DIR/raw" -type f -iname "*$term*.md" 2>/dev/null | sort | head -2)
    done < <(rh_brain_terms_for "$component")
    return 0
}

component_extra_findings() {
    local component="$1"
    case "$component" in
        step-02-rhoai)
            if grep -q 'termination: reencrypt' gitops/step-02-rhoai/base/rhoai-operator/maas-gateway-route.yaml \
                && grep -q 'configure_maas_gateway_route' steps/step-02-rhoai/deploy.sh \
                && grep -q '/spec/tls/destinationCACertificate' gitops/argocd/app-of-apps/step-02-rhoai.yaml; then
                cat <<'EOF'
- [PASS] MaaS gateway Route uses re-encrypt TLS and deploy-time product host/CA reconciliation for dashboard BFF discovery.
- [PASS] Argo CD ignores only the MaaS Route host and backend CA, preserving cluster-specific values while keeping the route GitOps-managed.
EOF
            fi
            ;;
        step-05-maas-model-serving)
            if grep -q 'configure_maas_gateway_route' steps/step-05-maas-model-serving/deploy.sh \
                && grep -q 'api/v1/maas/models' steps/step-05-maas-model-serving/validate.sh \
                && grep -q '/v1/models' steps/step-05-maas-model-serving/validate.sh; then
                cat <<'EOF'
- [PASS] MaaS model-serving deployment retries gateway product-host reconciliation before publishing model references.
- [PASS] MaaS validation checks the public `/v1/models` API and GenAI AI asset MaaS BFF API list both published demo models.
EOF
            fi
            ;;
        step-07-rag)
            if grep -q '"use_case"' gitops/step-07-rag/base/chatbot/chatbot.yaml \
                && grep -q 'loadExamplePrompts' scripts/validate-chatbot-ui.sh; then
                cat <<'EOF'
- [PASS] Chatbot example prompts are GitOps-managed in `RAG_QUESTION_SUGGESTIONS` and grouped by RAG/MCP use case.
- [PASS] Browser validation reads the deployed example prompt configuration and exercises each non-side-effect example prompt.
- [PASS] Direct RAG examples cover `whoami` identity, expertise, and event discovery.
- [PASS] Direct RAG examples cover `acme_corporate` corporate profile and L-900 equipment troubleshooting.
- [PASS] Agent examples cover OpenShift MCP pod listing and database MCP asset lookup.
- [PASS] Slack-send prompts are excluded from the chatbot regression set to avoid external side effects; Step 10 keeps the Slack MCP path.
EOF
            fi
            ;;
    esac
}

collect_changed_files() {
    if [[ -n "$COMPONENT" ]]; then
        return 0
    fi

    if git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
        git diff --name-only "$BASE_REF"...HEAD >> "$changed_files" || true
    else
        echo "WARN: base ref '$BASE_REF' is not available; using working-tree changes only." >&2
    fi

    git diff --name-only >> "$changed_files" || true
    git diff --cached --name-only >> "$changed_files" || true
    git ls-files --others --exclude-standard >> "$changed_files" || true
    sort -u "$changed_files" -o "$changed_files"
}

collect_changed_files

if [[ -n "$COMPONENT" ]]; then
    add_unique "$COMPONENT" "$components"
else
    while IFS= read -r path; do
        component="$(component_from_path "$path" || true)"
        component="$(canonical_component "$component")"
        add_unique "$component" "$components"
    done < "$changed_files"
fi

while IFS= read -r component; do
    add_unique "$component" "$audit_components"
    while IFS= read -r dependency; do
        add_unique "$dependency" "$audit_components"
    done < <(dependencies_for "$component")
done < "$components"

if [[ -s "$audit_components" && -f "$LEDGER_PATH" ]]; then
    # Audits should not discard unrelated evidence that is already in the
    # committed ledger. Refresh existing component sections as well until
    # section-level replacement is implemented.
    while IFS= read -r existing_component; do
        add_unique "$existing_component" "$audit_components"
    done < <(awk '/^### / { print $2 }' "$LEDGER_PATH")
fi

sort -u "$audit_components" -o "$audit_components"

ledger_tmp="$tmp_dir/alignment-evidence-ledger.md"
blocked_total=0
warning_total=0
OC_CLUSTER_AVAILABLE=false
OC_CLUSTER_SERVER=""

if oc_cluster_available; then
    OC_CLUSTER_AVAILABLE=true
else
    status=$?
    echo "ERROR: live OpenShift cluster access is required; no offline fallback is available." >&2
    exit "$status"
fi

{
    echo "# Documentation Alignment Evidence Ledger"
    echo ""
    echo "**Generated:** $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "**Command:** \`$0 $ORIGINAL_ARGS\`"
    echo "**Base ref:** \`$BASE_REF\`"
    echo "**Docs baseline:** RHOAI 3.4 / OCP 4.20"
    echo "**Live cluster:** \`${OC_CLUSTER_SERVER:-unknown}\`"
    echo "**rh-brain source:** \`$RH_BRAIN_DIR\`"
    echo ""
    echo "This ledger is produced by \`scripts/audit-doc-alignment.sh\`. Official product documentation is the source of truth for supported configuration. \`rh-brain\` is read-only research input for narrative and Red Hat article alignment."
    echo ""
    echo "## Baseline References"
    echo ""
    echo "- [Red Hat OpenShift AI Self-Managed 3.4]($RHOAI_DOCS)"
    echo "- [RHOAI 3.4 Release Notes]($RHOAI_RELEASE_NOTES)"
    echo "- [OpenShift Container Platform 4.20]($OCP_DOCS)"
    echo ""
} > "$ledger_tmp"

if [[ ! -s "$audit_components" ]]; then
    {
        echo "## Audit Result"
        echo ""
        echo "No GitOps-managed step components were detected in the current diff."
        echo ""
        echo "| Status | Decision |"
        echo "|--------|----------|"
        echo "| aligned | No component-level evidence refresh required for this branch. |"
    } >> "$ledger_tmp"
else
    {
        echo "## Component Evidence"
        echo ""
    } >> "$ledger_tmp"
fi

while IFS= read -r component; do
    [[ -z "$component" ]] && continue

    gitops_path="$(gitops_path_for "$component")"
    readme_path="$(readme_path_for "$component")"
    app_path="$(app_path_for "$component")"
    rendered="$tmp_dir/$component.rendered.yaml"
    findings="$tmp_dir/$component.findings.txt"
    schema="$tmp_dir/$component.schema.txt"
    rh_sources="$tmp_dir/$component.rh-brain.txt"
    blocked=0
    warnings=0
    touch "$findings" "$schema" "$rh_sources"

    if [[ -z "$gitops_path" ]]; then
        echo "- [BLOCKED] No GitOps path found for component \`$component\`." >> "$findings"
        blocked=$((blocked + 1))
    elif [[ -f "$gitops_path/kustomization.yaml" ]]; then
        if run_kustomize "$gitops_path" > "$rendered" 2>"$tmp_dir/$component.kustomize.err"; then
            echo "- [PASS] \`kustomize build $gitops_path\` rendered successfully." >> "$findings"
        else
            echo "- [BLOCKED] \`kustomize build $gitops_path\` failed." >> "$findings"
            sed 's/^/  /' "$tmp_dir/$component.kustomize.err" >> "$findings"
            blocked=$((blocked + 1))
        fi
    else
        echo "- [WARN] No kustomization found at \`$gitops_path\`." >> "$findings"
        warnings=$((warnings + 1))
    fi

    stale_matches="$tmp_dir/$component.stale.txt"
    touch "$stale_matches"
    for path in "$gitops_path" "$readme_path" "$app_path"; do
        [[ -n "$path" && -e "$path" ]] || continue
        grep -RInE 'RHOAI 3\.3|OpenShift AI 3\.3|red_hat_openshift_ai_self-managed/3\.3' "$path" >> "$stale_matches" 2>/dev/null || true
    done
    if [[ -s "$stale_matches" ]]; then
        echo "- [BLOCKED] Stale RHOAI 3.3 reference found in component evidence scope:" >> "$findings"
        sed 's/^/  - /' "$stale_matches" >> "$findings"
        blocked=$((blocked + 1))
    else
        echo "- [PASS] No stale RHOAI 3.3 references found in component GitOps/README scope." >> "$findings"
    fi

    if [[ -n "$readme_path" ]]; then
        if grep -Eq 'docs\.redhat\.com/.*/(red_hat_openshift_ai_self-managed/3\.4|openshift_container_platform/4\.20|red_hat_build_of_microshift/4\.20)' "$readme_path"; then
            echo "- [PASS] README contains pinned official product documentation references." >> "$findings"
        else
            echo "- [WARN] README does not contain a pinned RHOAI 3.4/OCP 4.20 documentation reference." >> "$findings"
            warnings=$((warnings + 1))
        fi
    else
        echo "- [WARN] No step README found for \`$component\`." >> "$findings"
        warnings=$((warnings + 1))
    fi

    latest_matches="$tmp_dir/$component.latest-images.txt"
    latest_allowed="$tmp_dir/$component.latest-images.allowed.txt"
    latest_unmanaged="$tmp_dir/$component.latest-images.unmanaged.txt"
    touch "$latest_matches" "$latest_allowed" "$latest_unmanaged"
    if [[ -n "$gitops_path" && -e "$gitops_path" ]]; then
        grep -RInE 'image:[[:space:]]+[^#]*:latest([[:space:]]|$)' "$gitops_path" >> "$latest_matches" 2>/dev/null || true
    fi
    if [[ -s "$latest_matches" ]]; then
        while IFS= read -r latest_line; do
            image="$(sed -E 's/^.*image:[[:space:]]+([^[:space:]#]+).*$/\1/' <<< "$latest_line")"
            classification="$(latest_image_classification "$image")"
            if [[ "$classification" == "unmanaged external dependency" ]]; then
                echo "$latest_line ($classification)" >> "$latest_unmanaged"
            else
                echo "$latest_line ($classification)" >> "$latest_allowed"
            fi
        done < "$latest_matches"

        if [[ -s "$latest_unmanaged" ]]; then
            echo "- [WARN] Unmanaged external \`:latest\` image references found:" >> "$findings"
            sed 's/^/  - /' "$latest_unmanaged" >> "$findings"
            warnings=$((warnings + 1))
        fi
        if [[ -s "$latest_allowed" ]]; then
            echo "- [PASS] Managed or internal \`:latest\` image references are classified and accepted:" >> "$findings"
            sed 's/^/  - /' "$latest_allowed" >> "$findings"
        fi
    else
        echo "- [PASS] No unpinned \`:latest\` image references found in GitOps path." >> "$findings"
    fi

    component_extra_findings "$component" >> "$findings"

    if [[ -s "$rendered" ]]; then
        awk '
            /^apiVersion:/ { api=$2 }
            /^kind:/ { kind=$2; if (api != "" && kind != "") print api "|" kind }
        ' "$rendered" | sort -u > "$tmp_dir/$component.kinds"

        if [[ "$OC_CLUSTER_AVAILABLE" == "true" ]]; then
            dry_run_err="$tmp_dir/$component.server-dry-run.err"
            if oc_server_dry_run "$rendered" "$dry_run_err"; then
                echo "- [PASS] \`oc apply --dry-run=server --validate=strict -f rendered.yaml\` accepted rendered resources." >> "$schema"
            else
                if is_pvc_immutable_drift "$dry_run_err" && app_ignores_pvc_spec "$app_path"; then
                    echo "- [WARN] Server dry-run reported existing PVC immutable spec drift, but the matching Argo CD app intentionally ignores PVC \`/spec\`." >> "$schema"
                    echo "  Exact warning:" >> "$schema"
                    awk '{ gsub(/\t/, "    "); sub(/[[:space:]]+$/, ""); print ($0 == "" ? "" : "  " $0) }' "$dry_run_err" >> "$schema"
                    warnings=$((warnings + 1))
                elif missing_namespaces="$(dry_run_missing_declared_namespaces "$rendered" "$dry_run_err" 2>/dev/null)"; then
                    echo "- [WARN] Server dry-run reached the live API, but Kubernetes cannot dry-run namespaced resources before namespaces declared in the same render exist on the cluster: \`${missing_namespaces}\`." >> "$schema"
                    echo "  Argo CD creates these namespaces during sync; live \`oc explain\` checks below verify the rendered schemas against the current cluster API." >> "$schema"
                    warnings=$((warnings + 1))
                elif [[ "$STRICT_CLUSTER" == "true" ]]; then
                    echo "- [BLOCKED] \`oc apply --dry-run=server --validate=strict -f rendered.yaml\` failed." >> "$schema"
                    awk '{ gsub(/\t/, "    "); sub(/[[:space:]]+$/, ""); print ($0 == "" ? "" : "  " $0) }' "$dry_run_err" >> "$schema"
                    blocked=$((blocked + 1))
                else
                    echo "- [WARN] Server dry-run failed against the live cluster. Recheck with \`kustomize build $gitops_path | oc apply --dry-run=server --validate=strict -f -\`." >> "$schema"
                    awk '{ gsub(/\t/, "    "); sub(/[[:space:]]+$/, ""); print ($0 == "" ? "" : "  " $0) }' "$dry_run_err" >> "$schema"
                    warnings=$((warnings + 1))
                fi
            fi

            while IFS='|' read -r api kind; do
                [[ -n "$api" && -n "$kind" ]] || continue
                if oc_explain_kind "$kind" "$api"; then
                    echo "- [PASS] \`oc explain $kind --api-version=$api\`" >> "$schema"
                else
                    if [[ "$STRICT_CLUSTER" == "true" ]]; then
                        echo "- [BLOCKED] \`oc explain $kind --api-version=$api\` failed." >> "$schema"
                        blocked=$((blocked + 1))
                    else
                        echo "- [WARN] \`oc explain $kind --api-version=$api\` failed on the live cluster." >> "$schema"
                        warnings=$((warnings + 1))
                    fi
                fi
            done < "$tmp_dir/$component.kinds"
        else
            echo "- [BLOCKED] Live cluster schema verification did not run." >> "$schema"
            while IFS='|' read -r api kind; do
                [[ -n "$api" && -n "$kind" ]] || continue
                echo "- [BLOCKED] Verify with \`oc explain $kind --api-version=$api\`." >> "$schema"
            done < "$tmp_dir/$component.kinds"
            blocked=$((blocked + 1))
        fi
    else
        echo "- [BLOCKED] Schema verification skipped because no rendered YAML was available." >> "$schema"
        blocked=$((blocked + 1))
    fi

    find_rh_brain_sources "$component" | sort -u > "$rh_sources"

    decision="aligned"
    if [[ $blocked -gt 0 ]]; then
        decision="blocked"
    elif [[ $warnings -gt 0 ]]; then
        decision="aligned-with-notes"
    fi

    blocked_total=$((blocked_total + blocked))
    warning_total=$((warning_total + warnings))

    {
        echo "### $component"
        echo ""
        echo "| Field | Evidence |"
        echo "|-------|----------|"
        echo "| Status | \`$decision\` |"
        echo "| GitOps path | \`${gitops_path:-not found}\` |"
        echo "| Argo CD app | \`${app_path:-not found}\` |"
        echo "| README | \`${readme_path:-not found}\` |"
        echo "| Official docs | [RHOAI 3.4]($RHOAI_DOCS), [OCP 4.20]($OCP_DOCS) |"
        echo ""
        echo "**Findings**"
        echo ""
        cat "$findings"
        echo ""
        echo "**Schema Verification**"
        echo ""
        cat "$schema"
        echo ""
        echo "**rh-brain Research Sources**"
        echo ""
        if [[ -s "$rh_sources" ]]; then
            sed 's/^/- `rh-brain: /; s/$/`/' "$rh_sources"
        else
            echo "- No matching read-only rh-brain sources found."
        fi
        echo ""
    } >> "$ledger_tmp"
done < "$audit_components"

{
    echo "## Summary"
    echo ""
    echo "| Result | Count |"
    echo "|--------|-------|"
    echo "| Blocking findings | $blocked_total |"
    echo "| Notes | $warning_total |"
    echo ""
    if [[ $blocked_total -gt 0 ]]; then
        echo "**Decision:** blocked. Resolve high-risk findings before merge."
    else
        echo "**Decision:** aligned. Notes may be handled as follow-up work."
    fi
} >> "$ledger_tmp"

mv "$ledger_tmp" "$LEDGER_PATH"

echo "Alignment evidence written to: $LEDGER_PATH"
echo "Blocking findings: $blocked_total"
echo "Notes: $warning_total"

if [[ $blocked_total -gt 0 ]]; then
    exit 1
fi
