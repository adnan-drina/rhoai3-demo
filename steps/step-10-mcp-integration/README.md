# Step 10: Agentic AI with MCP
**"Enterprise Tool Orchestration"** — Give the AI agent access to live enterprise systems through Model Context Protocol.

## Overview

Steps 07-09 proved your RAG system can retrieve, answer, evaluate, and stay safe. But real enterprise AI goes beyond document Q&A — it takes action. As Red Hat's AI adoption guide describes: *"Agentic architectures orchestrate multiple AI agents that can query databases, call APIs, search internal knowledge bases, and take actions based on results. This moves AI from answering questions to completing tasks."* An AI agent that can only search documents is a chatbot. An AI agent that can query databases, inspect infrastructure, and notify teams is an autonomous operations assistant. As the guide notes: *"Modern models also now support function calling, allowing them to interact with external tools, APIs, and databases, transforming them from text generators to action-takers."*

**Red Hat OpenShift AI 3.3** accelerates agentic AI with built-in support for the **Model Context Protocol (MCP)** — an open source protocol that enables standardized communication between AI applications and external services. MCP servers from the [Red Hat Ecosystem Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers) connect the LLM to live enterprise systems through a unified API layer, with the **Llama Stack API** orchestrating tool calls autonomously.

This step demonstrates the **Accelerating Agentic AI** pillar of Red Hat's AI platform: building workflows that perform complex tasks with limited supervision, using standardized tool interfaces that deploy and manage like any other platform component.

### What Gets Deployed

```text
MCP Integration
├── database-mcp         → EDB Postgres MCP — generic SQL access to ACME equipment DB
├── openshift-mcp        → Kubernetes MCP Server — read-only cluster inspection
├── slack-mcp            → Slack MCP Server — workspace messaging
├── PostgreSQL           → ACME equipment/calibration data
├── MCP ConfigMap        → Dashboard registration for GenAI Playground
├── ACME demo namespace  → Simulated equipment pods (healthy + failing)
└── Tool Groups          → Registered in LlamaStack via deploy.sh
```

| Component | Image Source | Purpose | Namespace |
|-----------|-------------|---------|-----------|
| **database-mcp** | `quay.io/mcp-servers/edb-postgres-mcp` | Generic SQL access to ACME equipment DB | `private-ai` |
| **openshift-mcp** | `quay.io/mcp-servers/kubernetes-mcp-server` | Read-only cluster inspection | `private-ai` |
| **slack-mcp** | `quay.io/mcp-servers/slack-mcp-server` | Slack workspace messaging | `private-ai` |
| **PostgreSQL** | `registry.redhat.io/rhel9/postgresql-15` | ACME equipment/calibration data | `private-ai` |

All MCP server images come from the [Red Hat Ecosystem Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers). Zero on-cluster builds required.

#### ACME Corp Demo Environment

Step 10 deploys an `acme-corp` namespace with three simulated equipment monitoring pods:

| Pod | Equipment | Status | Behavior |
|-----|-----------|--------|----------|
| `acme-equipment-0001` | LITHO-001 | Healthy | Logs OK health checks every 30s |
| `acme-equipment-0005` | L-900-07 | Healthy | Logs OK health checks every 30s |
| `acme-equipment-0007` | L-900-08 | **CrashLoopBackOff** | Exits with DFO calibration error |

Pod `acme-equipment-0007` is deliberately broken — the demo agent investigates this failure.

#### MCP Server Tools

**database-mcp** (EDB Postgres MCP) — generic SQL access, LLM discovers schema autonomously:

| Tool | Description |
|------|-------------|
| `list_schemas` | List database schemas |
| `list_objects` | List tables/views in a schema |
| `execute_sql` | Execute SQL queries |
| `get_object_details` | Column details for a table |
| `explain_query` | Query execution plan |
| `analyze_db_health` | Database health checks |

**openshift-mcp** (Kubernetes MCP Server) — read-only cluster inspection:

| Tool | Description |
|------|-------------|
| `pods_list_in_namespace` | List pods in a namespace |
| `pods_get` | Get pod details |
| `pods_log` | Get pod logs |
| `events_list` | List cluster events |
| `namespaces_list` | List namespaces |
| `resources_list` / `resources_get` | Generic resource operations |

**slack-mcp** (Slack MCP Server) — workspace messaging:

| Tool | Description |
|------|-------------|
| `conversations_add_message` | Post message to a channel |
| `channels_list` | List workspace channels |
| `conversations_history` | Get channel message history |
| `conversations_search_messages` | Search messages |

