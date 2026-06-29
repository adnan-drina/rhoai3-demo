# Per-Stage Deploy Notes

## Inputs Required

| Input | Required | Default |
|-------|----------|---------|
| Cluster API URL | Yes | — |
| Credentials (token or kubeadmin password) | Yes | — |
| HF_TOKEN (HuggingFace) | Yes (model uploads) | from `.env` |
| Git repo URL | No | from `env.example` |

## Phase 0: Environment Setup

1. Store the cluster kubeconfig as an ignored local file under `tmp/` and point
   `.env` `KUBECONFIG` to it with an absolute path.
2. Set `.env` `RHOAI_EXPECTED_API_SERVER` to a unique API-server substring for
   the new cluster.
3. Set `.env` `GIT_REPO_URL` and `GIT_REPO_BRANCH` to the repo and branch Argo
   CD should sync.
4. `oc login` with provided credentials (`--insecure-skip-tls-verify=true`) if
   the kubeconfig does not already contain a valid context.
5. Verify cluster version: `oc get clusterversion`
6. GPU quota check — current demo intent is a `g6e.2xlarge` GPU worker with
   one `nvidia.com/gpu` per node; default desired count is one node unless the
   active environment plan says otherwise.
7. Run `./stage-110-rhoai-base-platform/deploy.sh`
8. Verify ArgoCD configuration:
   ```bash
   # AppProject must exist
   oc get appproject rhoai-demo -n openshift-gitops
   # Tracking method must be annotation
   oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.spec.resourceTrackingMethod}'
   ```
9. Patch DSCI CA bundle:
   ```bash
   CA=$(oc get configmap kube-root-ca.crt -n openshift-config -o jsonpath='{.data.ca\.crt}')
   oc patch dscinitializations default-dsci --type merge \
     -p "{\"spec\":{\"trustedCABundle\":{\"managementState\":\"Managed\",\"customCABundle\":$(echo "$CA" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}}}"
   ```

## Fresh Environment Rollout Checklist

Use this sequence when redeploying the active demo to a new AWS/OpenShift
environment:

1. Export local environment values before any manual `oc` or `kubectl`
   command:

   ```bash
   set -a
   source .env
   set +a
   ```

   This avoids stale default kubeconfig usage. If the guard reports the wrong
   API server, fix `.env` or `KUBECONFIG` instead of bypassing the guard.
2. Treat `validate-prerequisites.sh` as an advisory readiness check for a
   fresh cluster. Missing GitOps, RHOAI, KServe, GPU, MaaS, or model CRDs can
   be expected before their owning stage deploys.
3. Deploy and validate one stage at a time. Do not continue until the current
   stage validate script returns 0 or only documented warnings.
4. For Stage 120, regenerate the AWS GPU MachineSet from a current worker
   MachineSet in the target cluster. Do not reuse the previous cluster's
   availability zone, subnet, AMI, or provider spec.
5. Expect first model-serving rollouts to take longer than steady-state
   reconciles. Fresh clusters may need to pull the modelcar, vLLM runtime,
   scheduler, router, and tokenizer images before readiness conditions settle.
6. After each stage, capture Argo CD sync/health, important CR readiness, pod
   state, and validation output. Use this evidence before changing manifests.

## Per-Stage Notes

- **Stage 120**: Create or reconcile GPU MachineSets for `g6e.2xlarge`
  workers. The current demo default is one replica. GPU nodes should be labeled
  for GPU infrastructure, tainted `nvidia-gpu-only:NoSchedule`, and expected to
  advertise four time-sliced `nvidia.com/gpu` units.
- **Shared DSC stage boundaries**: Stage 110 creates the base
  `DataScienceCluster` only. Later stages enable their component deltas with
  GitOps hook jobs: Stage 120 patches `kueue: Unmanaged`, Stage 210 patches
  `kserve: Managed`, and Stage 220 patches `kserve.modelsAsService` plus
  `llamastackoperator`. Do not add future-stage DSC patches directly to the
  Stage 110 Kustomize overlay; a fresh environment will fail Stage 110
  readiness before the later-stage prerequisites exist.
- **Stage 210**: Private model serving should use `nemotron-3-nano-30b-a3b`
  from `oci://registry.redhat.io/rhai/modelcar-nvidia-nemotron-3-nano-30b-a3b-fp8:3.0`
  through RHOAI model serving and vLLM. Validation may deploy Nemotron
  temporarily, verify inference, and remove it for fresh-environment smoke
  testing.
