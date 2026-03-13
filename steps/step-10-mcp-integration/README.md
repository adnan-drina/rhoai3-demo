# Step 10: MCP Integration

**"Enterprise Tool Orchestration"** - Give the AI agent access to live enterprise systems through Model Context Protocol.

## The Business Story

Steps 07-09 proved your RAG system can retrieve, answer, evaluate, and stay safe. But real enterprise AI goes beyond document Q&A. Step 10 adds MCP (Model Context Protocol) servers that give the LLM agent access to live systems: query an equipment database, inspect an OpenShift cluster, or send team notifications -- all through standardized tool interfaces that the model invokes autonomously.

This completes the **four pillars of Red Hat AI**:
1. Flexible Foundation (steps 01-05)
2. Data and AI Integration (steps 06-08)
3. Trust and Governance (step 09)
4. **Integration and Automation (step 10)**

| Component | Image Source | Purpose |
|-----------|-------------|---------|
| **database-mcp** | `quay.io/mcp-servers/edb-postgres-mcp:10-03-2025` | Generic SQL access to ACME equipment DB |
| **openshift-mcp** | `quay.io/mcp-servers/kubernetes-mcp-server:2025-11-24` | Read-only cluster inspection |
| **slack-mcp** | `quay.io/mcp-servers/slack-mcp-server:10-03-2025` | Slack workspace messaging |
| **PostgreSQL** | `registry.redhat.io/rhel9/postgresql-15` | ACME equipment/calibration data |

All MCP server images come from the [Red Hat Ecosystem Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers). Zero on-cluster builds required.

## Architecture

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

## Prerequisites

```bash
# granite-8b-agent with tool-calling enabled (step-05)
oc get isvc granite-8b-agent -n private-ai

# LlamaStack running (step-05 or step-07)
oc get llamastackdistribution -n private-ai
```

## Deployment

### A) One-shot (recommended)

```bash
./steps/step-10-mcp-integration/deploy.sh
```

This will:
1. Create Slack credentials Secret from `.env` (if `SLACK_BOT_TOKEN` is set)
2. Deploy via ArgoCD (all catalog images, no builds)
3. Wait for PostgreSQL and MCP servers
4. Verify MCP ConfigMap in Dashboard namespace
5. Restart Playground LSD (safe, no RAG data loss)

### B) Step-by-step (manual)

```bash
# 1. Create Slack credentials (from .env)
source .env
oc create secret generic slack-mcp-credentials \
  --from-literal=SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
  -n private-ai --dry-run=client -o yaml | oc apply -f -

# 2. Deploy via ArgoCD
oc apply -f gitops/argocd/app-of-apps/step-10-mcp-integration.yaml

# 3. Wait for servers (all use prebuilt images — start in seconds)
oc get deploy database-mcp openshift-mcp slack-mcp -n private-ai -w

# 4. Verify Playground ConfigMap (managed by ArgoCD)
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications
```

## ACME Corp Demo Environment

Step 10 deploys an `acme-corp` namespace with three simulated equipment monitoring pods:

| Pod | Equipment | Status | Behavior |
|-----|-----------|--------|----------|
| `acme-equipment-0001` | LITHO-001 | Healthy | Logs OK health checks every 30s |
| `acme-equipment-0005` | L-900-07 | Healthy | Logs OK health checks every 30s |
| `acme-equipment-0007` | L-900-08 | **CrashLoopBackOff** | Exits with DFO calibration error |

Pod `acme-equipment-0007` is deliberately broken — the demo agent investigates this failure.

## Demo Scenarios

### The End-to-End Demo (4-question flow)

In the chatbot, select `granite-8b-agent`, switch to **Agent-based** mode, and toggle on all MCP servers (database, openshift, slack):

**Q1: "List pods in acme-corp project"**
Agent calls `pods_list_in_namespace(namespace="acme-corp")` via OpenShift MCP.
Returns 3 pods — `acme-equipment-0007` in CrashLoopBackOff.

**Q2: "Fetch the equipment name for the failed pod"**
Agent calls `execute_sql` via Database MCP with a query on `acme_pod_equipment_map`.
Returns: L-900-08 (L-900 EUV Scanner 08), product: L-900 EUV Calibration Suite.

**Q3: "Search for known issues for the mentioned product"**
Agent calls `knowledge_search` (RAG) against the `acme_corporate` vector store.
Returns: DFO calibration procedure documentation.

> **Note:** Requires ACME PDFs ingested via step-07.

**Q4: "Send a Slack message with the summary to the platform team"**
Agent calls `conversations_add_message` via Slack MCP to `#all-acme-mcp-demo`.
Message delivered to real Slack workspace.

## MCP Server Details

### database-mcp (EDB Postgres MCP)

Generic PostgreSQL MCP server providing read-only SQL access. The LLM discovers the schema and writes queries autonomously.

| Tool | Description |
|------|-------------|
| `list_schemas` | List database schemas |
| `list_objects` | List tables/views in a schema |
| `execute_sql` | Execute SQL queries |
| `get_object_details` | Column details for a table |
| `explain_query` | Query execution plan |
| `analyze_db_health` | Database health checks |

