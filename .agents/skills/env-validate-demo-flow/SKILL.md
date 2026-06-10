---
name: env-validate-demo-flow
metadata:
  author: rhoai3-demo
  version: 2.0.0
  platform-family: "rhoai"
  platform-baseline: "repo"
  ocp-baseline: "repo"
  skill-group: "Demo Environment"
description: >
  Validate the end-to-end ACME demo flow by running the 3-layer agentic
  workflow against the live cluster once active validation scripts exist.
  During the reimplementation, use this skill to rebuild demo-flow validation
  from legacy references. Use when the user asks to validate the demo, test the
  demo flow, check if the demo works, run the 4-question test, verify MCP tools
  are working, check RAG quality, test guardrails PII detection, or asks "is
  the demo ready to present?".
  Do NOT use for deploying or re-deploying steps (use env-deploy-and-evaluate),
  chatbot customization (use rhoai-chatbot-customization), or model benchmarking
  (use rhoai-model-evaluation).
---

# Validate ACME Demo Flow

Run the 3-layer end-to-end demo validation against a live OpenShift cluster.

## Reimplementation Status

The active implementation is being rewritten. No active demo-flow validation
script exists yet. Treat the ACME flow, step references, and command examples
in this skill as reference material for rebuilding validation, not as runnable
active-project instructions.

Do not run scripts from `backup/legacy-implementation-2026-06-09/` unless the
user explicitly asks to restore or inspect the legacy implementation.

## When to Use

- After deploying the GenAI steps (01-10) to verify the ACME demo flow end-to-end
- Before presenting the demo to an audience
- After making changes to step-07 (RAG), step-09 (Guardrails), or step-10 (MCP) infrastructure
- When the user asks "does the demo work?" or "run the 4-question test"

## Instructions

### Prerequisites

Steps 01-05, 07, 09, and 10 must be deployed and validated. Steps 06, 08 are optional for the E2E flow.

### The 3-Layer Validation

```
Layer 1: Tool Runtime (deterministic)
  Q1: pods_list_in_namespace → mcp::openshift → acme-equipment-0007
  Q2: execute_sql            → mcp::database  → L-900-08
  Q3: vector-io/query        → acme_corporate → chunks > 0
  Q4: conversations_add_message → mcp::slack  → message sent

Layer 2: Agentic (LLM-driven, scoped tools per test)
  A1: "List pods in acme-corp namespace"                              → openshift tools → pods_list_in_namespace
  A2: "Fetch the equipment name for pod acme-equipment-0007"          → database tools  → execute_sql
  A3: "Search for known issues related to the L-900 EUV scanner"     → RAG file_search → calibration/DFO
  A4: "Send summary of L-900-08 issue to Slack channel C09JL81TUQJ"  → slack tools     → conversations_add_message

Layer 3: Guardrails (deterministic)
  PII: email + Dutch phone + LinkedIn regex → >= 2 detections
```

### Running the Validation

Run this only after the active demo-flow script has been recreated:

```bash
./scripts/validate-demo-flow.sh
```

### Interpreting Results

| Layer | Check | Pass Criteria | Common Fix |
|-------|-------|--------------|------------|
| Tool Runtime | Q1: Pod listing | `acme-equipment-0007` in output | Deploy step-10; register mcp::openshift tool_group |
| Tool Runtime | Q2: Equipment lookup | `L-900-08` in response | Check PostgreSQL running; env var ordering in database-mcp |
| Tool Runtime | Q3: RAG search | >= 1 chunk from pgvector | Run the active ingestion workflow once recreated |
| Tool Runtime | Q4: Slack message | `ok` or `message_ts` in response | Check slack-mcp + SLACK_BOT_TOKEN |
| Agentic | A1-A4 | Keywords in LLM response | WARN is acceptable (non-deterministic); FAIL indicates model issue |
| Guardrails | PII detection | >= 2 regex matches | Check guardrails-orchestrator health on port 8034 |

### Key Details

- **Model ID**: use the provider-prefixed Llama Stack/MaaS model ID for
  `nemotron-3-nano-30b-a3b`; do not assume the bare model name is accepted.
- **Slack channel ID**: `C09JL81TUQJ` (`#all-acme-mcp-demo`)
- **Orchestrator API**: HTTPS port 8032, v2 API (`/api/v2/text/detection/content`)
- **DB tool parameter**: `sql` (not `query`) for `execute_sql`
- **Agentic tests use `tool_choice=required`, `max_infer_iters=20`, `max_output_tokens=512`**
- **Each agentic test scopes tools to its relevant MCP server** — broad tool
  sets make deterministic validation harder; in the chatbot UI, conversational
  context can compensate, but automated tests should stay scoped.
- **file_search requires vector store IDs** — the script resolves `acme_corporate` → `vs_...` at runtime via `/v1/vector_stores`
- **Agent instructions include execute_sql hint** — "For database lookups, use execute_sql on the acme_pod_equipment_map table" steers the model to the correct database tool

### Quick Troubleshooting

If MCP tool calls fail (LlamaStack uses SSE transport, separate from Dashboard):
```bash
oc exec deploy/lsd-rag -n private-ai -- curl -s http://localhost:8321/v1/toolgroups
```

If Dashboard shows "Error" or "Token Required" for MCP servers:
```bash
# Check ConfigMap transport field — SSE-only servers need "transport": "sse"
oc get configmap gen-ai-aa-mcp-servers -n redhat-ods-applications -o yaml
# Check gen-ai backend status response
TOKEN=$(oc whoami -t)
GATEWAY=$(oc get route data-science-gateway -n redhat-ods-applications -o jsonpath='{.spec.host}')
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://${GATEWAY}/gen-ai/api/v1/mcp/status?namespace=acme-corp&server_url=<url-encoded>"
```

If RAG returns 0 results:
```bash
oc exec deploy/lsd-rag -n private-ai -- curl -s http://localhost:8321/v1/vector_stores
```

If agentic tests fail with "model not found":
```bash
oc exec deploy/lsd-rag -n private-ai -- curl -s http://localhost:8321/v1/models
```
