# Shared Hook Utilities

This directory contains all hook implementations. They are tool-agnostic —
each AI tool's configuration file (`.cursor/hooks.json`, `.codex/hooks.json`)
points here instead of maintaining its own copy.

| Script | Trigger | Purpose |
|--------|---------|---------|
| `guard-openshift-command.py` | Before shell (mutating oc/kubectl) | Blocks risky cluster mutations unless `RHOAI_EXPECTED_API_SERVER` matches |
| `check-docs-consistency.sh` | After file edit | Reminds agents to keep code, docs, and GitOps aligned |
| `validate-yaml.sh` | After file edit (gitops YAML) | Runs `kustomize build` to catch manifest errors early |
