#!/usr/bin/env bash
# Pre-merge documentation and product-alignment audit for GitOps-managed demo components.
#
# The audit is intentionally local-first: it renders Kustomize bases, checks for
# stale product-version references, records schema verification commands, and
# writes a durable evidence ledger. Live-cluster schema checks are best-effort
# unless AUDIT_STRICT_CLUSTER=true is set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BASE_REF="origin/main"
COMPONENT=""
ORIGINAL_ARGS="$*"
LEDGER_PATH="$REPO_ROOT/docs/alignment-evidence-ledger.md"
RH_BRAIN_DIR="${RH_BRAIN_DIR:-/Users/adrina/Sandbox/rh-brain/Red Hat Brain}"
STRICT_CLUSTER="${AUDIT_STRICT_CLUSTER:-false}"
OC_REQUEST_TIMEOUT="${OC_REQUEST_TIMEOUT:-5s}"

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
  AUDIT_STRICT_CLUSTER=true   # fail when live oc explain checks fail
  OC_REQUEST_TIMEOUT=5s       # timeout for live oc whoami/explain checks
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
        edge-ai-microshift) echo "step-13b-edge-ai-microshift" ;;
    esac
}

gitops_path_for() {
    local component="$1"
    if [[ -d "gitops/$component/base" ]]; then
        printf 'gitops/%s/base\n' "$component"
    elif [[ -d "gitops/$component" ]]; then
        printf 'gitops/%s\n' "$component"
    else
        printf '\n'
    fi
}

readme_path_for() {
    local component="$1"
    if [[ -f "steps/$component/README.md" ]]; then
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
    command -v oc >/dev/null 2>&1 && oc --request-timeout="$OC_REQUEST_TIMEOUT" whoami >/dev/null 2>&1
}

oc_explain_kind() {
    local kind="$1" api="$2"
    oc --request-timeout="$OC_REQUEST_TIMEOUT" explain "$kind" --api-version="$api" >/dev/null 2>&1
}

oc_server_dry_run() {
    local rendered_file="$1"
    oc --request-timeout="$OC_REQUEST_TIMEOUT" apply --dry-run=server --validate=strict -f "$rendered_file" >/dev/null 2>&1
}

rh_brain_terms_for() {
    local component="$1"
    case "$component" in
        step-05-*|step-06-*) echo "Models-as-a-Service"; echo "llm-d"; echo "vLLM" ;;
        step-07-*|step-08-*) echo "RAG"; echo "AutoRAG"; echo "evaluation" ;;
        step-09-*) echo "guardrails"; echo "AI safety" ;;
        step-10-*) echo "MCP"; echo "agentic" ;;
        step-11-*|step-12-*) echo "MLflow"; echo "MLOps"; echo "predictive AI" ;;
        step-13-*|edge-ai-microshift) echo "edge AI"; echo "MicroShift" ;;
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

sort -u "$audit_components" -o "$audit_components"

ledger_tmp="$tmp_dir/alignment-evidence-ledger.md"
blocked_total=0
warning_total=0
OC_CLUSTER_AVAILABLE=false

if oc_cluster_available; then
    OC_CLUSTER_AVAILABLE=true
fi

{
    echo "# Documentation Alignment Evidence Ledger"
    echo ""
    echo "**Generated:** $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "**Command:** \`$0 $ORIGINAL_ARGS\`"
    echo "**Base ref:** \`$BASE_REF\`"
    echo "**Docs baseline:** RHOAI 3.4 / OCP 4.20"
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
    touch "$latest_matches"
    if [[ -n "$gitops_path" && -e "$gitops_path" ]]; then
        grep -RInE 'image:[[:space:]]+[^#]*:latest([[:space:]]|$)' "$gitops_path" >> "$latest_matches" 2>/dev/null || true
    fi
    if [[ -s "$latest_matches" ]]; then
        echo "- [WARN] Unpinned \`:latest\` image references found:" >> "$findings"
        sed 's/^/  - /' "$latest_matches" >> "$findings"
        warnings=$((warnings + 1))
    else
        echo "- [PASS] No unpinned \`:latest\` image references found in GitOps path." >> "$findings"
    fi

    if [[ -s "$rendered" ]]; then
        awk '
            /^apiVersion:/ { api=$2 }
            /^kind:/ { kind=$2; if (api != "" && kind != "") print api "|" kind }
        ' "$rendered" | sort -u > "$tmp_dir/$component.kinds"

        if [[ "$OC_CLUSTER_AVAILABLE" == "true" ]]; then
            if oc_server_dry_run "$rendered"; then
                echo "- [PASS] \`oc apply --dry-run=server --validate=strict -f rendered.yaml\` accepted rendered resources." >> "$schema"
            else
                if [[ "$STRICT_CLUSTER" == "true" ]]; then
                    echo "- [BLOCKED] \`oc apply --dry-run=server --validate=strict -f rendered.yaml\` failed." >> "$schema"
                    blocked=$((blocked + 1))
                else
                    echo "- [DEFERRED] Server dry-run failed or required CRDs are unavailable on this cluster. Recheck with \`kustomize build $gitops_path | oc apply --dry-run=server --validate=strict -f -\`." >> "$schema"
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
                        echo "- [DEFERRED] \`oc explain $kind --api-version=$api\` failed or CRD is unavailable on this cluster." >> "$schema"
                        warnings=$((warnings + 1))
                    fi
                fi
            done < "$tmp_dir/$component.kinds"
        else
            echo "- [DEFERRED] Verify rendered schema and CR fields with \`kustomize build $gitops_path | oc apply --dry-run=server --validate=strict -f -\`." >> "$schema"
            while IFS='|' read -r api kind; do
                [[ -n "$api" && -n "$kind" ]] || continue
                echo "- [DEFERRED] Verify with \`oc explain $kind --api-version=$api\`." >> "$schema"
            done < "$tmp_dir/$component.kinds"
            warnings=$((warnings + 1))
        fi
    else
        echo "- [DEFERRED] Schema verification skipped because no rendered YAML was available." >> "$schema"
        warnings=$((warnings + 1))
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
    echo "| Notes / deferred checks | $warning_total |"
    echo ""
    if [[ $blocked_total -gt 0 ]]; then
        echo "**Decision:** blocked. Resolve high-risk findings before merge."
    else
        echo "**Decision:** aligned. Notes and deferred checks may be handled as follow-up work."
    fi
} >> "$ledger_tmp"

mv "$ledger_tmp" "$LEDGER_PATH"

echo "Alignment evidence written to: $LEDGER_PATH"
echo "Blocking findings: $blocked_total"
echo "Notes / deferred checks: $warning_total"

if [[ $blocked_total -gt 0 ]]; then
    exit 1
fi
