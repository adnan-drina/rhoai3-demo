# Source Capture

## Official Source

| Field | Value |
|-------|-------|
| Product family | Red Hat OpenShift Container Platform |
| Baseline source | `docs/PLATFORM_BASELINE.md` |
| Documentation category | Specialized hardware and driver enablement |
| Official chapter | Node Feature Discovery Operator sections |
| Source URL | https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html-single/specialized_hardware_and_driver_enablement/index#psap-node-feature-discovery-operator |
| Single-page URL | https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html-single/specialized_hardware_and_driver_enablement/index |
| Capture date | 2026-06-10 |

## Captured Sections

- Installing the Node Feature Discovery Operator
- Using the Node Feature Discovery Operator
- Configuring the Node Feature Discovery Operator
- About the `NodeFeatureRule` custom resource
- Using the `NodeFeatureRule` custom resource
- Using the NFD Topology Updater
- `NodeResourceTopology` custom resource examples and topology updater flags

## Source Boundaries

The same official documentation page also covers Driver Toolkit and Kernel
Module Management. Those topics are related but out of scope for this skill.
Create separate `ocp-driver-toolkit` or `ocp-kernel-module-management` skills
when the demo implementation needs kernel module build, signing, loading, or
driver container behavior.

This skill does not define NVIDIA GPU Operator, RHOAI hardware profile, KServe,
or model-serving behavior. Use `rhoai-nvidia-gpu-accelerators` and relevant
`rhoai-*` serving skills for that layer.

## Related Official Sources

- OCP Nodes: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/index
- OCP Machine management: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/machine_management/index
- RHOAI working with accelerators: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_accelerators
