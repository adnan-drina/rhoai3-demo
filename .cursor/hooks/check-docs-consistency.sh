#!/bin/bash
# afterFileEdit hook: remind agents to keep code, docs, and GitOps aligned.
#
# When a gitops manifest or stage script is edited, warn if the companion
# README wasn't also edited. When a README is edited, warn if no manifest
# or script was touched. Tracks edits in a session-local temp file.

input=$(cat)
file_path=$(echo "$input" | jq -r '.file_path // empty' 2>/dev/null)

if [[ -z "$file_path" ]]; then
    exit 0
fi

SESSION_ID=$(echo "$input" | jq -r '.conversation_id // "unknown"' 2>/dev/null)
TRACK_FILE="/tmp/cursor-edit-track-${SESSION_ID}.log"

echo "$file_path" >> "$TRACK_FILE"

# Extract stage name from path (supports both gitops/ and stage-*/ trees)
stage_name=""
if [[ "$file_path" == *gitops/stage-* ]]; then
    stage_name=$(echo "$file_path" | grep -o 'stage-[0-9]*-[a-z-]*' | head -1)
elif [[ "$file_path" == stage-* ]]; then
    stage_name=$(echo "$file_path" | grep -o 'stage-[0-9]*-[a-z-]*' | head -1)
elif [[ "$file_path" == *.agents/skills/* ]]; then
    # Skill edits should check if related stage README needs updating
    skill_name=$(echo "$file_path" | grep -o 'skills/[^/]*' | head -1 | sed 's|skills/||')
    if [[ -n "$skill_name" ]]; then
        cat << EOF
{"additional_context": "REMINDER: You edited skill '$skill_name'. If this skill references implementation details from a stage, verify those details still match the GitOps manifests. Run the documentation alignment audit if uncertain."}
EOF
    fi
    exit 0
fi

if [[ -z "$stage_name" ]]; then
    exit 0
fi

edited_type=""
companion_hint=""

if [[ "$file_path" == gitops/*/*.yaml ]] || [[ "$file_path" == gitops/*/*.yml ]]; then
    edited_type="manifest"
    companion_hint="$stage_name/README.md"
elif [[ "$file_path" == */README.md ]]; then
    edited_type="readme"
    companion_hint="gitops/$stage_name/"
elif [[ "$file_path" == *deploy.sh ]] || [[ "$file_path" == *validate.sh ]] || [[ "$file_path" == *setup-*.sh ]]; then
    edited_type="script"
    companion_hint="$stage_name/README.md and gitops/$stage_name/"
elif [[ "$file_path" == *.ipynb ]] || [[ "$file_path" == *.py ]]; then
    edited_type="pipeline/notebook"
    companion_hint="$stage_name/README.md"
fi

if [[ -z "$edited_type" ]]; then
    exit 0
fi

companion_edited=false
if [[ "$edited_type" == "manifest" ]]; then
    if grep -q "$stage_name/README.md" "$TRACK_FILE" 2>/dev/null; then
        companion_edited=true
    fi
elif [[ "$edited_type" == "readme" ]]; then
    if grep -q "gitops/$stage_name" "$TRACK_FILE" 2>/dev/null; then
        companion_edited=true
    fi
elif [[ "$edited_type" == "script" ]]; then
    if grep -q "$stage_name/README.md" "$TRACK_FILE" 2>/dev/null || \
       grep -q "gitops/$stage_name" "$TRACK_FILE" 2>/dev/null; then
        companion_edited=true
    fi
elif [[ "$edited_type" == "pipeline/notebook" ]]; then
    if grep -q "$stage_name/README.md" "$TRACK_FILE" 2>/dev/null; then
        companion_edited=true
    fi
fi

if [[ "$companion_edited" == "false" ]]; then
    cat << EOF
{"additional_context": "REMINDER: You edited a $edited_type in $stage_name but have not touched $companion_hint yet. Code and documentation must stay aligned — update the README to reflect implementation changes, and ensure any related .agents/skills/ contain accurate implementation details."}
EOF
else
    exit 0
fi
