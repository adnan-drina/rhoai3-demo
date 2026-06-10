# OpenShift Platform Skill Roadmap

This roadmap identifies `ocp-*` skills to build from official Red Hat
OpenShift Container Platform documentation for the active baseline in
`docs/PLATFORM_BASELINE.md`. Official docs are authoritative; Red Hat articles
and `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` provide narrative framing
and examples only after official behavior is verified.

## Official Documentation Map

Current baseline index; update this when `docs/PLATFORM_BASELINE.md` changes:
https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/

| OCP area | Official docs category | Skill status |
|----------|------------------------|--------------|
| etcd, control plane data store, quorum, performance, backup/restore, encryption, unhealthy member replacement, disaster recovery, and stretched-cluster caveats | Configure > Postinstallation configuration > etcd | Added: `ocp-etcd` |
| Cluster updates, channels, release images, Cincinnati graph, update safety, and upgrade troubleshooting | Update and migrate | Missing: `ocp-cluster-updates` |
| Authentication, OAuth, identity providers, groups, and cluster-admin boundaries | Configure, Authentication and authorization | Missing: `ocp-authentication-identity-providers` |
| Observability overview, default monitoring stack, user-defined project monitoring, metrics, customized alerts, monitoring release boundary, logging overview, node system audit logs, application container logs, infrastructure logs, logging release boundary, and Cluster Observability Operator customizable monitoring stacks | Observability overview, Monitoring, Logging, Cluster Observability Operator | Added: `ocp-observability` |
| Red Hat OpenShift distributed tracing platform, Tempo Operator, `TempoStack`, `TempoMonolithic`, object storage, tenants, trace read/write RBAC, Jaeger UI, distributed tracing UI plugin, Tempo monitoring, upgrades, removal, and must-gather troubleshooting | Red Hat OpenShift distributed tracing platform 3.9 | Added: `ocp-distributed-tracing` |
| Red Hat build of OpenTelemetry Operator, `OpenTelemetryCollector`, `Instrumentation`, Collector deployment modes, receivers, processors, exporters, connectors, extensions, metrics integration, telemetry forwarding, telemetry receiving, and troubleshooting | Red Hat build of OpenTelemetry 3.9 | Added: `ocp-opentelemetry` |
| Red Hat OpenShift GitOps, OpenShift GitOps Operator, Argo CD product boundary, multicluster GitOps workflows, OpenShift integration, release-cadence boundary, and handoff to separate Red Hat OpenShift GitOps documentation | GitOps | Added: `ocp-gitops-operator` |
| CI/CD overview, OpenShift Builds, Builds using Shipwright, Builds using BuildConfig, BuildConfig, Build, BuildRequest, BuildLog, Docker, S2I, custom, and pipeline build strategies, build inputs, outputs, triggers, hooks, logs, resources, pruning, run policy, and build strategy RBAC | CI/CD, Builds using Shipwright, Builds using BuildConfig | Added: `ocp-cicd-builds` |
| Red Hat build of Kueue, Kueue CR, ClusterQueue, ResourceFlavor, LocalQueue, Workload, RBAC, quotas, cohorts, fair sharing, gang scheduling, pending workload visibility, Leader Worker Set Operator, LeaderWorkerSet, JobSet Operator, and JobSet | AI workloads | Added: `ocp-ai-workloads` |
| Web console access, dashboard, user preferences, Console configuration, branding, links, routes, login page, notifications, downloads, perspectives, developer catalog customization, dynamic plugins, Web Terminal Operator, DevWorkspace, disabling the console, and quick starts | Web console | Added: `ocp-web-console` |
| Node and pod overview, scheduling, node affinity, taints/tolerations, node selectors, topology spread, descheduler, jobs, daemon sets, node operations, node tuning, rebooting, garbage collection, node metrics, remote workers, SNO worker nodes, and sigstore | Nodes | Added: `ocp-nodes` |
| Machine API, compute MachineSets, AWS MachineSets, manual scaling, MachineSet modification, machine phases and lifecycle, deletion, autoscaling, infrastructure MachineSets, user-provisioned infrastructure, control plane machines, and machine health checks | Machine management | Added: `ocp-machine-management` |
| Machine Config Operator, MachineConfig, MachineConfigPool, MachineConfiguration, KubeletConfig, ContainerRuntimeConfig, PinnedImageSet, node disruption policies, boot image management, rendered machine config pruning, image mode, MachineOSConfig, MachineOSBuild, and Machine Config Daemon metrics | Machine configuration | Added: `ocp-machine-configuration` |
| Node Feature Discovery Operator, specialized hardware detection, feature labels, `NodeFeatureDiscovery`, `NodeFeatureRule`, NFD Topology Updater, `NodeResourceTopology`, and accelerator discovery handoff | Specialized hardware and driver enablement | Added: `ocp-node-feature-discovery` |
| Ingress, Routes, Gateway API, certificates, and external access patterns | Networking | Missing: `ocp-ingress-gateway-routes` |
| Storage overview, ephemeral storage, persistent storage, PV/PVC lifecycle, StorageClass behavior, dynamic provisioning, CSI, snapshots, cloning, expansion, local storage, and volume detach after non-graceful node shutdown | Storage | Added: `ocp-storage` |
| Registry, image streams, pull secrets, disconnected mirroring, and trusted registries | Images, Disconnected environments | Missing: `ocp-image-registry-and-mirroring` |
| SecurityContextConstraints, RBAC, service accounts, and workload security posture | Security and compliance | Missing: `ocp-security-rbac-scc` |

## Skill Build Standard

Each `ocp-*` skill should include:

- creation through
  `.agents/skills/project-red-hat-doc-skill-authoring/SKILL.md`
- official docs URLs and baseline metadata that points to
  `docs/PLATFORM_BASELINE.md`
- exact product versions only in `docs/PLATFORM_BASELINE.md` or
  version-specific reference notes
- supported/preview/deprecated posture when relevant
- required API groups, fields, namespaces, operators, and verification commands
- explicit "do not invent fields" guidance
- demo repo examples only after they are tied back to official docs

## Recommended Next Component Skills

Build these before the new GitOps implementation depends on them:

1. `ocp-authentication-identity-providers` for user and group integration.
2. Create narrower observability skills only when implementation requires them,
   such as `ocp-network-observability` or `ocp-power-monitoring`.
3. Create narrower machine-management skills only when implementation requires
   them, such as `ocp-aws-machinesets` or
   `ocp-control-plane-machine-sets`.
4. Create narrower storage skills only when implementation requires them, such
   as `ocp-local-storage`, `ocp-csi-snapshots`, or `ocp-aws-ebs-csi`.
