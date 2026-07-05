# Implementation Detail Boundary

Stage READMEs are not deployment runbooks, but they must contain enough
implementation detail that a reader can understand the system without reading
every manifest. This reference defines what belongs in a README versus what
belongs in `docs/OPERATIONS.md` or the manifests alone.

## The Boundary Rule

> **Include implementation details that affect understanding, troubleshooting,
> or cross-stage dependencies. Exclude operational procedures, step-by-step
> commands, and transient runtime state.**

A reader of the README should be able to answer:
- What mechanism deploys this component? (hook Job, overlay, direct CR, script)
- What are the key governance boundaries? (quotas, RBAC, rate limits)
- Why are specific values chosen? (sizing rationale, compatibility guards)
- What does this stage provide to downstream stages?

A reader should NOT find in the README:
- Shell commands to run
- Login credentials or secret values
- Step-by-step deployment walkthroughs
- Validation output or log excerpts
- Transient cluster state or timestamps

## What Belongs in a README

### Deployment Mechanisms

When a component is deployed through a non-obvious mechanism, name it:

| Pattern | README should say |
|---------|-------------------|
| Argo CD Sync hook Job patches a shared CR | "via an Argo CD Sync hook Job (`job-name`) using a dedicated ServiceAccount" |
| Overlay patches a Subscription channel | "operator channel pinned via kustomize overlay at `path`" |
| Script creates imperative resources | "created imperatively by `script-name.sh`; not GitOps-managed" |
| ConsoleLink patched from live route | "ConsoleLink URL patched at sync time from the Grafana route via hook Job" |

Naming the mechanism helps troubleshooting: when a sync fails, the reader knows
whether to look at a Job, an overlay, or a script.

### Quota, Sizing, and Rate Limit Rationale

When a numeric value has a reason, state it:

- "CPU quota `40` / `128Gi` — sized for Stage 230's CPU model plane"
- "Prometheus retention `15d` — covers benchmark iteration history"
- "AutoRAG subscription: 2M tokens/h — sized for burst optimization runs"

When a value is a default with no special rationale, omit the explanation.

### Cross-Stage Dependencies

When a resource in this stage serves a downstream stage, document it:

- "`enterprise-rag-autorag` MaaSSubscription provides elevated rate limits
  consumed by Stage 230 AutoRAG optimization runs"
- "`benchmark-data` PVC is reused by `prepare-policy-benchmark-data.sh` for
  MaaS quota profiling input to Stage 220"

This prevents the downstream README from being the only place the dependency
is documented.

### RBAC Topology

Document who can access what at the component level:

- "`rhods-admins` → admin on `rhoai-model-registries`"
- "`rhoai-developers` → edit on registry namespace, viewer on Grafana"

Omit per-resource RoleBinding details unless they are non-obvious.

### Compatibility Guards

When an operator is pinned or held, explain why in the README:

- "COO held at `v1.4.0` — RHOAI 3.4 / COO 1.5 generated-resource incompatibility"
- "RHCL pinned to `v1.3.4` — RHCL 1.4 deprecated per official release notes"

### Component Topology

When a subsystem has internal structure that matters:

- "Alertmanager: 3 receivers (Default, Watchdog, Critical) with inhibit rules,
  routing to a demo-local webhook Deployment"
- "Kueue: `cq-gpu-shared` + `cq-gpu-priority` in `gpu-pool` cohort (can borrow);
  `cq-gpu-reserved-demo` isolated (no cohort)"

## What Does NOT Belong in a README

| Content type | Correct home |
|--------------|--------------|
| `oc apply` commands, script invocations | `docs/OPERATIONS.md` |
| Login steps, credential setup | `docs/OPERATIONS.md` |
| Error symptoms and recovery | `docs/TROUBLESHOOTING.md` |
| Validation check output | Stage `PLAN.md` or `docs/OPERATIONS.md` |
| Full manifest YAML excerpts | The manifest itself; cite path instead |
| Transient cluster state (pod names, timestamps) | Nowhere permanent |
| Deferred features with no implementation | `docs/BACKLOG.md` |

## The "What Enables It" Section Format

Two formats are acceptable. Choose based on complexity:

**Header + bullets** (Stage 110 pattern) — when each component needs multiple
detail lines (channel, lifecycle policy, compatibility notes):

```markdown
### Component Name

One-sentence role description.

- **Operator:** name (namespace)
- **Channel:** `stable-3.4`
- **Key detail:** explanation
- **Docs:** [link](url)
```

**Compact table** (Stage 210/220 pattern) — when components can be described
in one sentence each:

```markdown
| Technology | Role in this stage | Source |
|------------|-------------------|--------|
| Component | One-sentence role | [docs](url) |
```

Both formats must include: component name, role, and official docs link.
The header+bullets format additionally accommodates channel versions,
lifecycle policies, and compatibility notes inline.

## Architecture Section Format

Use whichever diagram format communicates the architecture delta clearly:

- **ASCII art** (Stage 110, 120) — best for linear flows and box diagrams
- **Mermaid** (Stage 220) — best for relationship graphs with labeled edges
- **SVG** (when generated) — best for polished capability maps

All formats must distinguish current-stage components from previously-introduced
components. Follow with a short delta list:

```markdown
- New in this stage: <components introduced now>
- Already available: <relevant components from earlier stages>
- Value of the integration: <why the combined architecture matters>
```

## Review Checklist for Implementation Details

After writing or updating a stage README, verify:

- [ ] Every GitOps-managed operator states its channel and namespace
- [ ] Non-obvious deployment mechanisms are named (hook Jobs, overlay patches)
- [ ] Cross-stage resources document their downstream consumer
- [ ] Quota/sizing values with cross-stage rationale include the reasoning
- [ ] Compatibility guards explain the specific incompatibility they prevent
- [ ] RBAC grants are documented at the component level
- [ ] No operational procedures or shell commands appear in the README
- [ ] The architecture diagram accurately reflects all deployed components
