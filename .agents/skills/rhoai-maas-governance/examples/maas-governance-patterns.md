# MaaS Governance Patterns

These snippets are review patterns derived from the official MaaS guide. Before
committing GitOps, verify exact installed CRD schemas with `oc explain` and
the OpenShift safety guard in `AGENTS.md`.

## Local Model Reference Pattern

```yaml
apiVersion: models.opendatahub.io/v1alpha1
kind: MaaSModelRef
metadata:
  name: nemotron-3-nano-30b-a3b
  namespace: model-serving
spec:
  modelRef:
    kind: LLMInferenceService
    name: nemotron-3-nano-30b-a3b
```

Review points:

- underlying `LLMInferenceService` must be ready before MaaS exposure
- namespace must match the model-serving namespace
- vLLM with MaaS is Technology Preview if this backend uses vLLM

## External OpenAI Model Pattern

```yaml
apiVersion: maas.opendatahub.io/v1alpha1
kind: ExternalModel
metadata:
  name: gpt-5
  namespace: external-models
spec:
  provider: openai
  endpoint: api.openai.com
  targetModel: gpt-5
  credentialRef:
    name: openai-provider-api-key
---
apiVersion: models.opendatahub.io/v1alpha1
kind: MaaSModelRef
metadata:
  name: gpt-5
  namespace: external-models
spec:
  modelRef:
    kind: ExternalModel
    name: gpt-5
```

Review points:

- `openai-provider-api-key` is a Secret, not a committed value
- external models through MaaS are Technology Preview
- provider-level rate limits apply across all users sharing the provider key
- users still need a MaaS API key, subscription, and authorization policy

## Subscription And Auth Policy Pattern

```yaml
apiVersion: models.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: enterprise-ai-builders
  namespace: models-as-a-service
spec:
  owner:
    groups:
      - kind: Group
        name: enterprise-ai-builders
  modelRefs:
    - name: nemotron-3-nano-30b-a3b
      namespace: model-serving
      tokenRateLimits:
        - limit: 100000
          window: "1h"
    - name: gpt-5
      namespace: external-models
      tokenRateLimits:
        - limit: 20000
          window: "1h"
  priority: 100
---
apiVersion: models.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata:
  name: enterprise-ai-builders
  namespace: models-as-a-service
spec:
  subjects:
    groups:
      - name: enterprise-ai-builders
  modelRefs:
    - name: nemotron-3-nano-30b-a3b
      namespace: model-serving
    - name: gpt-5
      namespace: external-models
  meteringMetadata:
    organizationId: acme-eu
    costCenter: ai-platform
    labels:
      environment: demo
```

Review points:

- subscription and auth policy are both required
- every model has at least one token limit
- token limits include a supported time window such as `1h` or `24h`
- priority matters when users belong to overlapping groups
- cost metadata supports showback, not billing-grade invoicing

## Client Request Pattern

```bash
curl -k -X POST "https://<maas-gateway-url>/llm/<model-name>/v1/chat/completions" \
  -H "Authorization: Bearer <maas-api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<model-name>",
    "messages": [
      {"role": "user", "content": "Summarize the current demo architecture."}
    ]
  }'
```

Review points:

- `<maas-api-key>` is a MaaS key with the `sk-oai-` prefix
- key owner must have matching subscription and authorization policy access
- use `-k` only when the demo environment uses self-signed certificates
