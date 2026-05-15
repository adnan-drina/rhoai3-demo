# Operations Guide

This guide keeps runbook content out of the step READMEs. Use it when you are deploying, validating, operating, or cleaning up the RHOAI 3.4 demo environment.

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| OpenShift Container Platform 4.20 | The manifests and scripts target OCP 4.20. Verify cluster APIs with `oc version` and `oc get clusterversion`. |
| Cluster-admin access | Bootstrap grants the OpenShift GitOps Argo CD application controller cluster-admin for this demo. |
| AWS GPU capacity | Step 01 creates `g6.4xlarge` and `g6.12xlarge` MachineSets for NVIDIA L4 GPUs. Confirm regional quota before deployment. |
| `oc` CLI | Required by every script. Login before running bootstrap or step scripts. |
| Git remote | `scripts/bootstrap.sh` detects `origin` and rewrites Argo CD Application repo URLs for forks. |
| Optional credentials | `HF_TOKEN` speeds or authorizes Hugging Face downloads; `SLACK_BOT_TOKEN` enables Slack MCP; Step 13b needs `EDGE_HOST`, `EDGE_USER`, and `EDGE_PASS`. |
| Pull access | Red Hat registry, Quay, and other image sources must be reachable unless you adapt the demo for disconnected mirroring. |

Self-signed or demo certificates are expected. The scripts and examples use `--insecure-skip-tls-verify=true` and `curl -k` where needed.

## Deployment Order

Run bootstrap once, then deploy steps in order.

```bash
./scripts/bootstrap.sh
```

| Phase | Steps | Purpose |
|-------|-------|---------|
| Platform | 01-02 | GPU prerequisites, OpenShift Serverless, Red Hat build of Kueue Operator, RHOAI operator, DataScienceCluster, hardware profiles. |
| Governance | 03-04 | Project boundary, users, RBAC, MinIO, data connections, model registry. |
| Generative AI | 05-10 | LLM serving, metrics, RAG, evaluation, guardrails, MCP tools. |
| Predictive AI | 11-12 | Face recognition serving, notebooks, training pipeline, TrustyAI monitoring. |
| Edge AI | 13-13b | Simulated edge namespace and optional MicroShift edge host. |

Use the same pattern for each step:

```bash
./steps/step-XX-name/deploy.sh
./steps/step-XX-name/validate.sh
```

## Bootstrap Behavior

`scripts/bootstrap.sh` performs cluster-wide setup for GitOps:

| Action | Why It Exists |
|--------|---------------|
| Installs OpenShift GitOps | Provides the Argo CD instance used by every step. |
| Detects Git remote | Makes forks work without manually editing all Application manifests. |
| Grants Argo CD cluster-admin | Simplifies a demo that installs operators and cluster-scoped resources. Do not copy this blindly into production. |
| Sets `resourceTrackingMethod: annotation` | Avoids label tracking collisions on resources managed by operators. |
| Adds Argo CD health checks | Handles PVC `WaitForFirstConsumer`, KServe `InferenceService`, and `TrustyAIService` health more accurately. |
| Creates `rhoai-demo` AppProject | All step Applications use this project. |

## Deploy Script Model

Every `deploy.sh` applies its Argo CD Application as the first material deployment action. Do not deploy Argo CD managed resources directly with `oc apply -k`.

Some deploy scripts then perform runtime actions that cannot live cleanly in Git:

| Step | Runtime Work |
|------|--------------|
| 01 | Detects cluster ID, AMI, region, and availability zone; creates GPU MachineSets. |
| 02 | Approves Service Mesh 3 install plan when RHOAI creates it manually; patches DSCI CA bundle; re-enables GenAI Studio if reconciled away. |
| 03 | Creates OpenShift groups; applies MinIO console Route excluded from Argo CD due to diff behavior. |
| 05 | Creates Hugging Face token secret if available; uploads large Mistral model to MinIO; registers models. |
| 07 | Builds or deploys ingestion/chatbot resources and initializes RAG data. |
| 08 | Copies evaluation configs and can launch evaluation jobs. |
| 10 | Creates Slack secret from `.env`, patches route-specific MCP config, registers MCP tool groups in Llama Stack. |
| 11 | Creates Hugging Face token secret if available and uploads pre-trained face model. |
| 12 | Uploads training data when present, ensures YOLO base model, launches the KFP training pipeline, configures TrustyAI metrics. |
| 13 | Optionally builds/pushes edge camera image, then waits for the edge app and InferenceService. |
| 13b | SSHes to the edge host, installs/configures MicroShift, creates ModelCar image, and deploys edge workloads. |

