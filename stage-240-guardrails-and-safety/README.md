# Guardrails and Safety

Stage 240 adds AI safety controls around the demo's governed GenAI models: a
NeMo Guardrails service, managed by the Red Hat OpenShift AI TrustyAI
Operator, that screens user input and model output before and after every
guarded LLM call, plus distributed tracing so guardrail decisions are
observable.

## Why This Matters

A private AI platform is not production-ready when it can only generate
answers — it must also refuse the right requests. European enterprises in
particular need demonstrable safety controls before exposing LLMs to
employees or customers: personal data must not leak into prompts or
responses, prompt-injection attempts must not subvert assistants, and
assistant behavior must stay within an approved business scope. Stage 240
shows those controls as platform capabilities — declarative, auditable, and
GitOps-managed — rather than as ad-hoc application code.

Guardrails here are safety controls and policy enforcement. They are not
proof that the system is compliant or risk-free; formal measurement belongs
to a later evaluation stage.

## What Enables It

- **NeMo Guardrails on OpenShift AI** — the `NemoGuardrails` custom resource
  (`trustyai.opendatahub.io/v1alpha1`), reconciled by the TrustyAI Operator
  after Stage 240 flips `trustyai` to `Managed` in the shared
  `DataScienceCluster`. Included with OpenShift AI; no separate NVIDIA
  subscription.
- **Built-in detectors** — Presidio sensitive-data detection (email, phone,
  credit card, SSN, person names) and regex detection (credential keywords,
  API-key shapes) run deterministically, without LLM calls.
- **Custom rails as code** — Colang flows and Python actions (message-length
  policy, prompt-injection patterns) reviewed like any other code in Git.
- **LLM self-check rails** — `self_check_input` / `self_check_output` policy
  prompts evaluated by the governed Nemotron model, adding semantic policy
  and topic control on top of the deterministic rails.
- **Governed model access** — the guardrails service calls Nemotron through
  the Stage 220 Models-as-a-Service gateway with a dedicated
  `MaaSSubscription` and API key, so every guardrail LLM call stays inside
  MaaS quotas and rate limits.
- **Chatbot shield integration** — the Stage 230 Llama Stack registers the
  guardrails service as a safety shield (`remote::nvidia` provider), which
  lights up the guardrail selectors already built into the RAG chatbot.
- **Observability** — the service exports OpenTelemetry spans to a
  stage-local collector and Tempo instance (operators installed by Stage
  110), making rail execution, LLM latency, and block decisions visible.

## Architecture

```text
User / chatbot / curl
        │
        ▼
NeMo Guardrails service (ai-safety, TrustyAI-managed)
  /v1/guardrail/checks      validation only: input rails, no generation
  /v1/chat/completions      guarded generation: input + output rails
        │  input rails: Presidio → regex → length → injection → self-check
        │  output rails: Presidio → self-check
        ▼
maas-internal-proxy (ai-safety)  ── SNI/Host of public gateway hostname
        ▼
MaaS gateway (models-as-a-service, Stage 220)  ── auth, quotas, rate limits
        ▼
Nemotron 3 Nano 30B (GPU node, Stage 120/220)

Stage 230 chatbot ── Llama Stack safety API ── shield nemo-demo-safety
                                                (remote::nvidia provider →
                                                 /v1/guardrail/checks)

NeMo spans ──► OTel collector (ai-safety) ──► TempoMonolithic + Jaeger UI
```

Architecture delta against Stage 230: a new `ai-safety` namespace owns the
guardrails service, its MaaS egress proxy, and the tracing operands; the
shared `DataScienceCluster` gains `trustyai: Managed`; the Stage 220 policy
layer gains the `ai-safety-guardrails` subscription; the Stage 230 Llama
Stack config gains the NeMo safety provider and one registered shield.

## Demo Flow

1. Un-park the environment if needed (GPU MachineSet and Nemotron replicas;
   see `docs/OPERATIONS.md`), then `./deploy.sh` and, after sync,
   `./validate.sh`.
2. Show validation-only checks with curl against `/v1/guardrail/checks`:
   a benign platform question passes; an email address, a credential
   keyword, and an injection prompt are blocked, each attributed to the rail
   that fired (`rails_status`).
3. Show guarded generation against `/v1/chat/completions`: a normal question
   is answered by Nemotron through MaaS; an injection prompt gets the policy
   refusal instead of an answer.
4. Open the Stage 230 chatbot, enable the `nemo-demo-safety` shield in the
   guardrail selectors, and replay the same prompts through the RAG flow.
5. Open the Jaeger UI route in `ai-safety` and inspect the
   `nemo-guardrails` trace spans: rail execution order, LLM call latency,
   and block decisions.

## Limitations And Expectations

- Detector and self-check verdicts have false positives and false negatives;
  tuning them is expected guardrails work, not a defect. The Presidio person
  detector in particular is aggressive on name-like strings.
- Self-check rails add one Nemotron call per direction, so guarded requests
  cost up to three LLM calls; the dedicated subscription quota is sized for
  that amplification.
- Trace content capture is enabled for demo visibility; disable
  `enable_content_capture` outside demos so sensitive data stays out of
  traces.

## References

- [Enabling AI safety with guardrails (RHOAI 3.4)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/enabling_ai_safety_with_guardrails/index)
- `docs/PLATFORM_BASELINE.md` — pinned product versions and doc index
- `.agents/skills/rhoai-guardrails-safety/` — product skill backing this stage
- `PLAN.md` — implementation plan, source capture, and decision log
