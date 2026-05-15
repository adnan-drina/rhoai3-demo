# RHOAI 3.4 Demo — Codex Instructions

Demo of building Private AI platform infrastructure for enterprise generative and
predictive AI use cases using **Red Hat OpenShift AI (RHOAI) 3.4** on
**Red Hat OpenShift Container Platform (RHOCP) 4.20**.

## Documentation first

- Official RHOAI 3.4 and RHOCP 4.20 docs are the source of truth
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

For YAML standards, cross-resource consistency, and comment hygiene:
@.cursor/rules/40-openshift-rhoai-manifests.mdc

For GitOps structure, ArgoCD Application standards, and Kustomize patterns:
@.cursor/rules/10-gitops-kustomize.mdc

For README structure (Tell-Show-Tell demo format, Red Hat narrative alignment):
@.cursor/rules/20-readme-standard.mdc

For Kubernetes labels, OpenShift Topology annotations, and RHOAI Dashboard labels:
@.cursor/rules/50-kubernetes-labels.mdc

For secrets handling, ODH managed label gotcha, and security posture:
@.cursor/rules/30-secrets-and-certs.mdc

## Skills available

Skills in `.cursor/skills/` provide workflows for:
- `deploy-and-evaluate` — step-by-step deployment of the demo steps, including optional edge paths
- `rhoai-troubleshoot` — structured diagnostic workflow
- `validate-demo-flow` — 3-layer E2E validation
- `chatbot-customization` — system prompts, guardrails, tool_choice
- `model-evaluation` — RAG eval (LLM-as-judge) + LM-Eval benchmarks
- `manage-resources` — scale models and GPU nodes up/down
- `maintain-rules-and-skills` — manage Cursor/Codex platform configuration
- `refactor-architecture-diagrams` — align root and step README architecture diagrams with the shared Red Hat layered capability-map design

## Subagents available

Subagents in `.cursor/agents/` for context-isolated tasks:
- `cluster-inspector` (readonly, fast) — gather cluster state safely
- `manifest-reviewer` (readonly) — review manifests for compliance
- `doc-alignment-reviewer` (readonly) — verify manifests match pinned RHOAI 3.4/OCP 4.20 docs
