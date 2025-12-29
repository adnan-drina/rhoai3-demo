# PLAN: Step 08 — Distributed Inference (llm-d) on RHOAI 3.0 / OCP 4.20

> **Status:** Temporary planning document for `step-08-llm-d` (to be refined into the final step README + GitOps manifests).
>
> **Scope of this PLAN:** Capture what we have verified so far from this repo and the **official RHOAI 3.0 GA documentation**, highlight assumptions vs. confirmed requirements, and provide an implementation checklist that a coding assistant can execute.

---

## Conceptual Foundation (Platform → Business)

### The business story: “Elastic scale-out on a budget”

We want to demonstrate that enterprises can increase **inference capacity** without moving to more expensive GPU instances by horizontally scaling a single model across multiple smaller GPU nodes.

In this repo’s demo narrative:

- Step 07 frames the economics story (“ROI of quantization”) with **measured breakpoints**.
- Step 08 should extend that story by introducing **Distributed Inference with llm-d** as the “scale-out” option.

### What “success” looks like in the demo

- A distributed model deployment is created using the **RHOAI 3.0 GA supported flow** (per docs).
- The endpoint is reachable and returns valid inference responses.
- We can benchmark it using the existing measurement tools/patterns (GuideLLM + vLLM metrics) and compare to the single-node INT4 baseline.

---

## Layered Architecture Analysis

### Layer 1 — Infrastructure

**Existing repo components**

- GPU nodes created via Step 01 (AWS MachineSets) with taint `nvidia.com/gpu=true:NoSchedule`.
- NVIDIA GPU Operator installed; driver pinning handled as part of Step 01’s guidance and Step 05 troubleshooting.

**Step 08 intent**

- Use **2× `g6.4xlarge`** (1× NVIDIA L4 each) for a “scale-out” story.

### Layer 2 — Platform

**Existing repo components**

- Kueue operator is installed in Step 01; queues/flavors are created in Step 03.
- RHOAI platform installed in Step 02.

**Important constraints from official docs**

- The RHOAI 3.0 “Deploying models” guide for llm-d assumes:
  - **Gateway API** is configured by a cluster admin (GatewayClass + a Gateway named `openshift-ai-inference` in `openshift-ingress`)
  - **LeaderWorkerSet operator** is installed by a cluster admin
  - **Authentication configured using Red Hat Connectivity Link**
  - Then the user creates an **`LLMInferenceService`** custom resource
  - Source: RHOAI 3.0 “Deploying models” → “Deploying models by using Distributed Inference with llm-d”
    - `https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index`

**Repo-specific nuance**

- This repo currently installs components that are described as “required for llm-d inference gateway” (Authorino/Limitador/DNS) in Step 01.
- However, the official llm-d authentication procedure references **Connectivity Link + Kuadrant** objects.
- We must verify what is actually installed in the target demo cluster and what CRDs exist before writing Step 08 YAML.

### Layer 3 — Application (Model Serving)

**Baseline model in this repo**

- INT4 ModelCar model is already deployed in Step 05:
  - `gitops/step-05-llm-on-vllm/base/inference/mistral-3-int4.yaml`
  - Uses ModelCar image: `oci://registry.redhat.io/rhelai1/modelcar-mistral-small-24b-instruct-2501-quantized-w4a16:1.5`
  - Tunes for 1× L4 and 8K context.

**Step 08 target**

- Deploy the *distributed inference* version using the **RHOAI-supported CR**: `LLMInferenceService`
  - The official doc explicitly describes “replace the default InferenceService with the LLMInferenceService.”
  - Source: `deploying_models` guide above.

**Warning about “InferenceGateway”**

- This repo includes an `InferenceGateway` manifest **as a placeholder** and it explicitly says **“DO NOT APPLY”** and that the CRD is **not present** in RHOAI 3.0 GA:
  - `gitops/step-06-private-ai-playground-maas/base/maas/inference-gateway.yaml`
  - Therefore, Step 08 must not assume `InferenceGateway` exists unless the cluster’s CRDs prove otherwise.

### Layer 4 — Governance / Observability

**Existing repo components**

- Step 07 provides Grafana + GuideLLM benchmarking and a repeatable comparison framework.

**Step 08 intent**

- Benchmark the distributed endpoint with the same approach used in Step 07.
- Keep claims data-driven: “measure” > “promise.”

---

## Metrics & Strategy

### Metrics to compare (Step 07 baseline vs Step 08 distributed)

- **TTFT** (p95), **TPOT** (p95)
- **Queue depth** (e.g., `vllm:num_requests_waiting`)
- **KV cache utilization** (`vllm:kv_cache_usage_perc`)
- **Throughput** (`rate(vllm:generation_tokens_total[...])`)

### Strategy: “targets” vs “guarantees”

We will set hypotheses (e.g., higher throughput at the same SLA threshold), but we will not claim fixed numbers (e.g., “45+ users”) until the benchmarks confirm them.

