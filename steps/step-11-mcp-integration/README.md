# Step 12: MCP Integration

**"Enterprise Tool Orchestration"** - Give the AI agent access to live enterprise systems through Model Context Protocol.

## The Business Story

Steps 09-11 proved your RAG system can retrieve, answer, evaluate, and stay safe. But real enterprise AI goes beyond document Q&A. Step 12 adds MCP (Model Context Protocol) servers that give the LLM agent access to live systems: query an equipment database, inspect an OpenShift cluster, or send team notifications -- all through standardized tool interfaces that the model invokes autonomously.

This completes the **four pillars of Red Hat AI**:
1. Flexible Foundation (steps 01-05)
2. Data and AI Integration (steps 06-09)
3. Trust and Governance (steps 10-11)
4. **Integration and Automation (step 12)**

| Component | Purpose | Persona |
|-----------|---------|---------|
| **database-mcp** | Equipment queries via PostgreSQL | Manufacturing Engineer |
| **openshift-mcp** | Cluster inspection via K8s API | Platform Engineer |
| **slack-mcp** | Team notifications (demo mode) | Operations Team |
| **PostgreSQL** | ACME equipment/calibration data | Data layer |
| **Playground ConfigMap** | MCP server discovery in UI | Platform Admin |

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
    |--- database-mcp:8080/sse  -> PostgreSQL (equipment data)
    |--- openshift-mcp:8000/sse -> Kubernetes API (read-only)
    |--- slack-mcp:8080/sse     -> Demo logger (no webhook)
```

## Prerequisites

```bash
# granite-8b-agent with tool-calling enabled (step-05)
oc get isvc granite-8b-agent -n private-ai

# LlamaStack running (step-06 or step-09)
oc get llamastackdistribution -n private-ai
```

## Deployment

### A) One-shot (recommended)

```bash
./steps/step-11-mcp-integration/deploy.sh
```

This will:
1. Deploy PostgreSQL with ACME equipment data
2. Trigger BuildConfigs for 3 MCP server images
3. Deploy the MCP servers once images are built
4. Register MCP servers in the GenAI Playground
5. Restart LlamaStack pods to discover MCP tools

### B) Step-by-step (manual)

```bash
# 1. Deploy via ArgoCD
oc apply -f gitops/argocd/app-of-apps/step-11-mcp-integration.yaml

# 2. Wait for builds
oc get builds -n private-ai -w

# 3. Wait for servers
oc get deploy database-mcp openshift-mcp slack-mcp -n private-ai

# 4. Register in Playground
oc apply -f steps/step-11-mcp-integration/mcp-playground-config.yaml

# 5. Restart LlamaStack
oc rollout restart deploy/lsd-genai-playground -n private-ai
```

## Validation

```bash
./steps/step-11-mcp-integration/validate.sh
```

## ACME Corp Demo Environment

Step 12 deploys an `acme-corp` namespace with three simulated equipment monitoring pods:

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

The agent calls `list_pods_summary(namespace="acme-corp")` via the OpenShift MCP server. Returns 3 pods -- two Running, one in CrashLoopBackOff (`acme-equipment-0007`).

**Q2: "Fetch the equipment name for the failed pod"**

The agent calls `query_pod_equipment(pod_name="acme-equipment-0007")` via the Database MCP server. Returns: "Pod acme-equipment-0007 monitors equipment L-900-08 (L-900 EUV Scanner 08), product: L-900 EUV Calibration Suite."

**Q3: "Search for known issues for the mentioned product"**

The agent calls `knowledge_search` (RAG) against the `acme_corporate` Milvus collection with a query about L-900 EUV issues. Returns relevant calibration procedure documentation from the ingested ACME PDFs.

> **Note:** This step requires that ACME PDFs have been ingested via step 09. See `steps/step-08-rag-pipeline/scenario-docs/README.md`.

**Q4: "Send a Slack message with the summary to the platform team"**

The agent calls `send_slack_message` or `send_equipment_alert` via the Slack MCP server with a summary of findings. In demo mode, the message is logged (not sent to Slack).

### Additional Scenarios

#### Equipment Lookup

> "What lithography equipment do we have and when was LITHO-001 last calibrated?"

The agent calls `query_equipment` and returns structured equipment data with calibration dates.

#### Combined RAG + MCP

Enable both RAG and Database MCP:

> "Based on our calibration documentation, what procedure should I follow for LITHO-001, and when was it last calibrated?"

The agent uses `knowledge_search` (RAG) for the procedure docs AND `query_equipment` (MCP) for the actual calibration date -- combining document knowledge with live system data.

#### Cluster Events

> "Check for any warning events in the acme-corp namespace."

The agent calls `get_recent_events(namespace="acme-corp")` to surface Kubernetes events related to the failing pod.

## MCP Server Details

### database-mcp (Node.js)

| Tool | Description |
|------|-------------|
| `query_pod_equipment` | Map a pod name to its monitored equipment |
| `query_equipment` | Get equipment details by ID |
| `query_service_history` | Get recent service/maintenance records |
| `query_parts_inventory` | Look up spare parts by part number |

Backend: PostgreSQL with 4 tables (equipment, service_history, parts_inventory, calibration_records) seeded with ACME semiconductor data.

### openshift-mcp (Python)

| Tool | Description |
|------|-------------|
| `get_pod_status` | Summarized pod status (phase, ready, restarts) |
| `get_pod_logs` | Pod logs (last N lines) |
| `list_pods_summary` | All pods in a namespace with status |
| `get_recent_events` | Recent events (warnings, errors) |

Backend: Kubernetes API via `view` ClusterRole (read-only).

### slack-mcp (Node.js)

| Tool | Description |
|------|-------------|
| `send_slack_message` | Send custom message to channel |
| `send_equipment_alert` | Formatted equipment alert with severity |
| `send_maintenance_plan` | Maintenance plan with priority |

Backend: Demo mode (logged only). Set `SLACK_WEBHOOK_URL` in ConfigMap for real Slack delivery.

## Image Builds

MCP server images are built on-cluster via OpenShift BuildConfigs:

```bash
# Check build status
oc get builds -n private-ai

