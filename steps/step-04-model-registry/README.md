# Step 04: Model Registry
**The Gatekeeper — only admin-vetted models reach production.**

## The Business Story

Developers should never pull models straight from Hugging Face into production. The **Model Registry** is the organization's gatekeeper: `ai-admin` downloads, validates, and registers models; `ai-developer` discovers and consumes only what's been approved. No "Shadow AI."

Meanwhile, RHOAI 3.3 ships a **Model Catalog** with 48+ Red Hat-validated models (IBM Granite, Meta Llama, Mistral, Qwen, DeepSeek, Gemma) — a curated starting point that complements the registry's custom governance.

## What It Does

The registry lives in `rhoai-model-registries`. The RHOAI operator creates an OAuth-protected API on `:8443` for Dashboard access. We add a second **internal** service on `:8080` (unauthenticated) so seed jobs can register models without token negotiation.

| Component | Purpose |
|-----------|---------|
| **MariaDB 10.5** | Metadata storage (5 Gi PVC) |
| **ModelRegistry CR** (`private-ai-registry`) | Operator-managed registry with OAuth API |
| **Internal Service** (`:8080`) | Unauthenticated endpoint for automation |
| **RBAC** | `ai-admin` = full control, `ai-developer` = read-only |
| **Seed Job** | Registers Granite 3.1 8B Instruct FP8 on first deploy |

```
  Hugging Face ──X──▶ ╔══════════════════════╗ ◀──── ai-developer
                       ║   MODEL REGISTRY     ║       (discovers via
  ai-admin ──────────▶ ║  ✓ Granite 3.1 8B    ║        GenAI Studio)
  (downloads,          ║  ✓ Llama 3.3/4       ║
   validates,          ║  ✓ Mistral 24B       ║
   registers)          ╚══════════════════════╝
```

## Demo Walkthrough

> **Credentials:** `ai-admin` / `redhat123` · `ai-developer` / `redhat123`

---

### Scene 1 — Model Catalog (48+ Validated Models)

**Do:** Log in as `ai-developer`. Navigate to **GenAI Studio → AI Available Assets**.

**Expect:** A catalog page showing 48+ pre-bundled models grouped by provider — IBM Granite, Meta Llama, Mistral, Qwen, phi-4, DeepSeek, Gemma. Each card shows parameter count, license, and recommended hardware.

*"Out of the box, RHOAI ships a curated catalog of over 48 validated models. These are Red Hat-tested — you know they'll run on your hardware. But a catalog alone isn't governance…"*

---

### Scene 2 — Registered Model (Granite 3.1 8B from Seed Job)

**Do:** Switch to `ai-admin`. Navigate to **Settings → Model registries → private-ai-registry**.

**Expect:** The Granite 3.1 8B Instruct FP8 model appears — registered by the automated seed job during deployment. Click into it to show version, S3 artifact path, and owner metadata.

*"This is our private registry. The admin team downloaded Granite, validated it against our security baseline, and registered it here. Notice the artifact points to our internal S3 — not Hugging Face. The model went through us before anyone can serve it."*

---

### Scene 3 — Access Control (ai-admin vs ai-developer)

**Do:** In the `ai-admin` session, show the registry management UI — ability to register, archive, delete models. Then switch to `ai-developer` and show that the registry appears read-only.

**Expect:** `ai-admin` sees full CRUD controls. `ai-developer` sees the same models but with no edit/delete options — consumption only.

*"This is the gatekeeper in action. The admin controls what enters the registry. Developers consume only what's been vetted. If someone tries to skip this — spin up a random Hugging Face model — it won't have a registry entry, it won't get served, and the audit trail will show the gap. No Shadow AI."*

## Design Decisions

> **External MariaDB instead of embedded:** The ModelRegistry CR supports an embedded database, but an external MariaDB gives us explicit PVC control and simpler backup/restore for the demo.

> **Internal service on port 8080:** The operator-managed service requires OAuth. A second headless service bypasses auth so Kubernetes Jobs can seed models without token negotiation.

> **Registry vs. Catalog:** The Model Registry stores custom metadata (our registered models). The Model Catalog is a pre-bundled read-only UI of 48+ Red Hat-validated models — no external sync required.

> **Seed job uses `metadataType: MetadataStringValue`:** This is the format expected by the RHOAI 3.3 registry API. Omitting the type wrapper causes silent metadata loss.

## References

- [Enabling Model Registry Component](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/enabling_the_model_registry_component/index)
- [Managing Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/managing_model_registries/index)
- [Working with Model Registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/working_with_model_registries/index)
- [Granite 3.1 8B Instruct FP8](https://huggingface.co/RedHatAI/granite-3.1-8b-instruct-FP8-dynamic)

## Operations

```bash
./steps/step-04-model-registry/deploy.sh      # Deploy registry, MariaDB, RBAC, seed job
./steps/step-04-model-registry/validate.sh     # Verify CR status, seed job, API health
```

## Next Steps

Proceed to **[Step 05: LLM on vLLM](../step-05-llm-on-vllm/README.md)** — deploy the registered Granite model as a live inference endpoint using KServe + vLLM.
