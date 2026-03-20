# Step 02: Red Hat OpenShift AI 3.3 Platform

**Install the full RHOAI 3.3 AI platform — GenAI Studio, Hardware Profiles, model serving, distributed training, and governance — on a fresh OpenShift cluster.**

## The Business Story

This step deploys the full RHOAI 3.3 platform on top of the GPU infrastructure from step-01, giving data scientists a self-service AI environment with built-in model serving, training, pipelines, and governance. GenAI Studio provides an Agent Playground and Model Catalog, Hardware Profiles direct workloads to the right GPU nodes, and the DataScienceCluster manages the complete component stack.

## What It Does

```text
RHOAI 3.3 Platform
├── RHOAI Operator         → stable-3.x channel, manages all components
├── DSCInitialization      → Service Mesh 3 auto-installed
├── DataScienceCluster     → Full component stack (see table)
├── GenAI Studio           → Agent Playground + Model Catalog UI
└── Hardware Profiles      → GPU/CPU profiles with GPU node scheduling
```

| Component | State | Purpose |
|-----------|-------|---------|
| Dashboard | Managed | RHOAI web console |
| Workbenches | Managed | Jupyter notebooks, VS Code, RStudio |
| AI Pipelines | Managed | ML Pipelines (formerly `datasciencepipelines`) |
| LlamaStack Operator | Managed | GenAI Playground, agentic workflows |
| GenAI Studio | Enabled | Agent Playground + Model Catalog UI |
| KServe | Managed | Model serving (RawDeployment mode) |
| Model Registry | Managed | Model versioning and catalog |
| Training Operator | Managed | Kubernetes-native distributed training |
| Ray | Managed | Distributed computing framework |
| TrustyAI | Managed | Explainability, bias detection, drift monitoring |
| Feast Operator | Managed | Feature store for ML features |

**Hardware Profiles** (global, in `redhat-ods-applications`):

| Profile | Display Name | Scheduling |
|---------|-------------|------------|
| cpu-small | Small (CPU Only) | Node (direct) |
| default-profile | NVIDIA L4 1GPU (Default) | Node (direct) |
| nvidia-l4-1gpu | NVIDIA L4 1GPU | Node (direct) |
| nvidia-l4-4gpu | NVIDIA L4 4GPUs | Node (direct) |

Manifests: [`gitops/step-02-rhoai/base/`](../../gitops/step-02-rhoai/base/)

## What to Verify After Deployment

- **Dashboard URL** — RHOAI console accessible at `https://data-science-gateway.apps.<cluster>` (via Service Mesh 3 Gateway in `openshift-ingress`)
- **GenAI Studio visible** — Agent Playground and Model Catalog appear in the left nav
- **Hardware Profiles available** — four profiles (CPU Small, L4 1GPU, L4 1GPU Default, L4 4GPU) listed in Settings
- **DataScienceCluster Ready** — `default-dsc` phase is `Ready` with all components managed
- **Service Mesh 3** — auto-installed by DSCInitialization for KServe traffic management

## Demo Walkthrough

### Scene 1: RHOAI Dashboard

**Do:** Open `https://data-science-gateway.apps.<cluster>` and log in as `ai-admin` / `redhat123`.

**Expect:** The RHOAI Dashboard with GenAI Studio in the left navigation — Agent Playground, Model Catalog, AI Available Assets.

*"This is the self-service AI platform. Data scientists get a curated environment — models, pipelines, notebooks, and monitoring — without managing infrastructure."*

### Scene 2: Hardware Profiles

**Do:** Navigate to **Settings** → **Hardware profiles**.

**Expect:** Four profiles — CPU Small, NVIDIA L4 1GPU, NVIDIA L4 1GPU (Default), NVIDIA L4 4GPUs. Each shows nodeSelector and tolerations targeting the correct GPU node type.

*"Hardware Profiles replace the old Accelerator Profiles from RHOAI 2.x. They control exactly which node type a workload lands on — CPU, 1-GPU, or 4-GPU. The platform admin defines these once, and every user selects from the same curated list."*

### Scene 3: Model Catalog

**Do:** Navigate to **GenAI Studio** → **Model Catalog**.

**Expect:** 48+ Red Hat Validated models from IBM, Meta, Mistral, Qwen, and others. Each card shows parameter count, license, and recommended hardware.

