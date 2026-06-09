# Shared Hook Utilities

This directory contains reusable hook implementations that are not tied to one
agent tool.

Tool-specific hook configuration files can call these scripts instead of
duplicating logic under `.cursor/` or `.codex/`.

| Script | Purpose |
|--------|---------|
| `guard-openshift-command.py` | Blocks risky OpenShift and Kubernetes mutations unless the project cluster guard matches |