Manifests: [`gitops/step-10-mcp-integration/base/`](../../gitops/step-10-mcp-integration/base/)

### Design Decisions

> **Red Hat Ecosystem Catalog images:** All 3 MCP servers use prebuilt images from `quay.io/mcp-servers/`. Zero on-cluster builds, faster deployment, trusted supply chain.

> **Generic SQL access:** The Database MCP uses EDB Postgres MCP rather than custom endpoints. The LLM discovers the schema autonomously and writes targeted SQL — no application-specific API required.

> **No lsd-rag restart:** MCP tool_groups are registered via the LlamaStack API and persist in PostgreSQL. Only the Dashboard Playground LSD is restarted. Vector store data is unaffected.

> **MCP transport configuration (RHOAI 3.3):** The gen-ai backend defaults to `streamable-http` transport (POST directly to URL). MCP servers that only support SSE transport (GET `/sse` + POST `/messages`) **must** include `"transport": "sse"` in the ConfigMap JSON, or the Dashboard shows "Error" status. OpenShift-MCP (kubernetes-mcp-server v0.0.54+) supports streamable-http on `/mcp`, so its URL uses `/mcp` instead of `/sse`. LlamaStack tool_group registrations still use `/sse` URLs since LlamaStack's MCP client handles SSE natively.

> **GitOps-managed ConfigMap:** The `gen-ai-aa-mcp-servers` ConfigMap is managed by ArgoCD, following the [RHOAI 3.3 documentation pattern](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user).

> **Slack credentials at deploy time:** Bot token is created from `.env` by deploy.sh (not stored in git).

### Deploy

```bash
./steps/step-10-mcp-integration/deploy.sh     # ArgoCD app + Slack secret + MCP tool_group registration
./steps/step-10-mcp-integration/validate.sh   # 19 checks: infrastructure + functional MCP tests
```

### What to Verify After Deployment

`validate.sh` runs 19 checks: 12 infrastructure + 7 functional MCP tests.

| Check | What It Tests | Pass Criteria |
|-------|--------------|---------------|
| ArgoCD sync/health | App is Synced (Degraded expected — 0007 CrashLoop) | Synced |
| MCP deployments | database-mcp, openshift-mcp, slack-mcp | All available |
| PostgreSQL | Pod running | Ready |
| ConfigMap | `gen-ai-aa-mcp-servers` in `redhat-ods-applications` | Exists |
| ACME environment | acme-corp namespace, 3 equipment pods | Namespace + 3 pods |
| MCP connectivity | Pod found for each server | 3 pods |
| **Tool_group registration** | mcp::openshift, mcp::database, mcp::slack | All registered in lsd-rag |
| **OpenShift MCP** | `pods_list_in_namespace(acme-corp)` | Returns acme-equipment pods |
| **Database MCP** | `list_schemas` | Returns public schema |
| **Database MCP** | `execute_sql` for acme-equipment-0007 | Returns L-900-08 |
| **Slack MCP** | `channels_list` | Returns demo channel |

## The Demo

> In this demo, the AI agent autonomously resolves an equipment alert using four integrated enterprise systems. Starting from a failing pod on OpenShift, it identifies the equipment in a database, finds the resolution procedure in internal documents, and notifies the platform team on Slack — all in a single conversation, with no scripted logic.

In the chatbot, select `granite-8b-agent`, switch to **Agent-based** mode, and toggle on all MCP servers (database, openshift, slack).

### Inspect the Cluster

> An equipment monitoring pod is failing in the `acme-corp` namespace. We ask the agent to investigate — it will query the live OpenShift cluster through the Kubernetes MCP Server to find the problem.

1. Ask: *"List pods in acme-corp project"*

**Expect:** The agent calls `pods_list_in_namespace(namespace="acme-corp")` via the OpenShift MCP server. Returns 3 pods — two healthy, one (`acme-equipment-0007`) in CrashLoopBackOff.

> The agent just queried the live OpenShift cluster through MCP. No kubectl, no scripts — the LLM decided which API to call and parsed the response. It immediately identifies the failing pod.

### Identify the Equipment

> The agent found a failing pod, but a pod name is not actionable for a maintenance team. We need the actual equipment identifier. The agent will pivot to the equipment database and look up the mapping.

1. Ask: *"Fetch the equipment name for the failed pod"*

**Expect:** The agent calls `execute_sql` via the Database MCP server, querying the `acme_pod_equipment_map` table. Returns L-900-08 (L-900 EUV Scanner 08), product: L-900 EUV Calibration Suite.

