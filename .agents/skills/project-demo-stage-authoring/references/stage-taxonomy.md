# Demo Stage Taxonomy

Use this taxonomy when assigning root-level stage folder names.

## Naming Contract

Stage folders live directly under the repository root:

```text
stage-YXX-slug/
  README.md
  PLAN.md
  deploy.sh
  validate.sh
```

`YXX` is a three-digit identifier:

- `Y` is the theme family.
- `XX` is the ordered stage number inside that family.
- The folder name uses lowercase kebab-case: `stage-YXX-descriptive-slug`.

Do not create a `steps/` or `stages/` grouping folder for active content.

## Theme Families

| Range | Theme | Purpose |
|-------|-------|---------|
| `100-199` | AI Platform Foundation | Establish the enterprise platform substrate: OpenShift GitOps, ODF/object storage, NFD, GPU Operator, GPU MachineSets, OpenShift AI Self-Managed base install, DSCI/DSC ownership, users/groups, access, and baseline observability. |
| `200-299` | Production GenAI & Private Data | Demonstrate the GenAI endpoint lifecycle: deploy a model, measure its performance envelope, expose it through governed Models-as-a-Service, and then extend into private data, RAG, guardrails, model safety, and evaluation of the resulting system. |
| `300-399` | Agentic AI & Enterprise Integration | Demonstrate agentic workflows and integration: Llama Stack, Gen AI Studio, MCP, enterprise tools, multi-step agent workflows, and user-facing GenAI applications. |
| `400-499` | AI Operations, Evaluation & MLOps | Demonstrate operational control: AI Pipelines, MLflow, distributed workloads, Kueue, evaluation, LLM-as-judge, observability, monitoring, governance evidence, and lifecycle operations. |
| `500-599` | Edge & Applied AI | Optional future range for edge, predictive AI, device-oriented demos, or applied workloads that do not fit the primary platform-to-operations flow. Use this only when the demo story needs a separate applied track. |

## Red Hat Theme Alignment

The taxonomy is derived from Red Hat AI 3 and OpenShift AI production themes:

- Production inference: llm-d, vLLM-based inference, validated models,
  accelerator support, and Models-as-a-Service.
- Agentic AI: Llama Stack API, MCP, AI Hub, and Gen AI Studio.
- Private data and RAG: data ingestion, synthetic data generation, tuning,
  evaluation, and expanded RAG workflows.
- Hybrid-cloud AI operations: model registry, pipelines, observability, GPU
  monitoring, GPU slicing, and Kueue scheduling.
- Pilot-to-production workflows: AI Hub, governed Model-as-a-Service access,
  Gen AI Studio, and continuous evaluation and optimization.

Primary narrative sources:

- https://www.redhat.com/en/blog/red-hat-ai-3-delivers-speed-accelerated-delivery-and-scale
- https://www.redhat.com/en/blog/whats-new-red-hat-openshift-ai-33-ui-moving-pilot-production

## Initial Candidate Stage Map

Use this as a planning aid, not as a committed implementation promise. Stage
numbers can change before a stage is created.

| Candidate | Theme | Candidate concept |
|-----------|-------|-------------------|
| `stage-110-rhoai-base-platform` | AI Platform Foundation | GitOps bootstrap, ODF MCG object storage, RHOAI Self-Managed base install, model registry, access personas, and the shared DSC owner. |
| `stage-120-gpu-as-a-service` | AI Platform Foundation | NFD, NVIDIA GPU Operator, AWS GPU MachineSet, Kueue quota, and RHOAI hardware profiles. |
| `stage-210-model-serving-foundation` | Production GenAI & Private Data | Enable model serving, ensure Nemotron vLLM endpoint readiness, and establish a lightweight GuideLLM/Grafana serving baseline. |
| `stage-220-models-as-a-service` | Production GenAI & Private Data | Govern internal Nemotron access and register external OpenAI `gpt-5.4-mini` through the DNS-safe MaaS resource alias `gpt-5-4-mini`. |
| `stage-230-private-data-rag` | Production GenAI & Private Data | Private data ingestion, retrieval, and RAG application path. |
| `stage-240-guardrails-and-safety` | Production GenAI & Private Data | AI safety, guardrails, and policy controls around GenAI workloads. |
| `stage-250-model-evaluation` | Production GenAI & Private Data | Evaluate the served/guarded GenAI system: EvalHub/LMEval-style checks, LLM-as-judge, and evidence capture. Sits in the GenAI arc after guardrails so evaluation closes the Production-GenAI story. |
| `stage-310-gen-ai-studio` | Agentic AI & Enterprise Integration | Gen AI Studio or playground-based workflow design and testing. |
| `stage-320-llama-stack-runtime` | Agentic AI & Enterprise Integration | Llama Stack runtime and API integration. |
| `stage-330-mcp-enterprise-tools` | Agentic AI & Enterprise Integration | MCP-based connection to enterprise tools and services. |
| `stage-410-ai-pipelines` | AI Operations, Evaluation & MLOps | AI Pipelines and data processing workflows. |
| `stage-430-mlflow-experiment-tracking` | AI Operations, Evaluation & MLOps | MLflow experiment tracking and model lifecycle evidence. |
| `stage-440-observability-and-governance` | AI Operations, Evaluation & MLOps | TrustyAI, monitoring, Grafana dashboards, and operational evidence. |
| `stage-450-distributed-workload-operations` | AI Operations, Evaluation & MLOps | Kueue, distributed workloads, scheduling, and GPU utilization controls. |

## Selection Rules

- Pick the lowest unused identifier that preserves narrative order.
- Keep each stage small enough to explain in one concise README and implement
  as one GitOps slice or one clear shared-owner patch.
- If a capability patches a shared owner, the stage still gets a root-level
  `stage-YXX-slug/` folder for README, PLAN, deploy, and validate wrappers.
- Use `docs/BACKLOG.md` for deferred stage candidates instead of reserving
  empty folders.