### openshift-mcp (Kubernetes MCP Server)

Read-only Kubernetes/OpenShift MCP server. Single Go binary from [containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server).

| Tool | Description |
|------|-------------|
| `pods_list_in_namespace` | List pods in a namespace |
| `pods_get` | Get pod details |
| `pods_log` | Get pod logs |
| `events_list` | List cluster events |
| `namespaces_list` | List namespaces |
| `resources_list` / `resources_get` | Generic resource operations |

### slack-mcp (Slack MCP Server)

Slack workspace integration via [korotovsky/slack-mcp-server](https://github.com/korotovsky/slack-mcp-server). Requires bot token from [api.slack.com/apps](https://api.slack.com/apps).

| Tool | Description |
|------|-------------|
| `conversations_add_message` | Post message to a channel |
| `channels_list` | List workspace channels |
| `conversations_history` | Get channel message history |
| `conversations_search_messages` | Search messages |

Required Slack App scopes: `channels:read`, `channels:history`, `chat:write`, `users:read`

## Troubleshooting

### MCP server not starting

```bash
oc logs deploy/database-mcp -n private-ai
oc logs deploy/openshift-mcp -n private-ai
oc logs deploy/slack-mcp -n private-ai
```

### Slack MCP: `not_in_channel`

The bot app must be invited to the target channel:
```
/invite @<bot-name>
```
in the Slack channel.

### Slack MCP: `missing_scope`

Add required scopes to the Slack App at [api.slack.com/apps](https://api.slack.com/apps) → OAuth & Permissions → Bot Token Scopes.

### MCP tools not visible in chatbot

```bash
# Verify ConfigMap
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o yaml

# Verify LlamaStack tool_groups
oc exec deploy/lsd-rag -n private-ai -- \
  curl -s http://localhost:8321/v1/toolgroups | python3 -m json.tool
```

### Agent doesn't call MCP tools

1. Ensure **Agent-based** mode is selected in the chatbot
2. Toggle ON the MCP servers (database, openshift, slack) in the sidebar
3. Verify granite-8b-agent has tool-calling enabled:

```bash
oc get isvc granite-8b-agent -n private-ai \
  -o jsonpath='{.spec.predictor.model.args}' | tr ',' '\n' | grep tool
```

### PostgreSQL tables empty

The init schema runs via a `postStart` lifecycle hook. If tables are missing:
```bash
oc exec deploy/postgresql -n private-ai -- \
  psql -U acmeadmin -d acme_equipment -f /opt/app-root/src/postgresql-start/init.sql
```

## GitOps Structure

```
gitops/step-10-mcp-integration/
├── base/
│   ├── kustomization.yaml
│   ├── mcp-servers-configmap.yaml  # gen-ai-aa-mcp-servers (redhat-ods-applications)
│   ├── acme-corp/                  # Demo namespace + 3 pods + RBAC
│   ├── postgresql/                 # RHEL9 PostgreSQL 15 + init schema
│   ├── database-mcp/              # Deployment (catalog) + Service
│   ├── openshift-mcp/             # Deployment (catalog) + SA + ClusterRoleBinding
│   └── slack-mcp/                 # Deployment (catalog) + ConfigMap + Service

steps/step-10-mcp-integration/
├── deploy.sh                       # ArgoCD deploy + Slack secret from .env
├── validate.sh
└── README.md
```

## Rollback / Cleanup

```bash
oc delete application step-10-mcp-integration -n openshift-gitops
oc delete configmap gen-ai-aa-mcp-servers -n redhat-ods-applications
oc delete clusterrolebinding openshift-mcp-view
oc delete secret slack-mcp-credentials -n private-ai
```

## Design Decisions

> **Design Decision:** All 3 MCP servers use prebuilt images from the [Red Hat Ecosystem Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers) (`quay.io/mcp-servers/`). Zero on-cluster builds, faster deployment, trusted supply chain.

> **Design Decision:** The Database MCP uses generic SQL access (EDB Postgres MCP) rather than custom tool endpoints. The LLM discovers the schema autonomously and writes targeted SQL.

> **Design Decision:** deploy.sh does NOT restart lsd-rag. MCP tool_groups are registered via the LlamaStack API (not in config files) and persist in PostgreSQL across restarts. Only the Dashboard Playground LSD is restarted. Vector store data persists via pgvector.

> **Design Decision:** The `gen-ai-aa-mcp-servers` ConfigMap is managed by ArgoCD (not applied manually by deploy.sh), following the [RHOAI 3.3 documentation pattern](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user).

> **Design Decision:** Slack credentials are created from `.env` at deploy time (not in git). The bot token is required for the catalog Slack MCP server.

## References

- [RHOAI 3.3 -- Configuring MCP Servers](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user)
- [Red Hat Ecosystem Catalog -- MCP Servers](https://catalog.redhat.com/en/categories/ai/mcpservers)
- [Kubernetes MCP Server (Red Hat Developer)](https://developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management)
- [Model Context Protocol](https://modelcontextprotocol.io/)