- **Stage 210 fresh image pulls**: The first direct Nemotron deployment can
  spend more than 10 minutes pulling the modelcar and vLLM runtime. Validation
  should use configurable readiness attempts and inspect pod events before
  treating transient `ImagePullBackOff` as a manifest defect.
- **Stage 210 Grafana token ordering**: When Grafana uses a service-account
  token Secret for the Prometheus datasource, GitOps must create the
  `ServiceAccount` before the token Secret. Do not rely on
  `Grafana.spec.serviceAccount` to create the service account early enough for
  Argo CD sync waves.
- **Stage 210 baseline**: Run GuideLLM-style performance baseline tests and
  record concurrency, latency, throughput, and GPU-utilization breakpoints.
- **Stage 220**: Register governed MaaS access for Nemotron and external
  OpenAI `gpt-5.4-mini` through the DNS-safe `gpt-5-4-mini` resource alias
  after MaaS gateway/API compatibility is verified.
- **Stage 220 Gateway TLS**: Prepare a stable `maas-gateway-tls` Secret in
  `openshift-ingress` from the active OpenShift ingress certificate before the
  `maas-default-gateway` sync wave. A missing initial certificate reference can
  degrade the Gateway and prevent later patch hooks from running.
- **Stage 220 service health ordering**: Keep `service/maas-postgres` and
  `statefulset/maas-postgres` in the same Argo CD sync wave. If the Service is
  in an earlier wave, Argo CD can wait for endpoints before the StatefulSet has
  been created.
- **Stage 220 local model readiness**: MaaS CRs and Gateway routes can be
  healthy before the generated Nemotron `LLMInferenceService` reaches
  `Ready=True`. Validate local MaaS inference only after the
  `LLMInferenceService` readiness condition is true.
- **Step 07**: LlamaStack RAG (`lsd-rag`) uses `rh-dev` env vars with pgvector + minimal `userConfig` (overrides `annotation_instruction_template` to prevent `<|file-xxx|>` markers). Key env vars: `ENABLE_PGVECTOR=true`, `PGVECTOR_*` from Secret, `EMBEDDING_PROVIDER=sentence-transformers`, `FMS_ORCHESTRATOR_URL`. Vector stores persist across restarts.
- **Step 07 — rag-chatbot build**: The `rag-chatbot` BuildConfig may not auto-trigger on first deploy. deploy.sh now triggers `oc start-build` automatically.
- **Step 07 — Agent-based system prompt**: Grounding, retry, execute_sql hint, OpenShift hint, concise answers, "don't print Sources".
- **Step 07 — Annotation template override**: LlamaStack's default `annotation_instruction_template` tells the model to cite with `<|file-id|>` format. Overridden via `lsd-rag-config` ConfigMap (Lightspeed team approach) to "Never include any citation that is in the form file-id."
- **Step 07 — max_output_tokens=512**: The chatbot passes `max_output_tokens` from the sidebar slider to the Responses API. Without this, vLLM defaults to 4096, which overflows the 16K context after MCP tool results consume 12-16K tokens (`response.failed: Unknown error`).
- **Step 07 — max_infer_iters=20**: Default raised from 10 to 20. MCP multi-step chains need 4-5 iterations; 10 was too low for database-mcp queries.
- **Step 07 — file_search requires vector store IDs**: The Responses API `file_search` tool requires vector store **IDs** (e.g., `vs_a9e2f1ae-...`), not names. The chatbot resolves names → IDs via `client.vector_stores.list()`; the E2E script resolves at runtime via `/v1/vector_stores`.
- **Step 07 — pgvector anyuid SCC**: `pgvector/pgvector:pg16` entrypoint runs chown/chmod as root. deploy.sh creates a dedicated `llamastack-postgres` SA and grants `anyuid` SCC to it (NOT the default SA — that breaks KServe modelcar mounts).
- **Step 07 — RAG data pipeline**: deploy.sh uploads PDFs via `upload-to-minio.sh` (port-forward + boto3, not mc pods — mc image is distroless), compiles the KFP pipeline, and launches batch ingestion runs for `whoami` and `acme` scenarios via DSPA. KFP v2 requires `version_id` — `run-batch-ingestion.sh` calls `list_pipeline_versions()` automatically. Vector stores MUST be populated for the RAG dropdown to appear.
- **Step 08 — Eval pipeline**: `run-eval.sh` uses the same KFP v2 pattern (upload + version_id + run). Depends on step-07 vector stores being populated — post-RAG evaluation scores will be empty if ingestion hasn't completed.
- **Step 09 — Guardrails validation**: `validate.sh` runs 12 checks including 4 functional detector tests (HAP, prompt injection, PII regex, clean input). Uses orchestrator v2 API on HTTPS port 8032. Detector names in config are `hap`, `prompt_injection`, `regex` (not the ISVC names).
- **Step 07 — Two LSDs coexist**: `lsd-genai-playground` (Dashboard) and `lsd-rag` (GitOps) in same namespace.
- **Step 07/08 — llama-stack-client**: Must be `>=0.4,<0.5` for server v0.4.2.1+rhai0.
- **Stage 210/220 model roles**: Candidate = `nemotron-3-nano-30b-a3b` for
  private-path performance baselining. External OpenAI `gpt-5.4-mini` belongs
  behind MaaS governance using the `gpt-5-4-mini` resource alias when policy
  allows; do not use it to size GPU MachineSets.
