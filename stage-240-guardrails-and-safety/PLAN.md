# Stage 240: Guardrails and Safety Plan

## Intent

Deploy the NeMo Guardrails service with an LLM, following the RHOAI 3.4
guide "Enabling AI safety with guardrails": built-in Presidio and regex
detectors, custom Colang rails with Python actions, and LLM self-check
input/output rails evaluated by the MaaS-governed Nemotron model. Wire the
service into the Stage 230 RAG chatbot as a Llama Stack shield and export
OpenTelemetry traces to a stage-local Tempo instance.

NeMo Guardrails is the repo-preferred path per `rhoai-guardrails-safety`
Demo Policy. FMS Guardrails stays untouched as legacy: the Stage 230 LSD
`trustyai_fms` provider keeps empty shields.

## Acceptance Criteria

- `DataScienceCluster` `trustyai` is `Managed`, flipped by a stage-owned
  Argo Sync-hook Job (stage-210 pattern), not by editing the stage-110 file.
- `NemoGuardrails` `nemo-guardrails` in `ai-safety` reaches `PHASE Ready`
  with `security.opendatahub.io/enable-auth: 'true'`.
- `/v1/guardrail/checks` (bearer-authenticated): benign message →
  `status: success`; email (Presidio), credential keyword (regex), and
  injection prompt (custom action) → `status: blocked`.
- `/v1/chat/completions` answers a benign prompt through MaaS → Nemotron and
  refuses an injection prompt.
- The Stage 230 Llama Stack lists shield `nemo-demo-safety` and
  `run-shield` reports a violation for an injection prompt; the chatbot
  guardrail selectors show the shield.
- OTel collector and TempoMonolithic run in `ai-safety`; Tempo returns
  `nemo-guardrails` spans after guarded traffic.
- No MaaS API key appears in any ConfigMap or committed file.
- `validate.sh` exits 0 with the checks above.

## Source Capture

Primary: RHOAI 3.4 "Enabling AI safety with guardrails"
(`docs/PLATFORM_BASELINE.md` index; repo copy of the official PDF at
`stage-230-private-data-rag/data/rhoai-product-docs/source/`). Sections
used: 1.1 standalone quickstart (detector config, checks endpoint
verification bodies), 1.2.1–1.2.6 service with an LLM (auth, env
substitution pattern, custom actions, self-check rails, CR reference),
1.2.7 OpenTelemetry (tracing block in `config.yaml`; `OTEL_*` env set),
1.3 validation-only checks.

Skill: `.agents/skills/rhoai-guardrails-safety/` (extraction, patterns,
validation checklist). Legacy blueprint modernized:
`backup/legacy-implementation-2026-06-09/gitops/step-09-guardrails/`.

### rh-brain Article Selection

No rh-brain article selected; the official product guide fully covers the
implementation. User-shared secondary references (2026-07-05), used for
rail-placement framing only:

- Stackademic "Industrial RAG with NeMo Guardrails and LlamaIndex" —
  NeMo-as-orchestrator library mode **not adopted** (Llama Stack owns RAG;
  NeMo is the safety service); topic-control rail adopted into the
  self-check input policy prompt.
- NVIDIA medical-RAG blog — five rail placements; confirms input/output
  shield placement; retrieval rails deferred (the Llama Stack shield API
  passes messages, not retrieved chunks).
- github.com/NVIDIA-NeMo/Guardrails — upstream syntax reference only
  (Colang 1.0 default matches the shipped rails); effective version is
  whatever the RHOAI 3.4 TrustyAI operator ships.

## Skill Routing

- `rhoai-guardrails-safety` — product authority for the CR, endpoints,
  detectors, rails, OTel env set, and demo policy.
- `rhoai-llama-stack` + stage-230 memory — LSD config contracts
  (`${env.VAR:=default}` substitution, registered_resources shields,
  operator env-merge behavior).
- `rhoai-maas-governance` / stage-220 — MaaSSubscription and API-key
  minting.
- `ocp-opentelemetry`, `ocp-distributed-tracing` — collector and Tempo
  operand schemas (verified live via `oc explain`).
- `project-gitops-authoring`, `project-red-hat-operator-gitops` — stage
  layout, Application, DSC patch-Job pattern.

## GitOps Ownership

Stage 240 owns `gitops/stage-240-guardrails-and-safety/` (namespace
`ai-safety`: project RBAC, DSC patch Job, vendored maas-internal-proxy,
guardrails ConfigMap + CR + SA, Tempo + OTel collector) and the Application
`gitops/argocd/app-of-apps/stage-240-guardrails-and-safety.yaml`
(sync-wave "6").

Shared resources touched:

