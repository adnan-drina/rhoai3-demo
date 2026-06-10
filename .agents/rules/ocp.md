---
name: ocp
skill-group: OpenShift Platform
skill-prefix: ocp-
applies-to:
  - docs/PLATFORM_BASELINE.md
  - docs/**/*.md
  - gitops/**
  - scripts/**
  - .agents/skills/ocp-*/**
---

# OpenShift Platform

Use the `ocp-*` skills as the source of truth for OpenShift Container Platform
infrastructure, control plane, networking, authentication, monitoring, GitOps,
and cluster integration guidance:

- `.agents/skills/ocp-ai-workloads/SKILL.md`
- `.agents/skills/ocp-cicd-builds/SKILL.md`
- `.agents/skills/ocp-distributed-tracing/SKILL.md`
- `.agents/skills/ocp-etcd/SKILL.md`
- `.agents/skills/ocp-gitops-operator/SKILL.md`
- `.agents/skills/ocp-machine-configuration/SKILL.md`
- `.agents/skills/ocp-machine-management/SKILL.md`
- `.agents/skills/ocp-node-feature-discovery/SKILL.md`
- `.agents/skills/ocp-nodes/SKILL.md`
- `.agents/skills/ocp-observability/SKILL.md`
- `.agents/skills/ocp-opentelemetry/SKILL.md`
- `.agents/skills/ocp-storage/SKILL.md`
- `.agents/skills/ocp-web-console/SKILL.md`

Official Red Hat documentation for the active OCP baseline in
`docs/PLATFORM_BASELINE.md` is product authority. Do not invent OpenShift API
fields, unsupported operator settings, MachineConfig, MachineConfiguration,
KubeletConfig, ContainerRuntimeConfig, PinnedImageSet, MachineOSConfig,
MachineOSBuild, or MCO rollout assumptions, storage provisioners, StorageClass
parameters, access modes, CSI driver features, or node labels, taints,
scheduler profiles, topology keys, node operations, or MachineSet provider
specs, autoscaler bounds, machine health-check policies, or recovery
procedures, NodeFeatureDiscovery, NodeFeatureRule, NFD Topology Updater,
NodeResourceTopology, hardware feature labels, feature source settings, NFD
operand image behavior, Kueue, ClusterQueue, ResourceFlavor, LocalQueue,
Workload, LeaderWorkerSet, JobSet, AI workload queue labels, quotas,
fair-sharing, gang-scheduling, or visibility API assumptions, console
configuration fields, Console Operator customization, ConsoleLink,
ConsolePlugin, ConsoleQuickStart, web terminal, DevWorkspace behavior,
BuildConfig, Build, BuildRequest, BuildLog, Shipwright build APIs, build
strategies, build triggers, build hooks, build secrets, build outputs, or build
strategy RBAC, OpenShift GitOps Operator, Argo CD, ArgoCD custom resources,
Application, ApplicationSet, AppProject, repository credentials, cluster
credentials, GitOps RBAC, SSO, notifications, resource tracking, or sync
behavior, OpenShift monitoring stack, user workload monitoring, Prometheus,
Alertmanager, Thanos, ServiceMonitor, PodMonitor, PrometheusRule,
AlertmanagerConfig, logging collectors, log stores, log forwarders, logging
outputs, Cluster Observability Operator, observability dashboards, telemetry,
tracing, OpenTelemetry, `OpenTelemetryCollector`, `Instrumentation`,
OpenTelemetry receivers, processors, exporters, connectors, extensions,
auto-instrumentation annotations, Tempo Operator, TempoStack,
TempoMonolithic, Tempo storage, Tempo tenants, Tempo read/write RBAC, Jaeger
UI, distributed tracing UI plugin, Network Observability, or Power monitoring
behavior.

Use `.agents/references/red-hat-doc-map.yaml` to route OCP documentation by
category, book, and chapter topic to the matching flat `ocp-*` skill. If an
official OCP source is not mapped yet, use
`project-red-hat-doc-skill-authoring` to update the map and create or update
the relevant flat skill; do not create nested skill folders that mirror Red Hat
documentation categories.

For live `oc` or `kubectl` commands, follow the OpenShift safety guard in
`AGENTS.md` and pair OCP skills with the relevant `env-*` skill. Treat etcd,
control plane, MachineConfig, and cluster-wide authentication changes as
high-risk operations that require explicit user approval and official docs.
Treat storage mutations, local storage changes, volume detach, and PVC
expansion as live-environment operations unless they are only documented as
future GitOps intent. Treat node drain, reboot, deletion, tuning, schedulable
state changes, and control-plane scheduling changes as live-environment
operations unless they are only documented as future intent. Treat MachineSet
scale, machine deletion, control plane machine replacement, autoscaler changes,
and MachineHealthCheck changes as live-environment operations unless they are
only documented as future GitOps intent. Treat MCO, MCP, `MachineConfig`,
`MachineConfiguration`, `KubeletConfig`, `ContainerRuntimeConfig`,
`PinnedImageSet`, and image mode changes as live-environment operations unless
they are only documented as future GitOps intent. Treat Console Operator
configuration, console route customization, dynamic plugin enablement, web
terminal installation or removal, and disabling the web console as
live-environment operations unless they are only documented as future GitOps
intent. Treat NFD Operator installation, `NodeFeatureDiscovery` changes,
`NodeFeatureRule` labels or taints, topology updater enablement, and NFD
operand image changes as live-environment operations unless they are only
documented as future GitOps intent. Treat Kueue, Leader Worker Set, JobSet,
queue, quota, RBAC, namespace opt-in, cohort, fair-sharing, gang-scheduling,
and AI workload submission changes as live-environment operations unless they
are only documented as future GitOps intent. Treat BuildConfig, Shipwright,
build start/cancel/delete/prune, build controller, build strategy RBAC, webhook
secret, registry credential, and subscription entitlement changes as
live-environment operations unless they are only documented as future GitOps
intent. Treat OpenShift GitOps Operator installation, Argo CD instance changes,
Application or AppProject changes, repository or cluster credential changes,
SSO, notifications, GitOps RBAC, and resource tracking changes as
live-environment operations unless they are only documented as future GitOps
intent.

Treat monitoring stack changes, user workload monitoring changes, alerting
rule changes, logging Operator, collector, forwarder, store, or output changes,
Cluster Observability Operator changes, observability dashboard changes, and
observability credential or endpoint changes, OpenTelemetry Operator changes,
Collector changes, `Instrumentation` changes, auto-instrumentation injection,
telemetry pipeline changes, and telemetry sink changes as live-environment
operations unless they are only documented as future GitOps intent. Treat
Tempo Operator changes, TempoStack or TempoMonolithic changes, object storage
secret changes, tenant changes, trace read/write RBAC changes, Jaeger UI route
changes, distributed tracing UI plugin changes, receiver TLS changes, and
trace retention or deletion changes as live-environment operations unless they
are only documented as future GitOps intent.

Use `project-red-hat-doc-skill-authoring` to create additional `ocp-*` skills
from official OpenShift documentation chapters.
