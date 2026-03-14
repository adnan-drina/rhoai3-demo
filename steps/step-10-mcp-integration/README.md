# Step 10: MCP Integration
**"Enterprise Tool Orchestration"** — Give the AI agent access to live enterprise systems through Model Context Protocol.

## The Business Story

Steps 07-09 proved your RAG system can retrieve, answer, evaluate, and stay safe. But real enterprise AI goes beyond document Q&A. Step 10 adds MCP (Model Context Protocol) servers that give the LLM agent access to live systems: query an equipment database, inspect an OpenShift cluster, or send team notifications — all through standardized tool interfaces that the model invokes autonomously.

This completes the **four pillars of Red Hat AI**:
1. Flexible Foundation (steps 01-05)
2. Data and AI Integration (steps 06-08)
3. Trust and Governance (step 09)
4. **Integration and Automation (step 10)**

## What It Does

```
GenAI Playground / Chatbot
    |
    |--- gen-ai-aa-mcp-servers ConfigMap -> lists 3 MCP servers
    |
    v
LlamaStack (lsd-genai-playground / lsd-rag)
    |--- tool_groups: mcp::database, mcp::openshift, mcp::slack
    |--- granite-8b-agent decides which tools to invoke
    |
    v
MCP Servers (SSE endpoints in private-ai)
    |--- database-mcp:8080/sse  -> PostgreSQL (EDB Postgres MCP)
    |--- openshift-mcp:8000/sse -> Kubernetes API (kubernetes-mcp-server)
    |--- slack-mcp:8080/sse     -> Slack API (slack-mcp-server)
```

| Component | Image Source | Purpose |
|-----------|-------------|---------|
| **database-mcp** | `quay.io/mcp-servers/edb-postgres-mcp:10-03-2025` | Generic SQL access to ACME equipment DB |
| **openshift-mcp** | `quay.io/mcp-servers/kubernetes-mcp-server:2025-11-24` | Read-only cluster inspection |
| **slack-mcp** | `quay.io/mcp-servers/slack-mcp-server:10-03-2025` | Slack workspace messaging |
| **PostgreSQL** | `registry.redhat.io/rhel9/postgresql-15` | ACME equipment/calibration data |

All MCP server images come from the [Red Hat Ecosystem Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers). Zero on-cluster builds required.

### ACME Corp Demo Environment

Step 10 deploys an `acme-corp` namespace with three simulated equipment monitoring pods:

| Pod | Equipment | Status | Behavior |
|-----|-----------|--------|----------|
| `acme-equipment-0001` | LITHO-001 | Healthy | Logs OK health checks every 30s |
| `acme-equipment-0005` | L-900-07 | Healthy | Logs OK health checks every 30s |
| `acme-equipment-0007` | L-900-08 | **CrashLoopBackOff** | Exits with DFO calibration error |

Pod `acme-equipment-0007` is deliberately broken — the demo agent investigates this failure.

### MCP Server Tools

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

## Demo Walkthrough

In the chatbot, select `granite-8b-agent`, switch to **Agent-based** mode, and toggle on all MCP servers (database, openshift, slack).

### Scene 1: List Pods in acme-corp (openshift-mcp)

**Prompt:** "List pods in acme-corp project"

The agent calls `pods_list_in_namespace(namespace="acme-corp")` via the OpenShift MCP server.

**Expected result:** Returns 3 pods — two healthy, one (`acme-equipment-0007`) in CrashLoopBackOff.

_What to say: "The agent just queried the live OpenShift cluster through MCP. No kubectl, no scripts — the LLM decided which API to call and parsed the response. It immediately spots the failing pod."_

### Scene 2: Fetch Equipment Name (database-mcp)

**Prompt:** "Fetch the equipment name for the failed pod"

The agent calls `execute_sql` via the Database MCP server, querying the `acme_pod_equipment_map` table.

**Expected result:** Returns L-900-08 (L-900 EUV Scanner 08), product: L-900 EUV Calibration Suite.

_What to say: "Now it pivots to the equipment database. The LLM discovered the schema on its own, wrote a SQL query joining the pod name to equipment records, and returned the specific scanner model. No one taught it this query."_

### Scene 3: Search Known Issues (RAG)

**Prompt:** "Search for known issues for the mentioned product"

The agent calls `knowledge_search` against the `acme_corporate` vector store (RAG from step-07).

**Expected result:** Returns DFO calibration procedure documentation for the L-900 product line.

_What to say: "This is where it all comes together — the agent combines live cluster data, database lookups, and document retrieval in a single conversation. It found the calibration procedure for the exact scanner that's failing."_

### Scene 4: Send Slack Message (slack-mcp)

**Prompt:** "Send a Slack message with the summary to the platform team"

The agent calls `conversations_add_message` via the Slack MCP server, posting to `#all-acme-mcp-demo`.

**Expected result:** A structured summary — pod name, equipment ID, product line, known issue, and recommended procedure — delivered to the real Slack workspace.

_What to say: "Four questions, four different systems — OpenShift cluster, PostgreSQL database, RAG document store, and Slack. The LLM orchestrated all of it autonomously through MCP. This is what enterprise AI integration looks like."_

## Design Decisions

> **Red Hat Ecosystem Catalog images:** All 3 MCP servers use prebuilt images from `quay.io/mcp-servers/`. Zero on-cluster builds, faster deployment, trusted supply chain.

> **Generic SQL access:** The Database MCP uses EDB Postgres MCP rather than custom endpoints. The LLM discovers the schema autonomously and writes targeted SQL — no application-specific API required.

> **No lsd-rag restart:** MCP tool_groups are registered via the LlamaStack API and persist in PostgreSQL. Only the Dashboard Playground LSD is restarted. Vector store data is unaffected.

> **GitOps-managed ConfigMap:** The `gen-ai-aa-mcp-servers` ConfigMap is managed by ArgoCD, following the [RHOAI 3.3 documentation pattern](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user).

> **Slack credentials at deploy time:** Bot token is created from `.env` by deploy.sh (not stored in git).

## References

- [RHOAI 3.3 — Configuring MCP Servers](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user)
- [Red Hat Ecosystem Catalog — MCP Servers](https://catalog.redhat.com/en/categories/ai/mcpservers)
- [Kubernetes MCP Server (Red Hat Developer)](https://developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management)
- [Model Context Protocol](https://modelcontextprotocol.io/)

## What to Verify After Deployment

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

## Operations

```bash
./steps/step-10-mcp-integration/deploy.sh     # ArgoCD app + Slack secret + MCP tool_group registration
./steps/step-10-mcp-integration/validate.sh   # 19 checks: infrastructure + functional MCP tests
```