- `DataScienceCluster default-dsc` (stage-110 owner): `trustyai` →
  `Managed` via Sync-hook Job, mirroring stage-210 (`kserve`) and stage-230
  (`aipipelines`).
- `gitops/stage-220-models-as-a-service/policies/base/`: new
  `MaaSSubscription ai-safety-guardrails` (nemotron-only, 500k tokens/h —
  self-check amplification), following the stage-230 precedent that all
  MaaS policy lives in the stage-220 policies base.
- `gitops/stage-230-private-data-rag/llamastack/base/configmap.yaml`: adds
  the `remote::nvidia` safety provider (config_id `demo-safety`,
  service URL via `${env.GUARDRAILS_SERVICE_URL:=…}` with in-cluster
  default) and registers shield `nemo-demo-safety`.

Environment-local, never committed: `maas-internal-proxy-config` ConfigMap
(generated nginx server config) and Secret `nemo-guardrails-api-token`
(minted MaaS key; Application `ignoreDifferences` on `/data`).

## Manifest Inventory

| Path | Content |
|------|---------|
| `gitops/argocd/app-of-apps/stage-240-guardrails-and-safety.yaml` | Application, wave "6", ignoreDifferences for the token Secret |
| `project/base/` | Namespace `ai-safety` (wave 0), developer/admin RoleBindings (wave 1) |
| `rhoai-dsc/base/patch-dsc-trustyai.yaml` | SA + ClusterRole + CRB (wave 1), Sync-hook Job (wave 2) patching trustyai → Managed |
| `maas-proxy/base/` | Vendored nginx hairpin proxy Deployment + Service (wave 3) |
| `guardrails/base/configmap-nemo-config.yaml` | `config.yaml` (env-substituted model, tracing block, detector config, flows), `prompts.yml` (self-check policies incl. topic control), `rails.co`, `actions.py` (wave 3) |
| `guardrails/base/serviceaccount.yaml`, `rolebinding-view.yaml` | `nemo-guardrails-sa` + view binding (wave 3) |
| `guardrails/base/nemoguardrails.yaml` | `NemoGuardrails` CR, enable-auth, config `demo-safety`, model + OTel env (wave 4, SkipDryRun) |
| `observability/base/tempo.yaml` | `TempoMonolithic guardrails`, pv 5Gi, OTLP + Jaeger UI route (wave 3) |
| `observability/base/otel-collector.yaml` | `OpenTelemetryCollector guardrails`, OTLP in → Tempo out (wave 3) |
| `gitops/stage-220-…/policies/base/ai-safety-guardrails-access.yaml` | Dedicated MaaSSubscription (shared-owner touch) |
| `gitops/stage-230-…/llamastack/base/configmap.yaml` | NeMo safety provider + shield registration (shared-owner touch) |

Sync-wave hazards handled: the `NemoGuardrails` CRD appears only after the
TrustyAI operator reconciles (SkipDryRunOnMissingResource + Application
retry cover the gap); the token Secret is created by deploy.sh before the
first NeMo pod can schedule; the LSD does not roll on ConfigMap changes, so
deploy.sh restarts it after the stage-230 sync.

## Script Plan

### deploy.sh

1. Safety guard (`RHOAI_EXPECTED_API_SERVER`), `require_cmd`, and
   `RHOAI_STAGE240_*` overrides.
2. `ensure_nemotron_available` — readiness preflight only; prints the
   un-park procedure and exits if Nemotron or its MaaS endpoint is missing.
   The script never scales GPU infrastructure (env-manage-resources owns
   that decision).
3. `apply_argocd_application` — sed repoURL/targetRevision, apply, hard
   refresh; also hard-refreshes stage-220 and stage-230 so the shared-owner
   changes sync.
4. `wait_for_namespace`, `wait_for_maas_subscription`.
5. `ensure_maas_proxy_config` — generates the env-specific nginx config
   (public gateway hostname via SNI + Host).
6. `ensure_nemo_secret` — reuses or mints the `sk-oai-*` key against
   subscription `ai-safety-guardrails` (ai-developer token; escape hatch
   `RHOAI_STAGE240_MAAS_API_KEY`), writes the Secret, restarts the NeMo
   deployment when the key changes.
7. `wait_for_guardrails` — DSC trustyai Managed → NemoGuardrails CRD →
   CR `Ready` (first TrustyAI reconcile is slow; generous timeouts).
8. `restart_lsd_for_shields` — restarts the Stage 230 LSD once its config
   carries the NeMo provider.

### validate.sh

