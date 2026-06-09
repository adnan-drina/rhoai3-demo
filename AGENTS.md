# RHOAI Demo — Codex Instructions

Demo of building Private AI platform infrastructure for enterprise generative
and predictive AI use cases using the product baseline in
`docs/PLATFORM_BASELINE.md`.

## Documentation first

- Official Red Hat docs for the active `docs/PLATFORM_BASELINE.md` versions are
  the source of truth
- Do not invent CR fields, API versions, annotations, or operator configurations
- If unsure, propose a verification command (`oc explain`, `oc get crd`)

## Key commands

```bash
# First-time setup (installs ArgoCD + AppProject)
./scripts/bootstrap.sh

# Deploy a step (applies ArgoCD Application first, then waits)
./steps/step-XX-name/deploy.sh

# Validate a step (deterministic cluster checks)
./steps/step-XX-name/validate.sh

# E2E demo validation (3-layer: Tool Runtime + Agentic + Guardrails)
./scripts/validate-demo-flow.sh
```

## Repository structure

```
gitops/                    # Kustomize manifests (GitOps source of truth)
  argocd/app-of-apps/      # ArgoCD Application per step
  step-XX-name/base/       # Kustomize base per step
steps/                     # Deployment docs + scripts per step
  step-XX-name/
    README.md               # Educational technical article, not a runbook
    deploy.sh               # Applies ArgoCD app + runtime tasks
    validate.sh             # Post-deploy verification
scripts/                   # Shared utilities (lib.sh, validate-lib.sh)
docs/assets/architecture/  # SVG layered capability maps for workshop + step READMEs (generate-readme-visuals.py)
```

Every `deploy.sh` applies its ArgoCD Application as the first action. Never apply
manifests directly with `oc apply -k` for ArgoCD-managed resources.

## Bootstrap constraints

- ArgoCD `resourceTrackingMethod` MUST be `annotation` (not `label`)
- All Applications use `project: rhoai-demo`
- ArgoCD has `cluster-admin` (acceptable for demo)

## OpenShift safety guard

- Open this repository as its own Codex project; do not open `/Users/adrina/Sandbox` as the active project for live cluster work.
- Before running live `oc`/`kubectl` commands, call `load_env` and `check_oc_logged_in` from `scripts/lib.sh`.
- Set `RHOAI_EXPECTED_API_SERVER` in the local `.env` to a unique target API-server substring before deploy, validate, bootstrap, or resource-management scripts run.
- Do not bypass the guard with `RHOAI_ALLOW_UNGUARDED_CLUSTER=true` unless the user explicitly confirms the current cluster and the command is low risk.
- Do not read credentials from another project by default. Use `RHOAI_OPENAI_ENV_FILE` only when cross-project credential reuse is intentional and approved.

## Code and docs must be aligned

Never update a README without changing the corresponding manifest, and never change
a manifest without updating the README. Every change is atomic: code + docs together.
READMEs should teach the platform story first and keep commands concise. Put operational
details in `docs/OPERATIONS.md` and failure recovery in `docs/TROUBLESHOOTING.md`.
Do not claim capabilities that are not implemented. Future or deferred capabilities
must be clearly labeled.

## Self-signed certs

Use `--insecure-skip-tls-verify=true` (oc) and `-k` (curl) freely. Do not implement
production PKI for this demo.

## Branching and commits

GitHub Flow + Trunk-Based Development. `main` is the trunk — ArgoCD syncs from it.
Commit directly to `main` for small changes. Use feature branches (`feat/step-XX-desc`)
for multi-step or parallel agent work. Always merge via PR with `--no-ff`.

Commit format: `type(scope): description` — types: feat, fix, docs, refactor, chore, ci.
Scope: step number for step-specific, component name for cross-cutting.

## GPU configuration

| Node | GPUs | Model | Role |
|------|------|-------|------|
| g6.4xlarge | 1 | granite-8b-agent (FP8) | MaaS, RAG, MCP, Guardrails |
| g6.12xlarge | 4 | mistral-3-bf16 (BF16) | Judge, Benchmarking |

## Detailed rules

For project structure, GitOps authoring, documentation, manifest review, doc
alignment, and shared agent guidance, read `.agents/rules/project.md`.

For live demo environment deployment, validation, troubleshooting, shutdown,
recovery, and redeploy, read `.agents/rules/env.md`.

For RHOAI platform component guidance, chatbot behavior, KFP, and evaluation,
read `.agents/rules/rhoai.md`.

For visual assets, architecture diagrams, decks, and presentation outputs, read
`.agents/rules/assets.md`.

## Shared Skills

Canonical skills live in `.agents/skills/`, the Codex repo-skill discovery
path. Short tool-neutral rules live in `.agents/rules/`. Do not maintain
tool-specific skill discovery folders in this repo. Use the prefix plus
`metadata.skill-group` taxonomy for skill review:

| Group | Prefix | Skills | Purpose |
|-------|--------|--------|---------|
| Project Structure | `project-*` | `project-structure`, `project-agent-guidance`, `project-architecture-diagrams`, `project-gitops-authoring`, `project-documentation-authoring`, `project-manifest-review`, `project-red-hat-doc-alignment-review` | Repo layout, GitOps step conventions, documentation structure, Red Hat narrative alignment, manifest review, Red Hat doc alignment, and shared AI guidance |
| Demo Environment | `env-*` | `env-deploy-and-evaluate`, `env-troubleshoot`, `env-manage-resources`, `env-validate-demo-flow` | Live AWS/OpenShift demo deployment, validation, troubleshooting, shutdown, recovery, and redeploy |
| RHOAI Platform | `rhoai-*` | `rhoai-chatbot-customization`, `rhoai-model-evaluation`, `rhoai-kfp-pipeline-authoring`; additional component skills planned | Official-doc-backed active-baseline RHOAI component installation, configuration, and usage |
| Assets & Miscellaneous | `assets-*` | `assets-red-hat-quick-deck` | Visual, deck, and presentation assets |

See [docs/AI_COLLABORATION.md](docs/AI_COLLABORATION.md) for the full governance model.

## Subagents

No shared subagents are currently tracked. Add tool-specific subagents only for
genuinely tool-specific context isolation needs; shared workflows belong in
`.agents/skills/`.
