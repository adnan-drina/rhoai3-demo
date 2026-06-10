# Shared Rules

This directory contains short, tool-neutral project rules.

Use these files for durable domain constraints that should apply across agent
tools. Keep detailed workflows in `.agents/skills/` and make each rule point to
the relevant skill instead of duplicating procedure text.

| Rule | Purpose |
|------|---------|
| `project.md` | Project structure, GitOps authoring, documentation, manifest review, Red Hat source alignment, and shared agent guidance |
| `env.md` | Live demo environment deployment, validation, troubleshooting, shutdown, recovery, and redeploy |
| `rhoai.md` | RHOAI platform component guidance backed by official Red Hat documentation |
| `ocp.md` | OpenShift Container Platform infrastructure, control plane, networking, auth, monitoring, GitOps, cluster, and storage integration guidance |
| `odf.md` | OpenShift Data Foundation storage, object storage, NooBaa, OBC, and storage-class guidance |
| `assets.md` | Visual assets, architecture diagrams, decks, and presentation outputs |
