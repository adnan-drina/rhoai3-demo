# Diagnostic Patterns

Known symptom → cause → fix patterns for the RHOAI demo active baseline.

| Pattern | Likely Cause | First Check |
|---------|-------------|-------------|
| Operator not installing | CatalogSource, Subscription issue | `oc get csv -n <ns>`, `oc get sub -n <ns>` |
| CRD not found | Operator CSV not succeeded | `oc get csv -A \| grep <name>` |
| Pod not starting | Resource limits, image pull, taint | `oc describe pod`, `oc get events` |
| Argo CD not syncing | Resource conflict, RBAC | `oc get application <name> -n openshift-gitops -o yaml` |
| Argo CD ComparisonError | CRD schema not resolvable | Add `ServerSideDiff=true` to syncOptions |
| Argo CD sync stuck on hooks | Upload jobs re-running | Wait — check `oc get jobs -n minio-storage` |
| InferenceService not ready | GPU scheduling, model storage | `oc get pods`, `oc describe isvc`, `oc get workload` |
| Predictor pod in Init:0/1 | Storage-initializer downloading model | Wait — check init logs |
| LlamaStack CrashLoop | Config error, missing model | `oc logs deploy/<lsd-name>` |
| LlamaStack "Provider not found" | Custom config bypasses rh-dev template | Remove userConfig, use env vars only. Set `EMBEDDING_PROVIDER=sentence-transformers` |
| Playground RAG ignores documents | Model doesn't invoke knowledge_search | Set System instructions: "You MUST use the knowledge_search tool" (GenAI Playground only) |
| Chatbot shows `<\|file-xxx\|>` citation markers | LlamaStack `annotation_instruction_template` tells model to cite with `<\|file-id\|>` format | Override template in `lsd-rag-config` ConfigMap: "Never include any citation that is in the form file-id." See Lightspeed approach. |
| llamastack-postgres CrashLoop: "data directory has wrong ownership" | pgvector image needs root; restricted SCC blocks chown | Grant anyuid to `llamastack-postgres` SA (NOT default SA): `oc adm policy add-scc-to-user anyuid -z llamastack-postgres -n private-ai` |
| Modelcar-backed LLM CrashLoop: "Repo id must be in the form 'repo_name'" | anyuid SCC on default SA breaks modelcar FUSE mount | Remove anyuid from default SA; use dedicated SA for postgres only |
| Agent stops mid-chain on database MCP queries | `max_infer_iters` too low for multi-step tool chains | Increase to 20+ (default is now 20 in chatbot sidebar) |
| file_search returns empty results despite populated vector store | Responses API `file_search` requires vector store IDs, not names | Resolve name → ID via `/v1/vector_stores` before passing to `vector_store_ids` |
| Agent ignores file_search results and hallucinates | System prompt missing grounding instruction | Add "Base your answer on the tool results, not prior knowledge" to prompt |
| Agent response empty / "Response failed: Unknown error" | vLLM context overflow: MCP tool results consume 12-16K of 16K context, default max_tokens=4096 exceeds remaining | Pass `max_output_tokens=512` to Responses API; verify `agent.py` includes `"max_output_tokens": config.sampling.max_tokens` |
| Agent uses get_object_details instead of execute_sql | Model can't pick correct tool from 31 options without guidance | Add "For database lookups, use execute_sql on the acme_pod_equipment_map table" to system prompt |
| Playground shows no MCP servers | Missing ConfigMap | Verify `gen-ai-aa-mcp-servers` in `redhat-ods-applications` |
| Dashboard MCP servers show "Error" | Transport mismatch: gen-ai backend defaults to `streamable-http` but server only supports SSE | Add `"transport": "sse"` to ConfigMap JSON. Check: `curl /gen-ai/api/v1/mcp/status?server_url=<url>` |
| Dashboard MCP shows "Token Required" | `streamable-http` POST to `/sse` returns 400 (needs SSE session) | Change URL to `/mcp` (if server supports streamable-http) or add `"transport": "sse"` |
| Model scaling overwritten | Used `oc scale` (imperative) | Use `oc patch inferenceservice` (declarative) |
| llama-stack-client HTTP 426 | Client/server version mismatch | Pin `llama-stack-client>=0.4,<0.5` |
| Docling KFP component 404 | Old v1alpha API path | Change to `/v1/convert/file` |
| Tool-call parser errors | vLLM/model parser mismatch | Verify the active `LLMInferenceService` tool-call and reasoning parser arguments for the served model |
| Responses API file_search empty | pgvector vector store has no data | Re-ingest: `./steps/step-07-rag/run-batch-ingestion.sh` |
| Vector store data missing after restart | pgvector extension not enabled | Check: `oc exec deploy/llamastack-postgres -- psql -c "SELECT extname FROM pg_extension WHERE extname='vector';"` |
| Eval pipeline scoring 404 | DNS resolution in short-lived executor pods | Use `llama_stack_client` SDK with retry logic |
| `llm-as-judge::base` scoring 500 | `prompt_template` is null | Provide prompt with `{input_query}`, `{generated_answer}`, `{expected_answer}` placeholders |
| Chat completions model not found | Model ID must be provider-prefixed or routed through MaaS | Resolve the active Llama Stack provider/MaaS model ID before testing |
| Secret deleted seconds after ArgoCD creates it | `opendatahub.io/managed: "true"` label triggers ODH controller deletion | Remove the label from the GitOps manifest; ODH only manages secrets it created |
| ArgoCD Application uses `project: default` | Bootstrap didn't run or Applications weren't updated after bootstrap | Verify `oc get appproject rhoai-demo -n openshift-gitops`; update Application to `project: rhoai-demo` |
| ArgoCD shows false Out-of-Sync on operator resources | Label tracking instead of annotation tracking | Verify: `oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.spec.resourceTrackingMethod}'` must be `annotation` |
| ArgoCD reconciles all steps on unrelated commit | Missing `manifest-generate-paths` annotation on Applications | Add `argocd.argoproj.io/manifest-generate-paths: gitops/step-XX-name` to each Application |