Framework: `check`/`warn` counters, summary line, exit 1 on failure.
Checks: Application Synced (Healthy = warn), namespace + RoleBindings, DSC
trustyai Managed, TrustyAI pods (warn), MaaSSubscription present, Nemotron
scaled up (warn + skip functional checks when parked), proxy deployment +
config, Secret holds `sk-oai-*`, no `sk-oai-` in any `ai-safety` ConfigMap,
NemoGuardrails Ready, operator-created route; functional bearer-token
curls: checks endpoint (benign pass; Presidio, regex, injection blocked),
guarded completions (benign answered, injection refused); LSD config
declares provider + shield, `/v1/shields` lists it, `run-shield` reports a
violation; TempoMonolithic Ready (warn), collector available, Tempo search
for `nemo-guardrails` spans (warn — indexing may lag).

## Operations And Troubleshooting

`docs/OPERATIONS.md`: stage-240 section — un-park/re-park pointer, MaaS key
rotation (delete Secret, re-run deploy.sh), proxy config regeneration,
authenticated curl examples, Jaeger UI route. `docs/TROUBLESHOOTING.md`:
CR stuck pending (trustyai not Managed / CRD missing), pod crash on missing
Secret, 401 on route (bearer required), 429 (subscription quota), guardrails
blocking everything (policy prompt too aggressive), hairpin symptoms.

## Risks And Deferred Work

Deferred, discussed with the user 2026-07-05 (separate self-check model
explicitly declined at question time; others accepted at plan approval):

| Item | Status |
|------|--------|
| Separate self-check model (guide 1.2.5) | Deferred — Nemotron self-checks itself. If revisited, the guide's industry-examples section notes the Red Hat AI Safety team recommends Qwen3-14B as the judge-model starting point |
| PII masking mode; library hate/profanity flows | Deferred — blocking-only demo |
| Retrieval rails (chunk filtering) | Deferred — Llama Stack shield API passes messages, not chunks |
| Guardrails metrics + formal safety measurement | Deferred → `rhoai-evaluation` (future stage-250) |
| FMS Guardrails path (incl. Llama Stack PII via FMS) | Not adopted — legacy per Demo Policy; `trustyai_fms` shields stay empty |

Risks:

- **Resolved 2026-07-05 (live):** the TrustyAI operator fronts the NeMo
  container (plain HTTP :8000) with a kube-rbac-proxy sidecar — Service
  `nemo-guardrails` is 443→8443 and requires a bearer token, which the
  `remote::nvidia` provider cannot send. Demo exception: stage-240 adds
  `Service nemo-guardrails-internal` (8000→8000, cluster-internal,
  unauthenticated) as the LSD provider path; the external route stays
  bearer-authenticated. The LSD provider default URL points at the internal
  Service.
- Self-check triples token spend per guarded turn; dedicated 500k/h quota,
  tune after live testing.
- TrustyAI Managed changes the shared DSC for all stages (precedent:
  stage-210/230 component flips).
- Trace content capture is on for demo visibility; documented as demo-only
  posture.

## Review Log

- 2026-07-05: Plan approved (user). Scope: detectors + self-check +
  custom rails + OTel + chatbot shield wiring; MaaS-governed Nemotron;
  separate self-check model declined. `remote::nvidia` availability in the
  rh-dev image verified live (provider list + config schema + request/
  response contract read from the shipped provider source).
- 2026-07-05: Deployed and validated on cluster-qt67m — **validate.sh
  29 passed / 0 warnings / 0 failed** (commit 8276b62). Evidence record:
  guardrails path NeMo; namespace ai-safety; model endpoint MaaS-governed
  Nemotron via stage-local hairpin proxy; validation endpoints
  `/v1/guardrail/checks` (benign success; Presidio email, regex credential,
  custom-action injection blocked with rail attribution) and
  `/v1/chat/completions` (benign answered, injection refused); Llama Stack
  shield `nemotron-3-nano-30b-a3b` listed and blocking via run-shield;
  secrets in `nemo-guardrails-api-token` only; telemetry enabled —
  `nemo-guardrails` spans queryable in Tempo. Known limitation: Presidio
  PERSON detector is aggressive; self-check verdicts depend on Nemotron.

### Live findings folded back during deployment

1. The RHOAI NeMo server does not substitute `${VAR}` in `config.yaml`; it
   merges `MAIN_MODEL_*` env values over the raw YAML per request. A
   literal `${OPENAI_API_KEY}` reached MaaS as the API key (401 on every
   LLM rail). Fix: no `api_key` in config — the OpenAI client falls back
   to the `OPENAI_API_KEY` env var from the CR Secret.
