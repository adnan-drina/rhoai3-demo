# RAG Prompt Templates

These templates support the RHOAI 3.4 Gen AI Studio **Prompts** demo flow.
Create each prompt in **Gen AI Studio > Prompts** or from the Playground
**Prompt** tab, then save a version with the matching name. The promotion label
is demo metadata used by Step 08 evaluation, following the MLflow Prompt Registry
pattern from `rh-brain`.

RHOAI stores reusable system instructions in MLflow for the project. This
directory keeps the workshop copy in Git so prompt intent, evaluation runs, and
demo narration stay aligned.

| Prompt | Promotion label | Purpose |
|---|---|---|
| `acme-rag-direct` | `development` | Direct RAG answers with strict context grounding. |
| `acme-rag-agentic` | `staging` | Agentic RAG with file search and MCP-aware tool behavior. |
| `acme-rag-troubleshooting` | `production` | Step 10 equipment troubleshooting with OpenShift, SQL, RAG, and Slack. |
| `acme-rag-guarded` | `production` | Step 09 safety posture: do not reveal system instructions, secrets, or sensitive contact data. |

## Evaluation Metadata

When comparing prompt versions, pass the prompt identity into Step 08:

```bash
PROMPT_NAME=acme-rag-agentic \
PROMPT_VERSION=v1 \
PROMPT_ALIAS=staging \
PROMPT_SOURCE=rhoai-gen-ai-studio-prompts \
PROMPT_COMMIT_MESSAGE="Initial agentic RAG prompt" \
./steps/step-08-model-evaluation/run-rag-eval.sh prompt-agentic-v1
```

Step 08 logs those values as MLflow params/tags beside the per-scenario quality
metrics. The aggregate RAG rollup remains in the JSON evidence artifact.

## References

- RHOAI 3.4 reusable system instructions: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/experimenting_with_models_in_the_gen_ai_playground/reusable-system-instructions_rhoai-user
- rh-brain: `/Users/adrina/Sandbox/rh-brain/Red Hat Brain/raw/Prompt Registry for LLMs & Agents.md`
