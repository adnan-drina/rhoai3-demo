# RHOAI 3.4 Documentation Alignment Remediation Backlog

This backlog is derived from the chapter-by-chapter documentation review. It does not replace `docs/alignment-evidence-ledger.md`; it translates documentation gaps into implementation or documentation work.

## P1

| Item | Area | Action | Acceptance |
|---|---|---|---|
| API/support-tier matrix | Cross-cutting | Add a table covering Llama Stack, OpenAI-compatible APIs, Vector Store Files, MaaS, NeMo Guardrails, MCP, LM-Eval, TrustyAI, KServe, and Model Registry support status. | Every preview/developer-preview capability used by the demo has a support-status note and official doc link. |
| Step 13b Argo standards | Edge | Normalize Step 13b app sync options and ignore differences to match the rest of the demo, while preserving remote MicroShift bootstrap exceptions. | Strict audit remains unblocked; README distinguishes central GitOps from remote edge bootstrap. |
| Qwen deferred model | MaaS/model catalog | Either document `qwen3-8b-agent.yaml` as future scope or remove it if it is not part of the active demo. | No inactive model manifest appears unexplained in Step 05. |
| Step 09 live validation | Guardrails | After Argo syncs the NeMo migration, run and record Step 09 validation. | `steps/step-09-guardrails/validate.sh` passes against live cluster. |

## P2

| Item | Area | Action | Acceptance |
|---|---|---|---|
| Supported configuration evidence | Platform | Add OCP/RHOAI/GPU/operator support evidence section. | Audit report lists exact live versions and supported-config references. |
| Telemetry posture | Administration | Document telemetry status and verification commands. | Step 02 or operations docs explain how telemetry is configured or intentionally left default. |
| Disconnected-install boundary | Install | Add an out-of-scope note for disconnected installation and list what would change. | Install chapter coverage is explicit rather than silent. |
| Model catalog source governance | Model catalog | Document as deferred or add a minimal source-governance example. | Model catalog admin chapter has a concrete disposition. |
| Product-native Gen AI Playground path | Gen AI UI | Add a Step 10 scene showing Dashboard/Playground MCP/model/guardrails usage. | Demo can show custom chatbot and product-native playground without conflict. |
| TrustyAI model monitoring mapping | Monitoring | Map Step 12 TrustyAI resources to RHOAI monitoring docs. | Monitoring chapter moves closer to `covered`. |
| MCP security narrative | MCP | Add least-privilege, auth boundary, logging, and tool-governance notes. | Step 10 aligns with Red Hat MCP security articles. |

## P3 / Future Tracks

| Item | Area | Action |
|---|---|---|
| Feature Store | Predictive AI | Add a future feature-store scenario or document out of scope. |
| AutoML | Predictive AI | Add as deferred unless predictive AI story expands. |
| AutoRAG | RAG quality | Evaluate as a future RAG optimization story. |
| Spark Operator | Data processing | Add only if the demo needs distributed batch data processing. |
| Ray/CodeFlare distributed workloads | Training/data | Add a minimal workload if GPU scale-out training becomes a demo requirement. |
| Model customization/fine-tuning | Gen AI | Add only after RAG/eval story is stable and GPUs are available. |
| llm-d | Distributed inference | Add optional path for scale-out LLM serving; current demo uses vLLM/KServe/MaaS. |
| Deploy-script lint | GitOps hygiene | Add deterministic lint for direct applies of Argo-managed resources, except documented Step 13b remote bootstrap. |
