# RHOAI 3 Demo

GitOps-driven demo of Red Hat OpenShift AI using OpenShift GitOps (Argo CD) and Kustomize.

## Prerequisites

- OpenShift 4.14+
- Cluster admin access
- `oc` CLI

## Quick Start

```bash
# 1. Configure
cp env.example .env
# Edit .env with your values

# 2. Bootstrap GitOps
oc login <cluster>
./scripts/bootstrap.sh

# 3. Deploy steps
./steps/step-01-gpu/deploy.sh
./steps/step-02-rhoai/deploy.sh
./steps/step-03-llms/deploy.sh
```

## Structure

```
gitops/
├── argocd/           # Argo CD application definitions
├── step-01-gpu/      # GPU infrastructure
├── step-02-rhoai/    # RHOAI platform
└── step-03-llms/     # LLM deployment

steps/
├── step-01-gpu/      # Deploy script + docs
├── step-02-rhoai/
└── step-03-llms/
```

## Adding a New Step

1. Create `gitops/step-XX-name/` with Kustomize resources
2. Create `gitops/argocd/app-of-apps/step-XX-name.yaml`
3. Create `steps/step-XX-name/deploy.sh` and `README.md`
4. Test: `kustomize build gitops/step-XX-name`