- **Step 08 — Reports**: `run-eval-report.sh` uploads HTML to `s3://rhoai-storage/eval-results/{run-id}/`.
- **Step 10 — MCP ConfigMap**: `gen-ai-aa-mcp-servers` in `redhat-ods-applications` managed by ArgoCD. Each JSON entry supports `url`, `description`, and `transport` fields.
- **Step 10 — MCP transport**: The gen-ai backend defaults to `streamable-http` transport. SSE-only servers (database-mcp, slack-mcp) MUST include `"transport": "sse"` in the ConfigMap JSON or the Dashboard shows "Error". OpenShift-MCP (kubernetes-mcp-server) supports streamable-http on `/mcp`.
- **Step 10 — Two MCP client paths**: The Dashboard validates via gen-ai backend (uses ConfigMap transport field). LlamaStack tool_groups use SSE transport natively and always connect via `/sse`. These are independent — changing the ConfigMap does NOT affect LlamaStack tool_groups.
- **Step 10 — MCP tool_groups**: deploy.sh auto-registers `mcp::openshift`, `mcp::database`, `mcp::slack` via LlamaStack API using internal `/sse` URLs. Persist in PostgreSQL across restarts.
- **Step 10 — database-mcp env ordering**: `PGUSER`/`PGPASSWORD` must be defined BEFORE `DATABASE_URI` in the deployment env list (Kubernetes `$(VAR)` expansion requires prior definition).
- **Step 10 — validation**: `validate.sh` runs 19 checks including 7 functional MCP tests (tool_group registration + actual tool invocations against all 3 servers).

## ArgoCD App Standards

The canonical ArgoCD Application standards (syncPolicy, ignoreDifferences, AppProject, labels, manifest-generate-paths) are routed through `.agents/rules/project.md` and detailed in `.agents/skills/project-gitops-authoring/`. Consult those shared files for the authoritative specification.

### Step-specific ignoreDifferences notes

| Pattern | Steps | Why |
|---------|-------|-----|
| `Notebook /spec/template` | 05, 06, 07 | RHOAI injects kube-rbac-proxy sidecar, TLS volumes, labels |
| `Notebook /metadata/labels` | 05, 06, 07 | RHOAI controller adds `opendatahub.io/dashboard`, `odh-managed` |

**Do NOT use:** `ServerSideApply=true` (breaks sync waves) or `Replace=true` (breaks PVCs).

**Note:** `ServerSideDiff=true` may need to be removed from apps with Notebooks if the CRD strips undeclared fields (e.g., `spec.template.metadata`). Step-05 uses client-side diff for this reason.

## Tool-Calling Requirements

| Model Family | `--tool-call-parser` | Chat Template |
|-------------|---------------------|---------------|
| Nemotron 3 Nano | `qwen3_coder` | Use the validated modelcar/vLLM arguments from the active `LLMInferenceService` |
| Llama 3.x | `llama3_json` | `/opt/app-root/template/tool_chat_template_llama3.1_json.jinja` |

## Known Deployment Issues