2. The request `model` overrides the config main model and MaaS authorizes
   per model, so the Llama Stack `shield_id` must be the governed model
   name (`nemotron-3-nano-30b-a3b`); `provider_shield_id` stays the NeMo
   config id (`demo-safety`).
3. Nemotron is a reasoning model and no prompt toggle disables thinking on
   this vLLM build; nemoguardrails' self-check default `max_tokens: 3`
   yielded empty completions that failed closed (blocked everything
   reaching the LLM rail). Fix: per-task `max_tokens: 512` in prompts.yml.
4. The NeMo server wraps internal errors as 200 assistant messages, and the
   `remote::nvidia` provider treats any non-"blocked" status as no
   violation — both mask LLM-rail failures. validate.sh guards against
   error-shaped answers; treat "benign passes" as the canary check.
5. Argo application controller OOM-looped at the operator-default 2Gi on
   this grown cluster; fixed in the bootstrap ArgoCD CR (4Gi limit).
6. Stage-110's DSC `ignoreDifferences` must gain
   `/spec/components/trustyai` or selfHeal reverts the stage-240 flip.
7. An old shield registration (`nemo-demo-safety`) persists in the LSD
   Postgres kvstore (no unregister API); harmless, remove via SQL if it
   clutters the chatbot selector.

- 2026-07-05 (wrap): chatbot integration hardening after the user's manual
  run — `run_shield(params=…)` TypeError made every chatbot shield fail
  open (fixed, verified through the app's own helpers); topic-control
  false positive on ecosystem questions (fixed by enumerating the domain
  in `self_check_input`; all 8 suggestion chips regression-tested against
  live rails); guardrail demo prompts shipped as the last two suggestion
  chips; `RAG_DEFAULT_MODEL` makes Nemotron the default model; stale
  `nemo-demo-safety` shield removed from the LSD kvstore. Final gates:
  stage-240 validate.sh **30/0/0** (now includes an LLM self-check block
  regression case), stage-230 validate.sh **110/1/0** (now checks
  `RAG_DEFAULT_MODEL` and the guardrail demo chips).
- 2026-07-05 (wrap): manifest review checklist executed against the
  rendered stage — selectors, label compliance, ConfigMap/Secret/SA
  reference resolution, and NemoGuardrails env completeness all pass
  mechanically; no credential literals in Git. Known accepted findings:
  the `nemo-guardrails-internal` Service targets operator-created pods
  (runtime dependency, documented in-manifest and as a demo exception);
  `maas-internal-proxy-config` and the token Secret are deploy.sh-created
  (documented, ignoreDifferences); the OTel collector and Tempo share sync
  wave 3, so the collector logs transient connection errors until Tempo is
  ready (self-heals via retry). Doc-alignment posture: CR shape, auth,
  env-substitution pattern, OTel variable set, self-check prompt format,
  and endpoint payloads all trace to the official 3.4 guide (repo PDF);
  deviations (no `api_key` in config.yaml, per-task `max_tokens`, internal
  Service, `remote::nvidia` shield wiring) are live-verified findings
  recorded above and in `rhoai-guardrails-safety` v1.1.0.

## Retrospective And Skill Updates

What worked: authoring against the official guide extracted from the
repo's own vendored PDF (docs.redhat.com blocks fetches); verifying
provider contracts by reading shipped source in the live image before
authoring; env-with-default (`${env.VAR:=…}`) for operator-created
endpoints so live corrections need no Git churn; parallelizing GPU warm-up
with the TrustyAI reconcile.

What to repeat next stage:

1. **Verify through the consumer's code path, not just the API.** The
   chatbot shields failed open for a whole demo session while the REST API
   validated perfectly; the fix took minutes once the app's own helpers
   were exercised via `oc exec` + python. Guardrails especially must be
   proven through every consumer.
2. **Treat "benign passes" as the canary.** Fail-open error masking (HTTP
   200 wrappers, providers that map errors to "no violation") makes broken
   LLM rails look like passing ones; only a benign message that *passes*
   proves the LLM rail actually ran.
3. **Policy prompts need explicit domain enumeration.** The judge model
   does not know a product's ecosystem; "related to X" blocks legitimate
   ecosystem questions deterministically.
4. **Reasoning models need token budgets in judge roles** (`max_tokens`
   per task); no prompt toggle disables Nemotron thinking on this build.

Skill updates shipped during the stage: `rhoai-guardrails-safety` 1.1.0
(live-verified platform behaviors), `rhoai-chatbot-customization` 2.1.0
(RAG_DEFAULT_MODEL, run_shield signature pitfall, guardrail chip
contract). Platform fixes folded back: Argo controller memory in the
bootstrap ArgoCD CR; `/spec/components/trustyai` in stage-110
ignoreDifferences.