> The LLM discovered the database schema on its own, wrote a SQL query joining the pod name to equipment records, and returned the specific scanner model. No one pre-built this query — the agent constructed it from the schema and the conversation context.

### Search Known Issues

> We now know which piece of equipment is failing. The agent will search the internal knowledge base — the same RAG vector store from Step 07 — for documented resolution procedures.

1. Ask: *"Search for known issues for the mentioned product"*

**Expect:** The agent calls `knowledge_search` against the `acme_corporate` vector store. Returns the DFO calibration procedure documentation for the L-900 product line.

> This is where it all comes together. The agent combined live cluster data, a database lookup, and document retrieval in a single conversation to find the exact calibration procedure for the scanner that is failing.

### Notify the Team

> The agent has the full picture: which pod failed, which equipment it maps to, and the documented resolution procedure. Now it delivers the summary to the platform team on Slack.

1. Ask: *"Send a Slack message with the summary to the platform team"*

**Expect:** The agent calls `conversations_add_message` via the Slack MCP server, posting a structured summary — pod name, equipment ID, product line, known issue, and recommended procedure — to `#all-acme-mcp-demo`.

> Four questions, four different enterprise systems — OpenShift cluster, PostgreSQL database, RAG document store, and Slack. *"Think of [Llama Stack] as Kubernetes for AI agents: just as Kubernetes orchestrates containers, Llama Stack orchestrates agents and their providers"* — and MCP provides the standardized tool interfaces from the Red Hat Ecosystem Catalog. This is what enterprise agentic AI looks like on Red Hat OpenShift AI.

## Key Takeaways

**For business stakeholders:**

- AI agents move from answering questions to resolving incidents — the model investigates, correlates, and notifies without human intervention
- MCP provides a standardized protocol for connecting AI to any enterprise system — databases, infrastructure, messaging — without custom integration code
- MCP servers are available from the [Red Hat Ecosystem Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers), extending the trusted supply chain to AI tooling

**For technical teams:**

- MCP servers deploy as standard containers from `quay.io/mcp-servers/` — zero on-cluster builds, managed via GitOps like every other component
- The Llama Stack API provides a unified entry point for tool orchestration — tool_groups register once and persist across restarts
- The agent discovers database schemas and writes SQL autonomously — no application-specific APIs or predefined queries required

## Troubleshooting

### Dashboard shows "Error" for MCP servers

**Symptom:** MCP servers show "Error" status in Gen AI Studio > AI asset endpoints > MCP servers tab, despite pods running and responding correctly.

**Root Cause:** The RHOAI 3.3 gen-ai backend defaults to `streamable-http` transport, which POSTs an `initialize` JSON-RPC call directly to the configured URL. MCP servers using SSE transport return `405 Method Not Allowed` because their `/sse` endpoint only accepts GET.

**Diagnosis:**
```bash
TOKEN=$(oc whoami -t)
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://$(oc get route data-science-gateway -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo 'data-science-gateway.apps.<cluster>')/gen-ai/api/v1/mcp/status?namespace=acme-corp&server_url=<url-encoded-mcp-url>"
```

**Solution:** Add `"transport": "sse"` to the ConfigMap JSON for servers that only support SSE:
```json
{
  "url": "https://<route>/sse",
  "transport": "sse",
  "description": "..."
}
```

### Dashboard shows "Token Required" for OpenShift-MCP

**Symptom:** OpenShift-MCP shows "Token Required" in the Dashboard.

**Root Cause:** The gen-ai backend POSTs to `/sse` using streamable-http transport, but `/sse` on kubernetes-mcp-server expects a session ID from a prior SSE handshake. The error message `"sessionid must be provided"` is misinterpreted as a token issue.

**Solution:** Change the URL to `/mcp` which supports streamable-http natively:
```json
{
  "url": "https://<route>/mcp",
  "description": "..."
}
```

## References

- [RHOAI 3.3 — Configuring MCP Servers](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user)
- [Red Hat Ecosystem Catalog — MCP Servers](https://catalog.redhat.com/en/categories/ai/mcpservers)
- [Kubernetes MCP Server (Red Hat Developer)](https://developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Red Hat OpenShift AI — Product Page](https://www.redhat.com/en/products/ai/openshift-ai)
- [Red Hat OpenShift AI — Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet)
- [Get started with AI for enterprise organizations — Red Hat](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook)

## Next Steps

- **Step 11**: [Face Recognition](../step-11-face-recognition/README.md) — Predictive AI on RHOAI: train a YOLO11 model, deploy on OpenVINO, CPU-only inference