1. **Argo CD CRD validation** — `SkipDryRunOnMissingResource=true`
2. **Argo CD ComparisonError** — `ServerSideDiff=true` (diff only; apply uses Replace)
3. **GPU Operator** — uses `installPlanApproval: Automatic` (no manual approval needed)
4. **GPU MachineSet AZ** — deploy.sh auto-detects AZ from existing workers (no hardcoded suffix)
5. **AWS GPU vCPU quota** — 64 for sandbox
6. **LlamaStack DSCI CA bundle** — automated in step-02 `deploy.sh` (runtime patch)
7. **Tool-calling args** — Missing `--enable-auto-tool-choice` causes silent Playground failures
8. **MCP ConfigMap transport** — `gen-ai-aa-mcp-servers` in `redhat-ods-applications` required for Dashboard UI. SSE-only servers need `"transport": "sse"` in ConfigMap JSON; streamable-http servers use `/mcp` URL. Without correct transport, Dashboard shows "Error" or "Token Required"
9. **GPU tolerations** — defined directly in ISVC manifests
10. **storage-config `opendatahub.io/managed` label** — Do NOT add `opendatahub.io/managed: "true"` to `storage-config-secret.yaml` in GitOps. The ODH model controller deletes secrets with this label that it didn't create. Label removed.
11. **PVC sync wave alignment** — PVCs using `WaitForFirstConsumer` must be in the same sync wave as their consumer Deployment. Affected: step-04 (wave 2), step-07 postgresql (wave 2). Step-05 upload PVCs have no sync wave (Jobs use `hook: Skip`).
12. **DSPA readiness check** — Use `conditions[?(@.type=="Ready")].status == "True"`, not `conditions[0].type == "Ready"`. The first condition may not be Ready, and the type name does not indicate status.
13. **Service Mesh 3 install plan approval** — RHOAI auto-creates `servicemeshoperator3` Subscription with `installPlanApproval: Manual` and reconciles it back if patched. deploy.sh (step-02) explicitly approves pending install plans.
14. **S3 upload must complete before ISVC creation** — KServe's `storage-initializer` lists S3 once at pod startup. If the upload job is still running, it gets a partial file list and vLLM crashes with "Invalid repository ID." deploy.sh (step-05) now runs the upload job and waits for completion before applying the ArgoCD Application.
15. **Step 11 face-recognition artifact rollback** — Model Registry versions currently point at the same mutable serving URI (`s3://models/face-recognition/`). If the latest promoted model regresses, verify the served object SHA in MinIO and restore a retained KFP training artifact by hash instead of assuming registry version metadata is an immutable artifact pointer.
16. **KServe webhook availability during registry outages** — If `oc patch` or pod admission fails with `no endpoints available for service "kserve-webhook-server-service"`, check `kserve-controller-manager` in `redhat-ods-applications`. During registry.redhat.io 502/504 incidents, pinning the controller to a node with the cached image, and using `imagePullPolicy: IfNotPresent` where the operator does not immediately reconcile it, can restore the webhook. Make the final fix through GitOps/operator state once the registry is healthy.
17. **Fresh Stage 110 DSC readiness leak** — If Stage 110 `validate.sh` fails
with `DataScienceCluster phase Ready (phase=Not Ready)` and DSC conditions name
later-stage components such as `kueue` or `modelsasservice`, Stage 110 is
rendering later-stage component state too early. Move that component enablement
to the owning stage's GitOps hook and keep Stage 110 base-ready.
18. **Stale manual cluster context** — If a manual `oc` command sees resources
from an old cluster, export `.env` values with `set -a; source .env; set +a`
and rerun `oc whoami --show-server`. Do not run live diagnosis from the user's
default kubeconfig by accident.
19. **Service endpoint sync deadlock** — Argo CD can block later waves when an
early-wave Service has no endpoints and the endpoint-producing workload is in a
later wave. Move the Service into the same wave as its first workload or split
health-sensitive resources into the same deployment unit.
20. **Stale Argo CD operation state** — If an Application remains stuck after
the underlying resource is fixed, inspect `.status.operationState` and prefer
documented OpenShift GitOps-compatible refresh or operation-state cleanup over
using an incompatible old local `argocd` CLI.

## Vector Store Persistence (pgvector)

Vector store data persists across pod restarts. The `rh-dev` template manages state through PostgreSQL. MCP tool_groups also persist in PostgreSQL.

## Upload Hooks Awareness

Legacy object-storage model upload jobs are no longer the target model path.
The current target uses Red Hat modelcar images, with
`nemotron-3-nano-30b-a3b` served by `LLMInferenceService`.
