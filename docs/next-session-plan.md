# Post-Migration State — All Steps Deployed

## Migration Completed This Session

Migrated step-07 from Milvus+`userConfig` to pgvector with pure `rh-dev` env vars. This fixed:
- Vector store persistence across restarts (was broken)
- Ragas evaluation providers (was broken by `userConfig`)
- Safety provider auto-wiring (`trustyai_fms`) (was broken)
- Agent-based mode `file_search` (was broken with custom config)

Key commits:
- `0100524` — feat: migrate from Milvus+userConfig to pgvector with rh-dev template
- `6338120` — chore: remove Milvus (replaced by pgvector)

## Current Cluster State

| App | Status | Notes |
|-----|--------|-------|
| step-01 through step-05 | Synced, Healthy | |
| step-06-model-metrics | OutOfSync, Healthy | |
| step-07-rag | Deployed | pgvector, no userConfig, lsd-rag Ready |
| step-08-model-evaluation | Synced, Healthy | |
| step-09-guardrails | Synced, Healthy | |
| step-10-mcp-integration | Deployed | 3 catalog MCP servers Running |

### Running Services
- **lsd-rag**: Running with pgvector, trustyai_fms safety, Ragas scoring, MCP tool runtime
- **lsd-genai-playground**: Running (Dashboard-created)
- **granite-8b-agent**: Running (1 GPU)
- **mistral-3-bf16**: Running (4 GPU)
- **PostgreSQL (llamastack-postgres)**: `pgvector/pgvector:pg16` with vector extension enabled
- **3 MCP servers**: kubernetes-mcp-server, edb-postgres-mcp, slack-mcp-server (all from Red Hat Catalog)
- **Guardrails Orchestrator**: Running with HAP + injection + PII regex
- **Chatbot**: Running with Agent-based mode + MCP tools

### Verified Providers in lsd-rag
- `remote::pgvector` — vector store (persistent)
- `remote::trustyai_fms` — safety/guardrails
- `inline::sentence-transformers` — embeddings
- `inline::basic` + `inline::llm-as-judge` — scoring (Ragas)
- `remote::model-context-protocol` — MCP tool runtime
- `inline::rag-runtime` — RAG knowledge_search

### MCP Tool Groups (persist in PostgreSQL)
- `mcp::database` → `http://database-mcp.private-ai.svc:8080/sse`
- `mcp::openshift` → `http://openshift-mcp.private-ai.svc:8000/sse`
- `mcp::slack` → `http://slack-mcp.private-ai.svc:8080/sse`

### 4-Question E2E Demo Flow (Validated)

```
Q1: List pods in acme-corp project
    → Tool: mcp::openshift → pods_list_in_namespace
    → Result: 3 pods, acme-equipment-0007 in CrashLoopBackOff ✅

Q2: Fetch the equipment name for the failed pod
    → Tool: mcp::database → execute_sql
    → Result: L-900-08 (L-900 EUV Scanner 08) ✅

Q3: Search for known issues for the mentioned product
    → Tool: builtin::rag → vector_stores/search on acme_corporate
    → Result: DFO calibration procedure documentation ✅

Q4: Send a Slack message with the summary
    → Tool: mcp::slack → conversations_add_message
    → Result: Message delivered to #all-acme-mcp-demo ✅
```

## Key Technical Details

### pgvector Configuration (lsd-rag)
```yaml
env:
  - name: ENABLE_PGVECTOR
    value: "true"
  - name: EMBEDDING_PROVIDER
    value: "sentence-transformers"
  - name: PGVECTOR_HOST/PORT/DB/USER/PASSWORD
    valueFrom: secretKeyRef (llamastack-pgvector-secret)
  # NO userConfig
```

### PostgreSQL Image
```
pgvector/pgvector:pg16
```
With `PGDATA=/var/lib/postgresql/data/pgdata` and `postStart` hook for `CREATE EXTENSION IF NOT EXISTS vector;`.

Requires `kueue.x-k8s.io/queue-name: default` label for pod scheduling in Kueue-managed namespace.

### MCP Servers (Red Hat Ecosystem Catalog)
```
quay.io/mcp-servers/kubernetes-mcp-server:2025-11-24
quay.io/mcp-servers/edb-postgres-mcp:10-03-2025
quay.io/mcp-servers/slack-mcp-server:10-03-2025
```

Slack bot token from `.env` (`SLACK_BOT_TOKEN`), applied as Secret at deploy time.

## What's Safe Now

- Restarting `lsd-rag` — vector stores, tool_groups, and search data persist
- Syncing step-07 ArgoCD app — no more data loss risk
- Running Ragas evaluations — providers auto-wired by `rh-dev`
- Agent-based mode in chatbot — `file_search` works with pgvector
