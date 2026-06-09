# Platform Baseline

This file is the canonical platform target for the demo and shared skills.
Update it first when preparing an upgrade.

## Current Baseline

| Component | Version | Documentation |
|-----------|---------|---------------|
| Red Hat OpenShift AI Self-Managed | 3.4 | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/ |
| Red Hat OpenShift Container Platform | 4.20 | https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/ |

## Version Match Rule

Project documentation, skills, and GitOps review notes must use the Red Hat
OpenShift AI Self-Managed documentation version that matches this baseline.
For the current baseline, RHOAI product-documentation links should use:

```text
https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/
```

Do not use `latest` or another RHOAI version for product configuration unless
the Red Hat documentation landing page intentionally links to an unversioned
Customer Portal article or no version-specific document exists. Record that as
an explicit exception in the relevant README, review note, or skill reference.

## Red Hat OpenShift AI 3.4 Documentation Index

Use the official RHOAI 3.4 landing page as the entry point:
https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/

- **What's New**:
  [Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/release_notes),
  [Red Hat OpenShift AI lifecycle](https://access.redhat.com/support/policy/updates/rhoai-sm/lifecycle)
- **Get started**:
  [Get started with projects, workbenches, and pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/getting_started_with_red_hat_openshift_ai_self-managed),
  [Fraud detection tutorial](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/openshift_ai_tutorial_-_fraud_detection_example)
- **Plan**:
  [Prepare your platform and hardware for Red Hat AI](https://docs.redhat.com/en/documentation/red_hat_ai/3/html/supported_product_and_hardware_configurations/index),
  [Choose a validated model](https://docs.redhat.com/en/documentation/red_hat_ai/3/html/validated_models/index)
- **Install**:
  [Installing and uninstalling OpenShift AI Self-Managed](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed),
  [Installing in a disconnected environment](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/installing_and_uninstalling_openshift_ai_self-managed_in_a_disconnected_environment)
- **Administer**:
  [Managing OpenShift AI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_openshift_ai),
  [Managing resources](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_resources),
  [Working with accelerators](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_accelerators),
  [Configuring your model-serving platform](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/configuring_your_model-serving_platform),
  [Working with Llama Stack](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_llama_stack),
  [Managing model registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_model_registries),
  [Managing and monitoring models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/managing_and_monitoring_models)
- **Develop**:
  [Working with model registries](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_model_registries),
  [Working with the model catalog](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_the_model_catalog),
  [Experimenting with models in the gen AI playground](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/experimenting_with_models_in_the_gen_ai_playground),
  [Working with distributed workloads](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_distributed_workloads),
  [Working on projects](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_on_projects),
  [Working with AI pipelines](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_ai_pipelines),
  [Working with MLflow](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow)
- **Train**:
  [Customize Models for Gen AI and Agentic AI Applications](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/customize_models_for_gen_ai_and_agentic_ai_applications)
- **Evaluate**:
  [Evaluating AI systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/evaluating_ai_systems)
- **Maintain Safety**:
  [Ensuring AI safety with guardrails](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/enabling_ai_safety_with_guardrails)
- **Monitor**:
  [Monitoring your AI systems](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/monitoring_your_ai_systems)
- **Deploy**:
  [Deploying models](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploying_models),
  [Govern LLM access with Models-as-a-Service](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/govern_llm_access_with_models-as-a-service),
  [Deploy models using Distributed Inference with llm-d](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/deploy_models_using_distributed_inference_with_llm-d)
- **Learn**:
  [RHOAI supported configurations](https://access.redhat.com/articles/rhoai-supported-configs-3.x),
  [Red Hat AI Foundations](https://docs.redhat.com/en/ai-foundations),
  [Red Hat AI learning hub](https://docs.redhat.com/en/learn/ai)

## Source Hierarchy

1. Official Red Hat product documentation for the active baseline.
2. Official Red Hat articles, blogs, and product messaging for narrative and examples.
3. `/Users/adrina/Sandbox/rh-brain/Red Hat Brain` as read-only research input.
4. Existing repo implementation, scripts, and READMEs.
5. Live cluster schema verification with commands such as `oc explain` and `oc get crd`.

Official product documentation remains the source of truth for supported
configuration. Do not invent CR fields, API versions, annotations, or operator
configuration.

## Skill Metadata Policy

Shared skills should reference this repository baseline rather than repeating
exact platform versions in every skill frontmatter. Use exact version-specific
reference files only when a workflow genuinely differs across platform versions.
