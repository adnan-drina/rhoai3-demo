# Next Session Plan — Step-10 MCP Integration

## Context from Previous Sessions

Read `docs/next-session-plan.md` and `.cursor/skills/deploy-and-evaluate/SKILL.md` for full context. Before making ANY changes, review this critical state:

### Current Cluster State

| App | Status | Notes |
|-----|--------|-------|
| step-01 through step-05 | Synced, Healthy | |
| step-06-model-metrics | OutOfSync, Healthy | |
| step-07-rag | Unknown, Healthy | **DO NOT sync** — ConfigMap changes restart lsd-rag → vector store data loss |
| step-08-model-evaluation | Synced, Healthy | |
| step-09-guardrails | Synced, Healthy | HAP + injection + PII regex all working |
| step-10-mcp-integration | **NOT deployed** | ArgoCD app not yet created |

### Running Services
- lsd-rag: Running (v0.4.2.1+rhai0) with eval, localfs, basic, llm-as-judge providers
- lsd-genai-playground: Running (Dashboard-created, NOT GitOps-managed)
- granite-8b-agent: Running (1 GPU)
- mistral-3-bf16: Running (4 GPU)
- Guardrails Orchestrator: Running (3/3), all 4 services HEALTHY
- Chatbot: Running with guardrails active in Agent mode
- Vector stores: acme_corporate (8/8), eu_ai_act (3/3 or 2/2), whoami (1/1)

### CRITICAL — Do NOT Do These Things
- Do NOT sync step-07 ArgoCD app without checking what will change — lsd-rag ConfigMap changes trigger pod restarts which lose vector store file associations
- Do NOT install llama-stack-client without version pin — default pip gets 0.6.0 which is incompatible (HTTP 426)
- Do NOT register non-running models in the Playground — causes connection errors
- Do NOT run multiple KFP pipeline scenarios simultaneously — Docling crashes under concurrent load
- Build pods may get SchedulingGated by Kueue — our step-03 fix removed namespace-wide Kueue management, so builds should be fine now

---

## Step-10 Implementation Plan

### What Already Exists (NOT yet deployed)

Step-10 has complete GitOps manifests in `gitops/step-10-mcp-integration/base/`:
- **PostgreSQL**: Equipment/calibration data with init schema
- **database-mcp**: MCP server for querying equipment DB (BuildConfig + Deployment)
- **openshift-mcp**: MCP server for K8s cluster inspection (ServiceAccount + ClusterRoleBinding)
- **slack-mcp**: Demo-mode Slack notification MCP server
- **mcp-builds**: 3 BuildConfigs that build MCP server images from source
- **acme-corp**: Demo namespace with 3 equipment pods (one in CrashLoopBackOff)
- **mcp-servers-configmap**: `gen-ai-aa-mcp-servers` in `redhat-ods-applications` for Playground discovery

The `deploy.sh` and `README.md` exist with documentation.

### What Needs to Be Done

1. **Deploy via ArgoCD** — apply the ArgoCD Application (`step-10-mcp-integration.yaml`)
2. **Wait for builds** — 3 MCP server images need to build (each ~1-2 min)
3. **Wait for pods** — PostgreSQL, 3 MCP servers, acme-corp demo pods
4. **Verify MCP tool registration** — check that lsd-rag has `mcp::database`, `mcp::openshift`, `mcp::slack` tool groups
5. **Register MCP ConfigMap in Playground namespace** — `gen-ai-aa-mcp-servers` ConfigMap goes to `redhat-ods-applications`
6. **Test the 4-question E2E demo flow** via chatbot or `scripts/validate-demo-flow.sh`

### The 4-Question ACME Demo Flow

The validation executes these questions sequentially:

```
Q1: List pods in acme-corp project
    → Tool: openshift-mcp list_pods_summary(namespace="acme-corp")
    → Expect: 3 pods listed, acme-equipment-0007 in CrashLoopBackOff

Q2: Fetch the equipment name for the failed pod
    → Tool: database-mcp query_pod_equipment(pod_name="acme-equipment-0007")
    → Expect: "L-900-08 (L-900 EUV Scanner 08), product: L-900 EUV Calibration Suite"

Q3: Search for known issues for the mentioned product
    → Tool: builtin::rag/knowledge_search on acme_corporate collection
    → Expect: chunks about DFO calibration, overlay accuracy, L-900 procedures

Q4: Send a Slack message with the summary to the platform team
    → Tool: slack-mcp send_slack_message or send_equipment_alert
    → Expect: "Message sent to #acme-litho (demo mode -- logged only)"
```

### Key Dependencies

- Q1 requires `openshift-mcp` + `acme-corp` namespace with demo pods
- Q2 requires `database-mcp` + PostgreSQL with seeded equipment data
- Q3 requires step-07 RAG with `acme_corporate` vector store populated
- Q4 requires `slack-mcp` running

### Known Issues to Watch For

1. **Build pods SchedulingGated** — if Kueue gates build pods, remove gates: `oc patch pod <name> -n private-ai --type=json -p '[{"op":"remove","path":"/spec/schedulingGates"}]'`
2. **MCP ConfigMap namespace** — `gen-ai-aa-mcp-servers` must go to `redhat-ods-applications` (NOT `private-ai`)
3. **Playground MCP discovery** — only works in lsd-genai-playground (Dashboard-created), not lsd-rag (GitOps)
4. **lsd-rag tool_groups** — mcp::database, mcp::openshift, mcp::slack are already registered in the lsd-rag config via `registered_resources.tool_groups`
5. **Chatbot Agent-based mode** — the MCP tools show up as available ToolGroups in the sidebar (database, openshift, slack)

### Validation

```bash
./steps/step-10-mcp-integration/validate.sh
./scripts/validate-demo-flow.sh   # Full 4-question E2E test
```

---

## Guidelines from This Session

1. **GitOps first**: Every step MUST have `gitops/step-XX/base/`, ArgoCD Application, and `deploy.sh` that applies the ArgoCD app as first action
2. **Never apply manifests directly** for ArgoCD-managed resources — commit to git, push, let ArgoCD sync
3. **LSD restart = data loss**: Any change to lsd-rag ConfigMap restarts the pod and loses vector store file associations. Plan for re-ingestion
4. **Test before concluding**: Don't claim something works without actually running the test in the browser or via API
5. **Pin llama-stack-client>=0.4,<0.5**: Server is v0.4.2.1+rhai0
6. **Use @RHOAI 3.3 docs** for all implementation decisions
