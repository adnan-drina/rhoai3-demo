# Readonly Cluster Inspection

Use this workflow when gathering OpenShift state before deciding on a fix.
Follow the OpenShift safety guard in `AGENTS.md` before any live command, and
prefer readonly inspection before mutation.

## Standard Inspection Sequence

For a step or component:

1. Check Argo CD Application sync and health:

   ```bash
   oc get application <step-name> -n openshift-gitops -o jsonpath='{.status.sync.status}/{.status.health.status}'
   ```

2. Check Pods in the target namespace and component group:

   ```bash
   oc get pods -n private-ai -l app.kubernetes.io/part-of=<component>
   ```

3. For failing Pods, inspect events and recent logs:

   ```bash
   oc describe pod <pod-name> -n private-ai | tail -30
   oc logs <pod-name> -n private-ai --tail=50
   ```

4. For model endpoints, check InferenceService readiness:

   ```bash
   oc get isvc -n private-ai
   ```

5. For operator issues, check CSV status:

   ```bash
   oc get csv -n openshift-operators
   ```

## Key Namespaces

| Namespace | Components |
|-----------|------------|
| `private-ai` | models, LlamaStack, chatbot, guardrails, MCP, pipelines |
| `openshift-gitops` | Argo CD |
| `openshift-operators` | NFD, GPU Operator, supporting operators |
| `minio-storage` | MinIO |
| `rhoai-model-registries` | Model Registry |
| `redhat-ods-applications` | RHOAI Dashboard and applications |
| `redhat-ods-operator` | RHOAI Operator |

## Output Format

```text
Component: <name>
ArgoCD: <Synced/OutOfSync> / <Healthy/Degraded>
Pods: <X/Y ready>
Issues: <problems found, or None>
Recommendation: <next action for the parent workflow>
```

## Boundaries

- Do not run cluster mutations in the inspection step.
- If not logged in, report that immediately instead of cascading failures.
- Use self-signed certificate bypasses where the repo guidance allows them.