---

## Design Decisions (Confirmed vs. Gated)

### Confirmed (repo + docs-aligned)

- **Use the official llm-d path:** `LLMInferenceService` is the primary supported CR in RHOAI 3.0 docs for llm-d.
  - Source: `https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index`
- **Avoid MaaS `InferenceGateway` assumptions:** this repo treats it as DP/placeholder and not present in RHOAI 3.0 GA.
  - Source: `gitops/step-06-private-ai-playground-maas/base/maas/inference-gateway.yaml`
- **CLI/API association required:** Release notes say Gateway discovery/association is not supported in UI for llm-d deployment.
  - Source: `https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/release_notes/index`

### Gated (must verify on cluster before implementing)

- **Which llm-d/Gateway-related CRDs exist** (and their schemas).
- **Whether Connectivity Link / Kuadrant is installed** as per the official llm-d auth procedure.
- **Exact vLLM distributed knobs** (env vars / CLI flags) supported by the llm-d runtime image shipped with RHOAI 3.0.
- **Whether we need a headless Service**: the term “headless service” is not present on the referenced “Deploying models” page; treat it as an implementation detail unless another official doc section explicitly requires it.

---

## Implementation Checklist / Coding Hand-off (for the coding assistant)

### A) Verification gates (run first, do not guess)

```bash
# Verify llm-d API surfaces
oc api-resources | grep -i llminferenceservice
oc explain llminferenceservice
oc explain llminferenceservice.spec

# Verify LWS operator is present (required per docs)
oc get crd | grep -i leaderworkerset
oc explain leaderworkerset || true

# Verify Gateway API prerequisites mentioned in docs
oc get gatewayclass
oc get gateway -n openshift-ingress openshift-ai-inference

# Verify whether MaaS/InferenceGateway CRD exists (expected: absent in RHOAI 3.0 GA)
oc get crd | grep -iE "inferencegateway|maas" || true

# Verify Kueue baseline resources (repo uses these for GPU-as-a-Service)
oc get clusterqueue rhoai-main-queue
oc get localqueue default -n private-ai
```

### B) New step scaffolding (repo conventions)

Create the following:

- `gitops/step-08-llm-d/base/`
  - `kustomization.yaml`
  - `llm-d/llminferenceservice.yaml` (primary CR, schema verified via `oc explain`)
  - `llm-d/route.yaml` (if exposing externally)
  - Optional: any Gateway association manifests required by docs (only if CRDs exist)
- `gitops/argocd/app-of-apps/step-08-llm-d.yaml`
  - Include `demo.rhoai.io/step: "08"` label, and an appropriate `sync-wave` after Step 07.
- `steps/step-08-llm-d/README.md`
  - Must include Goal, Prereqs, Reproduce (one-shot + step-by-step), Validate, Rollback/Cleanup, References.
- `steps/step-08-llm-d/deploy.sh`
  - Apply the ArgoCD Application or apply Kustomize directly.
  - Gate on the required CRDs and the presence of `openshift-ai-inference` Gateway if Step 08 depends on it.

### C) Step 08 constraints to reuse from existing demo patterns

- **GPU scheduling**
  - Must tolerate `nvidia.com/gpu` taint.
  - Must target `g6.4xlarge` nodes (this repo already uses `node.kubernetes.io/instance-type: g6.4xlarge` for the INT4 baseline in Step 05).
- **vLLM baseline env**
  - `VLLM_USE_V1: "1"` and `LD_LIBRARY_PATH: "/usr/local/nvidia/lib64"` are used in Step 05’s INT4 InferenceService and should be preserved where applicable.
- **Driver compatibility**
  - Step 05 documents a CUDA driver mismatch issue and the demo pins GPU driver versions; Step 08 should not introduce changes here.

### D) Validation (deterministic checks)

```bash
# Confirm the CR exists and is reconciling
oc get llminferenceservice -n private-ai
oc describe llminferenceservice -n private-ai <name>

# Confirm pods are created and placed on distinct g6.4xlarge nodes (expect 2 shards)
oc get pods -n private-ai -o wide | grep -i <name>

# Confirm endpoint/route exists (if exposed)
oc get route -n private-ai

# Optional: compare benchmark results (reuse Step 07 job/pipeline patterns)
oc get cronjob guidellm-daily -n private-ai
```

---

## References & Resources (official first)

### Red Hat Official (RHOAI 3.0)

- Deploying models (includes llm-d section and `LLMInferenceService` examples):
  - `https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/deploying_models/index`
- Release notes (llm-d GA note + UI limitation about Gateway association):
  - `https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/release_notes/index`

### Repo-internal knowledge (validated by code/docs in this repo)

- Step 01: prerequisites and operator stack (includes LeaderWorkerSet operator install reference):
  - `steps/step-01-gpu-and-prereq/README.md`
  - `gitops/step-01-gpu-and-prereq/base/leaderworkerset/subscription.yaml`