*"Out of the box, RHOAI ships a curated catalog of validated models in OCI ModelCar format. These are Red Hat-tested — deploy directly from the catalog using the cluster's pull secret."*

## Design Decisions

> **GPU scheduling via Hardware Profiles:** All GPU Hardware Profiles use direct `nodeSelector` and `tolerations` for GPU node placement. No workload queuing is used.

> **GenAI Studio enabled by default:** `genAiStudio: true` in `OdhDashboardConfig` plus `llamastackoperator: Managed` in the DSC activate the Agent Playground and Model Catalog for all users. The RHOAI operator may reset this field during reconciliation, so `deploy.sh` patches it explicitly after DSC is Ready.

> **DSCI CA bundle (runtime patch):** `deploy.sh` patches `DSCInitialization` with the cluster CA certificate (`kube-root-ca.crt`) so LlamaStack distributions can reach internal services over TLS. This is a runtime patch because the CA cert is cluster-specific and should not be committed to git. Ref: [Working with certificates](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/working-with-certificates_certs).

> **Service Mesh 3 install plan approval (Manual, enforced by operator):** The RHOAI operator auto-creates the `servicemeshoperator3` Subscription with `installPlanApproval: Manual` and reconciles it back to `Manual` if patched to `Automatic`. This is an operator-enforced constraint — the approval policy cannot be overridden. As a consequence, `deploy.sh` must explicitly approve pending Service Mesh install plans after the DSCI triggers the subscription creation. Without this step, the Gateway controller never starts and the RHOAI Dashboard becomes unreachable. ArgoCD cannot detect this because the Service Mesh subscription is a side effect of DSCI reconciliation, not a GitOps-managed resource.

## References

- [RHOAI 3.3 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/release_notes/index)
- [RHOAI 3.3 Installation Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index)
- [Installing Distributed Workloads Components](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-distributed-workloads-components_install)
- [Configuring Hardware Profiles](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/working_with_accelerators/index#working-with-hardware-profiles)

## Troubleshooting

### Dashboard "Application is not available" — Gateway stuck at "Waiting for controller"

**Symptom:** Browsing to `https://data-science-gateway.apps.<cluster>` shows the OpenShift "Application is not available" page.

**Root Cause:** The Service Mesh 3 operator CSV is stuck in `Pending` (e.g. due to a failed upgrade from v3.0.x to v3.1.x where the ServiceAccount was never created). Without the operator, istiod never starts, the `data-science-gateway` GatewayClass has no controller, and the Gateway cannot be programmed.

**Diagnosis:**
```bash
oc get gateway data-science-gateway -n openshift-ingress
# PROGRAMMED column shows "Unknown"

oc get csv -n openshift-operators | grep servicemesh
# Phase shows "Pending" instead of "Succeeded"

oc get pods -n openshift-operators | grep mesh
# No operator pod running
```

**Solution:**
```bash
# 1. Delete the stuck CSV (replace version as needed)
oc delete csv servicemeshoperator3.v3.1.0 -n openshift-operators

# 2. Find and approve the pending install plan for the next version
oc get installplan -n openshift-operators | grep servicemesh
oc patch installplan <plan-name> -n openshift-operators --type merge -p '{"spec":{"approved":true}}'

# 3. Wait for the CSV to reach Succeeded (~1-2 minutes)
oc get csv -n openshift-operators -w | grep servicemesh

# 4. Verify the gateway becomes Programmed
oc get gateway data-science-gateway -n openshift-ingress
# PROGRAMMED should show "True"

# 5. Verify dashboard responds (302 = redirect to login)
curl -sk -o /dev/null -w '%{http_code}' https://data-science-gateway.apps.<cluster>
```

> **Note (RHOAI 3.3):** The DSCI auto-installs Service Mesh 3 with `installPlanApproval: Manual`. On shared demo clusters where the operator catalog updates, pending upgrades require manual approval. If the cluster sits idle for hours, a new version may appear and require this approval step.

## Operations

Deploy: `./steps/step-02-rhoai/deploy.sh` · Validate: `./steps/step-02-rhoai/validate.sh`

## Next Steps

Continue to [Step 03 — Private AI Infrastructure](../step-03-private-ai/README.md) to configure MinIO storage, authentication, and RBAC for GPU-as-a-Service.
