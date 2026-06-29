# Validation Checklist

Use this checklist before accepting observability GitOps, documentation, or
runbook changes.

## Source And Scope

- The work references the active baseline in `docs/PLATFORM_BASELINE.md`.
- The official chapter URL uses the active `/3.4/` baseline path.
- Technology Preview status is called out in README, operation, or review
  material that enables this capability.
- Operator logs and audit records remain in `rhoai-logs-and-audit-records`.
- Model performance, fairness, drift, or TrustyAI monitoring remains outside
  this skill.

## Stack Enablement Review

- Required Operators are listed before enabling the stack:
  Cluster Observability Operator, Tempo Operator, and Red Hat build of
  OpenTelemetry.
- `DSCInitialization.spec.monitoring.managementState` is `Managed`.
- Monitoring namespace is explicitly set, normally `redhat-ods-monitoring`.
- Metrics storage, retention, replicas, and resources are intentional for the
  demo environment.
- Metrics are not left empty; `MonitoringStackAvailable=True` is required for
  the dashboard to load real metrics-backed components.
- Trace storage backend is one of the documented values: `pv`, `s3`, or `gcs`.
- Traces are not left empty; `TempoAvailable=True` and
  `OpenTelemetryCollectorAvailable=True` are required before trace visibility
  is claimed.
- `PersesAvailable=True` is validated on the RHOAI `Monitoring` service before
  accepting the dashboard as working.
- External exporter endpoints are placeholders unless approved endpoints exist.

## Dashboard Review

- `OdhDashboardConfig.spec.dashboardConfig.observabilityDashboard` is set to
  `true` only after the stack is enabled.
- The resource is reviewed in the OpenShift AI application namespace, normally
  `redhat-ods-applications`.
- User-facing docs describe the menu as "Observe & monitor".

## User Workload Metrics Review

- `monitoring.opendatahub.io/scrape: 'true'` is applied under the workload pod
  template labels.
- The workload exposes metrics before the scrape label is added.
- Operator-managed workloads are not modified with the scrape label.
- Prometheus access is documented through route or temporary port-forward.

## Metrics And Traces Review

- Metrics exporters use documented `type` values: `otlp` or
  `prometheusremotewrite`.
- Exporter names avoid reserved values such as `prometheus` and `otlp/tempo`.
- OTLP endpoints use port `4317` for gRPC or `4318` for HTTP when applicable.
- Trace-producing applications are instrumented before trace visibility is
  claimed.
- Tempo Query access uses a route or port-forward only when intentionally
  required.

## Alerts Review

- Alertmanager is treated as internal by default.
- Built-in alert access uses the Alertmanager service in
  `redhat-ods-monitoring` and port `9093`.
- Port-forward commands are documented as temporary operator access.

## Static Checks

Run the repo whitespace check and the focused stale-marker search from
`project-rhoai-doc-chapter-skill-authoring` against this skill directory.
