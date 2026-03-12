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

## Step-10 Implementation Plan (Updated: Catalog MCP Servers)

### Architecture Change: Prebuilt Images from Red Hat Ecosystem Catalog

Two of three MCP servers now use prebuilt container images from the [Red Hat Ecosystem Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers):

| Server | Old (custom build) | New (catalog image) |
|--------|-------------------|---------------------|
| openshift-mcp | Python + fastmcp BuildConfig | `quay.io/mcp-servers/kubernetes-mcp-server:latest` |
| database-mcp | Node.js + custom SQL tools BuildConfig | `quay.io/mcp-servers/awslabs/postgres-mcp-server:latest` |
| slack-mcp | Node.js + webhook BuildConfig | **Unchanged** (no catalog option for webhooks) |

### What Already Exists (manifests prepared, NOT yet deployed)

Step-10 has complete GitOps manifests in `gitops/step-10-mcp-integration/base/`:
- **PostgreSQL**: RHEL9 PostgreSQL 15, ACME equipment data with rich schema (views, indexes, calibration records)
- **database-mcp**: Generic PostgreSQL MCP server (catalog image, read-only SQL access)
- **openshift-mcp**: Kubernetes MCP server (catalog image, `--read-only` mode, SSE transport)
- **slack-mcp**: Custom webhook-based Slack MCP server (BuildConfig, real webhook URL)
- **mcp-builds**: 1 BuildConfig (slack-mcp only — down from 3)
- **acme-corp**: Demo namespace with 3 equipment pods (one in CrashLoopBackOff)
- **mcp-servers-configmap**: `gen-ai-aa-mcp-servers` in `redhat-ods-applications`

### What Needs to Be Done

1. **Deploy via ArgoCD** — apply the ArgoCD Application (`step-10-mcp-integration.yaml`)
2. **Wait for slack-mcp build** — only 1 image needs to build (~1-2 min)
3. **Wait for pods** — PostgreSQL, 3 MCP servers (2 start instantly from catalog images), acme-corp demo pods
4. **Verify MCP tool registration** — check that lsd-rag/playground has MCP tool groups
5. **Test the 4-question E2E demo flow** via chatbot or `scripts/validate-demo-flow.sh`

### The 4-Question ACME Demo Flow (Updated for Generic SQL)

```
Q1: List pods in acme-corp project
    → Tool: Kubernetes MCP server (resources_list or pods_list)
    → Expect: 3 pods listed, acme-equipment-0007 in CrashLoopBackOff

Q2: Fetch the equipment name for the failed pod
    → Tool: PostgreSQL MCP server (query — LLM writes SQL)
    → Expect: L-900-08 (L-900 EUV Scanner 08), product: L-900 EUV Calibration Suite

Q3: Search for known issues for the mentioned product
    → Tool: builtin::rag/knowledge_search on acme_corporate collection
    → Expect: chunks about DFO calibration, overlay accuracy, L-900 procedures

Q4: Send a Slack message with the summary to the platform team
    → Tool: slack-mcp send_slack_message or send_equipment_alert
    → Expect: Message delivered to #acme-litho Slack channel via webhook
```

### Key Dependencies

- Q1 requires `openshift-mcp` + `acme-corp` namespace with demo pods
- Q2 requires `database-mcp` + PostgreSQL with seeded equipment data
- Q3 requires step-07 RAG with `acme_corporate` vector store populated
- Q4 requires `slack-mcp` running with `SLACK_WEBHOOK_URL` configured

### Known Issues to Watch For

1. **Catalog images not available** — if `quay.io/mcp-servers/kubernetes-mcp-server:latest` or `quay.io/mcp-servers/awslabs/postgres-mcp-server:latest` are not pullable, restore the BuildConfig YAMLs from git history and re-add to `mcp-builds/kustomization.yaml`
2. **Build pods SchedulingGated** — if Kueue gates the slack-mcp build pod, remove gates: `oc patch pod <name> -n private-ai --type=json -p '[{"op":"remove","path":"/spec/schedulingGates"}]'`
3. **MCP ConfigMap namespace** — `gen-ai-aa-mcp-servers` must be in `redhat-ods-applications`
4. **PostgreSQL MCP transport** — verify the catalog image supports SSE on the expected port
5. **Kubernetes MCP server args** — verify `--transport=sse --sse-port=8000 --read-only` are valid flags
6. **Chatbot Agent-based mode** — the MCP tools show up as available ToolGroups in the sidebar

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
7. **Prefer catalog images**: Use prebuilt images from Red Hat Ecosystem Catalog when they fit the demo flow
8. **Fallback plan**: Keep custom BuildConfig source code in git history for servers where catalog images don't work