# Trigger a rebuild
oc start-build database-mcp -n private-ai
```

Source code is committed in `steps/step-11-mcp-integration/mcp-servers/`. BuildConfigs pull from the Git repo and build using the Dockerfiles in each server directory.

## Troubleshooting

### Build fails

```bash
oc logs build/database-mcp-1 -n private-ai
# Common: Git URL not reachable, npm install failure
```

### MCP server not starting

```bash
oc logs deploy/database-mcp -n private-ai
# Common: PostgreSQL not ready, image not built yet
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
gitops/step-11-mcp-integration/
├── base/
│   ├── kustomization.yaml
│   ├── acme-corp/               # Demo namespace + 3 pods + RBAC
│   ├── postgresql/              # Equipment database
│   ├── mcp-builds/              # 3x BuildConfig + ImageStream
│   ├── database-mcp/            # Deployment + ConfigMap + Service
│   ├── openshift-mcp/           # Deployment + SA + ClusterRoleBinding
│   └── slack-mcp/               # Deployment + ConfigMap + Service

steps/step-11-mcp-integration/
├── deploy.sh
├── validate.sh
├── mcp-playground-config.yaml   # gen-ai-aa-mcp-servers ConfigMap
├── mcp-servers/                 # Source code for BuildConfigs
│   ├── database-mcp/
│   ├── openshift-mcp/
│   └── slack-mcp/
└── README.md
```

## Rollback / Cleanup

```bash
# Delete ArgoCD Application
oc delete application step-11-mcp-integration -n openshift-gitops

# Remove Playground ConfigMap
oc delete configmap gen-ai-aa-mcp-servers -n redhat-ods-applications

# Clean up ClusterRoleBinding
oc delete clusterrolebinding openshift-mcp-view
```

## Key Design Decisions

> **Design Decision:** MCP servers are built on-cluster via BuildConfigs rather than pre-published images. This keeps the demo self-contained and reproducible without external registry dependencies.

> **Design Decision:** MCP as one tool source among several. The LlamaStack agent combines RAG tools (`builtin::rag`) with MCP tools (`mcp::database`, `mcp::openshift`, `mcp::slack`) -- the agent decides which tools to invoke based on the user's question.

> **Design Decision:** Playground ConfigMap in `redhat-ods-applications` is applied by `deploy.sh` (not GitOps) because ArgoCD targets the `private-ai` namespace. This is consistent with the RHOAI 3.3 documentation pattern.

## Official Documentation

- [RHOAI 3.3 -- Configuring MCP Servers](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/playground-prerequisites_rhoai-user#configuring-model-context-protocol-servers_rhoai-user)
- [RHOAI 3.3 -- Testing with MCP Servers](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/experimenting_with_models_in_the_gen_ai_playground/testing-with-model-control-protocol-servers_rhoai-user)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Llama Stack Agents](https://llama-stack.readthedocs.io/en/latest/concepts/agents.html)
