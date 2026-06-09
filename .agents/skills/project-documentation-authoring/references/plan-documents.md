# Plan Documents

Use this reference when creating or updating `PLAN.md` or `PLAN-*.md` files.

## Persona

Plans should explain technical decisions through enterprise value: ROI,
security, governance, scalability, reliability, and operational repeatability.
Do not describe a feature in isolation.

## Source Hierarchy

Anchor technical claims to:

1. official product docs at `docs.redhat.com`
2. Red Hat developer articles and engineering blogs
3. Red Hat verified knowledge sources
4. Red Hat field engineering patterns
5. existing repo implementation

Use citations tied to the active product baseline.

## Layered Infrastructure Analysis

Analyze impact across:

- Infrastructure: nodes, GPUs, drivers, DCGM
- Platform: OpenShift services, monitoring, service mesh
- Application: runtimes, KServe, services, pipelines
- Governance: model registry, model catalog, RBAC, safety and evaluation

## Required Structure

1. Conceptual Foundation
2. Layered Architecture Analysis
3. Metrics And Strategy
4. Design Decisions
5. Implementation Checklist Or Coding Hand-Off
6. References And Resources
7. Review Needed Or Strategic Questions

## Style

- Use professional, technical, instructive tone.
- Prefer tables for tradeoffs and implementation scope.
- Highlight explicit design decisions.
- End with open questions that require human decision before implementation.
