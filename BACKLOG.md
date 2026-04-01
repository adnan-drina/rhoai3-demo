# Demo Backlog

Future enhancements, capability gaps, and work items for the RHOAI 3.3 demo.

Items are prioritized by impact on demo coverage and customer conversations. The gap analysis is based on [Red Hat's AI for Enterprise Beginners Guide](https://www.redhat.com/en/resources/artificial-intelligence-for-enterprise-beginners-guide-ebook) and the [RHOAI 3.3 Datasheet](https://www.redhat.com/en/resources/red-hat-openshift-ai-hybrid-cloud-datasheet).

## High Priority

### LLM Fine-tuning with Training Hub

**Gap:** The e-book dedicates two full steps (Steps 6-7 of the adoption roadmap) to model customization. Our demo uses pre-trained models enhanced with RAG but never demonstrates LLM fine-tuning.

**Why it matters:** Solution Architects will be asked "can I customize the model with my own data beyond RAG?" Training Hub is a headline RHOAI capability.

**Proposed step:** New step between 08 and 09 (or extend step 08) — fine-tune Granite on ACME domain data using Training Hub, compare pre/post fine-tuning quality.

**Red Hat reference:** [Training Hub](https://github.com/redhat-ai/training-hub), [RHOAI 3.3 — Model customization](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/)

### Distributed Inference with llm-d

**Gap:** The RHCL stack (Authorino, Limitador, DNS, RHCL operator) and LeaderWorkerSet are installed in step 01 but never used. llm-d is a headline feature of RHOAI 3.3 for scalable inference.

**Why it matters:** Customers scaling beyond single-node inference need distributed serving. The infrastructure is already deployed — the demo just needs a workload that uses it.

**Proposed step:** Extend step 05 or step 06 — deploy a model using llm-d distributed inference, benchmark with GuideLLM, compare single-node vs distributed throughput.

**Red Hat reference:** [llm-d community](https://github.com/llm-d), [RHOAI 3.3 — Distributed inference](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/installing_and_uninstalling_openshift_ai_self-managed/index#installing-distributed-inference-dependencies)

## Medium Priority

### LLM Compressor

**Gap:** We use pre-quantized models (Granite FP8 from Red Hat registry) but don't demonstrate the compression process itself. The e-book highlights "1.8x speedup with 8-bit quantization."

**Why it matters:** Customers running custom or fine-tuned models need to compress them for production inference.

**Proposed approach:** Add a notebook or pipeline step that takes a full-precision model, compresses it with LLM Compressor, and deploys the compressed version alongside the original for a performance comparison.

**Red Hat reference:** [LLM Compressor](https://github.com/vllm-project/llm-compressor), [Red Hat AI validated models](https://docs.redhat.com/en/documentation/red_hat_ai/3/html-single/validated_models/index)

### RAFT (Retrieval-Augmented Fine-Tuning)

**Gap:** Our RAG pipeline uses retrieval without fine-tuning the model on retrieval patterns. RAFT bridges RAG and fine-tuning by training the model to work effectively with retrieved documents.

**Why it matters:** Customers with heavy RAG usage would benefit from seeing the quality improvement RAFT provides over vanilla RAG.

**Proposed approach:** Extend the evaluation step (08) to include a RAFT fine-tuned model as a third comparison point: base model vs RAG vs RAFT.

### Synthetic Data Generation

**Gap:** The e-book promotes synthetic data generation for building training datasets when real-world examples are limited. Not demonstrated in any step.

**Why it matters:** Many enterprises have limited labeled data. Showing synthetic data generation removes a common adoption blocker.

**Proposed approach:** Add synthetic data generation to the face recognition pipeline (step 12) or as part of an LLM fine-tuning step — generate training examples from ACME documents.

## Low Priority

### Feature Store (Feast)

**Gap:** `feastoperator: Managed` is set in the DSC (step 02) but Feast is never used in any subsequent step.

**Why it matters:** Low demand in current demo conversations, but the operator is already deployed and consuming resources without providing value.

**Proposed approach:** Add a Feast integration to the face recognition pipeline (step 12) for managing feature engineering, or disable the operator to reduce resource usage.

### InstructLab Toolkit

**Gap:** InstructLab is a Red Hat Enterprise Linux AI (RHEL AI) capability for model alignment. Not demonstrated in this RHOAI-focused demo.

**Why it matters:** Customers evaluating the broader Red Hat AI portfolio (RHEL AI + RHOAI) may ask about InstructLab. Low priority for RHOAI-specific demos.

**Proposed approach:** Out of scope for this repo. Document as a cross-reference to RHEL AI demos.

### Models-as-a-Service (MaaS)

**Gap:** MaaS offers API endpoints for self-service model access. Developer preview feature in RHOAI 3.3.

**Why it matters:** Will become more relevant as the feature reaches GA. Not demoed because it's still in developer preview.

**Proposed approach:** Add when the feature reaches GA in a future RHOAI release.

### Non-NVIDIA Accelerators (AMD, Intel)

**Gap:** Demo uses NVIDIA L4 GPUs exclusively. E-book highlights AMD, Intel Gaudi, and IBM Spyre support.

**Why it matters:** Relevant for customers with non-NVIDIA hardware, but requires different cloud instances.

**Proposed approach:** Out of scope for the current AWS-based demo. Could be addressed with a multi-cloud variant.

## Demo Strengths Beyond the E-book

These capabilities are demonstrated in our demo but NOT covered in the e-book — they represent differentiated value:

- **GitOps deployment model** (ArgoCD + Kustomize) — how enterprises actually deploy AI at scale
- **Edge AI on MicroShift** with embedded ArgoCD — real edge hardware, not just a concept
- **ModelCar OCI format** — model delivery as container images, a key RHOAI 3.3 innovation
- **Tekton CI/CD for model promotion** — bridges data science (KFP) and platform engineering (Tekton)
- **Multi-step agentic incident resolution** — complete 4-system autonomous workflow, not just a concept
- **TrustyAI adapter pattern** — novel approach to bias monitoring for computer vision models
- **Pre/Post RAG evaluation with LLM-as-Judge** — quantified RAG value (20% to 90% quality improvement)