- Step 05: baseline INT4 model configuration (node targeting, vLLM env/args):
  - `gitops/step-05-llm-on-vllm/base/inference/mistral-3-int4.yaml`
- Step 06 MaaS placeholder (InferenceGateway CR not available in GA):
  - `gitops/step-06-private-ai-playground-maas/base/maas/inference-gateway.yaml`
- Step 07 benchmarking/metrics framework:
  - `steps/step-07-model-performance-metrics/README.md`

### Additional reading (useful for enriching the demo narrative)

- Red Hat Developer (llm-d introduction): `https://developers.redhat.com/articles/2025/11/21/introduction-distributed-inference-llm-d`
- Red Hat Blog (llm-d + vLLM production framing): `https://www.redhat.com/en/blog/demystifying-llm-d-and-vllm-race-production?channel=/en/blog/channel/red-hat-ai`
- Red Hat Developer (vLLM autoscaling validation on OpenShift AI): `https://developers.redhat.com/articles/2025/11/26/autoscaling-vllm-openshift-ai-model-serving`

---

## Review Needed / Strategic Questions (Decision Gate)

1. **Supported path vs. “under the hood” path**
   - Do we implement Step 08 purely via the **supported** `LLMInferenceService` flow (recommended), or do we also include an “under the hood” appendix that explains `LeaderWorkerSet` objects if present?

2. **Gateway prerequisites**
   - Are we willing to add the `GatewayClass`/`Gateway openshift-ai-inference` prerequisites to the repo (GitOps), or do we treat them as “cluster-admin pre-reqs” documented only in the README?

3. **Connectivity Link / Kuadrant alignment**
   - Do we expand the repo to deploy what the llm-d auth procedure expects (Kuadrant/Connectivity Link components), or do we keep Step 08 unauthenticated (demo-only) and explicitly label it “not fully production-aligned”?

4. **Benchmark integration**
   - Should Step 08 ship a dedicated “benchmark job template” that targets the distributed endpoint, or should we extend Step 07’s GuideLLM dispatcher to include a new target?

---

## Demo enrichment opportunities (derived from the above articles)

> These are optional enhancements. Any “production-aligned” claims must still be backed by the official RHOAI 3.0 docs and validated on-cluster with `oc explain`/CRDs.

### 1) Add a “Production mental model” slide/script for Step 08 (llm-d vs vLLM)

Use the “engine vs platform” framing to improve audience understanding:

- **vLLM**: the high-performance inference engine.
- **llm-d**: the orchestration layer that enables disaggregation, cache-aware routing, and fleet-scale elasticity.

Source: Red Hat blog “Demystifying llm-d and vLLM: The race to production”:
- `https://www.redhat.com/en/blog/demystifying-llm-d-and-vllm-race-production?channel=/en/blog/channel/red-hat-ai`

### 2) Make “disaggregated prefill/decode” a gated “wow moment”

Both the Red Hat blog and the llm-d introduction emphasize:

- **Disaggregation**: separate scaling/placement of prefill vs decode workers
- **Prefix/KV-cache aware routing** concepts (route to where cache exists to reduce latency)

Recommendation:
- Keep Step 08 baseline as the **supported** llm-d flow (`LLMInferenceService`).
- Add an **optional appendix**: “If the cluster exposes the needed knobs/CRDs, enable disaggregation and show it in metrics/logs.”

Validation gates (before adding any new fields):

```bash
oc explain llminferenceservice.spec
oc explain llminferenceservice.spec.router || true
oc explain llminferenceservice.spec.model || true
```

Source concepts:
- `https://developers.redhat.com/articles/2025/11/21/introduction-distributed-inference-llm-d`
- `https://www.redhat.com/en/blog/demystifying-llm-d-and-vllm-race-production?channel=/en/blog/channel/red-hat-ai`

### 3) Add an autoscaling “extension” (Step 05/07), separate from Kueue admission

The autoscaling article is useful to enrich the demo by contrasting scaling mechanisms:

- **HPA vs KPA (Knative Pod Autoscaler)** and how replica count is computed
- How different metrics and modes change behavior (latency/throughput/replica ramp)

Recommendation:
- Introduce a **new optional sub-demo** (either late Step 05 or Step 07 add-on):
  - Compare a fixed replica deployment (current) vs autoscaled behavior (HPA/KPA), while keeping Kueue constraints in mind.
- Do NOT mix this into Step 08 initially (avoid compounding variables).

Validation gates (decide which autoscaler is in effect for your serving mode):

```bash
oc get inferenceservice -n private-ai -o yaml | grep -E \"deploymentMode|minReplicas|maxReplicas\" -n || true
oc get hpa -n private-ai
oc get knativepodautoscaler -n private-ai 2>/dev/null || true
```

Source:
- `https://developers.redhat.com/articles/2025/11/26/autoscaling-vllm-openshift-ai-model-serving`

---

*Drafted by Cursor Agent for RHOAI 3.0 Demo Project*


