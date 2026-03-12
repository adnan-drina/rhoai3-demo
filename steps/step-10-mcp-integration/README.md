# Step 10: MCP Integration

**"Enterprise Tool Orchestration"** - Give the AI agent access to live enterprise systems through Model Context Protocol.

## The Business Story

Steps 07-09 proved your RAG system can retrieve, answer, evaluate, and stay safe. But real enterprise AI goes beyond document Q&A. Step 10 adds MCP (Model Context Protocol) servers that give the LLM agent access to live systems: query an equipment database, inspect an OpenShift cluster, or send team notifications -- all through standardized tool interfaces that the model invokes autonomously.

This completes the **four pillars of Red Hat AI**:
1. Flexible Foundation (steps 01-05)
2. Data and AI Integration (steps 06-08)
3. Trust and Governance (step 09)
4. **Integration and Automation (step 10)**

| Component | Image Source | Purpose | Persona |
|-----------|-------------|---------|---------|
| **database-mcp** | [Red Hat Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers) (`awslabs/postgres-mcp-server`) | Generic SQL access to ACME equipment DB | Manufacturing Engineer |
| **openshift-mcp** | [Red Hat Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers) (`kubernetes-mcp-server`) | Read-only cluster inspection | Platform Engineer |
| **slack-mcp** | Custom build (webhook-based) | Real Slack notifications via webhook | Operations Team |
| **PostgreSQL** | `registry.redhat.io/rhel9/postgresql-15` | ACME equipment/calibration data | Data layer |
| **Playground ConfigMap** | N/A | MCP server discovery in UI | Platform Admin |

## Architecture

```
GenAI Playground (RHOAI Dashboard)
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
    |--- database-mcp:8080/sse  -> PostgreSQL (Red Hat Catalog: awslabs/postgres-mcp-server)
    |--- openshift-mcp:8000/sse -> Kubernetes API (Red Hat Catalog: kubernetes-mcp-server)
    |--- slack-mcp:8080/sse     -> Slack webhook (custom build)
```

## Prebuilt Images from Red Hat Ecosystem Catalog

Two of three MCP servers use prebuilt container images from the [Red Hat Ecosystem Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers), eliminating the need for on-cluster builds:

| Server | Catalog Image | Source |
|--------|--------------|--------|
| database-mcp | `quay.io/mcp-servers/awslabs/postgres-mcp-server:latest` | [AWS Labs PostgreSQL MCP](https://github.com/awslabs/mcp/tree/main/src/postgres-mcp-server) |
| openshift-mcp | `quay.io/mcp-servers/kubernetes-mcp-server:latest` | [containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server) |
| slack-mcp | Custom BuildConfig (UBI9 Node.js) | Webhook-based, no catalog equivalent |

> **Reference projects:**
> - [burrsutter/fantaco-redhat-one-2026](https://github.com/burrsutter/fantaco-redhat-one-2026/tree/main/mcp-examples) — LlamaStack + MCP registration patterns
> - [rhoai-genaiops/experiments/8-agents](https://github.com/rhoai-genaiops/experiments/tree/20b537e60c35e4ffdd5df34a611a2a41fc119d3b/8-agents) — MCP server notebooks

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
1. Deploy PostgreSQL with ACME equipment data
2. Trigger BuildConfig for slack-mcp image (only custom build)
3. Deploy 3 MCP servers (2 prebuilt from catalog + 1 custom build)
4. Register MCP servers in the GenAI Playground via ArgoCD-managed ConfigMap
5. Restart LlamaStack pods to discover MCP tools

### B) Step-by-step (manual)

```bash
# 1. Deploy via ArgoCD
oc apply -f gitops/argocd/app-of-apps/step-10-mcp-integration.yaml

# 2. Wait for slack-mcp build (only custom build)
oc get builds -n private-ai -l buildconfig=slack-mcp -w

# 3. Wait for servers (database-mcp and openshift-mcp start immediately from catalog images)
oc get deploy database-mcp openshift-mcp slack-mcp -n private-ai

# 4. Verify Playground ConfigMap (managed by ArgoCD)
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications

# 5. Restart LlamaStack
oc rollout restart deploy/lsd-genai-playground -n private-ai
```

## Validation

```bash
./steps/step-10-mcp-integration/validate.sh
```

## ACME Corp Demo Environment

Step 10 deploys an `acme-corp` namespace with three simulated equipment monitoring pods:

| Pod | Equipment | Status | Behavior |
|-----|-----------|--------|----------|
| `acme-equipment-0001` | LITHO-001 | Healthy | Logs OK health checks every 30s |
| `acme-equipment-0005` | L-900-07 | Healthy | Logs OK health checks every 30s |
| `acme-equipment-0007` | L-900-08 | **CrashLoopBackOff** | Exits with DFO calibration error |

Pod `acme-equipment-0007` is deliberately broken -- it prints error messages about "DFO calibration drift" and "overlay accuracy degraded to 4.2nm" then exits with code 1. This makes it the failing pod the agent investigates in the demo.

The pods map to equipment records in PostgreSQL via the `acme_pod_equipment_map` table.

## Demo Scenarios

### The End-to-End Demo (recommended)

This is a 4-question agentic workflow that chains all three MCP servers plus RAG. In the Playground, select `granite-8b-agent` and enable all MCP servers + RAG:

**Q1: "List pods in acme-corp project"**

The agent uses the Kubernetes MCP server to list pods in the `acme-corp` namespace. Returns 3 pods -- two Running, one in CrashLoopBackOff (`acme-equipment-0007`).

**Q2: "Fetch the equipment name for the failed pod"**

The agent uses the PostgreSQL MCP server to query the `acme_pod_equipment_map` table. The LLM discovers the schema and writes SQL to look up pod `acme-equipment-0007`. Returns: equipment L-900-08 (L-900 EUV Scanner 08), product: L-900 EUV Calibration Suite.

> **Note (generic SQL MCP):** The PostgreSQL MCP server provides generic SQL access. The LLM discovers the database schema via `list_tables` and `describe_table` tools, then writes targeted SQL queries. This is more flexible than hard-coded tool endpoints.

**Q3: "Search for known issues for the mentioned product"**

The agent calls `knowledge_search` (RAG) against the `acme_corporate` Milvus collection with a query about L-900 EUV issues. Returns relevant calibration procedure documentation from the ingested ACME PDFs.

> **Note:** This step requires that ACME PDFs have been ingested via step 07. See `steps/step-07-rag/scenario-docs/README.md`.

**Q4: "Send a Slack message with the summary to the platform team"**

The agent calls `send_slack_message` or `send_equipment_alert` via the Slack MCP server. Messages are delivered to the real `#acme-litho` Slack channel via webhook.

### Additional Scenarios

#### Equipment Lookup

> "What lithography equipment do we have and when was LITHO-001 last calibrated?"

The agent queries the PostgreSQL database for equipment records and calibration dates.

#### Combined RAG + MCP

Enable both RAG and Database MCP:

> "Based on our calibration documentation, what procedure should I follow for LITHO-001, and when was it last calibrated?"

The agent uses `knowledge_search` (RAG) for the procedure docs AND SQL queries (MCP) for the actual calibration date -- combining document knowledge with live system data.

#### Cluster Events

> "Check for any warning events in the acme-corp namespace."

The agent uses the Kubernetes MCP server to surface events related to the failing pod.

## MCP Server Details

### database-mcp (Red Hat Catalog: awslabs/postgres-mcp-server)

Generic PostgreSQL MCP server providing read-only SQL access. The LLM autonomously discovers the schema and writes queries.

| Tool | Description |
|------|-------------|
| `list_tables` | List all tables in the database |
| `describe_table` | Get column details for a table |
| `query` | Execute read-only SQL queries |

Backend: PostgreSQL with tables `equipment`, `service_history`, `parts_inventory`, `calibration_records`, `acme_pod_equipment_map` seeded with ACME semiconductor data.

### openshift-mcp (Red Hat Catalog: kubernetes-mcp-server)

Read-only Kubernetes/OpenShift MCP server. Single Go binary, no external dependencies.

| Capability | Description |
|------------|-------------|
| Pod operations | List, get status, logs, events |
| Resource CRUD | Read any K8s resource including CRDs |
| Safety mode | `--read-only` enforced |

Backend: Kubernetes API via `view` ClusterRole. See [kubernetes-mcp-server docs](https://developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management).

### slack-mcp (Custom Build)

| Tool | Description |
|------|-------------|
| `send_slack_message` | Send custom message to channel |
| `send_equipment_alert` | Formatted equipment alert with severity |
| `send_maintenance_plan` | Maintenance plan with priority |

Backend: Real Slack webhook. Messages delivered to `#acme-litho` channel.

## Troubleshooting

### Catalog image not pulling

```bash
# Verify images are accessible from the cluster
oc debug node/<node-name> -- chroot /host podman pull quay.io/mcp-servers/kubernetes-mcp-server:latest
oc debug node/<node-name> -- chroot /host podman pull quay.io/mcp-servers/awslabs/postgres-mcp-server:latest
```

> **Known Limitation:** If catalog images are not yet available on quay.io, fall back to custom BuildConfigs. Restore `database-mcp-bc.yaml` and `openshift-mcp-bc.yaml` from git history.

### slack-mcp build fails

```bash
oc logs build/slack-mcp-1 -n private-ai
```

### MCP server not starting

```bash
oc logs deploy/database-mcp -n private-ai
oc logs deploy/openshift-mcp -n private-ai
oc logs deploy/slack-mcp -n private-ai
```

### MCP tools not visible in Playground

```bash
# Verify Playground ConfigMap
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o yaml

# Verify LlamaStack tool_groups
oc exec deploy/lsd-genai-playground -n private-ai -- \
  curl -s http://localhost:8321/v1/tool-groups | python3 -m json.tool
```

### Agent doesn't call MCP tools

Ensure `granite-8b-agent` has tool-calling enabled:
```bash
oc get isvc granite-8b-agent -n private-ai \
  -o jsonpath='{.spec.predictor.model.args}' | tr ',' '\n' | grep tool
# Should show: --enable-auto-tool-choice and --tool-call-parser=granite
```

## GitOps Structure

```
gitops/step-10-mcp-integration/
├── base/
│   ├── kustomization.yaml
│   ├── mcp-servers-configmap.yaml  # gen-ai-aa-mcp-servers (redhat-ods-applications)
│   ├── acme-corp/                  # Demo namespace + 3 pods + RBAC
│   ├── postgresql/                 # RHEL9 PostgreSQL 15 + init schema
│   ├── mcp-builds/                 # BuildConfig for slack-mcp only
│   ├── database-mcp/              # Deployment (catalog image) + ConfigMap + Service
│   ├── openshift-mcp/             # Deployment (catalog image) + SA + ClusterRoleBinding
│   └── slack-mcp/                 # Deployment (custom build) + Secret + Service

steps/step-10-mcp-integration/
├── deploy.sh
├── validate.sh
├── mcp-servers/                    # Source code for custom builds
│   └── slack-mcp/                  # Only slack-mcp still needs source
└── README.md
```

## Rollback / Cleanup

```bash
# Delete ArgoCD Application
oc delete application step-10-mcp-integration -n openshift-gitops

# Remove Playground ConfigMap
oc delete configmap gen-ai-aa-mcp-servers -n redhat-ods-applications

# Clean up ClusterRoleBinding
oc delete clusterrolebinding openshift-mcp-view
```

## Key Design Decisions

> **Design Decision:** We use prebuilt MCP server images from the [Red Hat Ecosystem Catalog](https://catalog.redhat.com/en/categories/ai/mcpservers) where possible. This eliminates on-cluster builds for 2 of 3 servers, reduces deployment time, and leverages community-maintained implementations built on Red Hat UBI images.

> **Design Decision:** The PostgreSQL MCP server uses generic SQL access rather than custom tool endpoints. The LLM discovers the schema autonomously and writes targeted SQL queries. This is more flexible and demonstrates real-world MCP patterns (matching the [fantaco-redhat-one-2026](https://github.com/burrsutter/fantaco-redhat-one-2026/tree/main/mcp-examples) approach).

> **Design Decision:** The Kubernetes MCP server runs in `--read-only` mode with a `view` ClusterRole, following the [Red Hat developer preview guidance](https://developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management).

> **Design Decision:** Slack MCP keeps a custom build because no catalog MCP server supports simple webhook-based posting. Real messages are delivered via the configured `SLACK_WEBHOOK_URL`.

> **Design Decision:** The MCP servers ConfigMap (`gen-ai-aa-mcp-servers`) is managed by ArgoCD in `redhat-ods-applications`, matching the [RHOAI 3.3 documentation pattern](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user).

## Official Documentation

- [RHOAI 3.3 -- Configuring MCP Servers](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user)
- [RHOAI 3.3 -- Testing with MCP Servers](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/testing-with-model-control-protocol-servers_rhoai-user)
- [Red Hat Ecosystem Catalog -- MCP Servers](https://catalog.redhat.com/en/categories/ai/mcpservers)
- [Kubernetes MCP Server (Red Hat Developer)](https://developers.redhat.com/articles/2025/09/25/kubernetes-mcp-server-ai-powered-cluster-management)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Llama Stack Agents](https://llama-stack.readthedocs.io/en/latest/concepts/agents.html)