## GitOps And Argo CD Operating Model

The GitOps source of truth is split intentionally:

| Path | Responsibility |
|------|----------------|
| `gitops/argocd/app-of-apps/step-*.yaml` | Per-step Argo CD Applications. |
| `gitops/step-*/base/` | Kustomize bases applied by Argo CD. |
| `gitops/edge-ai-microshift/` | Manifests consumed by the optional MicroShift edge GitOps flow. |
| `steps/step-*/deploy.sh` | Runtime orchestration around the GitOps source. |
| `steps/step-*/validate.sh` | Read-only checks for cluster state. |

Most Applications enable automated sync and pruning. Step 01 and Step 05 intentionally set `selfHeal: false` for cases where operators or manual scaling can legitimately change live state during the demo.

When Argo CD reports drift, first check whether the Application contains an `ignoreDifferences` entry for an operator-managed field. If drift is not covered and the field matters, update the manifest and README together.

## Validation Strategy And Exit Codes

Most validation scripts source `scripts/validate-lib.sh`:

| Exit Code | Meaning |
|-----------|---------|
| 0 | All checks passed. |
| 1 | One or more critical checks failed. |
| 2 | Warnings only; the step may still be usable while asynchronous resources settle. |

Validation checks are deterministic cluster checks, not narrative demos. They normally verify Argo CD status, CRDs, CSVs, pods, Routes, key CR conditions, jobs, services, secrets, and selected API calls.

The full ACME flow has a separate validator:

```bash
./scripts/validate-demo-flow.sh
```

It checks tool runtime, agentic behavior, and guardrail behavior across the RAG/MCP flow. Slack tests require a valid Slack token and expected channel configuration.

## Day-2 Operational Notes

| Task | Command Or Guidance |
|------|---------------------|
| Check all Applications | `oc get applications -n openshift-gitops` |
| Inspect one Application | `oc describe application step-07-rag -n openshift-gitops` |
| Watch pods for a step | `oc get pods -n maas -w` or the step-specific namespace. |
| Verify RHOAI health | `oc get datasciencecluster default-dsc -o yaml` |
| Verify KServe models | `oc get inferenceservice -A` |
| Verify model registry | `oc get modelregistry -n rhoai-model-registries` |
| Verify GPU nodes | `oc get nodes -l nvidia.com/gpu.present=true` and `oc describe node <gpu-node>` |
| Scale GPU MachineSets | Use `oc scale machineset ... -n openshift-machine-api`; Step 01 self-heal is disabled to allow this. |
| Review external boundaries | Check `.env`, Llama Stack provider config, Slack secret, Hugging Face token secret, and image references. |
| Validate docs alignment | Keep step README, deploy script, validation script, and GitOps manifests aligned in the same change. |

## Pre-Merge Documentation Alignment Gate

Before merging a branch that changes GitOps-managed components, refresh the documentation alignment evidence ledger:

```bash
./scripts/audit-doc-alignment.sh --base origin/main
```

For a focused check while developing a single step:

```bash
./scripts/audit-doc-alignment.sh --component step-05-maas-model-serving
```

The gate is pinned to RHOAI 3.4 and OCP 4.20 until the demo baseline changes. It blocks only high-risk drift, including invalid Kustomize output, stale pre-3.4 product references in touched components, and unsupported API/schema evidence when strict live-cluster checks are enabled.

The generated ledger lives in `docs/alignment-evidence-ledger.md`. Treat it as the branch's evidence record. It can cite `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` as read-only research input for Red Hat article alignment, but official product documentation remains the source of truth.

## Cleanup

This repository does not provide a single destructive cleanup script. For individual resources, prefer Argo CD Application deletion only when you understand dependencies between steps:

```bash
oc delete application step-10-mcp-integration -n openshift-gitops
```

Avoid deleting shared namespaces such as `maas`, `minio-storage`, or RHOAI operator namespaces unless you are rebuilding the demo from scratch.

## References

- [OpenShift Container Platform 4.20 documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/)
- [Red Hat OpenShift AI Self-Managed 3.4 documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/)
- [OpenShift GitOps documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/latest/)
- [Using AI models on Red Hat build of MicroShift 4.20](https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.20/html-single/using_ai_models/index)
